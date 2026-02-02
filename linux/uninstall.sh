#!/usr/bin/env bash
set -euo pipefail

SERVICE_DST="/etc/systemd/system/opencode.service"
PASSDIR="/etc/opencode"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (sudo)." >&2
  exit 1
fi

echo "Stopping and disabling service..."
systemctl stop opencode.service 2>/dev/null || true
systemctl disable opencode.service 2>/dev/null || true

if [[ -f "$SERVICE_DST" ]]; then
  rm "$SERVICE_DST"
  systemctl daemon-reload
  echo "Removed: $SERVICE_DST"
else
  echo "Not found: $SERVICE_DST"
fi

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
