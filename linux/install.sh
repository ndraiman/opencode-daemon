#!/usr/bin/env bash
set -euo pipefail

# Installs:
# - /etc/systemd/system/opencode.service (main server)
# - /etc/systemd/system/opencode-updater.{service,timer} (auto-updater)
# - /usr/local/bin/update-opencode.sh (updater script)
# - /etc/opencode/server_password (auth credential)
# - Creates service user "opencode" if missing

SERVICE_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_SRC="$SERVICE_SRC_DIR/opencode.service"
SERVICE_DST="/etc/systemd/system/opencode.service"
PASSDIR="/etc/opencode"
PASSFILE="$PASSDIR/server_password"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (sudo)." >&2
  exit 1
fi

# Create service user if missing
if ! id -u opencode >/dev/null 2>&1; then
  useradd -r -m -s /usr/sbin/nologin opencode
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

# Ensure opencode binary exists
if [[ ! -x /usr/local/bin/opencode && ! -x /usr/bin/opencode ]]; then
  echo "ERROR: opencode not found at /usr/local/bin/opencode or /usr/bin/opencode." >&2
  echo "Install it, then re-run this script. If it's elsewhere, edit linux/opencode.service ExecStart path." >&2
  exit 1
fi

# If it's in /usr/bin, patch the unit on the fly (minimal convenience)
TMP_UNIT="$SERVICE_SRC"
if [[ ! -x /usr/local/bin/opencode && -x /usr/bin/opencode ]]; then
  TMP_UNIT="/tmp/opencode.service"
  sed 's#/usr/local/bin/opencode#/usr/bin/opencode#g' "$SERVICE_SRC" > "$TMP_UNIT"
fi

cp "$TMP_UNIT" "$SERVICE_DST"

SCRIPT_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"
UPDATER_SERVICE_SRC="$SERVICE_SRC_DIR/opencode-updater.service"
UPDATER_TIMER_SRC="$SERVICE_SRC_DIR/opencode-updater.timer"
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
