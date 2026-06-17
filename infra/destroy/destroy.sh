#!/usr/bin/env bash
set -euo pipefail

# Safely destroy the full EKS environment. Kubernetes-created AWS resources are
# removed before Terraform destroys the VPC and EKS infrastructure.

# Run Terraform commands from the Terraform root regardless of the caller's
# current working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"
cd "$TERRAFORM_DIR"

source "$SCRIPT_DIR/../script-common.sh"

PLAN_FILE="${PLAN_FILE:-idp-eks-destroy.plan}"
RUN_WORKLOAD_TEARDOWN="${RUN_WORKLOAD_TEARDOWN:-1}"
RUN_ORPHAN_CLEANUP="${RUN_ORPHAN_CLEANUP:-1}"

load_terraform_context
require_command terraform

echo "Initializing Terraform..."
terraform init

# Delete Kubernetes ingresses and applications while the EKS API is still
# available, allowing AWS Load Balancer Controller to remove its resources.
if [[ "$RUN_WORKLOAD_TEARDOWN" == "1" ]]; then
  log "Tearing down Kubernetes workloads before Terraform destroy..."
  "$SCRIPT_DIR/teardown-workloads.sh"
else
  log "Skipping Kubernetes workload teardown because RUN_WORKLOAD_TEARDOWN=$RUN_WORKLOAD_TEARDOWN."
fi

# Remove any remaining Kubernetes-managed ALBs, ENIs, or security groups that
# could block Terraform from deleting the VPC.
if [[ "$RUN_ORPHAN_CLEANUP" == "1" ]]; then
  log "Cleaning orphaned Kubernetes load balancer resources before Terraform destroy..."
  SKIP_TERRAFORM_INIT=1 "$SCRIPT_DIR/cleanup-orphaned-elbs.sh"
else
  log "Skipping AWS orphan cleanup because RUN_ORPHAN_CLEANUP=$RUN_ORPHAN_CLEANUP."
fi

# Use a saved destroy plan so the final apply performs the planned teardown.
echo "Creating destroy plan..."
terraform plan -destroy -out="$PLAN_FILE"

echo "Applying destroy plan..."
terraform apply "$PLAN_FILE"

echo "Done."
