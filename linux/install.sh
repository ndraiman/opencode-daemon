#!/usr/bin/env bash
set -euo pipefail

# Installs:
# - /etc/systemd/system/opencode.service
# - password at /etc/opencode/server_password
# - creates service user "opencode" if missing

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

systemctl daemon-reload
systemctl enable --now opencode.service
systemctl status --no-pager opencode.service || true

echo "Installed systemd unit: $SERVICE_DST"
echo "Logs: journalctl -u opencode.service -f"
echo "Connect via: http://<server-tailscale-or-wg-ip>:4096"
