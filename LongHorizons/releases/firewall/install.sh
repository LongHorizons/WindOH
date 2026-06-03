#!/bin/bash
# Firewall Telemetry Agent — Install Script
# Usage: sudo ./install.sh [config.toml] [/opt/firewall-agent]

set -e
CONFIG="${1:-config.toml}"
INSTALL_DIR="${2:-/opt/firewall-agent}"
DATA_DIR="/var/lib/firewall-agent"
BIN="firewall-agent"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Firewall Telemetry Agent — Installer                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

[ "$(id -u)" -ne 0 ] && { echo "  [!] Run with sudo."; exit 1; }
[ ! -f "./$BIN" ] && { echo "  [!] $BIN not found."; exit 1; }

INIT=$(cat /proc/1/comm 2>/dev/null || echo unknown)
case "$INIT" in systemd) INIT="systemd";; init) [ -f /sbin/openrc ] && INIT="openrc" || INIT="sysvinit";; *) INIT="unknown";; esac
echo "  Init system:    $INIT"

echo "  [1/3] Installing..."
mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/logs" "$INSTALL_DIR/state" "$DATA_DIR"
cp "./$BIN" "$INSTALL_DIR/$BIN" && chmod 755 "$INSTALL_DIR/$BIN"
[ -f "$CONFIG" ] && cp "$CONFIG" "$INSTALL_DIR/config.toml"

echo "  [2/3] Creating service..."
case "$INIT" in
    systemd)
        cat > /etc/systemd/system/firewall-agent.service << UNIT
[Unit]
Description=Firewall Telemetry Agent
After=network-online.target
[Service]
Type=simple
ExecStart=$INSTALL_DIR/$BIN run --config $INSTALL_DIR/config.toml
Restart=always
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_NET_ADMIN
[Install]
WantedBy=multi-user.target
UNIT
        systemctl daemon-reload && systemctl enable firewall-agent && systemctl start firewall-agent
        echo "  Service:    systemd (firewall-agent.service)";;
    openrc)
        cat > /etc/init.d/firewall-agent << EOF
#!/sbin/openrc-run
name="firewall-agent"
command="$INSTALL_DIR/$BIN"
command_args="run --config $INSTALL_DIR/config.toml"
command_background=false
depend() { need net; }
EOF
        chmod 755 /etc/init.d/firewall-agent
        rc-update add firewall-agent default && rc-service firewall-agent start
        echo "  Service:    OpenRC";;
    *) echo "  Run manually: $INSTALL_DIR/$BIN run --config $INSTALL_DIR/config.toml";;
esac

echo ""
echo "  [3/3] Done."
echo "  Probe:    $INSTALL_DIR/$BIN probe"
echo "  Logs:     journalctl -u firewall-agent -f"
echo ""
