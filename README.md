# opencode-persistent

Run **OpenCode Server** persistently on macOS (launchd) and Linux (systemd).

Designed for private access via **Tailscale/WireGuard/SSH**.

Inspired by [thdxr's post](https://x.com/thdxr/status/2017691649384620057).

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Uninstall](#uninstall)
- [Restart](#restart)
- [Auto-Updates](#auto-updates)
- [Configuration](#configuration)
- [Logs](#logs)
- [Project Layout](#project-layout)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Install OpenCode before running the install script:

```bash
bun install -g opencode
```

Verify installation:
```bash
opencode --version
```

---

## Quick Start

The universal installer auto-detects your OS:

```bash
./install.sh
```

Or use platform-specific scripts directly:

| Platform | Command |
|----------|---------|
| macOS    | `./macos/install.sh` |
| Linux    | `sudo ./linux/install.sh` |

After install, connect via: `http://<your-tailscale-or-wg-ip>:4096`

---

## Uninstall

```bash
./uninstall.sh
```

Or platform-specific:

| Platform | Command |
|----------|---------|
| macOS    | `./macos/uninstall.sh` |
| Linux    | `sudo ./linux/uninstall.sh` |

You'll be prompted to optionally remove password files and logs.

---

## Restart

```bash
./restart.sh
```

Or platform-specific:

| Platform | Command |
|----------|---------|
| macOS    | `./macos/restart.sh` |
| Linux    | `sudo ./linux/restart.sh` |

---

## Auto-Updates

The install scripts set up automatic updates that:

- Run daily at 3am
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

## Project Layout

```
.
├── install.sh          # Universal installer (auto-detects OS)
├── uninstall.sh        # Universal uninstaller
├── restart.sh          # Universal restart
├── macos/
│   ├── install.sh      # macOS LaunchAgent setup
│   ├── uninstall.sh    # macOS cleanup
│   └── restart.sh      # macOS service restart
├── linux/
│   ├── install.sh      # systemd service setup
│   ├── uninstall.sh    # Linux cleanup
│   ├── restart.sh      # Linux service restart
│   ├── opencode.service
│   └── opencode-updater.service
└── scripts/
    └── update-opencode.sh  # Shared auto-updater script
```

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
