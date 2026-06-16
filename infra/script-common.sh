#!/usr/bin/env bash

# Shared Bash helpers sourced by the Terraform apply, bootstrap, teardown, and
# cleanup scripts. This file defines functions and defaults; it does not perform
# infrastructure operations by itself.

# BASH_SOURCE points to this helper file even when another script sources it.
# Use the shared infra root to locate the Terraform configuration independently
# of the caller's current working directory.
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${TERRAFORM_DIR:-$INFRA_DIR/terraform}"

# Callers may override these defaults through environment variables.
TFVARS_FILE="${TFVARS_FILE:-$TERRAFORM_DIR/terraform.tfvars}"
POLL_SECONDS="${POLL_SECONDS:-10}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-900}"

# Read one quoted string assignment from terraform.tfvars.
# Example: aws_region = "eu-central-1"
#
# This intentionally supports only simple quoted strings; it is not a complete
# HCL parser and should not be used for lists, maps, numbers, or expressions.
read_tfvars_string() {
  local key="$1"

  # Return an empty value when the optional tfvars file does not exist.
  if [[ ! -f "$TFVARS_FILE" ]]; then
    return 0
  fi

  sed -n "s/^${key}[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\"/\\1/p" "$TFVARS_FILE" | head -n 1
}

# Establish the AWS region and EKS cluster name shared by all helper scripts.
# Precedence: existing environment variable, terraform.tfvars value, fallback.
# Exporting the values makes them available to child scripts and commands.
load_terraform_context() {
  REGION="${REGION:-$(read_tfvars_string aws_region)}"
  CLUSTER_NAME="${CLUSTER_NAME:-$(read_tfvars_string cluster_name)}"
  REGION="${REGION:-eu-central-1}"
  CLUSTER_NAME="${CLUSTER_NAME:-idp-eks}"
  export REGION CLUSTER_NAME POLL_SECONDS WAIT_TIMEOUT_SECONDS
}

# Print a normal informational message to standard output.
log() {
  printf '%s\n' "$*"
}

# Print a warning to standard error so it remains visible when output is piped.
warn() {
  printf 'Warning: %s\n' "$*" >&2
}

# Fail early with a clear message when a required executable is unavailable.
require_command() {
  local cmd

  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || {
      echo "Missing required command: $cmd"
      exit 1
    }
  done
}
