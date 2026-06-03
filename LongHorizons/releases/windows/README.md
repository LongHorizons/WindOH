# Windows Telemetry Agent

ETW-based kernel and userspace telemetry collector for Windows 10/11 and Windows Server 2016+.

## Features
- 30+ ETW providers: kernel process/network/file/registry, security auditing, PowerShell, Defender, WMI, COM, .NET, SMB, RPC, WinHTTP, and more
- Automatic provider discovery (200+ providers in "all" mode)
- Process lineage tracking (parent/child/grandparent)
- PE binary metadata (compile timestamp, section count, import entropy, debug path, PDB)
- Command-line obfuscation analysis (PowerShell base64, caret escaping, IEX, download cradle detection)
- IP geolocation and threat intel enrichment
- Deterministic tokenization (stable + payload hashing for cross-host baselining)
- Count-Min Sketch rarity estimation with exemplar reservoir sampling
- Elasticsearch bulk export with gzip compression
- SQLite outbox with retry and dead-letter queue
- Windows service wrapper with stall detection and auto-recovery
- Embedded config mode (PE overlay trailer)

## Install
```powershell
# Using wizard (recommended)
.\wizard.exe install config.toml

# Or smart mode (auto-detects existing install)
.\wizard.exe config.toml

# Manual install
.\agent.exe install --config config.toml
```

## Configuration
See `config.example.toml` for full annotated configuration.

## Requirements
- Windows 10/11 or Windows Server 2016+
- Administrator privileges (for ETW session creation)
- Elasticsearch 7.x or 8.x
