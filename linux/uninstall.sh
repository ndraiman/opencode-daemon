#!/usr/bin/env bash
set -euo pipefail

SERVICE_DST="/etc/systemd/system/opencode.service"
UPDATER_SERVICE="/etc/systemd/system/opencode-updater.service"
UPDATER_TIMER="/etc/systemd/system/opencode-updater.timer"
UPDATER_SCRIPT="/usr/local/bin/update-opencode.sh"
PASSDIR="/etc/opencode"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (sudo)." >&2
  exit 1
fi

echo "Stopping and disabling services..."
systemctl stop opencode.service 2>/dev/null || true
systemctl disable opencode.service 2>/dev/null || true
systemctl stop opencode-updater.timer 2>/dev/null || true
systemctl disable opencode-updater.timer 2>/dev/null || true

for unit in "$SERVICE_DST" "$UPDATER_SERVICE" "$UPDATER_TIMER"; do
  if [[ -f "$unit" ]]; then
    rm "$unit"
    echo "Removed: $unit"
  fi
done

if [[ -f "$UPDATER_SCRIPT" ]]; then
  rm "$UPDATER_SCRIPT"
  echo "Removed: $UPDATER_SCRIPT"
fi

systemctl daemon-reload

read -p "Remove password directory? ($PASSDIR) [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  rm -rf "$PASSDIR"
  echo "Removed: $PASSDIR"
fi

read -p "Remove opencode service user? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  userdel opencode 2>/dev/null || true
  echo "Removed user: opencode"
fi

echo "Uninstall complete."
