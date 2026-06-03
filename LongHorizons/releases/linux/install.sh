#!/bin/bash
# Linux Telemetry Agent — Install Script
# Usage: sudo ./install.sh [--config config.toml] [--install-dir /opt/telemetry-agent]

set -e
CONFIG="${1:-/etc/telemetry-agent/config.toml}"
INSTALL_DIR="${2:-/opt/telemetry-agent}"
DATA_DIR="/var/lib/telemetry-agent"
BIN="telemetry-agent"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Linux Telemetry Agent — Installer                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo "  [!] This script requires root. Run with sudo."
    exit 1
fi

# Check binary
if [ ! -f "./$BIN" ]; then
    echo "  [!] $BIN not found in current directory."
    echo "      Download the pre-built binary from LongHorizons/releases/linux/"
    exit 1
fi

# Detect init system
detect_init() {
    local comm=$(cat /proc/1/comm 2>/dev/null || echo "unknown")
    case "$comm" in
        systemd) echo "systemd" ;;
        init)
            if [ -f /sbin/openrc ] || [ -f /sbin/openrc-init ]; then echo "openrc"
            elif [ -f /sbin/runit ] || [ -d /etc/runit ]; then echo "runit"
            else echo "sysvinit"; fi ;;
        runit) echo "runit" ;;
        *) echo "unknown" ;;
    esac
}
INIT=$(detect_init)
echo "  Init system:    $INIT"

# Create directories
echo "  [1/4] Creating directories..."
mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/logs" "$INSTALL_DIR/state" "$DATA_DIR"

# Install binary
echo "  [2/4] Installing binary..."
cp "./$BIN" "$INSTALL_DIR/$BIN"
chmod 755 "$INSTALL_DIR/$BIN"

# Install config
echo "  [3/4] Installing config..."
if [ -f "$CONFIG" ]; then
    cp "$CONFIG" "$INSTALL_DIR/config.toml"
else
    echo "  [!] Config not found: $CONFIG — generating default"
    "$INSTALL_DIR/$BIN" init --output "$INSTALL_DIR/config.toml" 2>/dev/null || true
fi

# Create service
echo "  [4/4] Creating service ($INIT)..."
case "$INIT" in
    systemd)
        cat > /etc/systemd/system/telemetry-agent.service << EOF
[Unit]
Description=Telemetry Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/$BIN run --config $INSTALL_DIR/config.toml
Restart=always
RestartSec=10
LimitNOFILE=65536
AmbientCapabilities=CAP_BPF CAP_NET_ADMIN CAP_SYS_ADMIN CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
NoNewPrivileges=false
ProtectSystem=strict
ReadWritePaths=$DATA_DIR /tmp /var/tmp

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable telemetry-agent
        systemctl start telemetry-agent
        echo "  Service:    systemd (telemetry-agent.service)"
        ;;
    openrc)
        cat > /etc/init.d/telemetry-agent << EOF
#!/sbin/openrc-run
name="telemetry-agent"
command="$INSTALL_DIR/$BIN"
command_args="run --config $INSTALL_DIR/config.toml"
command_background=false
pidfile="/run/\${RC_SVCNAME}.pid"
depend() { need net; }
EOF
        chmod 755 /etc/init.d/telemetry-agent
        rc-update add telemetry-agent default
        rc-service telemetry-agent start
        echo "  Service:    OpenRC"
        ;;
    *)
        echo "  Service:    skipped (unknown init — run manually)"
        echo "  Run: $INSTALL_DIR/$BIN run --config $INSTALL_DIR/config.toml"
        ;;
esac

echo ""
echo "  ✓ Installation complete."
echo ""
echo "  Binary:     $INSTALL_DIR/$BIN"
echo "  Config:     $INSTALL_DIR/config.toml"
echo "  Data:       $DATA_DIR"
echo ""
echo "  Probe:      $INSTALL_DIR/$BIN probe"
echo "  Status:     systemctl status telemetry-agent"
echo "  Logs:       journalctl -u telemetry-agent -f"
echo ""
