<#
.SYNOPSIS
    Installs the LongHorizons Telemetry Agent as a Windows service.

.DESCRIPTION
    Copies agent.exe and config.toml into C:\ProgramData\LongHorizonsAgent\,
    creates a Windows service running as LocalSystem, configures auto-start
    and failure recovery, and starts the service.

    Run from an Administrator PowerShell prompt.

.PARAMETER BinaryPath
    Path to agent.exe. Defaults to ".\agent.exe" (same directory as this script).

.PARAMETER ConfigPath
    Path to config.toml. Defaults to ".\config.toml" (same directory as this script).

.PARAMETER InstallDir
    Destination directory. Defaults to "C:\ProgramData\LongHorizonsAgent".

.PARAMETER ServiceName
    Windows service name. Defaults to "LongHorizonsTelemetryAgent".

.PARAMETER SkipStart
    Install the service but don't start it. Use when you want to verify
    configuration before the agent begins collecting events.

.EXAMPLE
    .\install.ps1
    Install with defaults — agent.exe and config.toml must be in the same directory.

.EXAMPLE
    .\install.ps1 -ConfigPath "C:\my-config.toml"
    Install using a specific config file.

.EXAMPLE
    .\install.ps1 -SkipStart
    Install the service but don't start it — edit config first, then start manually.

.NOTES
    Requires Administrator privileges.
    The agent runs as LocalSystem for ETW kernel trace access.
#>

param(
    [string]$BinaryPath = ".\agent.exe",
    [string]$ConfigPath = ".\config.toml",
    [string]$InstallDir = "C:\ProgramData\LongHorizonsAgent",
    [string]$ServiceName = "LongHorizonsTelemetryAgent",
    [switch]$SkipStart
)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── Banner ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   LongHorizons Telemetry Agent — Windows Service Installer   ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Check Administrator ──────────────────────────────────────────────────────

Write-Host "[0/5] Checking prerequisites..." -ForegroundColor Yellow

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  ✗ ERROR: Administrator privileges required." -ForegroundColor Red
    Write-Host "    This script installs a Windows service and starts an ETW kernel trace."
    Write-Host "    Both operations require Administrator rights."
    Write-Host ""
    Write-Host "    To fix: Right-click PowerShell → 'Run as Administrator', then re-run:"
    Write-Host "      .\install.ps1"
    Write-Host ""
    exit 1
}
Write-Host "  ✓ Running as Administrator" -ForegroundColor Green

# ── Resolve paths ────────────────────────────────────────────────────────────

# If the user gave a relative path, resolve it relative to the script directory
if (-not (Test-Path $BinaryPath)) {
    $resolved = Join-Path $scriptDir (Split-Path $BinaryPath -Leaf)
    if (Test-Path $resolved) { $BinaryPath = $resolved }
}
if (-not (Test-Path $ConfigPath)) {
    $resolved = Join-Path $scriptDir (Split-Path $ConfigPath -Leaf)
    if (Test-Path $resolved) { $ConfigPath = $resolved }
}

if (-not (Test-Path $BinaryPath)) {
    Write-Host "  ✗ ERROR: agent.exe not found." -ForegroundColor Red
    Write-Host "    Looked at: $BinaryPath"
    Write-Host "    Make sure you extracted ALL files from release.zip into the same directory."
    Write-Host "    You should have agent.exe, config.toml, and install.ps1 in one folder."
    Write-Host ""
    Write-Host "    Expected layout after extracting release.zip:"
    Write-Host "      $scriptDir\"
    Write-Host "        agent.exe"
    Write-Host "        config.toml"
    Write-Host "        install.ps1       ← you are here"
    Write-Host "        uninstall.ps1"
    Write-Host ""
    exit 1
}

if (-not (Test-Path $ConfigPath)) {
    Write-Host "  ✗ ERROR: config.toml not found." -ForegroundColor Red
    Write-Host "    Looked at: $ConfigPath"
    Write-Host "    Edit config.toml before installing — at minimum set:"
    Write-Host "      agent.id              = unique host identifier"
    Write-Host "      export.events.endpoint = Elasticsearch URL"
    Write-Host "      export.events.api_key  = ES API key"
    Write-Host ""
    Write-Host "    See CONFIG-GUIDE.md for detailed instructions."
    Write-Host ""
    exit 1
}

Write-Host "  ✓ agent.exe found at: $BinaryPath" -ForegroundColor Green
Write-Host "  ✓ config.toml found at: $ConfigPath" -ForegroundColor Green

# ── Parse & validate config ──────────────────────────────────────────────────

Write-Host ""
Write-Host "[1/5] Validating configuration..." -ForegroundColor Yellow

$configContent = Get-Content $ConfigPath -Raw

# Extract paths from config for directory creation
$dbPathMatch    = [regex]::Match($configContent, 'db_path\s*=\s*"([^"]+)"')
$logDirMatch    = [regex]::Match($configContent, 'log_dir\s*=\s*"([^"]+)"')
$stateDirMatch  = [regex]::Match($configContent, 'state_dir\s*=\s*"([^"]+)"')
$agentIdMatch   = [regex]::Match($configContent, '^\s*id\s*=\s*"([^"]+)"')

$dbPath   = if ($dbPathMatch.Success)   { $dbPathMatch.Groups[1].Value }   else { "$InstallDir\state\agent.db" }
$logDir   = if ($logDirMatch.Success)   { $logDirMatch.Groups[1].Value }   else { "$InstallDir\logs" }
$stateDir = if ($stateDirMatch.Success) { $stateDirMatch.Groups[1].Value } else { "$InstallDir\state" }
$agentId  = if ($agentIdMatch.Success)  { $agentIdMatch.Groups[1].Value }  else { "(not set)" }

Write-Host "  Agent ID:     $agentId"
Write-Host "  Log dir:      $logDir"
Write-Host "  State dir:    $stateDir"
Write-Host "  Install dir:  $InstallDir"
Write-Host "  Service name: $ServiceName"

# Check for CHANGEME placeholders
if ($configContent -match "CHANGEME") {
    Write-Host ""
    Write-Host "  ⚠ WARNING: config.toml still contains CHANGEME placeholders." -ForegroundColor Magenta
    Write-Host "    The service may fail to start. Edit config.toml and set:"
    Write-Host "      - agent.id"
    Write-Host "      - export.events.endpoint"
    Write-Host "      - export.events.api_key"
    Write-Host "    (Repeat endpoint + api_key for exemplars, patterns, diagnostics, health)"
    Write-Host ""
    $continue = Read-Host "    Continue anyway? (y/N)"
    if ($continue -notmatch '^[yY]') {
        Write-Host "  Aborted. Edit config.toml and re-run install.ps1." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "  ✓ No CHANGEME placeholders found" -ForegroundColor Green
}

# ── Create directories ───────────────────────────────────────────────────────

Write-Host ""
Write-Host "[2/5] Creating directories..." -ForegroundColor Yellow

$dirs = @($InstallDir, $logDir, $stateDir)
foreach ($dir in $dirs) {
    try {
        New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Created: $dir" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ ERROR: Cannot create $dir — $_" -ForegroundColor Red
        Write-Host "    Check permissions on the parent directory."
        exit 1
    }
}

# ── Copy binary ──────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "[3/5] Installing binary and config..." -ForegroundColor Yellow

$destBinary = "$InstallDir\agent.exe"
try {
    Copy-Item -Force $BinaryPath $destBinary -ErrorAction Stop
    Write-Host "  ✓ agent.exe → $destBinary" -ForegroundColor Green
} catch {
    Write-Host "  ✗ ERROR: Failed to copy agent.exe — $_" -ForegroundColor Red
    exit 1
}

$destConfig = "$InstallDir\config.toml"
try {
    Copy-Item -Force $ConfigPath $destConfig -ErrorAction Stop
    Write-Host "  ✓ config.toml → $destConfig" -ForegroundColor Green
} catch {
    Write-Host "  ✗ ERROR: Failed to copy config.toml — $_" -ForegroundColor Red
    exit 1
}

# ── Create Windows Service ───────────────────────────────────────────────────

Write-Host ""
Write-Host "[4/5] Creating Windows service..." -ForegroundColor Yellow

# Stop and remove existing service if present
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  Found existing service '$ServiceName' — removing..." -ForegroundColor Gray
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $result = sc.exe delete $ServiceName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ⚠ Warning: Could not remove existing service: $result" -ForegroundColor Yellow
    }
    Start-Sleep -Seconds 1
}

# Create the service
$binaryArgs = "run --config `"$destConfig`""
Write-Host "  Creating service: $ServiceName"
Write-Host "  Command: $destBinary $binaryArgs"

$createResult = sc.exe create $ServiceName `
    binPath= "$destBinary $binaryArgs" `
    start= auto `
    DisplayName= "LongHorizons Telemetry Agent" `
    obj= LocalSystem 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ ERROR: Failed to create service." -ForegroundColor Red
    Write-Host "    sc.exe output: $createResult"
    Write-Host ""
    Write-Host "    Common causes:"
    Write-Host "      - Service name already exists and couldn't be deleted"
    Write-Host "      - Path contains spaces and quoting is off"
    Write-Host "      - System policy prevents service creation"
    exit 1
}
Write-Host "  ✓ Service created" -ForegroundColor Green

# Set service description
sc.exe description $ServiceName "LongHorizons Telemetry Agent — Real-time Windows ETW event capture, tokenization, behavioral baselining, and Elasticsearch export. 200+ ETW providers, 49 event types." 2>&1 | Out-Null

# Set failure recovery: restart on failure (up to 3 times in 24 hours)
sc.exe failure $ServiceName `
    reset= 86400 `
    actions= restart/60000/restart/60000/restart/60000 2>&1 | Out-Null

Write-Host "  ✓ Failure recovery configured (auto-restart on crash)" -ForegroundColor Green

# ── Start service ────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "[5/5] Starting service..." -ForegroundColor Yellow

if ($SkipStart) {
    Write-Host "  ⊘ Skipped (--SkipStart flag set)" -ForegroundColor Gray
    Write-Host "  Start manually: sc.exe start $ServiceName"
} else {
    Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Host "  ✓ Service is RUNNING" -ForegroundColor Green
    } elseif ($svc) {
        Write-Host "  ⚠ Service status: $($svc.Status)" -ForegroundColor Yellow
        Write-Host "    It may still be starting. Check again:"
        Write-Host "      Get-Service $ServiceName"
        Write-Host ""
        Write-Host "    If it stopped, check logs at: $logDir"
        Write-Host "    Also check Windows Event Viewer → '$ServiceName'"
    } else {
        Write-Host "  ✗ Service not found after creation." -ForegroundColor Red
        Write-Host "    Check: sc.exe query $ServiceName"
    }
}

# ── Verify ES index templates exist ──────────────────────────────────────────

Write-Host ""
Write-Host "── Post-install checklist ──" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Before the agent can export events, create the Elasticsearch index templates."
Write-Host "  See ES-INDEX-TEMPLATES.md for the full JSON — copy/paste into Kibana Dev Tools."
Write-Host ""
Write-Host "  Quick check — these should return HTTP 200:"
Write-Host "    curl http://your-es:9200/_index_template/telemetry-events"
Write-Host "    curl http://your-es:9200/_index_template/telemetry-exemplars"
Write-Host "    curl http://your-es:9200/_index_template/telemetry-patterns"
Write-Host "    curl http://your-es:9200/_index_template/telemetry-diagnostics"
Write-Host "    curl http://your-es:9200/_index_template/telemetry-health"
Write-Host ""

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              Installation Complete                           ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Service:   $ServiceName"
Write-Host "  Config:    $destConfig"
Write-Host "  Binary:    $destBinary"
Write-Host "  Logs:      $logDir"
Write-Host "  State:     $stateDir"
Write-Host ""
Write-Host "  Service commands:" -ForegroundColor Cyan
Write-Host "    Get-Service  $ServiceName       # check status"
Write-Host "    sc.exe stop  $ServiceName       # stop agent"
Write-Host "    sc.exe start $ServiceName       # start agent"
Write-Host ""
Write-Host "  View logs:" -ForegroundColor Cyan
Write-Host "    Get-Content $logDir\*.log -Tail 50"
Write-Host ""
Write-Host "  Uninstall:" -ForegroundColor Cyan
Write-Host "    .\uninstall.ps1                 # remove service, keep data"
Write-Host "    .\uninstall.ps1 -RemoveData     # remove service + all data"
Write-Host ""
