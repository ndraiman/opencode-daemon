#!/usr/bin/env bash
set -euo pipefail

# OpenCode Daemon Restart
# Self-contained - works with: curl -fsSL <url> | bash

case "$(uname -s)" in
  Darwin)
    launchctl kickstart -k "gui/$(id -u)/com.opencode.server"
    echo "Restarted com.opencode.server"
    ;;
  Linux)
    if [[ $EUID -ne 0 ]]; then
      echo "ERROR: run as root (sudo)." >&2
      exit 1
    fi
    systemctl restart opencode.service
    echo "Restarted opencode.service"
    ;;
  *)
    echo "Unsupported platform: $(uname -s)" >&2
    exit 1
    ;;
esac
