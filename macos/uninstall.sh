#!/usr/bin/env bash
set -euo pipefail

LABEL="com.opencode.server"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
PASSFILE="$HOME/.config/opencode/credentials/server_password"
LOGFILE="$HOME/Library/Logs/opencode-server.log"
ERRLOGFILE="$HOME/Library/Logs/opencode-server.err.log"

echo "Stopping and unloading LaunchAgent..."
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

if [[ -f "$PLIST_DST" ]]; then
  rm "$PLIST_DST"
  echo "Removed: $PLIST_DST"
else
  echo "Not found: $PLIST_DST"
fi

read -p "Remove password file? ($PASSFILE) [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  rm -f "$PASSFILE"
  echo "Removed: $PASSFILE"
fi

read -p "Remove log files? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  rm -f "$LOGFILE" "$ERRLOGFILE"
  echo "Removed log files"
fi

echo "Uninstall complete."
