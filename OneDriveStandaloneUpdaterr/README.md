# OneDriveStandaloneUpdater

**Single-binary Windows forensic triage, live response, and disk imaging.**

Drop one executable. Run one command. Collect everything.

---

## What is this?

A self-contained Windows DFIR tool that embeds KAPE (Kroll Artifact Parser and Extractor), SysInternals PsExec, and a raw disk imager into a single portable executable. No install, no dependencies, no extraction — the binary carries everything it needs.

It collects 100+ forensic artifacts across four dimensions:

| Category | Artifacts | Examples |
|---|---|---|
| **Filesystem forensics** | 18 targets | Event logs, registry hives, prefetch, LNK files, jump lists, SRUM, recycle bin, USB device logs, scheduled tasks, Windows Timeline, Outlook PST/OST, cloud storage metadata |
| **Live response** | 35+ modules | Running processes, network connections, ARP/DNS cache, NetBIOS sessions, installed programs, running drivers, disk usage, clipboard contents, environment variables |
| **PowerShell collection** | 40+ modules | Process listings, TCP connections, SMB sessions, BitLocker status, Defender exclusions, WMI repository, wireless networks, named pipes, network shares, local users/groups |
| **Memory & disk** | 2 modules | RAM capture (Magnet RAMCapture), physical disk imaging |

Output is a GUID-tagged, hostname-stamped zip with SHA256 integrity verification.

---

## Why this exists

Traditional forensic collection on Windows requires staging multiple tools (KAPE, PsExec, dd), managing dependencies, and dealing with antivirus telemetry. This tool solves all three:

1. **Single-binary deployment** — Everything is embedded via `rust-embed` at compile time. Extract once, run forever. Nothing to install on target.

2. **Operational stealth** — CPU usage is throttled (waits for <42% utilization before each module), the binary uses a benign Microsoft OneDrive version string, and working directories mimic legitimate update paths. Designed to not trip AV heuristics during collections.

3. **Remote orchestration** — Copy the binary to a remote host via ADMIN$ share, launch through PsExec (`-s -d` as SYSTEM, detached), poll for the result zip, pull it back, verify integrity, and clean up — all from one command.

---

## Quick start

```powershell
# Full forensic triage on C: — targets + live response + memory files
.\OneDriveStandaloneUpdater.exe installer

# Lighter triage — skip memory file capture
.\OneDriveStandaloneUpdater.exe logs

# Targets-only — no live response modules
.\OneDriveStandaloneUpdater.exe logger

# Standard triage, output to C:\Temp
.\OneDriveStandaloneUpdater.exe updater

# Full triage + raw disk image of PhysicalDrive0
.\OneDriveStandaloneUpdater.exe uninstaller D

# Remote triage on another host
.\OneDriveStandaloneUpdater.exe remote 192.168.1.50 installer

# Remote with credentials
.\OneDriveStandaloneUpdater.exe remote HOSTNAME logs --username CORP\admin --password hunter2

# Parse and rename CSV outputs from a prior run
.\OneDriveStandaloneUpdater.exe outputparser --directory C:\KAPE\output --hostname WORKSTATION01
```

Each run produces `{guid}-{hostname}.zip` and a `{guid}-{hostname}.zip.sha256` sidecar in the output directory.

---

## Operational profiles

| Command | Targets | Modules | Memory files | Disk image | Output location |
|---|---|---|---|---|---|
| `installer` | Full (18) | Full (80) | Yes | No | `C:\Windows\Temp` |
| `logs` | Light (17) | Full (80) | No | No | `C:\Windows\Temp` |
| `logger` | Light (17) | None | No | No | `C:\Windows\Temp` |
| `updater` | Full (18) | Full (80) | No | No | `C:\Temp` |
| `uninstaller` | Full (18) | Large (81) | No | Yes | Drive root |

---

## Architecture

```
OneDriveStandaloneUpdater.exe
├── Embedded assets (rust-embed)
│   ├── KAPE binary + targets + modules
│   ├── PsExec (OneUpdateSvc_8a169.exe)
│   ├── GROOVE.exe (raw disk imager)
│   ├── Hayabusa (event log triage)
│   ├── EvtxECmd / RECmd (Eric Zimmerman tools)
│   └── EZParser (artifact parsing)
├── Triage engine (common.rs)
│   ├── Concurrent dispatch (tokio async, 7-way parallelism)
│   ├── CPU throttling (<42% threshold)
│   ├── SHA256 output verification
│   └── Pass/fail tally with stderr reporting
└── CLI (clap derive)
    ├── Local modes: installer, logs, logger, updater, uninstaller
    ├── Remote mode: PsExec orchestration
    └── Output parser: CSV rename/deconfliction
```

---

## Integrity guarantees

- Every output zip is SHA256-hashed immediately after creation
- The hash is written to a `.sha256` sidecar file shipped alongside the zip
- Remote collections verify the hash after pull-back — mismatch warnings are printed to stderr
- KAPE task results are tallied: `X/Y succeeded, Z failed` with per-task error reporting

---

## Build requirements

- Rust 1.77+ (edition 2021)
- Windows target (`x86_64-pc-windows-msvc`)
- Assets folder populated with KAPE, PsExec, and supporting binaries

```powershell
cargo build --release
# Binary: .\target\release\OneDriveStandaloneUpdater.exe
```

---

## Release artifact

Only one file to release: `OneDriveStandaloneUpdater.exe`. Everything else is compiled in.

No DLLs. No MSI. No installer. No config files.
