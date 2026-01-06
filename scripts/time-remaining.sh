#!/usr/bin/env bash
# Show auto-shutdown configuration and time remaining on the Jenkins host.
# Usage: ./scripts/time-remaining.sh
# Notes:
#   - Run on the Jenkins server (not the management host).
#   - Requires sudo for reading the scheduled shutdown file.

set -euo pipefail

echo "Configured auto-shutdown hours (if set):"
if [[ -f /etc/jenkins/auto_shutdown_hours ]]; then
  cat /etc/jenkins/auto_shutdown_hours
else
  echo "Not set"
fi

echo
echo "Scheduled shutdown status:"
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
