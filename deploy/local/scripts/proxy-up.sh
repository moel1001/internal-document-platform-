#!/usr/bin/env bash
set -euo pipefail

DOCKER_NETWORK="${KIND_DOCKER_NETWORK:-kind}"

for bin in kind kubectl docker; do
  command -v "$bin" >/dev/null || { echo "$bin not found"; exit 1; }
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"

CLUSTER_NAME="${KIND_CLUSTER_NAME:-$(kind get clusters | head -n1)}"
if [[ -z "${CLUSTER_NAME}" ]]; then
  echo "No kind clusters found. Create one first."
  exit 1
fi

NODE_CONTAINER="${CLUSTER_NAME}-control-plane"

NODE_IP="$(docker inspect -f "{{(index .NetworkSettings.Networks \"${DOCKER_NETWORK}\").IPAddress}}" "$NODE_CONTAINER" 2>/dev/null || true)"
if [[ -z "${NODE_IP}" ]]; then
  echo "Could not determine kind node IP for container ${NODE_CONTAINER} on network ${DOCKER_NETWORK}."
  exit 1
fi

HTTP_NODEPORT="$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null || true)"
HTTPS_NODEPORT="$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}' 2>/dev/null || true)"

if [[ -z "${HTTP_NODEPORT}" || -z "${HTTPS_NODEPORT}" ]]; then
  echo "Could not determine ingress-nginx NodePorts. Is ingress-nginx installed?"
  exit 1
fi

TPL="${REPO_ROOT}/deploy/local/nginx-proxy.conf.tpl"
if [[ ! -f "${TPL}" ]]; then
  echo "Missing ${TPL}"
  exit 1
fi

CERT_DIR="${REPO_ROOT}/deploy/local/certs"
if [[ ! -f "${CERT_DIR}/argocd.local.crt" || ! -f "${CERT_DIR}/argocd.local.key" ]]; then
  echo "Missing certs in ${CERT_DIR}. Run: ${REPO_ROOT}/deploy/local/scripts/cert-gen.sh"
  exit 1
fi

RUNTIME_DIR="${REPO_ROOT}/deploy/local/.runtime"
mkdir -p "${RUNTIME_DIR}"
CONF="${RUNTIME_DIR}/nginx.conf"

sed -e "s|__NODE_IP__|$NODE_IP|g" \
    -e "s|__HTTP_NODEPORT__|$HTTP_NODEPORT|g" \
    -e "s|__HTTPS_NODEPORT__|$HTTPS_NODEPORT|g" \
    "${TPL}" > "${CONF}"

docker rm -f idp-local-proxy 2>/dev/null || true

docker run -d --name idp-local-proxy \
  --network "${DOCKER_NETWORK}" \
  -p 80:80 \
  -p 443:443 \
  -v "${CONF}:/etc/nginx/nginx.conf:ro" \
  -v "${CERT_DIR}:/etc/nginx/certs:ro" \
  nginx:alpine

echo "Proxy up:"
echo "  http://grafana.local"
echo "  http://prometheus.local"
echo "  https://argocd.local"
echo "  http://document-service.local"
