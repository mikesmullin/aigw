#!/usr/bin/env bash
# Install the user systemd unit with WorkingDirectory / EnvironmentFile set to this clone.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$UNIT_DIR"

sed "s|@REPO@|$ROOT|g" "$ROOT/systemd/aigw.service" > "$UNIT_DIR/aigw.service"

systemctl --user daemon-reload
systemctl --user enable --now aigw.service
echo "installed $UNIT_DIR/aigw.service (WorkingDirectory=$ROOT)"
systemctl --user status aigw.service --no-pager
