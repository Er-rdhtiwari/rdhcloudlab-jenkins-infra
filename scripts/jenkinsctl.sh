#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

load_env

export AWS_REGION="${AWS_REGION:-ap-south-1}"

REQUIRED_CMDS=(terraform aws jq)

require_base_env() {
  local required=(AWS_REGION TF_VAR_project_name TF_VAR_env TF_VAR_key_name TF_VAR_allowed_ssh_cidr TF_VAR_root_domain TF_VAR_hosted_zone_id)
  for var in "${required[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      err "Required env var $var is not set"
      exit 1
    fi
  done
}

usage() {
  cat <<'EOF'
Usage: jenkinsctl.sh <command> [args]

Commands:
  help                    Show this help
  create-keypair NAME [PATH]  Create an EC2 key pair via AWS CLI and save PEM locally (default ~/.ssh/NAME.pem)
  init                    terraform init
  deploy                  terraform apply -auto-approve
  destroy                 terraform destroy -auto-approve
  status                  Show instance state, IP/EIP, URL
  start                   Start the EC2 instance
  stop                    Stop the EC2 instance
  reboot                  Reboot the EC2 instance
  ssh [ssh-args]          SSH into the instance (uses SSH_KEY_PATH if set)
  url                     Print the Jenkins URL
  password                Fetch Jenkins initial admin password via SSH
  set-auto-shutdown HRS   Set auto-shutdown hours and re-apply
EOF
}

main() {
  for cmd in "${REQUIRED_CMDS[@]}"; do
    require_cmd "$cmd"
  done

  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    help|-h|--help)
      usage
      ;;
    create-keypair)
      "$SCRIPT_DIR/create-keypair.sh" "$@"
      ;;
    init)
      tf_init
      ;;
    deploy)
      require_base_env
      tf apply -auto-approve
      ;;
    destroy)
      tf destroy -auto-approve
      ;;
    status)
      show_status
      ;;
    start)
      aws ec2 start-instances --instance-ids "$(get_instance_id)" $(aws_profile_args)
      ;;
    stop)
      aws ec2 stop-instances --instance-ids "$(get_instance_id)" $(aws_profile_args)
      ;;
    reboot)
      aws ec2 reboot-instances --instance-ids "$(get_instance_id)" $(aws_profile_args)
      ;;
    ssh)
      ssh_into "$@"
      ;;
    url)
      echo "$(jenkins_url)"
      ;;
    password)
      fetch_password "$@"
      ;;
    set-auto-shutdown)
      set_auto_shutdown "$@"
      ;;
    *)
      err "Unknown command: $cmd"
      usage
      exit 1
      ;;
  esac
}

show_status() {
  local instance_id state public_ip fqdn
  instance_id="$(get_instance_id)"
  state="$(aws ec2 describe-instances --instance-ids "$instance_id" --query "Reservations[0].Instances[0].State.Name" --output text $(aws_profile_args))"
  public_ip="$(get_public_ip)"
  fqdn="$(get_output_value "jenkins_fqdn")"

  log "Instance ID: $instance_id"
  log "State     : $state"
  log "Public IP : $public_ip"
  if [[ -n "$fqdn" ]]; then
    log "FQDN      : $fqdn"
  fi
  log "URL       : $(jenkins_url)"
}

ssh_into() {
  local ip
  ip="$(get_public_ip)"
  local ssh_cmd=(ssh)
  if [[ -n "${SSH_KEY_PATH:-}" ]]; then
    ssh_cmd+=(-i "$SSH_KEY_PATH")
  fi
  ssh_cmd+=("ubuntu@${ip}")
  ssh_cmd+=("$@")
  "${ssh_cmd[@]}"
}

fetch_password() {
  local ip
  ip="$(get_public_ip)"
  local ssh_cmd=(ssh)
  if [[ -n "${SSH_KEY_PATH:-}" ]]; then
    ssh_cmd+=(-i "$SSH_KEY_PATH")
  fi
  ssh_cmd+=("ubuntu@${ip}" "sudo cat /var/lib/jenkins/secrets/initialAdminPassword")
  "${ssh_cmd[@]}"
}

set_auto_shutdown() {
  local hours="${1:-}"
  if [[ -z "$hours" ]]; then
    err "Usage: jenkinsctl.sh set-auto-shutdown <hours>"
    exit 1
  fi
  if ! [[ "$hours" =~ ^[0-9]+$ ]]; then
    err "Hours must be an integer."
    exit 1
  fi

  cat >"$TF_DIR/auto.tfvars" <<EOF
auto_shutdown_hours = ${hours}
EOF
  log "Updated $TF_DIR/auto.tfvars with auto_shutdown_hours=${hours}"
  tf apply -auto-approve

  local ip
  ip="$(get_public_ip)"
  log "Rescheduling auto-shutdown on instance ${ip}"
  local ssh_cmd=(ssh)
  if [[ -n "${SSH_KEY_PATH:-}" ]]; then
    ssh_cmd+=(-i "$SSH_KEY_PATH")
  fi
  ssh_cmd+=("ubuntu@${ip}" "echo ${hours} | sudo tee /etc/jenkins/auto_shutdown_hours >/dev/null && sudo /usr/local/bin/schedule-autoshutdown.sh ${hours}")
  "${ssh_cmd[@]}"
}

main "$@"
