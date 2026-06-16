#!/usr/bin/env bash
set -euo pipefail

# Bootstrap GitOps and optional platform applications into an existing EKS
# cluster. Environment flags control which applications and ingresses are
# applied, allowing this script to be reused by apply-full-stack.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"

source "$SCRIPT_DIR/../script-common.sh"

load_terraform_context

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
INSTALL_ARGOCD="${INSTALL_ARGOCD:-1}"
INSTALL_MONITORING="${INSTALL_MONITORING:-0}"
INSTALL_LOKI="${INSTALL_LOKI:-0}"
INSTALL_ALB_CONTROLLER="${INSTALL_ALB_CONTROLLER:-0}"
EXPOSE_ARGOCD="${EXPOSE_ARGOCD:-0}"
EXPOSE_GRAFANA="${EXPOSE_GRAFANA:-0}"
EXPOSE_PROMETHEUS="${EXPOSE_PROMETHEUS:-0}"
AWS_LBC_ROLE_ARN="${AWS_LBC_ROLE_ARN:-}"

# The upstream stable manifest is applied directly to install Argo CD.
ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

require_command aws kubectl

echo "Updating kubeconfig for $CLUSTER_NAME in $REGION..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null

echo "Checking cluster connectivity..."
kubectl get nodes >/dev/null

# Install Argo CD and wait for its core controllers before submitting
# Application custom resources.
if [[ "$INSTALL_ARGOCD" == "1" ]]; then
  echo "Ensuring namespace '$ARGOCD_NAMESPACE' exists..."
  kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  echo "Installing Argo CD manifests..."
  kubectl apply --server-side --force-conflicts -n "$ARGOCD_NAMESPACE" -f "$ARGOCD_MANIFEST_URL"

  echo "Waiting for core Argo CD workloads to become ready..."
  kubectl rollout status statefulset/argocd-application-controller -n "$ARGOCD_NAMESPACE" --timeout=10m
  kubectl rollout status deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE" --timeout=10m
  kubectl rollout status deployment/argocd-server -n "$ARGOCD_NAMESPACE" --timeout=10m
  kubectl rollout status deployment/argocd-redis -n "$ARGOCD_NAMESPACE" --timeout=10m
  kubectl rollout status deployment/argocd-dex-server -n "$ARGOCD_NAMESPACE" --timeout=10m
  kubectl rollout status deployment/argocd-notifications-controller -n "$ARGOCD_NAMESPACE" --timeout=10m
else
  echo "Skipping Argo CD install because INSTALL_ARGOCD=$INSTALL_ARGOCD"
fi

# The document service is always part of an EKS bootstrap. Monitoring and Loki
# are optional so this helper can also create a smaller cluster-side stack.
echo "Applying EKS document-service application..."
kubectl apply -f "$REPO_ROOT/argocd/document-service-app-eks.yaml"

if [[ "$INSTALL_MONITORING" == "1" ]]; then
  echo "Applying EKS monitoring application..."
  kubectl apply -f "$REPO_ROOT/argocd/monitoring-app-eks.yaml"
else
  echo "Skipping monitoring bootstrap. Set INSTALL_MONITORING=1 to include it."
fi

if [[ "$INSTALL_LOKI" == "1" ]]; then
  echo "Applying EKS Loki application..."
  kubectl apply -f "$REPO_ROOT/argocd/loki-app-eks.yaml"
else
  echo "Skipping Loki bootstrap. Set INSTALL_LOKI=1 to include it."
fi

# Render the Terraform-managed IRSA role ARN into the controller Application
# manifest before applying it to Argo CD.
if [[ "$INSTALL_ALB_CONTROLLER" == "1" ]]; then
  echo "Applying AWS Load Balancer Controller Argo CD application..."
  if [[ -z "$AWS_LBC_ROLE_ARN" ]]; then
    command -v terraform >/dev/null 2>&1 || {
      echo "Missing required command for AWS Load Balancer Controller bootstrap: terraform"
      exit 1
    }

    AWS_LBC_ROLE_ARN="$(cd "$TERRAFORM_DIR" && terraform output -raw aws_load_balancer_controller_role_arn)"
  fi

  tmp_manifest="$(mktemp)"
  trap 'rm -f "$tmp_manifest"' EXIT
  sed "s|__AWS_LBC_ROLE_ARN__|$AWS_LBC_ROLE_ARN|g" \
    "$REPO_ROOT/argocd/aws-load-balancer-controller-app-eks.yaml" >"$tmp_manifest"
  kubectl apply -f "$tmp_manifest"
else
  echo "Skipping AWS Load Balancer Controller app. Set INSTALL_ALB_CONTROLLER=1 to include it."
fi

# Browser exposure is applied separately from application installation so the
# full-stack wrapper can wait for workloads and the ALB controller first.
if [[ "$EXPOSE_ARGOCD" == "1" ]]; then
  echo "Configuring Argo CD for no-domain browser access..."
  kubectl apply -f "$REPO_ROOT/argocd/argocd-server-insecure-eks.yaml"
  kubectl rollout restart deployment/argocd-server -n "$ARGOCD_NAMESPACE"
  kubectl rollout status deployment/argocd-server -n "$ARGOCD_NAMESPACE" --timeout=10m
  kubectl apply -f "$REPO_ROOT/argocd/argocd-ingress-eks.yaml"
else
  echo "Skipping Argo CD ingress exposure. Set EXPOSE_ARGOCD=1 to include it."
fi

if [[ "$EXPOSE_GRAFANA" == "1" ]]; then
  echo "Applying Grafana ingress..."
  kubectl apply -f "$REPO_ROOT/argocd/grafana-ingress-eks.yaml"
else
  echo "Skipping Grafana ingress exposure. Set EXPOSE_GRAFANA=1 to include it."
fi

if [[ "$EXPOSE_PROMETHEUS" == "1" ]]; then
  echo "Applying Prometheus ingress..."
  kubectl apply -f "$REPO_ROOT/argocd/prometheus-ingress-eks.yaml"
else
  echo "Skipping Prometheus ingress exposure. Set EXPOSE_PROMETHEUS=1 to include it."
fi

echo
echo "Bootstrap complete."
echo
echo "Helpful follow-up commands:"
echo "  kubectl get applications -n $ARGOCD_NAMESPACE"
echo "  kubectl get pods -n platform"
echo "  kubectl get ingress -A"
echo "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
