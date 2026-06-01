# Feature Breakdown

## Embedded dependency model

All external tooling is compiled into the binary via `rust-embed`. On first run, assets are extracted to a working directory under `C:\Windows\Temp\OneDriveUpdater\` and reused for subsequent operations.

**Embedded components**:

| Component | Purpose | Binary |
|---|---|---|
| KAPE | Forensic artifact collection engine | `kape.exe` |
| PsExec | Remote SYSTEM-level execution | `OneUpdateSvc_8a169.exe` |
| GROOVE | Raw disk imaging (dd-like) | `GROOVE.exe` |
| Hayabusa | Windows event log threat hunting | `hayabusa.exe` |
| EvtxECmd | Event log parsing (Eric Zimmerman) | `EvtxECmd.exe` |
| RECmd | Registry parsing (Eric Zimmerman) | `RECmd.exe` |
| EZParser | Generic artifact parser | `EZParser.exe` |

---

## Concurrent dispatch engine

KAPE targets and modules run concurrently via `tokio`'s async runtime rather than sequentially.

- **7-way parallelism** by default (semaphore-gated)
- Each task acquires a permit from a `tokio::sync::Semaphore` before launching
- CPU throttling gates task start — `wait_for_cpu_idle()` spins until `global_cpu_info().cpu_usage() < 42%`
- Results collected via `std::sync::mpsc::channel` — succeeded and failed tasks tallied
- Failed tasks reported individually to stderr: `FAIL TaskName — error message`
- Partial failures don't abort the run — remaining tasks continue

**Performance impact**: A full `installer` run with 98 tasks completes in minutes rather than sequential execution time, while the CPU throttle prevents the collection from saturating the host.

---

## Native Rust zip engine

Zipping uses the `zip` crate directly — no PowerShell, no .NET, no external processes.

| Property | Old (PowerShell/.NET) | New (native Rust) |
|---|---|---|
| Overhead | 2-5s PowerShell startup + CLR load | ~0ms instant |
| Compression | Single-threaded .NET | Rust flate2, runs in dedicated blocking thread |
| Error popups | .NET can show modal "file in use" / "access denied" dialogs | Never — pure Rust, no UI framework |
| Per-file errors | One bad file → entire zip fails | File skipped, logged, remainder zips successfully |
| Large files | .NET loads directory enumeration into managed memory | Streaming `io::copy` with 1 MiB buffer — safe for multi-GB outputs |
| Async safety | Blocks calling thread | Wrapped in `tokio::task::spawn_blocking` |

### Per-file error resilience

```
Zipping 1,847 files from C:\Windows\Temp\... -> C:\Windows\Temp\a1b2c3d4-HOST.zip
Zip complete: 1,844/1,847 files succeeded
3 file(s) skipped due to errors:
  SKIP  LiveResponse/MemoryFiles/pagefile.sys  —  open: Access is denied. (os error 5)
  SKIP  RegistryHives/NTUSER.DAT  —  write: The file is locked by another process
  SKIP  EventLogs/System.evtx  —  open: The process cannot access the file
```

The zip is still valid and contains everything else. Skipped files are listed to stderr.

## Windows error-mode suppression

At startup, `SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX)` is called via kernel32.dll FFI (no extra dependencies). This suppresses:

- **Critical-error message boxes** — "Drive not ready", "Cannot read from drive", etc.
- **GPF dialogs** — "Program has stopped working" crash boxes

The setting is process-wide and inherits to child processes (KAPE, PowerShell modules, SysInternals tools). The tool will never hang indefinitely waiting for someone to click a dialog that isn't there.

## Mounted forensic drive support

Any drive letter visible to Windows works as a target — including drives mounted by forensic imaging tools. This enables triage against disk images without restoring them to physical hardware.

| Tool | Use case |
|---|---|
| **Arsenal Image Mounter** | Mount DD/E01/Ex01 images as virtual drives, run triage directly against the mounted filesystem |
| **FTK Imager** | Mount forensic images as read-only drive letters |
| **Windows VHD/VHDX attach** | Native disk attachment via Disk Management |

```powershell
# Triage an E01 mounted as F: (Arsenal Image Mounter)
.\OneDriveStandaloneUpdater.exe installer F

# Light triage on a VHD mounted as G:
.\OneDriveStandaloneUpdater.exe logs G

# Remote: triage a mounted image on another host
.\OneDriveStandaloneUpdater.exe remote 10.0.0.15 installer --drive F
```

> **Note**: `uninstaller` mode targets `\\.\PhysicalDrive0` (the system disk), not the mounted image. Use `installer`/`logs`/`logger` for mounted volumes. Export the raw image from your mounting tool if needed.

## Operational stealth

| Technique | Implementation |
|---|---|
| Binary identity | Microsoft OneDrive version string (`22.156.724+FOR05`), Microsoft-authored metadata in PE |
| Working paths | `C:\Windows\Temp\OneDriveUpdater\` — looks like a legitimate update staging directory |
| CPU throttle | No KAPE task launches above 42% CPU utilization — avoids triggering performance alerts |
| Process name | `OneDriveStandaloneUpdater.exe` — matches Microsoft naming conventions |
| Network behavior | No C2, no beaconing — single SMB copy for remote mode, standard Windows share access |

---

## SHA256 integrity pipeline

Every output zip is hashed immediately after compression:

1. `zip_folder()` streams files through the native Rust `zip` crate with `Deflated` compression — no PowerShell, no .NET overhead
2. `sha256_file()` streams the zip through `sha2::Sha256` in 8KB chunks
3. Hash written to `{zipname}.sha256` sidecar: `{hash}  {filename}\n`
4. On remote collections, the hash is verified after pull-back — mismatches printed to stderr

Keeps an audit trail even if the transport channel is untrusted.

---

## Disk space guard (uninstaller mode)

Before imaging PhysicalDrive0, the tool checks that the destination has enough free space:

1. Queries physical disk size: `wmic diskdrive where Index=0 get Size /value`
2. Queries free space on target: `(Get-PSDrive -Name D).Free`
3. Fails with a clear error if `free_space < disk_size`

Prevents partial images and disk-full failures mid-collection.

---

## Remote cleanup

After a remote collection completes:

- The worker binary is deleted from `C:\Windows\Temp\`
- Result zip and sha256 sidecar are deleted
- `C:\Windows\Temp\OneDriveUpdater\` working directory is rmdir'd

Cleanup is fire-and-forget via PsExec — the orchestrator doesn't wait for confirmation.

---

## KAPE task audit

Every run reports a tally to stderr:

```
KAPE results: 78/82 succeeded, 4 failed:
  FAIL  SysInternals_Handle  —  Access denied
  FAIL  PowerShell_NamedPipes  —  Timeout
  ...
```

- Total task count, success count, failure count
- Per-failure detail with module name and error message
- Non-zero exit only for orchestration failures, not individual task failures

---

## Defense against common failure modes

| Failure mode | Mitigation |
|---|---|
| ADMIN$ share inaccessible on remote | Fallback to C$\Windows\Temp |
| Disk full during imaging | Pre-flight disk space check, fails before imaging starts |
| CPU saturation triggering alerts | Per-task CPU throttle (<42%) |
| Corrupted zip in transit | SHA256 hash verification after remote pull-back |
| KAPE module crash | Per-task error isolation, remaining tasks continue |
| Locked or inaccessible file during zipping | Per-file skip with `SKIP` log — zip completes with remaining files |
| System error popup (drive not ready, crash dialog) | `SetErrorMode` FFI at startup — process-wide, inherits to children |
| PowerShell/.NET zip overhead and popups | Native Rust `zip` crate — no process spawn, no CLR, no UI framework |
| Stale temp files after crash | `permanently_delete_assets()` retries up to 500 times with 1-second backoff |
| PsExec not found in extracted assets | Recursive walkdir search for `*8a169*`, `*psexec*.exe`, or `*psexec64*.exe` |

---

## Module inventory

### Targets (18 full / 17 light)

```
SANS_Triage          EventLogs            MemoryFiles
USBDevicesLogs       RecycleBin_DataFiles OutlookPSTOST
CloudStorage_All     RegistryHives        PrefetchFiles
ShimCache            LNKFiles             JumpLists
ScheduledTasks       WindowsTimeline      SRUM
EvidenceOfExecution  NetworkLogs          Prefetch
```

*Light mode excludes MemoryFiles.*

### Live response (39 modules)

```
LiveResponse_NetSystemInfo                 LiveResponse_NetworkDetails
LiveResponse_ProcessDetails                LiveResponse_ARPCache
LiveResponse_DNSCache                      LiveResponse_NetStat
LiveResponse_IPConfig                      LiveResponse_NBTStat_NetBIOS_Cache
LiveResponse_NBTStat_NetBIOS_Sessions      LiveResponse_NetSystemInfo_Accounts
LiveResponse_NetSystemInfo_Administrators  LiveResponse_NetSystemInfo_File
LiveResponse_NetSystemInfo_LocalGroup      LiveResponse_NetSystemInfo_Session
LiveResponse_NetSystemInfo_Share           LiveResponse_NetSystemInfo_Start
LiveResponse_NetSystemInfo_Use             LiveResponse_NetSystemInfo_User
LiveResponse_InstalledPrograms             LiveResponse_RunningDrivers
LiveResponse_DiskUsage                     LiveResponse_UserAssist
LiveResponse_Clipboard                     LiveResponse_EnvironmentVariables
SysInternals_Autoruns                      SysInternals_Handle
SysInternals_PsFile                        SysInternals_PsInfo
SysInternals_PsList                        SysInternals_PsLoggedOn
SysInternals_PsService                     SysInternals_PsTree
SysInternals_Tcpvcon                       SysInternals_Streams
SysInternals_DiskView                      SysInternals_DiskExt
SysInternals_DebugView                     SysInternals_CoreInfo
SysInternals_BGInfo
```

### PowerShell (41 modules)

```
PowerShell_ActiveDrives         PowerShell_AccessibilityFeatures
PowerShell_Arp_Cache_Extraction PowerShell_Bitlocker_Key_Extraction
PowerShell_Bitlocker_Status     PowerShell_DLL_List
PowerShell_Defender_Exclusions  PowerShell_DnsClientCache
PowerShell_Dns_Cache            PowerShell_Docker_Containers
PowerShell_Drivers              PowerShell_LocalAdmin
PowerShell_LocalGroups          PowerShell_LocalUsers
PowerShell_Local_Group_List     PowerShell_NamedPipes
PowerShell_NetNeighbor          PowerShell_NetRoute
PowerShell_NetUserAdministrators PowerShell_NetworkAdapters
PowerShell_NetworkIPAddresses   PowerShell_NetworkIPConfiguration
PowerShell_NetworkShares        PowerShell_ParseScheduledTasks
PowerShell_ProcessList_CimInstance PowerShell_ProcessList_WMI
PowerShell_Process_Cmdline      PowerShell_Processes
PowerShell_ProcessesIncludingServices PowerShell_RecycleBinParsing
PowerShell_SMBMapping           PowerShell_SMBOpenFile
PowerShell_SMBSession           PowerShell_Services_List
PowerShell_Startup_Commands     PowerShell_SystemInformation
PowerShell_TCPConnections       PowerShell_User_List
PowerShell_WMIProviders         PowerShell_WMIRepositoryAuditing
PowerShell_Wireless_Network_Connections
```

### Large mode extras (+1)

```
MagnetForensics_RAMCapture
```
