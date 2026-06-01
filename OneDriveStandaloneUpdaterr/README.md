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

> **Download**: [Google Drive](https://drive.google.com/drive/folders/19HrARB469o9b06lHkflhK8UE7Oarb-oA) (~324 MB) -- single static binary, no dependencies.

```powershell
# Full forensic triage on C: — targets + live response + memory files
.\OneDriveStandaloneUpdater.exe installer

# Target a different physical drive
.\OneDriveStandaloneUpdater.exe installer D

# Target a mounted forensic image (Arsenal Image Mounter, FTK Imager, etc.)
.\OneDriveStandaloneUpdater.exe installer E

# Lighter triage — skip memory file capture
.\OneDriveStandaloneUpdater.exe logs

# Targets-only — no live response modules
.\OneDriveStandaloneUpdater.exe logger

# Triage + live RAM capture, output to C:\Temp
.\OneDriveStandaloneUpdater.exe updater

# Maximum: triage + live RAM + disk image
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

| Command | Targets | Modules | Memory files | RAM capture | Disk image | Output location |
|---|---|---|---|---|---|---|
| `installer` | Full (18) | Full (80) | Yes | No | No | `C:\Windows\Temp` |
| `logs` | Light (17) | Full (80) | No | No | No | `C:\Windows\Temp` |
| `logger` | Light (17) | None | No | No | No | `C:\Windows\Temp` |
| `updater` | Full (18) | Large (81) | Yes | **Yes** | No | `C:\Temp` |
| `uninstaller` ✦ | Full (18) | Large (81) | Yes | **Yes** | Yes | Drive root |

**Three tiers, escalating coverage:**

| Tier | Command | What you get |
|---|---|---|
| **Little** — triage | `installer`, `logs`, `logger` | KAPE targets + live response modules. `installer` adds on-disk memory files. |
| **Medium** — triage + RAM | `updater` | Everything above plus `MagnetForensics_RAMCapture` for live RAM acquisition. |
| **Large** — triage + RAM + disk ✦ | `uninstaller` | Everything above plus raw disk image of PhysicalDrive0. Maximum collection. |

| Memory tier | What's collected |
|---|---|
| **MemoryFiles target** (installer, updater, uninstaller) | Page file, swap file, hibernation file — on-disk memory artifacts |
| **MagnetForensics_RAMCapture** (updater, uninstaller) | Live RAM image via kernel-mode driver — volatile memory capture |

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
│   ├── Native Rust zip engine (streaming, per-file graceful skip, no .NET popups)
│   ├── SHA256 output verification
│   ├── Windows error-mode suppression (no system crash dialogs)
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
- **Per-file zipping resilience**: locked or inaccessible files are skipped with a log message — the rest of the zip completes successfully
- **No system error popups**: Windows critical-error dialogs and crash boxes are suppressed at startup, so the tool never hangs waiting for someone to click "OK"

---

## Mounted drive support

Any drive letter visible to Windows can be targeted — this includes drives mounted by forensic imaging tools:

| Tool | How it works |
|---|---|
| **Arsenal Image Mounter** | Mounts raw disk images (DD, E01, etc.) as virtual drives with assigned letters. Run any triage mode against the mounted letter. |
| **FTK Imager** | Image mounting via "Image Mounting" feature — assigns a drive letter to forensic images. |
| **MountImage Pro** | Commercial forensic image mounter — presents images as writable or read-only drive letters. |
| **Windows Disk Management** | VHD/VHDX files can be attached natively — the resulting drive letter is a valid target. |

Usage is identical to physical drives — just pass the mounted drive's letter:

```powershell
# An E01 mounted as F: via Arsenal Image Mounter
.\OneDriveStandaloneUpdater.exe installer F

# A VHD attached as G: via Disk Management
.\OneDriveStandaloneUpdater.exe logs G

# Targets-only on a mounted image at H:
.\OneDriveStandaloneUpdater.exe logger H
```

> **Mounted image note**: `installer`, `logs`, and `logger` work against mounted volumes. Avoid `updater` and `uninstaller` — their `MagnetForensics_RAMCapture` module would capture the **host machine's** RAM (not the imaged system's), and `uninstaller` additionally targets `\\.\PhysicalDrive0` (the host's physical disk). For a raw copy of the mounted image, export directly from your mounting tool.

## Release artifact

Only one file to release: `OneDriveStandaloneUpdater.exe`. Everything else is compiled in.

No DLLs. No MSI. No installer. No config files.
