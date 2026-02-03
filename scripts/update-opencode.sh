#!/usr/bin/env bash
set -euo pipefail

# OpenCode auto-updater with idle detection
# Checks /session/status API, waits for idle, then updates

# Configuration
PORT="${OPENCODE_PORT:-4096}"
HOST="${OPENCODE_HOST:-127.0.0.1}"
MAX_RETRIES=12          # 12 retries × 5 min = 1 hour max wait
RETRY_INTERVAL=300      # 5 minutes between retries

# Detect OS and set paths
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
# Pipe 'y' for non-interactive upgrade confirmation.
# opencode uses @clack/prompts which handles 'y'/'n' as yes/no shortcuts even when stdin is piped.
# See: https://github.com/bombshell-dev/clack/blob/main/packages/core/src/prompts/prompt.ts
UPDATE_CMD="echo y | $OPENCODE_BIN upgrade"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Build auth header if password exists
AUTH_HEADER=""
if [[ -f "$PASSFILE" ]]; then
  PASS=$(cat "$PASSFILE")
  AUTH_HEADER="Authorization: Basic $(echo -n "opencode:$PASS" | base64)"
fi

# Check if any sessions are active
# Returns: 0 if idle, 1 if busy, 2 if error
check_idle() {
  local body
  local status_code
  local curl_args=(-s -w "HTTP_CODE:%{http_code}" --max-time 10)
  
  if [[ -n "$AUTH_HEADER" ]]; then
    curl_args+=(-H "$AUTH_HEADER")
  fi
  curl_args+=("http://$HOST:$PORT/session/status")

  local response
  response=$(curl "${curl_args[@]}" 2>/dev/null) || {
    log "ERROR: Failed to connect to OpenCode server"
    return 2
  }

  status_code="${response##*HTTP_CODE:}"
  body="${response%HTTP_CODE:*}"

  if [[ "$status_code" != "200" ]]; then
    log "ERROR: API returned status $status_code"
    return 2
  fi

  if ! command -v jq &>/dev/null; then
    log "WARNING: jq not installed, falling back to grep"
    if echo "$body" | grep -qE '"status"\s*:\s*"(running|pending|streaming)"'; then
      log "Sessions are active (grep detection)"
      return 1
    fi
  else
    local active_count
    active_count=$(echo "$body" | jq '[.[] | select(.status != "idle" and .status != "completed")] | length' 2>/dev/null || echo "0")
    
    if [[ "$active_count" -gt 0 ]]; then
      log "Found $active_count active session(s)"
      return 1
    fi
  fi

  log "Server is idle"
  return 0
}

# Get current installed version
get_current_version() {
  if [[ -x "$OPENCODE_BIN" ]]; then
    "$OPENCODE_BIN" --version 2>/dev/null | head -1 || echo "unknown"
  else
    echo "not-installed"
  fi
}

# Main update logic
main() {
  log "Starting OpenCode update check"
  
  local current_version
  current_version=$(get_current_version)
  log "Current version: $current_version"

  # Wait for idle with retries
  local attempt=0
  while [[ $attempt -lt $MAX_RETRIES ]]; do
    if check_idle; then
      break
    fi
    
    local ret=$?
    if [[ $ret -eq 2 ]]; then
      # Server error - maybe not running, proceed with update
      log "Server not responding, proceeding with update"
      break
    fi

    attempt=$((attempt + 1))
    if [[ $attempt -lt $MAX_RETRIES ]]; then
      log "Waiting ${RETRY_INTERVAL}s before retry ($attempt/$MAX_RETRIES)"
      sleep $RETRY_INTERVAL
    fi
  done

  if [[ $attempt -ge $MAX_RETRIES ]]; then
    log "Max retries reached, server still busy. Skipping update."
    exit 0
  fi

  # Perform update
  log "Running update: $UPDATE_CMD"
  if eval "$UPDATE_CMD"; then
    local new_version
    new_version=$(get_current_version)
    
    if [[ "$new_version" != "$current_version" ]]; then
      log "Updated: $current_version -> $new_version"
      log "Restarting service: $RESTART_CMD"
      eval "$RESTART_CMD"
    else
      log "Already at latest version: $current_version"
    fi
  else
    log "ERROR: Update command failed"
    exit 1
  fi

  log "Update check complete"
}

main "$@"
