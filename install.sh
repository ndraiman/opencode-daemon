#!/usr/bin/env bash
set -euo pipefail

# OpenCode Daemon Installer
# Self-contained - works with: curl -fsSL <url> | bash

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32
  else
    python3 -c "import secrets,base64; print(base64.b64encode(secrets.token_bytes(32)).decode())"
  fi
}

ensure_password() {
  local passfile="$1"
  mkdir -p "$(dirname "$passfile")"
  if [[ -f "$passfile" ]]; then
    echo "Password already exists at: $passfile"
  else
    echo "Creating password at: $passfile"
    umask 077
    generate_password > "$passfile"
    chmod 600 "$passfile"
  fi
}

write_updater_script() {
  local dst="$1"
  cat > "$dst" <<'UPDATER_EOF'
#!/usr/bin/env bash
set -euo pipefail

# OpenCode auto-updater with idle detection

PORT="${OPENCODE_PORT:-4096}"
HOST="${OPENCODE_HOST:-127.0.0.1}"
MAX_RETRIES=12
RETRY_INTERVAL=300

case "$(uname -s)" in
  Darwin)
    PASSFILE="$HOME/.config/opencode/credentials/server_password"
    RESTART_CMD="launchctl kickstart -k gui/$(id -u)/com.opencode.server"
    ;;
  Linux)
    PASSFILE="/etc/opencode/server_password"
    RESTART_CMD="systemctl restart opencode.service"
    ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

OPENCODE_BIN=$(command -v opencode 2>/dev/null || echo "$HOME/.bun/bin/opencode")
UPDATE_CMD="echo y | $OPENCODE_BIN upgrade"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

AUTH_HEADER=""
if [[ -f "$PASSFILE" ]]; then
  PASS=$(cat "$PASSFILE")
  AUTH_HEADER="Authorization: Basic $(echo -n "opencode:$PASS" | base64)"
fi

check_idle() {
  local curl_args=(-s -w "HTTP_CODE:%{http_code}" --max-time 10)
  [[ -n "$AUTH_HEADER" ]] && curl_args+=(-H "$AUTH_HEADER")
  curl_args+=("http://$HOST:$PORT/session/status")

  local response
  response=$(curl "${curl_args[@]}" 2>/dev/null) || { log "ERROR: Failed to connect"; return 2; }

  local status_code="${response##*HTTP_CODE:}"
  local body="${response%HTTP_CODE:*}"

  [[ "$status_code" != "200" ]] && { log "ERROR: API returned $status_code"; return 2; }

  if ! command -v jq &>/dev/null; then
    echo "$body" | grep -qE '"status"\s*:\s*"(running|pending|streaming)"' && return 1
  else
    local active=$(echo "$body" | jq '[.[] | select(.status != "idle" and .status != "completed")] | length' 2>/dev/null || echo "0")
    [[ "$active" -gt 0 ]] && { log "Found $active active session(s)"; return 1; }
  fi
  log "Server is idle"
  return 0
}

get_version() {
  [[ -x "$OPENCODE_BIN" ]] && "$OPENCODE_BIN" --version 2>/dev/null | head -1 || echo "unknown"
}

main() {
  log "Starting OpenCode update check"
  local current=$(get_version)
  log "Current version: $current"

  local attempt=0
  while [[ $attempt -lt $MAX_RETRIES ]]; do
    check_idle && break
    local ret=$?
    [[ $ret -eq 2 ]] && { log "Server not responding, proceeding"; break; }
    attempt=$((attempt + 1))
    [[ $attempt -lt $MAX_RETRIES ]] && { log "Waiting ${RETRY_INTERVAL}s ($attempt/$MAX_RETRIES)"; sleep $RETRY_INTERVAL; }
  done

  [[ $attempt -ge $MAX_RETRIES ]] && { log "Max retries, skipping update"; exit 0; }

  log "Running update: $UPDATE_CMD"
  if eval "$UPDATE_CMD"; then
    local new=$(get_version)
    if [[ "$new" != "$current" ]]; then
      log "Updated: $current -> $new"
      log "Restarting: $RESTART_CMD"
      eval "$RESTART_CMD"
    else
      log "Already at latest: $current"
    fi
  else
    log "ERROR: Update failed"
    exit 1
  fi
  log "Update check complete"
}

main "$@"
UPDATER_EOF
}

install_macos() {
  LABEL="com.opencode.server"
  PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
  PASSFILE="$HOME/.config/opencode/credentials/server_password"
  UPDATER_LABEL="com.opencode.updater"
  UPDATER_PLIST_DST="$HOME/Library/LaunchAgents/$UPDATER_LABEL.plist"
  SCRIPT_DST="$HOME/.local/bin/update-opencode.sh"

  ensure_password "$PASSFILE"

  # Check opencode exists
  if [[ ! -x "$HOME/.bun/bin/opencode" ]]; then
    echo "ERROR: $HOME/.bun/bin/opencode not found. Install opencode first (bun install -g opencode)." >&2
    exit 1
  fi

  mkdir -p "$(dirname "$PLIST_DST")"

  # Generate LaunchAgent plist
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
      <string>export OPENCODE_SERVER_PASSWORD="\$(cat $PASSFILE)"; exec $HOME/.bun/bin/bun $HOME/.bun/bin/opencode serve --hostname 0.0.0.0 --port 4096</string>
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

  launchctl unload "$PLIST_DST" >/dev/null 2>&1 || true
  launchctl load "$PLIST_DST"
  launchctl kickstart -k "gui/$(id -u)/$LABEL" || true

  echo "Installed LaunchAgent: $PLIST_DST"

  # Install updater script
  mkdir -p "$(dirname "$SCRIPT_DST")"
  write_updater_script "$SCRIPT_DST"
  chmod +x "$SCRIPT_DST"

  # Generate updater LaunchAgent
  cat > "$UPDATER_PLIST_DST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>$UPDATER_LABEL</string>

    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>$SCRIPT_DST</string>
    </array>

    <key>StartCalendarInterval</key>
    <dict>
      <key>Hour</key>
      <integer>3</integer>
      <key>Minute</key>
      <integer>0</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/opencode-updater.log</string>

    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/opencode-updater.err.log</string>
  </dict>
</plist>
EOF

  launchctl unload "$UPDATER_PLIST_DST" >/dev/null 2>&1 || true
  launchctl load "$UPDATER_PLIST_DST"

  echo "Installed Updater LaunchAgent: $UPDATER_PLIST_DST"
  echo ""
  echo "Password: $PASSFILE"
  echo ""
  echo "Logs:"
  echo "  Server: $HOME/Library/Logs/opencode-server.log"
  echo "  Updater: $HOME/Library/Logs/opencode-updater.log"
  echo ""
  echo "Auto-updates daily at 3am (waits for idle sessions)"
  echo "Connect via: http://<your-tailscale-or-wg-ip>:4096"
}

install_linux() {
  SERVICE_DST="/etc/systemd/system/opencode.service"
  PASSDIR="/etc/opencode"
  PASSFILE="$PASSDIR/server_password"
  UPDATER_SCRIPT_DST="/usr/local/bin/update-opencode.sh"

  if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run as root (sudo)." >&2
    exit 1
  fi

  # Find opencode binary
  if [[ -n "${SUDO_USER:-}" ]]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  else
    USER_HOME="$HOME"
  fi

  OPENCODE_BIN=""
  for candidate in /usr/local/bin/opencode /usr/bin/opencode "$USER_HOME/.bun/bin/opencode"; do
    if [[ -x "$candidate" ]]; then
      OPENCODE_BIN="$candidate"
      break
    fi
  done

  if [[ -z "$OPENCODE_BIN" ]]; then
    if [[ -n "${SUDO_USER:-}" ]]; then
      OPENCODE_BIN=$(su - "$SUDO_USER" -c 'which opencode 2>/dev/null' || true)
    fi
    if [[ -z "$OPENCODE_BIN" ]]; then
      OPENCODE_BIN=$(which opencode 2>/dev/null || true)
    fi
  fi

  if [[ -z "$OPENCODE_BIN" || ! -x "$OPENCODE_BIN" ]]; then
    echo "ERROR: opencode not found. Install opencode first." >&2
    exit 1
  fi

  echo "Found opencode at: $OPENCODE_BIN"

  # Determine service user
  SERVICE_USER="opencode"
  SERVICE_HOME="/home/opencode"

  if [[ "$OPENCODE_BIN" == /root/* || "$OPENCODE_BIN" == /root/.* ]]; then
    SERVICE_USER="root"
    SERVICE_HOME="/root"
  elif [[ "$OPENCODE_BIN" == /home/*/.bun/* ]]; then
    SERVICE_USER=$(echo "$OPENCODE_BIN" | cut -d'/' -f3)
    SERVICE_HOME="/home/$SERVICE_USER"
  fi

  if [[ "$SERVICE_USER" == "opencode" ]]; then
    if ! id -u opencode >/dev/null 2>&1; then
      useradd -r -m -s /usr/sbin/nologin opencode
    fi
  fi

  mkdir -p "$PASSDIR"
  chmod 700 "$PASSDIR"
  ensure_password "$PASSFILE"

  # Hardening settings
  if [[ "$SERVICE_USER" == "root" ]]; then
    PROTECT_HOME="false"
    READ_WRITE_PATHS=""
  elif [[ "$SERVICE_USER" == "opencode" ]]; then
    PROTECT_HOME="true"
    READ_WRITE_PATHS="ReadWritePaths=/home/opencode"
  else
    PROTECT_HOME="false"
    READ_WRITE_PATHS="ReadWritePaths=$SERVICE_HOME"
  fi

  # Generate systemd service
  cat > "$SERVICE_DST" <<EOF
[Unit]
Description=OpenCode Server
After=network-online.target
Wants=network-online.target

[Service]
User=$SERVICE_USER
WorkingDirectory=$SERVICE_HOME

LoadCredential=opencode_password:/etc/opencode/server_password

ExecStart=/bin/sh -lc 'export OPENCODE_SERVER_PASSWORD="\$(cat "\$CREDENTIALS_DIRECTORY/opencode_password")"; exec $OPENCODE_BIN serve --hostname 0.0.0.0 --port 4096'

Restart=on-failure
RestartSec=2

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=$PROTECT_HOME
$READ_WRITE_PATHS

[Install]
WantedBy=multi-user.target
EOF

  # Install updater script
  write_updater_script "$UPDATER_SCRIPT_DST"
  chmod +x "$UPDATER_SCRIPT_DST"

  # Generate updater service
  cat > /etc/systemd/system/opencode-updater.service <<EOF
[Unit]
Description=OpenCode Auto-Updater
After=network-online.target opencode.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-opencode.sh

[Install]
WantedBy=multi-user.target
EOF

  # Generate updater timer
  cat > /etc/systemd/system/opencode-updater.timer <<EOF
[Unit]
Description=OpenCode Daily Update Check
After=network-online.target

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now opencode.service
  systemctl enable --now opencode-updater.timer
  systemctl status --no-pager opencode.service || true

  echo ""
  echo "Installed systemd units:"
  echo "  Service: $SERVICE_DST"
  echo "  Updater: /etc/systemd/system/opencode-updater.{service,timer}"
  echo ""
  echo "Logs:"
  echo "  Server:  journalctl -u opencode.service -f"
  echo "  Updater: journalctl -u opencode-updater.service"
  echo ""
  echo "Auto-updates daily at 3am (waits for idle sessions)"
  echo "Connect via: http://<server-tailscale-or-wg-ip>:4096"
}

# Main entry point
case "$(uname -s)" in
  Darwin)
    echo "Detected: macOS"
    install_macos
    ;;
  Linux)
    echo "Detected: Linux"
    install_linux
    ;;
  *)
    echo "Unsupported platform: $(uname -s)" >&2
    exit 1
    ;;
esac
