#!/usr/bin/env bash
set -euo pipefail

# OpenCode Daemon Uninstaller
# Self-contained - works with: curl -fsSL <url> | bash

# Helper for interactive prompts - defaults to 'n' in non-interactive mode
ask_yes_no() {
  local prompt="$1"
  if [[ -t 0 ]]; then
    read -p "$prompt [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
  else
    echo "$prompt [y/N] n (non-interactive, skipping)"
    return 1
  fi
}

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

  for f in "$PLIST_DST" "$UPDATER_PLIST_DST" "$SCRIPT_DST"; do
    if [[ -f "$f" ]]; then
      rm "$f"
      echo "Removed: $f"
    fi
  done

  if ask_yes_no "Remove password file? ($PASSFILE)"; then
    rm -f "$PASSFILE"
    echo "Removed: $PASSFILE"
  fi

  if ask_yes_no "Remove log files?"; then
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

  for f in "$SERVICE_DST" "$UPDATER_SERVICE" "$UPDATER_TIMER" "$UPDATER_SCRIPT"; do
    if [[ -f "$f" ]]; then
      rm "$f"
      echo "Removed: $f"
    fi
  done

  systemctl daemon-reload

  if ask_yes_no "Remove password directory? ($PASSDIR)"; then
    rm -rf "$PASSDIR"
    echo "Removed: $PASSDIR"
  fi

  if ask_yes_no "Remove opencode service user?"; then
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
