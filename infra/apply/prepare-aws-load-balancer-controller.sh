#!/usr/bin/env bash
set -euo pipefail

# Compatibility reminder for the retired manual controller-preparation flow.
# Terraform now creates the IAM policy, role, and IRSA trust relationship, so
# this script intentionally prints guidance and performs no infrastructure work.

cat <<'EOF'
Terraform now owns the AWS-side prerequisites for AWS Load Balancer Controller:

- the IAM policy
- the IAM role
- the IRSA trust policy against the EKS OIDC provider

This helper script is kept only as a reminder of the old manual path.

Use one of these instead:

  ./infra/apply/apply.sh
  INSTALL_ALB_CONTROLLER=1 ./infra/apply/bootstrap-argocd.sh

or the full wrapper:

  ./infra/apply/apply-full-stack.sh
EOF
