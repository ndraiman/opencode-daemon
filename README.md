# opencode-persistent

Run OpenCode Server persistently on:
- macOS (launchd)
- Linux (systemd)

Designed for private access via Tailscale/WireGuard/SSH.

## Layout
- `macos/` — launchd LaunchAgent plist + install script
- `linux/` — systemd unit + install script

## Quick start

### macOS
```bash
./macos/install.sh
```

### Linux
```bash
sudo ./linux/install.sh
```

## Notes
- Both setups use a password file on disk (chmod 600) and inject it into the process.
- Default listen: `0.0.0.0:4096` (safe if firewalled / only on private network). Adjust as needed.
