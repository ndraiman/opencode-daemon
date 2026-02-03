# opencode-persistent

Run **OpenCode Server** persistently on:
- macOS (launchd)
- Linux (systemd)

Inspired by thdxr’s post:
- https://x.com/thdxr/status/2017691649384620057

Designed for private access via **Tailscale/WireGuard/SSH**.

## Layout
- `macos/` — launchd LaunchAgent plist + install script
- `linux/` — systemd unit + install script
- `scripts/` — shared update script

## Quick start

### macOS
```bash
./macos/install.sh
```

### Linux
```bash
sudo ./linux/install.sh
```

## Auto-Updates

The install scripts set up automatic updates that:
- Run daily at 3am
- Check if any OpenCode sessions are active via `/session/status` API
- Wait up to 1 hour (retrying every 5 min) if sessions are busy
- Update only when idle, then restart the service

**Logs:**
- macOS: `~/Library/Logs/opencode-updater.log`
- Linux: `journalctl -u opencode-updater.service`

**Manual trigger:**
```bash
# macOS
~/.local/bin/update-opencode.sh

# Linux
sudo /usr/local/bin/update-opencode.sh
```

## Notes
- Both setups use a password file on disk (chmod 600) and inject it into the process.
- Default listen: `0.0.0.0:4096` (fine on a private network). If you prefer, change to `127.0.0.1` and use an SSH tunnel.
