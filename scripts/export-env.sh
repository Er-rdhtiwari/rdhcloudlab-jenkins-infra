#!/usr/bin/env bash
# Export all variables from .env for the current shell and validate required ones.
# Usage: source ./scripts/export-env.sh
# Notes:
#   - Must be sourced so the exports land in your shell: `. scripts/export-env.sh`
#   - Exits non-zero if required variables are missing, but will not close your shell if sourced.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

is_sourced() {
  [[ "${BASH_SOURCE[0]}" != "$0" ]]
}

die() {
  local msg="$1"
  echo "$msg" >&2
  if is_sourced; then
    return 1
  else
    exit 1
  fi
}

REQUIRED_VARS=(
  AWS_REGION
  TF_VAR_project_name
  TF_VAR_env
  TF_VAR_key_name
  TF_VAR_allowed_ssh_cidr
  TF_VAR_root_domain
  TF_VAR_hosted_zone_id
  TF_BACKEND_BUCKET
  TF_BACKEND_DYNAMODB_TABLE
)

if [[ ! -f "$ENV_FILE" ]]; then
  die "Missing ${ENV_FILE}. Copy .env.example to .env and fill values."
fi

# Export everything in .env
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

missing=()
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
  fi
done

if (( ${#missing[@]} > 0 )); then
  {
    echo "Exported variables, but these required ones are empty or missing:"
    printf "  - %s\n" "${missing[@]}"
    echo "Update .env and re-run: source ./scripts/export-env.sh"
  } >&2
  die "Missing required variables"
fi

echo "Environment exported from ${ENV_FILE}."
echo "Key values:"
printf "  TF_VAR_project_name=%s\n" "${TF_VAR_project_name}"
printf "  TF_VAR_env=%s\n" "${TF_VAR_env}"
printf "  TF_VAR_allowed_ssh_cidr=%s\n" "${TF_VAR_allowed_ssh_cidr}"
printf "  TF_VAR_root_domain=%s\n" "${TF_VAR_root_domain}"
printf "  TF_VAR_hosted_zone_id=%s\n" "${TF_VAR_hosted_zone_id}"
printf "  TF_BACKEND_BUCKET=%s\n" "${TF_BACKEND_BUCKET}"
printf "  TF_BACKEND_DYNAMODB_TABLE=%s\n" "${TF_BACKEND_DYNAMODB_TABLE}"
