# LongHorizons Telemetry Agent

**Cross-platform kernel and cloud telemetry. Normalized to Elasticsearch. One schema across every surface.**

## Scope

| Surface | Source | Depth |
|---------|--------|-------|
| **Windows** | ETW (Event Tracing for Windows) | 40+ kernel/userspace providers, PE metadata, registry, WMI, process forensics |
| **Linux** | eBPF CO-RE → auditd → netlink → /proc | 12 kernel probes, 5-tier adaptive ladder, any distro, kernel 2.6 through 6.x |
| **Firewall** | nflog, conntrack, syslog, REST APIs, cloud flow logs | 22+ vendors, 6 ingestion methods, 18 syslog format auto-detectors |
| **Cloud** | AWS, Azure, GCP, Oracle, Kubernetes APIs | 24 services across 5 providers, unified IAM + network + threat schema |

## What It Does

Every event — a process starting, a firewall denying a connection, an IAM role being assumed — flows through the same pipeline:

```
Raw event → Normalized schema → Deterministic tokenization → CMS rarity estimation
          → Reservoir exemplar selection → SQLite outbox → ES bulk export
```

The result: every event from every platform is queryable through the same Kibana fields, enrichable by the same LLM pipeline, and comparable across hosts, networks, and clouds.

## Design Decisions

**Deterministic tokenization.** Each event splits into a stable base hash (structural identity — what happened) and a variant payload hash (instance data — the specific details). Two hosts running the same binary produce the same base hash. Different command-line arguments produce different payload hashes. This is how cross-host baselining works without a central authority.

**Count-Min Sketch rarity.** Approximate frequency counting at sub-linear memory cost. A base token seen twice across the fleet is rare and exported immediately. One seen 10,000 times is common and exported as an aggregate pattern. This is how signal separates from noise without storing every event.

**SQLite outbox.** Every event lands in a local SQLite database before touching the network. Three priority tiers: exemplars (rare/interesting), patterns (aggregate summaries), events (everything). Survives Elasticsearch outages, network partitions, and credential rotation — events queue locally and drain when connectivity returns.

**Stringify JSON values.** All numeric and boolean leaf values are recursively cast to strings before ES indexing. A field that contains `"0xffff"` in one document and `1234` in another will not cause a mapping conflict. This is a single recursive function that prevents the most common cause of ES ingest failure in production.

**Platform-specific wizards.** Every platform ships a `wizard` binary. Same UX: `wizard install config.toml` for a fresh install, `wizard config.toml` for smart mode (detect existing → update or install), `wizard status` for health. Same wizard.json metadata tracking upgrades across versions. Same init system auto-detection on Linux (systemd, OpenRC, sysvinit, runit).

## Quick Start

```powershell
# Windows
cd windows; cargo build --release; .\wizard.exe install config.toml
```

```bash
# Linux (musl static — one binary, every distro)
cd linux; make -C ebpf-probes; cargo build --release --target x86_64-unknown-linux-musl
sudo ./wizard install config.toml
```

```bash
# Firewall (on-device or collector mode)
cd firewall; cargo build --release
sudo ./wizard-firewall init --agent-id fw01; sudo ./wizard-firewall install config.toml
```

```bash
# Cloud (per-provider wizards)
cd cloud; cargo build --release
./wizard-aws init --region us-east-1; ./wizard-aws install config-aws.toml
```

## Repository

```
├── windows/       ETW host agent — 4 crates, 76 source files
├── linux/         eBPF host agent — 4 crates, 39 source files, 5 BPF C probes
├── firewall/      Firewall agent — 10 crates, 40 source files
├── cloud/         Cloud agent — 5 providers, 12 crates, 28 source files
└── Presentation/  Documentation and per-platform release packages
```

Each platform is a fully independent Cargo workspace. No shared code, no cross-contamination. Build one without building the others.

## Requirements

- Rust 1.75+
- Elasticsearch 7.x or 8.x
- Platform: Windows 10+ / Linux kernel 2.6+ / CAP_NET_RAW (firewall) / cloud credentials (cloud)
