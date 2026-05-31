<#
.SYNOPSIS
    Uninstalls the LongHorizons Telemetry Agent Windows service.

.DESCRIPTION
    Stops the agent service, stops the ETW trace session, deletes the Windows
    service, and optionally removes all agent data (logs, database, state).

    Run from an Administrator PowerShell prompt.

.PARAMETER RemoveData
    Also delete C:\ProgramData\LongHorizonsAgent\ (logs, database, state, config).
    Without this flag, data is preserved for re-installation.

.PARAMETER ServiceName
    Windows service name. Defaults to "LongHorizonsTelemetryAgent".

.PARAMETER InstallDir
    Agent installation directory. Defaults to "C:\ProgramData\LongHorizonsAgent".

.PARAMETER EtwSessionName
    ETW trace session name to stop. Defaults to "LongHorizonsTelemetry".

.EXAMPLE
    .\uninstall.ps1
    Stop and remove the service. Keep all data for re-install.

.EXAMPLE
    .\uninstall.ps1 -RemoveData
    Full cleanup: stop service, stop ETW, delete everything.

.NOTES
    Requires Administrator privileges.
    The ETW session stop requires the session name to match what was configured.
#>

param(
    [switch]$RemoveData,
    [string]$ServiceName = "LongHorizonsTelemetryAgent",
    [string]$InstallDir = "C:\ProgramData\LongHorizonsAgent",
    [string]$EtwSessionName = "LongHorizonsTelemetry"
)

$ErrorActionPreference = "Continue"

# ── Banner ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  LongHorizons Telemetry Agent — Service Uninstaller          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($RemoveData) {
    Write-Host "  Mode: FULL REMOVAL — service + all data will be deleted" -ForegroundColor Magenta
    Write-Host ""
    $confirm = Read-Host "  This will delete $InstallDir and all contents. Continue? (y/N)"
    if ($confirm -notmatch '^[yY]') {
        Write-Host "  Aborted." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "  Mode: Service removal only — data preserved at $InstallDir" -ForegroundColor Gray
    Write-Host "  Use -RemoveData flag to also delete logs, database, and state." -ForegroundColor Gray
}
Write-Host ""

# ── Check Administrator ──────────────────────────────────────────────────────

Write-Host "[1/4] Checking prerequisites..." -ForegroundColor Yellow

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "  ✗ ERROR: Administrator privileges required." -ForegroundColor Red
    Write-Host "    Right-click PowerShell → 'Run as Administrator', then re-run:"
    Write-Host "      .\uninstall.ps1"
    Write-Host ""
    exit 1
}
Write-Host "  ✓ Running as Administrator" -ForegroundColor Green

# ── Stop ETW session ─────────────────────────────────────────────────────────

Write-Host ""
Write-Host "[2/4] Stopping ETW trace session..." -ForegroundColor Yellow

$etwResult = logman stop $EtwSessionName -ets 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ ETW session '$EtwSessionName' stopped" -ForegroundColor Green
} else {
    Write-Host "  ⊘ ETW session not running (or already stopped)" -ForegroundColor Gray
}
Start-Sleep -Seconds 2

# ── Stop and delete service ──────────────────────────────────────────────────

Write-Host ""
Write-Host "[3/4] Removing Windows service..." -ForegroundColor Yellow

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "  Stopping service '$ServiceName'..." -ForegroundColor Gray
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Verify it stopped
    $svcAfter = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svcAfter -and $svcAfter.Status -ne 'Stopped') {
        Write-Host "  ⚠ Service did not stop cleanly. Killing process..." -ForegroundColor Yellow
        $proc = Get-Process -Name agent -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Name agent -Force -ErrorAction SilentlyContinue
            Write-Host "  Killed agent.exe (PID $($proc.Id))" -ForegroundColor Gray
        }
        Start-Sleep -Seconds 2
    }

    Write-Host "  Deleting service..." -ForegroundColor Gray
    $deleteResult = sc.exe delete $ServiceName 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Service '$ServiceName' deleted" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Failed to delete service: $deleteResult" -ForegroundColor Red
        Write-Host "    Try: sc.exe delete $ServiceName"
    }
} else {
    Write-Host "  ⊘ Service '$ServiceName' not found (already removed?)" -ForegroundColor Gray
}

# Also check for any leftover agent processes
$agentProcs = Get-Process -Name agent -ErrorAction SilentlyContinue
if ($agentProcs) {
    Write-Host "  Killing orphaned agent.exe processes..." -ForegroundColor Gray
    $agentProcs | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        Write-Host "  Killed PID $($_.Id)" -ForegroundColor Gray
    }
}

# ── Optionally remove data ───────────────────────────────────────────────────

Write-Host ""
Write-Host "[4/4] Data cleanup..." -ForegroundColor Yellow

if ($RemoveData) {
    if (Test-Path $InstallDir) {
        try {
            Remove-Item -Recurse -Force $InstallDir -ErrorAction Stop
            Write-Host "  ✓ Removed: $InstallDir" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Could not fully remove $InstallDir" -ForegroundColor Red
            Write-Host "    $_"
            Write-Host "    Some files may be locked. Close any programs using them and try:"
            Write-Host "      Remove-Item -Recurse -Force $InstallDir"
        }
    } else {
        Write-Host "  ⊘ Directory not found: $InstallDir" -ForegroundColor Gray
    }
} else {
    if (Test-Path $InstallDir) {
        Write-Host "  ⊘ Data preserved at: $InstallDir" -ForegroundColor Gray
        Write-Host "    To delete it: Remove-Item -Recurse -Force $InstallDir"
        Write-Host "    Or re-run: .\uninstall.ps1 -RemoveData"
    } else {
        Write-Host "  ⊘ No data directory found" -ForegroundColor Gray
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              Uninstall Complete                               ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

if (-not $RemoveData) {
    Write-Host "  To re-install:" -ForegroundColor Cyan
    Write-Host "    1. Edit config.toml if needed"
    Write-Host "    2. Run: .\install.ps1"
    Write-Host ""
}
