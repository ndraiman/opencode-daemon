#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
  Darwin)
    echo "Detected: macOS"
    exec "$SCRIPT_DIR/macos/install.sh" "$@"
    ;;
  Linux)
    echo "Detected: Linux"
    exec "$SCRIPT_DIR/linux/install.sh" "$@"
    ;;
  *)
    echo "Unsupported platform: $(uname -s)" >&2
    exit 1
    ;;
esac
