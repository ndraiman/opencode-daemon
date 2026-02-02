#!/usr/bin/env bash
set -euo pipefail

LABEL="com.opencode.server"
PLIST_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_SRC="$PLIST_SRC_DIR/$LABEL.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
PASSFILE="$HOME/.config/opencode/credentials/server_password"

mkdir -p "$(dirname "$PASSFILE")"

if [[ ! -f "$PASSFILE" ]]; then
  echo "Creating password at: $PASSFILE"
  umask 077
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 > "$PASSFILE"
  else
    # fallback (less ideal)
    python3 - <<'PY'
import secrets, base64
print(base64.b64encode(secrets.token_bytes(32)).decode())
PY
  fi
  chmod 600 "$PASSFILE"
else
  echo "Password already exists at: $PASSFILE"
fi

# sanity checks
if [[ ! -x "$HOME/.bun/bin/opencode" ]]; then
  echo "ERROR: $HOME/.bun/bin/opencode not found/executable. Install opencode (bun) first." >&2
  exit 1
fi

mkdir -p "$(dirname "$PLIST_DST")"

# Generate plist with user-specific paths
cat > "$PLIST_DST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
      <string>/bin/sh</string>
      <string>-c</string>
      <string>exec $HOME/.bun/bin/bun $HOME/.bun/bin/opencode serve --hostname 0.0.0.0 --port 4096</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>WorkingDirectory</key>
    <string>$HOME</string>

    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/opencode-server.log</string>

    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/opencode-server.err.log</string>
  </dict>
</plist>
EOF

# reload
launchctl unload "$PLIST_DST" >/dev/null 2>&1 || true
launchctl load "$PLIST_DST"
launchctl kickstart -k "gui/$(id -u)/$LABEL" || true

echo "Installed LaunchAgent: $PLIST_DST"
echo "Logs:"
echo "  $HOME/Library/Logs/opencode-server.log"
echo "  $HOME/Library/Logs/opencode-server.err.log"
echo "Connect via: http://<your-tailscale-or-wg-ip>:4096"
