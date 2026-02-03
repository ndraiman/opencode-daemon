#!/usr/bin/env bash
set -euo pipefail

# OpenCode Always-On Uninstaller
# Self-contained - works with: curl -fsSL <url> | bash

uninstall_macos() {
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
}

uninstall_linux() {
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
}

# Main entry point
case "$(uname -s)" in
  Darwin)
    echo "Detected: macOS"
    uninstall_macos
    ;;
  Linux)
    echo "Detected: Linux"
    uninstall_linux
    ;;
  *)
    echo "Unsupported platform: $(uname -s)" >&2
    exit 1
    ;;
esac
