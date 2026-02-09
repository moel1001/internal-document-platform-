#!/usr/bin/env bash
set -euo pipefail

# ---------- colors ----------
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'
  GRN=$'\033[0;32m'
  YEL=$'\033[0;33m'
  BLU=$'\033[0;34m'
  BLD=$'\033[1m'
  RST=$'\033[0m'
else
  RED=""; GRN=""; YEL=""; BLU=""; BLD=""; RST=""
fi

step() { echo; echo "${BLD}${BLU}==> $*${RST}"; echo; }
ok()   { echo; echo "${GRN}✅ $*${RST}"; }
warn() { echo; echo "${YEL}⚠️  $*${RST}"; }
fail() { echo; echo "${RED}❌ $*${RST}" >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
cd "$REPO_ROOT"

step "Stopping local proxy"
if ./deploy/local/scripts/proxy-down.sh 2>&1 | sed 's/^/  /'; then
  ok "Proxy stopped"
else
  warn "Proxy was not running (or already removed)"
fi

step "Deleting local ingresses"
if kubectl delete -f deploy/local/ingress-local.yaml --ignore-not-found 2>&1 | sed 's/^/  /'; then
  ok "Ingresses removed"
else
  fail "Failed to delete ingresses"
fi

step "Removing generated local files"
rm -rf deploy/local/certs deploy/local/.runtime
echo "  Removed deploy/local/certs and deploy/local/.runtime"
ok "Local generated files removed"

echo
echo "${BLD}${GRN}Done.${RST} Local access removed (proxy, ingresses, certs/runtime)."
echo "Next: ./deploy/local/bootstrap.sh"
