# Firewall Telemetry Agent

Adaptive firewall log collector — run ON the firewall or as a centralized collector.

## Coverage — 22+ Firewalls, 6 Ingestion Methods

| Method | Firewalls Covered |
|--------|-------------------|
| **nflog** (netlink) | nftables (Linux kernel 3.13+) |
| **conntrack** (netlink) | Any Linux firewall |
| **iptables** log tail | iptables (legacy) |
| **pf** pflog | pfSense, OPNsense, FreeBSD pf |
| **Syslog UDP 514** | Cisco ASA/FTD/IOS, Palo Alto, Fortinet, Check Point, Juniper SRX, SonicWall, Sophos XG/UTM, WatchGuard, MikroTik, Huawei USG, Hillstone, Barracuda — any syslog device |
| **REST API** | Palo Alto Panorama, Fortinet FortiGate, Cisco FMC, Check Point Management |
| **Cloud Flow Logs** | AWS VPC, Azure NSG, GCP Firewall Rules |

## Features
- **Auto-detection** of firewall vendor from syslog messages (18 vendor patterns)
- **Unified schema** — every firewall maps to the same FirewallEvent (5-tuple, NAT, rule ID, threat, app/user, session bytes)
- **Connection tracking** — conntrack NEW/UPDATE/DESTROY events without nftables rules
- **NAT translation tracking** — pre/post SNAT/DNAT IP and port
- **Threat enrichment** — CVE, MITRE ATT&CK, IPS signature, file hash
- **GeoIP enrichment** — country, ASN for src/dst IPs (MaxMind GeoLite2)
- **3 operating modes**: on-device (runs on firewall), collector (syslog + API), hybrid (both)
- Systemd, OpenRC, sysvinit, runit service support

## Install
```bash
# Generate config
./wizard-firewall init --agent-id fw-prod-01 --endpoint https://es:9200/_bulk

# Edit config.toml — replace CHANGEME values
# Install
sudo ./wizard-firewall install config.toml

# Or run directly
sudo ./firewall-agent run --config config.toml
sudo ./firewall-agent probe
```

## Configuration
```
[agent]        id, mode (on-device/collector/hybrid)
[sources]      nftables, iptables, pf, syslog (UDP/TCP/TLS)
[sources.api_pollers]   Palo Alto, Fortinet, Cisco, Check Point
[sources.cloud_pollers] AWS, Azure, GCP
[enrichment]   GeoIP, ASN, AbuseIPDB, VirusTotal
[export]       Elasticsearch events + diagnostics + health
```
