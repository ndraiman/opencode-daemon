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
- Default listen: `0.0.0.0:4096` (fine on a private network). If you prefer, change to `127.0.0.1` and use an SSH tunnel.
