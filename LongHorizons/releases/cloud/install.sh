#!/bin/bash
# Cloud Telemetry Agent — Install Script
# Usage: sudo ./install.sh [provider] [config.toml]

set -e
PROVIDER="${1:-aws}"
CONFIG="${2:-config-$PROVIDER.toml}"
INSTALL_DIR="/opt/cloud-agent/$PROVIDER"
DATA_DIR="/var/lib/cloud-agent/$PROVIDER"
BIN="cloud-agent"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Cloud Telemetry Agent — $PROVIDER Installer                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

[ "$(id -u)" -ne 0 ] && { echo "  [!] Run with sudo."; exit 1; }
[ ! -f "./$BIN" ] && { echo "  [!] $BIN not found."; exit 1; }

echo "  Provider:  $PROVIDER"
echo "  Config:    $CONFIG"

mkdir -p "$INSTALL_DIR" "$DATA_DIR"
cp "./$BIN" "$INSTALL_DIR/$BIN" && chmod 755 "$INSTALL_DIR/$BIN"
cp "./wizard-$PROVIDER" "$INSTALL_DIR/wizard" 2>/dev/null || true
[ -f "$CONFIG" ] && cp "$CONFIG" "$INSTALL_DIR/config.toml"

cat > /etc/systemd/system/cloud-agent-$PROVIDER.service << UNIT
[Unit]
Description=Cloud Telemetry Agent — $PROVIDER
After=network-online.target
[Service]
Type=simple
ExecStart=$INSTALL_DIR/$BIN run --config $INSTALL_DIR/config.toml
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload && systemctl enable "cloud-agent-$PROVIDER" && systemctl start "cloud-agent-$PROVIDER"

echo ""
echo "  ✓ Installed to $INSTALL_DIR"
echo "  Status: systemctl status cloud-agent-$PROVIDER"
echo ""
