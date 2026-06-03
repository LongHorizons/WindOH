# Linux Telemetry Agent

eBPF-based adaptive kernel telemetry. One static musl binary, every Linux distribution.

## Distribution

This release contains `wizard` — the installer, updater, and agent in one binary. The agent is embedded inside the wizard at compile time via `build.rs` + `include_bytes!`. Running `wizard install` extracts it.

```
wizard                      — Installer + embedded agent (~15MB static musl)
config.example.toml         — Annotated configuration reference
install.sh                  — Shell install helper
```

## Install

```bash
# Generate default config
./wizard init --agent-id prod-web-01

# Smart mode (auto-detects existing → update or fresh install)
sudo ./wizard config.toml

# Explicit fresh install
sudo ./wizard install config.toml

# With custom directory
sudo ./wizard install config.toml --install-dir /opt/telemetry-agent

# Force (skip CHANGEME validation)
sudo ./wizard install config.toml --force
```

## Uninstall

```bash
sudo ./wizard uninstall              # Keep data
sudo ./wizard uninstall --remove-data # Remove logs, state, database
```

## Update

```bash
sudo ./wizard update config.toml     # Replace binary + config
```

## Status

```bash
./wizard status                      # Show installed version, init system, upgrade history
```

## Wizard Embeds the Agent

The wizard's `build.rs` finds the compiled `telemetry-agent` binary at build time and embeds it. During install, the embedded bytes are extracted to the install directory. A systemd/OpenRC/sysvinit/runit service is created pointing to that extracted binary.

```
cargo build --release -p agent-service-linux    # produces the agent
cargo build --release -p wizard                 # embeds agent → produces wizard
```

## Build from Source

Requires: Rust 1.75+, musl toolchain, clang 14+, bpftool, libbpf.

```bash
cd linux
make -C ebpf-probes vmlinux          # Generate vmlinux.h from running kernel BTF
make -C ebpf-probes                  # Build eBPF CO-RE bytecode
cargo build --release --target x86_64-unknown-linux-musl -p agent-service-linux
cargo build --release --target x86_64-unknown-linux-musl -p wizard
```

## Requirements
- Linux kernel 2.6+ (5.4+ recommended for eBPF CO-RE)
- Root or CAP_BPF, CAP_NET_ADMIN, CAP_SYS_ADMIN (for eBPF)
- Elasticsearch 7.x or 8.x
