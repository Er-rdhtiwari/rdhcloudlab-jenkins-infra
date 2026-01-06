#!/usr/bin/env bash
# Simple auto-shutdown helper for any Linux host.
# - Default shutdown after 6 hours; override by passing an integer hour value.
# - Persists across reboots by writing a cron @reboot entry pointing to this script.
# Usage:
#   sudo ./autoshutdown-any.sh            # schedule default 6 hours
#   sudo ./autoshutdown-any.sh 4          # schedule 4 hours
#   sudo ./autoshutdown-any.sh status     # show current schedule and time remaining (if any)
#
# Requirements: run as root (or via sudo); systemd-based host with `shutdown` available.

set -euo pipefail

DEFAULT_HOURS=6
HOURS_FILE=/etc/auto_shutdown_hours
CRON_FILE=/etc/cron.d/auto-shutdown-any

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (try: sudo $0 ...)" >&2
    exit 1
  fi
}

usage() {
  cat <<'EOF'
Usage: autoshutdown-any.sh [hours|status]
  hours  - integer number of hours until shutdown (default 6)
  status - show configured hours and current scheduled shutdown (if any)
EOF
}

show_status() {
  if [[ -f "$HOURS_FILE" ]]; then
    echo "Configured hours: $(cat "$HOURS_FILE")"
  else
    echo "Configured hours: not set (default ${DEFAULT_HOURS})"
  fi

  if [[ -f /run/systemd/shutdown/scheduled ]]; then
    sudo cat /run/systemd/shutdown/scheduled
    ts=$(sudo awk -F= '/USEC/ {print int($2/1000000)}' /run/systemd/shutdown/scheduled)
    shutdown_at=$(date -d @"$ts")
    minutes_left=$(( (ts-$(date +%s))/60 ))
    echo "Shutdown at: ${shutdown_at}"
    echo "Minutes left: ${minutes_left}"
  else
    echo "No shutdown currently scheduled"
  fi
}

write_cron() {
  local hours="$1"
  cat >"$CRON_FILE" <<EOF
@reboot root $(readlink -f "$0") ${hours}
EOF
  chmod 644 "$CRON_FILE"
}

schedule_shutdown() {
  local hours="$1"
  echo "$hours" >"$HOURS_FILE"
  chmod 644 "$HOURS_FILE"
  local minutes=$((hours * 60))
  shutdown -c || true
  shutdown -h "+${minutes}"
  echo "Scheduled shutdown in ${hours} hour(s) (${minutes} minutes)."
  write_cron "$hours"
}

main() {
  require_root
  local arg="${1:-}"

  if [[ "$arg" == "status" ]]; then
    show_status
    exit 0
  fi

  local hours="$arg"
  if [[ -z "$hours" ]]; then
    if [[ -f "$HOURS_FILE" ]]; then
      hours="$(cat "$HOURS_FILE")"
    else
      hours="$DEFAULT_HOURS"
    fi
  fi

  if ! [[ "$hours" =~ ^[0-9]+$ ]]; then
    usage >&2
    echo "Hours must be an integer." >&2
    exit 1
  fi

  schedule_shutdown "$hours"
  show_status
}

main "$@"
