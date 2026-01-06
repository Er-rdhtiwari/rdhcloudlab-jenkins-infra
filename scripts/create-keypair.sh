#!/usr/bin/env bash
# Helper to generate an EC2 key pair with AWS CLI and save the private key on this host.
# Usage: ./scripts/create-keypair.sh <key-name> [output-path]
# - key-name: required, the EC2 key pair name to create (e.g., jenkins-key)
# - output-path: optional, where to write the PEM file; defaults to ~/.ssh/<key-name>.pem
# The script prints checkpoints and the final file path. It will refuse to overwrite an existing key pair.

set -euo pipefail

TOTAL_STEPS=7
STEP=1

checkpoint() {
  printf "[%d/%d] %s\n" "$STEP" "$TOTAL_STEPS" "$1"
  STEP=$((STEP + 1))
}

usage() {
  cat <<'EOF'
Usage: ./scripts/create-keypair.sh <key-name> [output-path]

Creates a new EC2 key pair via AWS CLI and saves the private key locally.
Examples:
  ./scripts/create-keypair.sh jenkins-key
  ./scripts/create-keypair.sh jenkins-key /tmp/jenkins-key.pem
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

main() {
  local key_name="${1:-}"
  local output_path="${2:-}"

  if [[ -z "$key_name" ]]; then
    usage
    exit 1
  fi

  checkpoint "Validating prerequisites"
  require_cmd aws

  # Build AWS CLI args from env if set.
  local aws_args=()
  if [[ -n "${AWS_REGION:-}" ]]; then
    aws_args+=(--region "$AWS_REGION")
  fi
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    aws_args+=(--profile "$AWS_PROFILE")
  fi

  # Default output path.
  if [[ -z "$output_path" ]]; then
    output_path="${HOME}/.ssh/${key_name}.pem"
  fi

  local output_dir
  output_dir="$(dirname "$output_path")"

  checkpoint "Ensuring output directory exists: ${output_dir}"
  mkdir -p "$output_dir"

  checkpoint "Checking for existing EC2 key pair named '${key_name}'"
  if aws ec2 describe-key-pairs --key-names "$key_name" "${aws_args[@]}" >/dev/null 2>&1; then
    echo "Key pair '${key_name}' already exists in AWS. Aborting to avoid overwrite." >&2
    exit 1
  fi

  checkpoint "Creating EC2 key pair '${key_name}' and saving private key"
  aws ec2 create-key-pair \
    --key-name "$key_name" \
    --query 'KeyMaterial' \
    --output text \
    "${aws_args[@]}" >"$output_path"

  checkpoint "Setting permissions to 600 on ${output_path}"
  chmod 600 "$output_path"

  checkpoint "Verifying key file was written"
  if [[ ! -s "$output_path" ]]; then
    echo "Key file not found or empty at ${output_path}" >&2
    exit 1
  fi

  checkpoint "Done"
  printf "Key pair created. Private key saved to: %s\n" "$output_path"
  printf "Remember to reference this key in .env as TF_VAR_key_name=%s and set SSH_KEY_PATH if needed.\n" "$key_name"
}

main "$@"
