#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"

docker rm -f idp-local-proxy 2>/dev/null || true
rm -f "${REPO_ROOT}/deploy/local/.runtime/nginx.conf" 2>/dev/null || true

echo "Proxy down."
