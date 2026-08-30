# aigw (Mac splice)

A minimal TCP reverse proxy that runs as a macOS system daemon, forwarding
`127.0.0.1:$PORT` → `$HOST:$PORT` (the AI Gateway bind address from `.env`).

On the Mac this crate is checked out at `~/Workspace/me/aigw`. In a full aigw
clone it lives in `mac-aigw/`.

---

## Prerequisites

- Rust toolchain (`rustup` / `cargo`): https://rustup.rs
- macOS (tested on macOS 13+)
- `sudo` access on the laptop for daemon installation

---

## Build

```bash
cd ~/Workspace/me/aigw
# or, from a full aigw clone:
# cd mac-aigw
cargo build --release
```

The binary will be at `target/release/aigw`.

---

## Install as a system daemon

Edit `UPSTREAM_ADDR` in `com.msmullin.aigw.plist` to the gateway `HOST:PORT`
from aigw `.env` before copying the plist into place.

```bash
# 1. Copy binary to a system path
sudo cp target/release/aigw /usr/local/bin/aigw
sudo chmod 755 /usr/local/bin/aigw

# 2. Install the launchd plist
sudo cp com.msmullin.aigw.plist /Library/LaunchDaemons/com.msmullin.aigw.plist
sudo chown root:wheel /Library/LaunchDaemons/com.msmullin.aigw.plist
sudo chmod 644 /Library/LaunchDaemons/com.msmullin.aigw.plist

# 3. Load and start the daemon
sudo launchctl load /Library/LaunchDaemons/com.msmullin.aigw.plist
```

If you previously installed `com.msmullin.infer`, unload and remove it first:

```bash
sudo launchctl unload /Library/LaunchDaemons/com.msmullin.infer.plist
sudo rm /Library/LaunchDaemons/com.msmullin.infer.plist
sudo rm /usr/local/bin/infer
```

---

## Verify it's running

```bash
# Check daemon status
sudo launchctl list | grep aigw

# Check it's listening
netstat -an | grep 1234

# Test the endpoint
curl http://127.0.0.1:1234/v1/models
```

Logs are written to `/var/log/aigw.log`.

---

## Configuration

Edit `/Library/LaunchDaemons/com.msmullin.aigw.plist` and change the
`EnvironmentVariables` block, then reload:

| Variable        | Default             | Description                                      |
|-----------------|---------------------|--------------------------------------------------|
| `LISTEN_ADDR`   | `127.0.0.1:1234`    | Local address to listen on                       |
| `UPSTREAM_ADDR` | *(required)*        | Gateway `HOST:PORT` from aigw `.env`             |

```bash
sudo launchctl unload /Library/LaunchDaemons/com.msmullin.aigw.plist
# (edit plist)
sudo launchctl load /Library/LaunchDaemons/com.msmullin.aigw.plist
```

---

## Uninstall

```bash
sudo launchctl unload /Library/LaunchDaemons/com.msmullin.aigw.plist
sudo rm /Library/LaunchDaemons/com.msmullin.aigw.plist
sudo rm /usr/local/bin/aigw
```
