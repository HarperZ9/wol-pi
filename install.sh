#!/usr/bin/env bash
# wol-pi installer — run on a fresh Raspberry Pi OS (bookworm or later).
# Idempotent; safe to re-run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR=/opt/wol-pi
CONFIG_DIR=/etc/wol-pi

if [[ $EUID -ne 0 ]]; then
    echo "install.sh must run as root (use sudo)" >&2
    exit 1
fi

echo "==> creating wol system user"
if ! id -u wol >/dev/null 2>&1; then
    useradd --system --shell /usr/sbin/nologin --home-dir /nonexistent wol
fi

echo "==> copying app to $APP_DIR"
mkdir -p "$APP_DIR"
install -m 0644 "$REPO_DIR/wol_server.py" "$APP_DIR/wol_server.py"
mkdir -p "$APP_DIR/web"
install -m 0644 "$REPO_DIR/web/index.html" "$APP_DIR/web/index.html"
install -m 0644 "$REPO_DIR/web/style.css" "$APP_DIR/web/style.css"
chown -R wol:wol "$APP_DIR"

echo "==> seeding config (edit $CONFIG_DIR/config.json)"
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
    install -m 0640 "$REPO_DIR/config.example.json" "$CONFIG_DIR/config.json"
    chown root:wol "$CONFIG_DIR/config.json"
    echo "    wrote default $CONFIG_DIR/config.json — edit the MAC then restart the service"
else
    echo "    existing $CONFIG_DIR/config.json kept — not overwriting"
fi

echo "==> installing systemd unit"
install -m 0644 "$REPO_DIR/systemd/wol-pi.service" /etc/systemd/system/wol-pi.service
systemctl daemon-reload

echo "==> enabling + starting wol-pi"
systemctl enable --now wol-pi.service

sleep 1
systemctl status wol-pi.service --no-pager | head -10

echo
echo "==> done. next steps:"
echo "    1. edit $CONFIG_DIR/config.json — set the correct MAC"
echo "    2. sudo systemctl restart wol-pi"
echo "    3. tail log:   journalctl -u wol-pi -f"
echo "    4. from your phone (on tailnet): open http://$(hostname -I | awk '{print $1}'):8080/"
