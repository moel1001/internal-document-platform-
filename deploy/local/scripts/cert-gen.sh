#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
CERT_DIR="${REPO_ROOT}/deploy/local/certs"

mkdir -p "${CERT_DIR}"

openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
  -keyout "${CERT_DIR}/argocd.local.key" \
  -out "${CERT_DIR}/argocd.local.crt" \
  -subj "/CN=argocd.local"

echo "Generated certs in ${CERT_DIR}/"
