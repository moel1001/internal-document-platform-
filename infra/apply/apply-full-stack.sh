#!/usr/bin/env bash
set -euo pipefail

# End-to-end EKS demo deployment:
# 1. provision AWS infrastructure with Terraform,
# 2. bootstrap Argo CD and its applications,
# 3. expose selected services through ALBs,
# 4. verify that the public endpoints are serving traffic.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Polling defaults can be overridden for slower or faster environments.
POLL_SECONDS="${POLL_SECONDS:-5}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-1200}"

source "$SCRIPT_DIR/../script-common.sh"

# Read REGION and CLUSTER_NAME from terraform.tfvars, with shared fallbacks.
load_terraform_context

# Feature flags allow the same wrapper to perform a full rebuild or a partial
# reconciliation of an existing cluster.
SKIP_TERRAFORM="${SKIP_TERRAFORM:-0}"
INSTALL_MONITORING="${INSTALL_MONITORING:-1}"
INSTALL_LOKI="${INSTALL_LOKI:-1}"
INSTALL_ALB_CONTROLLER="${INSTALL_ALB_CONTROLLER:-1}"
EXPOSE_ARGOCD="${EXPOSE_ARGOCD:-1}"
EXPOSE_GRAFANA="${EXPOSE_GRAFANA:-1}"
EXPOSE_PROMETHEUS="${EXPOSE_PROMETHEUS:-1}"
WAIT_FOR_APPLICATIONS="${WAIT_FOR_APPLICATIONS:-1}"
WAIT_FOR_INGRESSES="${WAIT_FOR_INGRESSES:-1}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-20m}"
VERIFY_HTTP_ENDPOINTS="${VERIFY_HTTP_ENDPOINTS:-1}"
HTTP_CONNECT_TIMEOUT_SECONDS="${HTTP_CONNECT_TIMEOUT_SECONDS:-5}"
HTTP_TIMEOUT_SECONDS="${HTTP_TIMEOUT_SECONDS:-15}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

require_command aws kubectl curl

# Terraform is still needed when the cluster must be provisioned or when the
# AWS Load Balancer Controller role ARN must be read from Terraform output.
if [[ "$SKIP_TERRAFORM" != "1" || ( "$INSTALL_ALB_CONTROLLER" == "1" && -z "${AWS_LBC_ROLE_ARN:-}" ) ]]; then
  require_command terraform
fi

# Wait until Kubernetes has created a specific namespaced resource.
wait_for_namespaced_resource() {
  local kind="$1"
  local namespace="$2"
  local name="$3"
  local waited=0

  until kubectl get "$kind" "$name" -n "$namespace" >/dev/null 2>&1; do
    if (( waited >= WAIT_TIMEOUT_SECONDS )); then
      echo "Timed out waiting for $kind/$name in namespace $namespace" >&2
      exit 1
    fi

    sleep "$POLL_SECONDS"
    waited=$((waited + POLL_SECONDS))
  done
}

# Wait for a Deployment or StatefulSet rollout after ensuring it exists.
wait_for_rollout() {
  local kind="$1"
  local namespace="$2"
  local name="$3"

  wait_for_namespaced_resource "$kind" "$namespace" "$name"
  kubectl rollout status "$kind/$name" -n "$namespace" --timeout="$ROLLOUT_TIMEOUT"
}

# An Argo CD Application is ready only after Git state is synced and all
# managed Kubernetes resources report healthy.
wait_for_argocd_application() {
  local name="$1"
  local waited=0
  local sync_status=""
  local health_status=""
  local current_status=""
  local previous_status=""

  wait_for_namespaced_resource application "$ARGOCD_NAMESPACE" "$name"

  until [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; do
    sync_status="$(kubectl get application "$name" -n "$ARGOCD_NAMESPACE" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    health_status="$(kubectl get application "$name" -n "$ARGOCD_NAMESPACE" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    current_status="${sync_status:-Unknown}/${health_status:-Unknown}"

    # Print only status transitions to keep long waits readable.
    if [[ "$current_status" != "$previous_status" ]]; then
      printf 'Argo CD application %s: %s\n' "$name" "$current_status"
      previous_status="$current_status"
    fi

    if (( waited >= WAIT_TIMEOUT_SECONDS )); then
      echo "Timed out waiting for Argo CD application/$name to become Synced/Healthy"
      kubectl get application "$name" -n "$ARGOCD_NAMESPACE" -o wide || true
      kubectl describe application "$name" -n "$ARGOCD_NAMESPACE" || true
      exit 1
    fi

    sleep "$POLL_SECONDS"
    waited=$((waited + POLL_SECONDS))
  done
}

# Wait only for applications requested through the installation flags.
wait_for_expected_argocd_applications() {
  echo "Waiting for Argo CD applications to become Synced and Healthy..."

  if [[ "$INSTALL_ALB_CONTROLLER" == "1" ]]; then
    wait_for_argocd_application aws-load-balancer-controller-eks
  fi

  if [[ "$INSTALL_MONITORING" == "1" ]]; then
    wait_for_argocd_application monitoring-eks
  fi

  if [[ "$INSTALL_LOKI" == "1" ]]; then
    wait_for_argocd_application loki-eks
  fi

  wait_for_argocd_application document-service-eks
}

# Discover the controller by label because Helm-generated deployment names can
# vary between releases.
wait_for_aws_load_balancer_controller() {
  local namespace="kube-system"
  local selector="app.kubernetes.io/name=aws-load-balancer-controller"
  local waited=0
  local deployment_name=""

  until [[ -n "$deployment_name" ]]; do
    deployment_name="$(kubectl get deployment -n "$namespace" -l "$selector" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

    if [[ -n "$deployment_name" ]]; then
      kubectl rollout status "deployment/$deployment_name" -n "$namespace" --timeout="$ROLLOUT_TIMEOUT"
      return 0
    fi

    if (( waited >= WAIT_TIMEOUT_SECONDS )); then
      echo "Timed out waiting for AWS Load Balancer Controller deployment in namespace $namespace"
      exit 1
    fi

    sleep "$POLL_SECONDS"
    waited=$((waited + POLL_SECONDS))
  done
}

# An ALB hostname alone does not prove that traffic reaches the application.
# Retry the application's health endpoint until it returns a successful status.
wait_for_http_endpoint() {
  local label="$1"
  local url="$2"
  local waited=0

  until curl \
    --silent \
    --show-error \
    --fail \
    --connect-timeout "$HTTP_CONNECT_TIMEOUT_SECONDS" \
    --max-time "$HTTP_TIMEOUT_SECONDS" \
    "$url" >/dev/null 2>&1; do
    if (( waited >= WAIT_TIMEOUT_SECONDS )); then
      echo "Timed out waiting for $label endpoint to respond successfully: $url" >&2
      curl \
        --show-error \
        --fail \
        --connect-timeout "$HTTP_CONNECT_TIMEOUT_SECONDS" \
        --max-time "$HTTP_TIMEOUT_SECONDS" \
        "$url" >/dev/null || true
      exit 1
    fi

    sleep "$POLL_SECONDS"
    waited=$((waited + POLL_SECONDS))
  done
}

# Wait for AWS Load Balancer Controller to publish the ALB DNS hostname into
# the Kubernetes Ingress status.
wait_for_ingress_address() {
  local namespace="$1"
  local name="$2"
  local waited=0
  local address=""

  until [[ -n "$address" ]]; do
    address="$(kubectl get ingress "$name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

    if [[ -n "$address" ]]; then
      printf '%s\n' "$address"
      return 0
    fi

    if (( waited >= WAIT_TIMEOUT_SECONDS )); then
      echo "Timed out waiting for ingress/$name in namespace $namespace to get an ADDRESS" >&2
      exit 1
    fi

    sleep "$POLL_SECONDS"
    waited=$((waited + POLL_SECONDS))
  done
}

# Verify one browser-facing Ingress and return its ALB hostname to the caller.
check_ingress_endpoint() {
  local label="$1"
  local namespace="$2"
  local name="$3"
  local health_path="$4"
  local address=""

  printf 'Smoke test: verifying %s ingress (%s/%s)...\n' "$label" "$namespace" "$name" >&2
  wait_for_namespaced_resource ingress "$namespace" "$name"
  address="$(wait_for_ingress_address "$namespace" "$name")"

  if [[ "$VERIFY_HTTP_ENDPOINTS" == "1" ]]; then
    wait_for_http_endpoint "$label" "http://${address}${health_path}"
  fi

  printf '%s\n' "$address"
}

# Validate every enabled public endpoint and print the URLs for the operator.
run_post_bootstrap_smoke_test() {
  local document_service_address=""
  local argocd_address=""
  local grafana_address=""
  local prometheus_address=""

  echo
  echo "Running post-bootstrap ingress smoke test..."

  document_service_address="$(check_ingress_endpoint document-service platform document-service /health/ready)"
  printf 'document-service: http://%s\n' "$document_service_address"

  if [[ "$EXPOSE_ARGOCD" == "1" ]]; then
    argocd_address="$(check_ingress_endpoint argocd argocd argocd /healthz)"
    printf 'argocd:           http://%s\n' "$argocd_address"
  fi

  if [[ "$EXPOSE_GRAFANA" == "1" ]]; then
    grafana_address="$(check_ingress_endpoint grafana monitoring grafana /api/health)"
    printf 'grafana:          http://%s\n' "$grafana_address"
  fi

  if [[ "$EXPOSE_PROMETHEUS" == "1" ]]; then
    prometheus_address="$(check_ingress_endpoint prometheus monitoring prometheus /-/healthy)"
    printf 'prometheus:       http://%s\n' "$prometheus_address"
  fi

  echo "Ingress smoke test passed."
}

# Phase 1: create or update the AWS VPC, EKS cluster, node group, and IAM
# resources. Skip this phase when reconciling an existing cluster.
if [[ "$SKIP_TERRAFORM" == "1" ]]; then
  echo "Skipping Terraform apply because SKIP_TERRAFORM=$SKIP_TERRAFORM"
else
  "$SCRIPT_DIR/apply.sh"
fi

# Phase 2: install Argo CD and submit the workload Application resources.
# Browser exposure is deliberately disabled until the controller and workloads
# have reconciled successfully.
echo "Bootstrapping Argo CD and workload applications..."
INSTALL_MONITORING="$INSTALL_MONITORING" \
INSTALL_LOKI="$INSTALL_LOKI" \
INSTALL_ALB_CONTROLLER="$INSTALL_ALB_CONTROLLER" \
EXPOSE_ARGOCD=0 \
EXPOSE_GRAFANA=0 \
EXPOSE_PROMETHEUS=0 \
  "$SCRIPT_DIR/bootstrap-argocd.sh"

# Confirm that GitOps reconciliation completed before creating public routes.
if [[ "$WAIT_FOR_APPLICATIONS" == "1" ]]; then
  wait_for_expected_argocd_applications
else
  echo "Skipping Argo CD application health checks because WAIT_FOR_APPLICATIONS=$WAIT_FOR_APPLICATIONS"
fi

# The controller must be ready before Kubernetes Ingress resources can create
# or update AWS Application Load Balancers.
if [[ "$INSTALL_ALB_CONTROLLER" == "1" || "$WAIT_FOR_INGRESSES" == "1" || "$EXPOSE_ARGOCD" == "1" || "$EXPOSE_GRAFANA" == "1" || "$EXPOSE_PROMETHEUS" == "1" ]]; then
  echo "Waiting for AWS Load Balancer Controller to become ready..."
  wait_for_aws_load_balancer_controller
fi

# Grafana and Prometheus services are created asynchronously by their Argo CD
# application, so wait for them before applying Ingress backends.
if [[ "$EXPOSE_GRAFANA" == "1" ]]; then
  echo "Waiting for Grafana service to exist..."
  wait_for_namespaced_resource service monitoring monitoring-eks-grafana
fi

if [[ "$EXPOSE_PROMETHEUS" == "1" ]]; then
  echo "Waiting for Prometheus service to exist..."
  wait_for_namespaced_resource service monitoring monitoring-eks-kube-promet-prometheus
fi

# Phase 3: re-run the bootstrap helper without reinstalling applications. This
# pass applies only the requested browser-facing Ingress manifests.
echo "Applying browser exposure manifests..."
INSTALL_ARGOCD=0 \
INSTALL_MONITORING=0 \
INSTALL_LOKI=0 \
INSTALL_ALB_CONTROLLER=0 \
EXPOSE_ARGOCD="$EXPOSE_ARGOCD" \
EXPOSE_GRAFANA="$EXPOSE_GRAFANA" \
EXPOSE_PROMETHEUS="$EXPOSE_PROMETHEUS" \
  "$SCRIPT_DIR/bootstrap-argocd.sh"

# Phase 4: wait for ALB addresses and optionally confirm real HTTP responses.
if [[ "$WAIT_FOR_INGRESSES" == "1" ]]; then
  run_post_bootstrap_smoke_test
else
  echo "Skipping ingress smoke test. Use 'kubectl get ingress -A' to check ALB addresses."
fi
