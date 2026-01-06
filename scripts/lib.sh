#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/infra/terraform"

COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[0;31m"
COLOR_RESET="\033[0m"

log() {
  printf "%b%s%b\n" "$COLOR_GREEN" "$1" "$COLOR_RESET"
}

warn() {
  printf "%b%s%b\n" "$COLOR_YELLOW" "$1" "$COLOR_RESET" >&2
}

err() {
  printf "%b%s%b\n" "$COLOR_RED" "$1" "$COLOR_RESET" >&2
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || { err "Missing required command: $cmd"; exit 1; }
}

load_env() {
  if [[ -f "$ROOT_DIR/.env" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env"
  fi
}

aws_profile_args() {
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    echo "--profile" "$AWS_PROFILE"
  fi
}

tf() {
  terraform -chdir="$TF_DIR" "$@"
}

tf_init() {
  if [[ -z "${TF_BACKEND_BUCKET:-}" ]]; then
    err "TF_BACKEND_BUCKET is required for remote backend"
    exit 1
  fi
  if [[ -z "${TF_BACKEND_DYNAMODB_TABLE:-}" ]]; then
    err "TF_BACKEND_DYNAMODB_TABLE is required for state locking"
    exit 1
  fi

  local key_default="jenkins-${TF_VAR_env:-env}/terraform.tfstate"
  if [[ -n "${TF_VAR_project_name:-}" ]]; then
    key_default="${TF_VAR_project_name}-${TF_VAR_env:-env}/terraform.tfstate"
  fi
  local key="${TF_BACKEND_KEY:-$key_default}"
  local region="${TF_BACKEND_REGION:-${AWS_REGION:-ap-south-1}}"
  local args=(
    -backend-config="bucket=${TF_BACKEND_BUCKET}"
    -backend-config="key=${key}"
    -backend-config="region=${region}"
    -backend-config="encrypt=true"
    -backend-config="dynamodb_table=${TF_BACKEND_DYNAMODB_TABLE}"
  )
  log "Using remote backend (s3) bucket=${TF_BACKEND_BUCKET}, key=${key}, table=${TF_BACKEND_DYNAMODB_TABLE}"
  terraform -chdir="$TF_DIR" init "${args[@]}"
}

tf_output_json() {
  tf output -json 2>/dev/null || true
}

get_output_value() {
  local key="$1"
  local json
  json="$(tf_output_json)"
  if [[ -n "$json" ]]; then
    echo "$json" | jq -r --arg k "$key" '.[$k].value // empty'
  fi
}

get_instance_id() {
  local instance_id
  instance_id="$(get_output_value "instance_id")"
  if [[ -n "$instance_id" ]]; then
    echo "$instance_id"
    return
  fi

  if [[ -z "${TF_VAR_project_name:-}" || -z "${TF_VAR_env:-}" ]]; then
    err "Set TF_VAR_project_name and TF_VAR_env to discover the instance by tag."
    exit 1
  fi

  local name="${TF_VAR_project_name}-${TF_VAR_env}-jenkins"
  instance_id="$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${name}" "Name=instance-state-name,Values=running,stopped,pending" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text $(aws_profile_args))"

  if [[ -z "$instance_id" ]]; then
    err "Could not find instance id via tags."
    exit 1
  fi

  echo "$instance_id"
}

get_public_ip() {
  local json ip
  json="$(tf_output_json)"
  if [[ -n "$json" ]]; then
    ip="$(echo "$json" | jq -r '.elastic_ip.value // empty')"
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return
    fi
  fi

  local iid
  iid="$(get_instance_id)"
  aws ec2 describe-instances --instance-ids "$iid" --query "Reservations[0].Instances[0].PublicIpAddress" --output text $(aws_profile_args)
}

jenkins_url() {
  local fqdn
  fqdn="$(get_output_value "jenkins_fqdn")"
  if [[ -n "$fqdn" ]]; then
    echo "http://${fqdn}"
  else
    local ip
    ip="$(get_public_ip)"
    echo "http://${ip}"
  fi
}
