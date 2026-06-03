# Firewall Telemetry Agent

Adaptive firewall log collector. Run on the firewall or as a centralized syslog receiver. 22+ vendors, 6 ingestion methods.

## Distribution

This release contains `wizard-firewall` — the installer, updater, and agent in one binary. The agent is embedded inside the wizard at compile time.

```
wizard-firewall             — Installer + embedded agent (~12MB static musl)
config.example.toml         — Annotated configuration reference
install.sh                  — Shell install helper
```

## Install

```bash
# Generate default config
./wizard-firewall init --agent-id fw-prod-01 --endpoint https://es:9200/_bulk

# Smart mode
sudo ./wizard-firewall config.toml

# Explicit install
sudo ./wizard-firewall install config.toml
```

## Uninstall / Update / Status

```bash
sudo ./wizard-firewall uninstall --remove-data
sudo ./wizard-firewall update config.toml
./wizard-firewall status
```

## Operating Modes

| Mode | Description |
|------|-------------|
| `on-device` | Runs nftables/conntrack or pf directly on the firewall |
| `collector` | Listens for syslog on UDP 514 + polls REST APIs + cloud flow logs |
| `hybrid` | Both (default) |

Set in config.toml: `[agent] mode = "hybrid"`

## Build from Source

```bash
cd firewall
cargo build --release --target x86_64-unknown-linux-musl -p agent-service-firewall
cargo build --release --target x86_64-unknown-linux-musl -p wizard-firewall
```

## Requirements
- Linux kernel 2.6+ (3.13+ for nftables)
- CAP_NET_RAW + CAP_NET_BIND_SERVICE (for nflog/syslog)
- Elasticsearch 7.x or 8.x
