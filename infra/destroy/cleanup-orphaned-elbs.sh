#!/usr/bin/env bash
set -euo pipefail

# Rescue cleanup for AWS load-balancer resources created by Kubernetes rather
# than Terraform. These resources can otherwise prevent VPC deletion.

# Terraform state is read from the Terraform root to identify the exact VPC
# associated with this stack.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"
cd "$TERRAFORM_DIR"

source "$SCRIPT_DIR/../script-common.sh"

VPC_STATE_ADDRESS="module.vpc.aws_vpc.this[0]"

# Extract an AWS resource ID from a Terraform state address.
read_state_id() {
  local address="$1"

  terraform state show "$address" 2>/dev/null \
    | sed -n 's/^[[:space:]]*id[[:space:]]*=[[:space:]]*//p' \
    | head -n 1 \
    | tr -d '"'
}

# Use AWS Load Balancer Controller tags to avoid deleting unrelated load
# balancers that happen to share the same VPC.
load_balancer_is_k8s_managed() {
  local load_balancer_arn="$1"

  aws elbv2 describe-tags \
    --region "$REGION" \
    --resource-arns "$load_balancer_arn" \
    --output json | jq -e --arg cluster "$CLUSTER_NAME" '
      .TagDescriptions[]
      | (.Tags // [])
      | any(
          (.Key == "elbv2.k8s.aws/cluster" and .Value == $cluster)
          or (.Key == "kubernetes.io/cluster/\($cluster)")
          or (.Key == "ingress.k8s.aws/stack")
          or (.Key == "ingress.k8s.aws/resource")
          or (.Key == "service.k8s.aws/stack")
          or (.Key == "service.k8s.aws/resource")
        )
    ' >/dev/null
}

# List Kubernetes-managed load-balancer names and ARNs in the stack VPC.
list_k8s_load_balancers() {
  local vpc_id="$1"
  local load_balancer_name
  local load_balancer_arn

  aws elbv2 describe-load-balancers \
    --region "$REGION" \
    --output json | jq -r --arg vpc_id "$vpc_id" '
      .LoadBalancers[]
      | select(.VpcId == $vpc_id)
      | [.LoadBalancerName, .LoadBalancerArn]
      | @tsv
    ' | while IFS=$'\t' read -r load_balancer_name load_balancer_arn; do
      [[ -z "$load_balancer_name" || -z "$load_balancer_arn" ]] && continue

      if load_balancer_is_k8s_managed "$load_balancer_arn"; then
        printf '%s\t%s\n' "$load_balancer_name" "$load_balancer_arn"
      fi
    done
}

# Find ELB network interfaces by the load balancer name embedded in their AWS
# description.
list_network_interfaces_for_load_balancer_name() {
  local vpc_id="$1"
  local load_balancer_name="$2"

  aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$vpc_id" \
    --output json | jq -r --arg load_balancer_name "$load_balancer_name" '
      .NetworkInterfaces[]
      | select(
          ((.Description // "") | startswith("ELB "))
          and ((.Description // "") | contains($load_balancer_name))
        )
      | [.NetworkInterfaceId, .Status, (.Description // ""), (.Association.PublicIp // "")]
      | @tsv
    '
}

# List non-default security groups tagged as Kubernetes/controller-managed.
list_k8s_security_group_ids() {
  local vpc_id="$1"

  aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$vpc_id" \
    --output json | jq -r --arg cluster "$CLUSTER_NAME" '
      .SecurityGroups[]
      | select(.GroupName != "default")
      | select(
          ((.Tags // [])
            | map(select(
                (.Key == "elbv2.k8s.aws/cluster" and .Value == $cluster)
                or (.Key == "kubernetes.io/cluster/\($cluster)")
                or (.Key == "ingress.k8s.aws/stack")
                or (.Key == "ingress.k8s.aws/resource")
                or (.Key == "service.k8s.aws/stack")
                or (.Key == "service.k8s.aws/resource")
              ))
            | length) > 0
        )
      | .GroupId
    '
}

# Find ELB network interfaces still attached to a Kubernetes-managed security
# group.
list_network_interfaces_for_security_group() {
  local group_id="$1"

  aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --filters "Name=group-id,Values=$group_id" \
    --output json | jq -r '
      .NetworkInterfaces[]
      | select((.Description // "") | startswith("ELB "))
      | [.NetworkInterfaceId, .Status, (.Description // ""), (.Association.PublicIp // "")]
      | @tsv
    '
}

# Combine and deduplicate ENIs discovered by load-balancer name and security
# group association.
list_k8s_load_balancer_network_interfaces() {
  local vpc_id="$1"
  shift
  local load_balancer_name
  local group_id

  {
    for load_balancer_name in "$@"; do
      [[ -z "$load_balancer_name" ]] && continue
      list_network_interfaces_for_load_balancer_name "$vpc_id" "$load_balancer_name"
    done

    while IFS= read -r group_id; do
      [[ -z "$group_id" ]] && continue
      list_network_interfaces_for_security_group "$group_id"
    done < <(list_k8s_security_group_ids "$vpc_id")
  } | sort -u
}

# VPC deletion cannot finish while ALB-created ENIs still exist.
wait_for_k8s_load_balancer_network_interfaces_to_clear() {
  local vpc_id="$1"
  shift
  local waited=0
  local output=""

  while true; do
    output="$(list_k8s_load_balancer_network_interfaces "$vpc_id" "$@")"

    if [[ -z "$output" ]]; then
      return 0
    fi

    if (( waited >= WAIT_TIMEOUT_SECONDS )); then
      warn "Timed out waiting for Kubernetes load balancer network interfaces to disappear."
      printf '%s\n' "$output" >&2
      return 1
    fi

    log "Waiting for Kubernetes load balancer network interfaces to be released..."
    printf '%s\n' "$output"
    sleep "$POLL_SECONDS"
    waited=$((waited + POLL_SECONDS))
  done
}

# Retry deletion of Kubernetes-managed security groups after their load
# balancers and ENIs have disappeared.
cleanup_orphaned_k8s_security_groups() {
  local vpc_id="$1"
  local group_id
  local waited=0
  local remaining=0
  local -a group_ids=()

  while true; do
    group_ids=()

    while IFS= read -r group_id; do
      [[ -z "$group_id" ]] && continue
      group_ids+=("$group_id")
    done < <(list_k8s_security_group_ids "$vpc_id")

    if (( ${#group_ids[@]} == 0 )); then
      return 0
    fi

    log "Deleting orphaned Kubernetes load balancer security groups in VPC $vpc_id..."
    printf '%s\n' "${group_ids[@]}"

    for group_id in "${group_ids[@]}"; do
      aws ec2 delete-security-group --region "$REGION" --group-id "$group_id" >/dev/null 2>&1 || true
    done

    if (( waited >= WAIT_TIMEOUT_SECONDS )); then
      warn "Timed out waiting for Kubernetes load balancer security groups to disappear."
      aws ec2 describe-security-groups \
        --region "$REGION" \
        --group-ids "${group_ids[@]}" \
        --output table || true
      return 1
    fi

    remaining=0
    while IFS= read -r group_id; do
      [[ -z "$group_id" ]] && continue
      remaining=1
      break
    done < <(list_k8s_security_group_ids "$vpc_id")

    if (( remaining == 0 )); then
      return 0
    fi

    sleep "$POLL_SECONDS"
    waited=$((waited + POLL_SECONDS))
  done
}

load_terraform_context
require_command terraform aws jq

# destroy.sh already initializes Terraform and disables this duplicate init.
if [[ "${SKIP_TERRAFORM_INIT:-0}" != "1" ]]; then
  echo "Initializing Terraform..."
  terraform init
fi

# Without the VPC in Terraform state, there is no safe stack boundary for this
# targeted cleanup.
if ! terraform state list 2>/dev/null | grep -Fqx "$VPC_STATE_ADDRESS"; then
  log "VPC resource is no longer present in Terraform state. Skipping AWS orphan cleanup."
  exit 0
fi

vpc_id="$(read_state_id "$VPC_STATE_ADDRESS")"
if [[ -z "$vpc_id" ]]; then
  warn "Could not determine VPC ID from Terraform state. Skipping AWS orphan cleanup."
  exit 0
fi

load_balancer_names=()
load_balancer_arns=()
while IFS=$'\t' read -r load_balancer_name load_balancer_arn; do
  [[ -z "$load_balancer_name" || -z "$load_balancer_arn" ]] && continue
  load_balancer_names+=("$load_balancer_name")
  load_balancer_arns+=("$load_balancer_arn")
done < <(list_k8s_load_balancers "$vpc_id")

# Delete only load balancers identified by Kubernetes-specific AWS tags.
if (( ${#load_balancer_arns[@]} == 0 )); then
  log "No orphaned Kubernetes load balancers found in VPC $vpc_id."
else
  log "Deleting orphaned Kubernetes load balancers in VPC $vpc_id..."
  printf '%s\n' "${load_balancer_arns[@]}"

  for load_balancer_arn in "${load_balancer_arns[@]}"; do
    aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$load_balancer_arn" >/dev/null
  done

  aws elbv2 wait load-balancers-deleted --region "$REGION" --load-balancer-arns "${load_balancer_arns[@]}"
fi

# Wait for dependent AWS networking resources before removing security groups.
wait_for_k8s_load_balancer_network_interfaces_to_clear "$vpc_id" "${load_balancer_names[@]}"
cleanup_orphaned_k8s_security_groups "$vpc_id"

log "AWS orphan cleanup completed."
