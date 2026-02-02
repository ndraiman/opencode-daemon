#!/usr/bin/env bash
set -euo pipefail

launchctl kickstart -k "gui/$(id -u)/com.opencode.server"
echo "Restarted com.opencode.server"
