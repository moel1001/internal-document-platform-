#!/usr/bin/env bash
set -euo pipefail

# Provision or update only the Terraform-managed AWS infrastructure, then
# configure kubectl and confirm that the EKS API is reachable.

# Run Terraform commands from the Terraform root regardless of the caller's
# current working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"
cd "$TERRAFORM_DIR"

source "$SCRIPT_DIR/../script-common.sh"

PLAN_FILE="idp-eks.plan"
PLACEHOLDER_IP="203.0.113.10/32"

# These preflight checks can be disabled explicitly when the defaults do not
# match the operator's environment.
FREE_TIER_ONLY="${FREE_TIER_ONLY:-1}"
VERIFY_PUBLIC_IP="${VERIFY_PUBLIC_IP:-1}"

load_terraform_context
require_command terraform aws kubectl curl

if [[ ! -f "$TFVARS_FILE" ]]; then
  echo "Missing required file: $TFVARS_FILE"
  exit 1
fi

NODE_INSTANCE_TYPE="$(read_tfvars_string node_instance_type)"
CURRENT_PUBLIC_IP=""

# Prevent accidentally creating a cluster whose public API cannot be reached
# because the example CIDR was never replaced.
if grep -q "$PLACEHOLDER_IP" "$TFVARS_FILE"; then
  echo "terraform.tfvars still contains the placeholder IP: $PLACEHOLDER_IP"
  echo "Replace it with the real public IP before running this script."
  exit 1
fi

if [[ -z "$NODE_INSTANCE_TYPE" ]]; then
  echo "Could not determine node_instance_type from $TFVARS_FILE"
  exit 1
fi

# Compare the workstation's current IPv4 address with the EKS API allowlist
# before spending time provisioning infrastructure.
if [[ "$VERIFY_PUBLIC_IP" == "1" ]]; then
  if ! CURRENT_PUBLIC_IP="$(curl -4 --silent --show-error --fail --max-time 15 https://checkip.amazonaws.com | tr -d '[:space:]')"; then
    echo "Could not determine this workstation's public IPv4 address."
    echo "Check DNS/network connectivity, or set VERIFY_PUBLIC_IP=0 to skip this preflight."
    exit 1
  fi

  if ! grep -Fq "\"$CURRENT_PUBLIC_IP/32\"" "$TFVARS_FILE"; then
    echo "The current public IPv4 address is not allowed by $TFVARS_FILE."
    echo "Current public IPv4: $CURRENT_PUBLIC_IP"
    echo "Add \"$CURRENT_PUBLIC_IP/32\" to cluster_endpoint_public_access_cidrs before applying."
    echo "Set VERIFY_PUBLIC_IP=0 only if another configured CIDR intentionally covers the address."
    exit 1
  fi
fi

# Protect the demo environment from using an unexpected billable node type by
# default. Set FREE_TIER_ONLY=0 when a paid instance type is intentional.
if [[ "$FREE_TIER_ONLY" == "1" ]]; then
  if ! aws ec2 describe-instance-types \
    --region "$REGION" \
    --filters "Name=instance-type,Values=$NODE_INSTANCE_TYPE" "Name=free-tier-eligible,Values=true" \
    --query 'InstanceTypes[0].InstanceType' \
    --output text | grep -qx "$NODE_INSTANCE_TYPE"; then
    echo "node_instance_type '$NODE_INSTANCE_TYPE' is not free-tier-eligible in $REGION."
    echo "Choose a Free plan compatible instance type before running this script."
    echo "If later upgrading to a Paid plan, rerun with FREE_TIER_ONLY=0."
    exit 1
  fi
fi

# Create a saved plan first so Terraform applies exactly the reviewed changes.
echo "Initializing Terraform..."
terraform init

echo "Creating Terraform plan..."
terraform plan -out="$PLAN_FILE"

echo "Applying Terraform plan..."
terraform apply "$PLAN_FILE"

echo "Updating kubeconfig..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

# EKS endpoint and DNS changes can take time to propagate after Terraform
# completes, so retry kubectl connectivity before returning success.
echo "Waiting for EKS API connectivity..."
waited=0
until kubectl get nodes; do
  if (( waited >= WAIT_TIMEOUT_SECONDS )); then
    echo "Timed out waiting for EKS API connectivity after ${WAIT_TIMEOUT_SECONDS}s."
    echo "Check cluster_endpoint_public_access_cidrs in $TFVARS_FILE and the current public IP."
    exit 1
  fi

  sleep "$POLL_SECONDS"
  waited=$((waited + POLL_SECONDS))
done

echo "Done."
