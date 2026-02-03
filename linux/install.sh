#!/usr/bin/env bash
set -euo pipefail

# Installs:
# - /etc/systemd/system/opencode.service (main server)
# - /etc/systemd/system/opencode-updater.{service,timer} (auto-updater)
# - /usr/local/bin/update-opencode.sh (updater script)
# - /etc/opencode/server_password (auth credential)
# - Creates service user "opencode" if missing

SERVICE_DST="/etc/systemd/system/opencode.service"
PASSDIR="/etc/opencode"
PASSFILE="$PASSDIR/server_password"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (sudo)." >&2
  exit 1
fi

# Find opencode binary - check common paths first, then PATH
# Handle sudo: get the invoking user's home directory
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

# If not found in common paths, try to find via which (using SUDO_USER's environment)
if [[ -z "$OPENCODE_BIN" ]]; then
  if [[ -n "${SUDO_USER:-}" ]]; then
    # Try to find in the original user's PATH
    OPENCODE_BIN=$(su - "$SUDO_USER" -c 'which opencode 2>/dev/null' || true)
  fi
  if [[ -z "$OPENCODE_BIN" ]]; then
    OPENCODE_BIN=$(which opencode 2>/dev/null || true)
  fi
fi

if [[ -z "$OPENCODE_BIN" || ! -x "$OPENCODE_BIN" ]]; then
  echo "ERROR: opencode not found." >&2
  echo "Install opencode first, then re-run this script." >&2
  echo "Checked: /usr/local/bin/opencode, /usr/bin/opencode, ~/.bun/bin/opencode, and PATH" >&2
  exit 1
fi

echo "Found opencode at: $OPENCODE_BIN"

# Determine service user and working directory
# If opencode is in a user's home directory, run as that user
SERVICE_USER="opencode"
SERVICE_HOME="/home/opencode"

if [[ "$OPENCODE_BIN" == /root/* || "$OPENCODE_BIN" == /root/.* ]]; then
  SERVICE_USER="root"
  SERVICE_HOME="/root"
  echo "Note: opencode is in /root - service will run as root"
elif [[ "$OPENCODE_BIN" == /home/*/.bun/* ]]; then
  # Extract username from path like /home/username/.bun/bin/opencode
  SERVICE_USER=$(echo "$OPENCODE_BIN" | cut -d'/' -f3)
  SERVICE_HOME="/home/$SERVICE_USER"
  echo "Note: opencode is in $SERVICE_USER's home - service will run as $SERVICE_USER"
fi

# Create service user if running as dedicated opencode user and user doesn't exist
if [[ "$SERVICE_USER" == "opencode" ]]; then
  if ! id -u opencode >/dev/null 2>&1; then
    useradd -r -m -s /usr/sbin/nologin opencode
  fi
fi

mkdir -p "$PASSDIR"
chmod 700 "$PASSDIR"

if [[ ! -f "$PASSFILE" ]]; then
  echo "Creating password at: $PASSFILE"
  umask 077
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 > "$PASSFILE"
  else
    python3 - <<'PY' > "$PASSFILE"
import secrets, base64
print(base64.b64encode(secrets.token_bytes(32)).decode())
PY
  fi
  chmod 600 "$PASSFILE"
else
  echo "Password already exists at: $PASSFILE"
fi

# Generate systemd service file with actual opencode path
# Adjust hardening based on whether we need home directory access
# opencode needs write access to: ~/.cache/opencode, ~/.local/share/opencode, ~/.config/opencode
if [[ "$SERVICE_USER" == "root" ]]; then
  # Running as root - need full access to /root for opencode data
  PROTECT_HOME="false"
  READ_WRITE_PATHS=""
elif [[ "$SERVICE_USER" == "opencode" ]]; then
  PROTECT_HOME="true"
  READ_WRITE_PATHS="ReadWritePaths=/home/opencode"
else
  # Running as a regular user who has opencode installed
  PROTECT_HOME="false"
  READ_WRITE_PATHS="ReadWritePaths=$SERVICE_HOME"
fi

cat > "$SERVICE_DST" <<EOF
[Unit]
Description=OpenCode Server
After=network-online.target
Wants=network-online.target

[Service]
User=$SERVICE_USER
WorkingDirectory=$SERVICE_HOME

# systemd credential injection
LoadCredential=opencode_password:/etc/opencode/server_password

ExecStart=/bin/sh -lc 'export OPENCODE_SERVER_PASSWORD="\$(cat "\$CREDENTIALS_DIRECTORY/opencode_password")"; exec $OPENCODE_BIN serve --hostname 0.0.0.0 --port 4096'

Restart=on-failure
RestartSec=2

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=$PROTECT_HOME
$READ_WRITE_PATHS

[Install]
WantedBy=multi-user.target
EOF

SCRIPT_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"
LINUX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATER_SERVICE_SRC="$LINUX_DIR/opencode-updater.service"
UPDATER_TIMER_SRC="$LINUX_DIR/opencode-updater.timer"
UPDATER_SCRIPT_DST="/usr/local/bin/update-opencode.sh"

cp "$SCRIPT_SRC_DIR/update-opencode.sh" "$UPDATER_SCRIPT_DST"
chmod +x "$UPDATER_SCRIPT_DST"

cp "$UPDATER_SERVICE_SRC" /etc/systemd/system/opencode-updater.service
cp "$UPDATER_TIMER_SRC" /etc/systemd/system/opencode-updater.timer

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
