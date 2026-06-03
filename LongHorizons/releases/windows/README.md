# Windows Telemetry Agent

ETW-based kernel and userspace telemetry for Windows 10/11 and Windows Server 2016+.

## Distribution

This release contains one binary: `wizard.exe`. It is the installer, the updater, and the agent — all in one. The agent binary is embedded inside the wizard at compile time via `build.rs` + `include_bytes!`. Running `wizard.exe install` extracts it.

```
wizard.exe          (24MB) — Installer + embedded agent
config.example.toml         — Annotated configuration reference
install.ps1                 — PowerShell install helper
```

## Install

```powershell
# Smart mode (auto-detects existing → update or fresh install)
.\wizard.exe config.toml

# Explicit fresh install
.\wizard.exe install config.toml

# With custom directory
.\wizard.exe install config.toml --install-dir "C:\CustomPath"

# Force (skip CHANGEME validation)
.\wizard.exe install config.toml --force
```

## Uninstall

```powershell
.\wizard.exe uninstall              # Keep data
.\wizard.exe uninstall --remove-data # Remove logs, state, database
```

## Update

```powershell
.\wizard.exe update config.toml     # Replace binary + config
```

## Status

```powershell
.\wizard.exe status                 # Show installed version, service state, upgrade history
```

## Wizard Embeds the Agent

The wizard's `build.rs` finds the compiled `agent.exe` at build time and embeds it:

```rust
const AGENT_BYTES: &[u8] = include_bytes!(env!("AGENT_EXE_PATH"));
```

During `wizard install`, `AGENT_BYTES` is written to the install directory. The Windows service is created pointing to that extracted binary. No separate download. No network dependency.

## Build from Source

```powershell
cd windows
cargo build --release -p agent-service     # produces agent.exe
cargo build --release -p wizard            # embeds agent.exe → produces wizard.exe
```

## Requirements
- Windows 10/11 or Windows Server 2016+
- Administrator (ETW session creation)
- Elasticsearch 7.x or 8.x
