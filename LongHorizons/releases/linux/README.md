# Linux Telemetry Agent

eBPF-based adaptive kernel telemetry collector for all Linux distributions.

## One Binary, Every Linux
Statically linked musl binary. Runs on:
- Ubuntu 18.04–26.04, Debian 10–13, RHEL 7–10
- Fedora, Arch, Alpine, Gentoo, Void, NixOS, Yocto
- Distroless containers, scratch Docker images
- Any kernel 2.6.x through 6.x+

## Features
- **Capability ladder** — auto-detects best available telemetry source:
  1. eBPF CO-RE (kernel 5.4+, BTF) — 12 kernel probes, lowest overhead
  2. auditd + fanotify (kernel 3.x+) — process/security/file events
  3. netlink connector + inotify (kernel 2.6.x+)
  4. /proc polling — universal fallback
- **12 eBPF probes**: process exec/exit/fork, TCP connect/accept, DNS, file open/write/delete, module load, capability checks, mount events
- ELF binary metadata (build ID, section count, import entropy)
- Distribution-aware file path analysis (/tmp, /dev/shm, /etc/cron, systemd units, SSH authorized_keys, PAM config, etc.)
- Bash command-line obfuscation detection (base64 decode, eval, reverse shell, /dev/tcp)
- Deterministic tokenization with sanitization (AAA= rejection, hex pointer rejection, control char rejection)
- `stringify_json_values` for Elasticsearch type safety
- Systemd, OpenRC, sysvinit, and runit service support

## Build
```bash
# Requires: Rust 1.75+, musl toolchain, clang 14+, bpftool, libbpf
cd linux
make -C ebpf-probes vmlinux   # Generate vmlinux.h from running kernel
make -C ebpf-probes            # Build eBPF CO-RE bytecode
cargo build --release --target x86_64-unknown-linux-musl
# Output: target/x86_64-unknown-linux-musl/release/telemetry-agent
```

## Install
```bash
# Using wizard (recommended)
sudo ./wizard install config.toml

# Smart mode (auto-detects existing install)
sudo ./wizard config.toml

# Generate default config
./wizard init --agent-id prod-web-01

# Manual foreground run
./telemetry-agent run --config /etc/telemetry-agent/config.toml

# Probe system capabilities
./telemetry-agent probe
```

## Configuration
See `config.example.toml` for full annotated configuration with all 19 eBPF per-probe toggles.

## Requirements
- Linux kernel 2.6.x+ (5.4+ recommended for eBPF CO-RE)
- Root or CAP_BPF, CAP_NET_ADMIN, CAP_SYS_ADMIN for eBPF
- CAP_NET_BIND_SERVICE for syslog (if running firewall agent)
- Elasticsearch 7.x or 8.x

## Source Layout
```
linux/
├── agent-core-linux/       # Models, pipeline, tokenization, DB
├── agent-ebpf/             # Adaptive telemetry source (5 tiers)
├── agent-exporter-linux/   # ES bulk export
├── agent-service-linux/    # CLI, service install, run loop
├── ebpf-probes/            # C BPF programs with CO-RE
├── deploy/                 # systemd unit, init scripts, config
└── wizard/                 # Install/uninstall/update wizard
```
