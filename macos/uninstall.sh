#!/usr/bin/env bash
set -euo pipefail

LABEL="com.opencode.server"
UPDATER_LABEL="com.opencode.updater"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
UPDATER_PLIST_DST="$HOME/Library/LaunchAgents/$UPDATER_LABEL.plist"
PASSFILE="$HOME/.config/opencode/credentials/server_password"
SCRIPT_DST="$HOME/.local/bin/update-opencode.sh"

echo "Stopping and unloading LaunchAgents..."
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl unload "$UPDATER_PLIST_DST" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$UPDATER_LABEL" 2>/dev/null || true

for plist in "$PLIST_DST" "$UPDATER_PLIST_DST"; do
  if [[ -f "$plist" ]]; then
    rm "$plist"
    echo "Removed: $plist"
  fi
done

if [[ -f "$SCRIPT_DST" ]]; then
  rm "$SCRIPT_DST"
  echo "Removed: $SCRIPT_DST"
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
  rm -f "$HOME/Library/Logs/opencode-server.log" \
        "$HOME/Library/Logs/opencode-server.err.log" \
        "$HOME/Library/Logs/opencode-updater.log" \
        "$HOME/Library/Logs/opencode-updater.err.log"
  echo "Removed log files"
fi

echo "Uninstall complete."
