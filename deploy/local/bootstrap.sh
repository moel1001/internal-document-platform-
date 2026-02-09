#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
cd "$REPO_ROOT"

log()  { printf "\n==> %s\n" "$*"; }
fail() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null || fail "Missing '$1' in PATH"
}

check_host() {
  local host="$1"
  local out
  out="$(dscacheutil -q host -a name "$host" 2>/dev/null || true)"
  echo "$out" | grep -q "ip_address: 127.0.0.1" || fail "$host does not resolve to 127.0.0.1. Add it to /etc/hosts."
}

require_cmd kind
require_cmd kubectl
require_cmd docker
require_cmd curl
require_cmd dscacheutil

log "Checking required hostnames (/etc/hosts)"
check_host grafana.local
check_host prometheus.local
check_host argocd.local
check_host document-service.local

log "Checking ingress-nginx service exists"
kubectl -n ingress-nginx get svc ingress-nginx-controller >/dev/null \
  || fail "ingress-nginx not found. Install ingress-nginx first."

log "Checking Docker network 'kind' exists"
docker network inspect kind >/dev/null 2>&1 || fail "Docker network 'kind' not found."

log "Generating local TLS cert for argocd.local"
if ./deploy/local/scripts/cert-gen.sh >/dev/null 2>&1; then
  echo "✅ Certificates generated"
else
  echo "❌ Certificate generation failed"
  ./deploy/local/scripts/cert-gen.sh
  exit 1
fi

log "Applying local ingresses"
kubectl apply -f deploy/local/ingress-local.yaml >/dev/null
echo "✅ Ingress rules applied"

log "Starting local proxy"
./deploy/local/scripts/proxy-up.sh

log "Smoke tests"
curl -fsS -I http://grafana.local >/dev/null && echo "✅ Grafana reachable" || fail "Grafana not reachable"
curl -fsS -I -X GET http://prometheus.local >/dev/null && echo "✅ Prometheus reachable" || fail "Prometheus not reachable"
curl -fsS -k -I https://argocd.local >/dev/null && echo "✅ Argo CD reachable" || fail "Argo CD not reachable"
curl -fsS http://document-service.local/health/ready | grep -q 'ready' && echo "✅ Document service ready" || fail "Document service not ready"

log "Done. Open:"
echo "  http://grafana.local"
echo "  http://prometheus.local"
echo "  https://argocd.local"
echo "  http://document-service.local"
