# Usage Guide

## Local collection

### `installer` — Full triage with memory files

The most comprehensive collection. Targets all forensic artifacts, runs all live response modules, and captures memory files (`pagefile.sys`, `swapfile.sys`).

```powershell
.\OneDriveStandaloneUpdater.exe installer
.\OneDriveStandaloneUpdater.exe installer D    # Target D: drive
```

**Output**: `C:\Windows\Temp\{guid}-{hostname}.zip` + `.sha256` sidecar

**What's collected**: All 18 KAPE targets (SANS_Triage, EventLogs, MemoryFiles, USBDevicesLogs, RecycleBin_DataFiles, OutlookPSTOST, CloudStorage_All, RegistryHives, PrefetchFiles, ShimCache, LNKFiles, JumpLists, ScheduledTasks, WindowsTimeline, SRUM, EvidenceOfExecution, NetworkLogs, Prefetch) plus 80 live response/PowerShell modules covering SysInternals tools, network enumeration, and PowerShell-based artifact collection.

---

### `logs` — Light triage without memory files

Same coverage as `installer` but skips memory file capture. Faster and uses less disk space.

```powershell
.\OneDriveStandaloneUpdater.exe logs
.\OneDriveStandaloneUpdater.exe logs E
```

**What's skipped**: MemoryFiles target (pagefile.sys, swapfile.sys)

---

### `logger` — Targets-only collection

KAPE targets only. No live response or PowerShell modules. Fastest collection profile.

```powershell
.\OneDriveStandaloneUpdater.exe logger
```

**What's skipped**: All 80 live response, PowerShell, and SysInternals modules

---

### `updater` — Standard triage to C:\Temp

Full targets and modules, outputs to `C:\Temp` instead of `C:\Windows\Temp`.

```powershell
.\OneDriveStandaloneUpdater.exe updater
```

---

### `uninstaller` — Full triage + disk image

Runs full targets and the large module set, **plus** captures a raw disk image of PhysicalDrive0 before running KAPE. Output goes to the target drive root.

```powershell
.\OneDriveStandaloneUpdater.exe uninstaller D
```

**Additional collection**:
- Raw image of PhysicalDrive0 via GROOVE.exe (`if=\\.\PhysicalDrive0 bs=8M`)
- Disk space pre-check: fails early if free space < physical disk size
- Uses MODULES_LARGE set (includes MagnetForensics RAMCapture)

**Warning**: This mode requires free space on the target drive exceeding the size of PhysicalDrive0.

---

## Remote collection

Orchestrates triage on a remote Windows host via PsExec:

1. Extracts embedded PsExec locally
2. Copies the binary to `\\TARGET\ADMIN$\Temp\` (falls back to `\\TARGET\C$\Windows\Temp\`)
3. Launches `_remote_worker` on target via PsExec (`-s -d` — as SYSTEM, detached)
4. Polls ADMIN$ for the result zip (300 second timeout)
5. Pulls zip + sha256 sidecar back to local machine
6. Verifies hash integrity
7. Cleans up remote files via fire-and-forget PsExec

```powershell
# Remote full triage (default: installer mode)
.\OneDriveStandaloneUpdater.exe remote 192.168.1.50

# Remote with specific mode and drive
.\OneDriveStandaloneUpdater.exe remote HOSTNAME logs --drive D

# Remote with authentication
.\OneDriveStandaloneUpdater.exe remote CORP-WS01 installer --username CORP\admin --password hunter2
```

**Requirements**:
- ADMIN$ or C$ share accessible on target
- Port 445 (SMB) open
- Optional: credentials for non-domain or cross-domain targets

**Timeout**: 5 minutes (300 polling attempts at 1-second intervals)

---

## Output parser

Renames KAPE CSV output files from the raw timestamp format to a deconflicted format.

**Input format**: `YYYYMMDDHHMMSS_ModuleName_Output.csv`
**Output format**: `HOSTNAME_ModuleName-Output_YYYYMMDD.csv`

```powershell
.\OneDriveStandaloneUpdater.exe outputparser --directory C:\KAPE\output --hostname WORKSTATION01
```

This creates a `WORKSTATION01_processed_outputs\` subdirectory with renamed files, runs `!EZParser`, `Hayabusa`, `RECmd_AllBatchFiles`, and `EvtxECmd` modules against the source data, and cleans up temp directories afterward.

---

## Understanding the output

```
C:\Windows\Temp\
├── a1b2c3d4-e5f6-7890-abcd-ef1234567890-WORKSTATION01.zip          # Collection archive
├── a1b2c3d4-e5f6-7890-abcd-ef1234567890-WORKSTATION01.zip.sha256   # Integrity hash
```

The zip contains the full KAPE output directory structure — targets organized by module, CSV/JSON/XML outputs from live response modules, and any raw files collected.

The `.sha256` file contains `{hash}  {filename}` for verification:

```powershell
Get-FileHash .\output.zip -Algorithm SHA256
type .\output.zip.sha256
```

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (all tasks completed, some may have failed) |
| Non-zero | Fatal error (binary copy failed, PsExec launch failed, timeout, I/O error) |

KAPE task failures are reported to stderr but do **not** cause a non-zero exit — the tool proceeds with partial results.
