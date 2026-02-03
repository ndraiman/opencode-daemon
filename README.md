# opencode-daemon

Keep **OpenCode Server** running 24/7 on your Mac or Linux machine.

Access it remotely from anywhere via **Tailscale**, **WireGuard**, or **SSH**.

Inspired by [thdxr's post](https://x.com/thdxr/status/2017691649384620057).

---

## Quick Start

**Prerequisites:** Install OpenCode first:
```bash
bun install -g opencode
```

**Install:**
```bash
# macOS
curl -fsSL https://raw.githubusercontent.com/ndraiman/opencode-daemon/main/install.sh | bash

# Linux (requires sudo)
curl -fsSL https://raw.githubusercontent.com/ndraiman/opencode-daemon/main/install.sh | sudo bash
```

**Connect:** `http://<your-tailscale-or-wg-ip>:4096`

---

## Uninstall

```bash
# macOS
curl -fsSL https://raw.githubusercontent.com/ndraiman/opencode-daemon/main/uninstall.sh | bash

# Linux
curl -fsSL https://raw.githubusercontent.com/ndraiman/opencode-daemon/main/uninstall.sh | sudo bash
```

You'll be prompted to optionally remove password files and logs.

---

## Restart

```bash
# macOS
curl -fsSL https://raw.githubusercontent.com/ndraiman/opencode-daemon/main/restart.sh | bash

# Linux
curl -fsSL https://raw.githubusercontent.com/ndraiman/opencode-daemon/main/restart.sh | sudo bash
```

---

## Auto-Updates

Automatic updates run daily at 3am:
- Check if sessions are active via `/session/status` API
- Wait up to 1 hour (retrying every 5 min) if busy
- Update only when idle, then restart the service

**Manual trigger:**
```bash
# macOS
~/.local/bin/update-opencode.sh

# Linux
sudo /usr/local/bin/update-opencode.sh
```

---

## Configuration

### Password Files

Generated automatically on first install (chmod 600):

| Platform | Location |
|----------|----------|
| macOS    | `~/.config/opencode/credentials/server_password` |
| Linux    | `/etc/opencode/server_password` |

### Network

Default: `0.0.0.0:4096` (suitable for private networks).

For localhost-only access, edit the plist/service file to use `127.0.0.1` and connect via SSH tunnel.

### Updater Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCODE_PORT` | `4096` | Server port for idle check |
| `OPENCODE_HOST` | `127.0.0.1` | Server host for idle check |

---

## Logs

### Server Logs

| Platform | Location |
|----------|----------|
| macOS    | `~/Library/Logs/opencode-server.log` |
| macOS (stderr) | `~/Library/Logs/opencode-server.err.log` |
| Linux    | `journalctl -u opencode.service -f` |

### Updater Logs

| Platform | Location |
|----------|----------|
| macOS    | `~/Library/Logs/opencode-updater.log` |
| Linux    | `journalctl -u opencode-updater.service` |

---

## Troubleshooting

### Service not starting

Check logs for errors:
```bash
# macOS
cat ~/Library/Logs/opencode-server.err.log

# Linux
journalctl -u opencode.service -n 50
```

### OpenCode binary not found

Ensure `opencode` is installed and in your PATH:
```bash
which opencode
# Should return: ~/.bun/bin/opencode or /usr/local/bin/opencode
```

### Can't connect remotely

1. Verify the service is running:
   ```bash
   # macOS
   launchctl list | grep opencode

   # Linux
   systemctl status opencode.service
   ```

2. Check firewall allows port 4096

3. Ensure you're connecting via Tailscale/WireGuard IP, not public IP

### Updates not running

Check if the timer/agent is loaded:
```bash
# macOS
launchctl list | grep updater

# Linux
systemctl status opencode-updater.timer
```
