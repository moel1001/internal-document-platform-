#!/usr/bin/env bash
set -euo pipefail

# Remove cluster-side workloads and load-balancer resources before Terraform
# destroys EKS. This gives Kubernetes controllers time to clean up the AWS
# resources that they created outside Terraform.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"
cd "$TERRAFORM_DIR"

source "$SCRIPT_DIR/../script-common.sh"

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
WORKLOAD_APPLICATIONS=(
  document-service-eks
  monitoring-eks
  loki-eks
)

# Delete a namespaced resource only when it currently exists.
delete_if_present() {
  local kind="$1"
  local namespace="$2"
  local name="$3"

  if kubectl get "$kind" "$name" -n "$namespace" >/dev/null 2>&1; then
    log "Deleting $kind/$name from namespace $namespace..."
    kubectl delete "$kind" "$name" -n "$namespace" --ignore-not-found --wait=false >/dev/null
  fi
}

# List only Ingress resources managed by AWS Load Balancer Controller.
list_alb_ingresses() {
  kubectl get ingress -A -o jsonpath='{range .items[?(@.spec.ingressClassName=="alb")]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
}

# LoadBalancer Services can also create AWS load balancers and must be removed
# before the controller itself is deleted.
list_loadbalancer_services() {
  kubectl get service -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
}

# Repeatedly call a listing function until no matching resources remain.
wait_for_no_results() {
  local description="$1"
  local command_name="$2"
  local waited=0
  local output=""

  while true; do
    output="$($command_name)"
    if [[ -z "$output" ]]; then
      return 0
    fi

    if (( waited >= WAIT_TIMEOUT_SECONDS )); then
      warn "Timed out waiting for $description to be deleted."
      printf '%s\n' "$output" >&2
      return 1
    fi

    log "Waiting for remaining $description to be deleted..."
    printf '%s\n' "$output"
    sleep "$POLL_SECONDS"
    waited=$((waited + POLL_SECONDS))
  done
}

load_terraform_context

# Teardown is intentionally tolerant when the cluster or required local tools
# are already unavailable; AWS-side orphan cleanup runs afterward.
if ! command -v aws >/dev/null 2>&1 || ! command -v kubectl >/dev/null 2>&1; then
  warn "Skipping Kubernetes workload teardown because aws or kubectl is unavailable."
  exit 0
fi

if ! aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  log "EKS cluster $CLUSTER_NAME is not reachable in $REGION. Skipping Kubernetes workload teardown."
  exit 0
fi

log "Updating kubeconfig for $CLUSTER_NAME in $REGION..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null

if ! kubectl get nodes >/dev/null 2>&1; then
  warn "Connected kubeconfig did not become usable. Skipping Kubernetes workload teardown."
  exit 0
fi

# Remove workload Applications first so Argo CD stops recreating their
# resources while teardown is in progress.
for app in "${WORKLOAD_APPLICATIONS[@]}"; do
  delete_if_present application "$ARGOCD_NAMESPACE" "$app"
done

while IFS=$'\t' read -r namespace name; do
  [[ -z "$namespace" || -z "$name" ]] && continue
  delete_if_present ingress "$namespace" "$name"
done < <(list_alb_ingresses)

while IFS=$'\t' read -r namespace name; do
  [[ -z "$namespace" || -z "$name" ]] && continue
  log "Deleting service/$name from namespace $namespace..."
  kubectl delete service "$name" -n "$namespace" --ignore-not-found --wait=false >/dev/null
done < <(list_loadbalancer_services)

wait_for_no_results "ALB ingresses" list_alb_ingresses
wait_for_no_results "LoadBalancer services" list_loadbalancer_services

# Delete the controller Application last, after it has handled load-balancer
# cleanup requests.
delete_if_present application "$ARGOCD_NAMESPACE" aws-load-balancer-controller-eks

log "Kubernetes workload teardown completed."
