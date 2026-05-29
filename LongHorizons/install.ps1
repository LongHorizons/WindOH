# LongHorizons Telemetry Agent — Windows Service Installer
# Run from an Administrator PowerShell prompt.
#
# Usage:
#   .\install.ps1
#   .\install.ps1 -ConfigPath "C:\path\to\config.toml"
#   .\install.ps1 -BinaryPath ".\agent.exe" -ConfigPath ".\config.toml"

param(
    [string]$BinaryPath = ".\agent.exe",
    [string]$ConfigPath = ".\config.toml",
    [string]$InstallDir = "C:\ProgramData\LongHorizonsAgent",
    [string]$ServiceName = "LongHorizonsTelemetryAgent",
    [int]$HealthPort = 8080
)

$ErrorActionPreference = "Stop"

# ── Check Administrator ──────────────────────────────────────────────────────

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Re-launch PowerShell as Administrator and try again." -ForegroundColor Red
    exit 1
}

# ── Resolve paths ────────────────────────────────────────────────────────────

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path $BinaryPath)) {
    $BinaryPath = Join-Path $scriptDir "agent.exe"
}
if (-not (Test-Path $ConfigPath)) {
    $ConfigPath = Join-Path $scriptDir "config.toml"
}

if (-not (Test-Path $BinaryPath)) {
    Write-Host "ERROR: agent.exe not found at: $BinaryPath" -ForegroundColor Red
    Write-Host "Extract release.zip and place agent.exe alongside this installer." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $ConfigPath)) {
    Write-Host "ERROR: config.toml not found at: $ConfigPath" -ForegroundColor Red
    Write-Host "Edit the config template first — set agent.id, ES endpoint, and API key." -ForegroundColor Red
    exit 1
}

Write-Host "=== LongHorizons Telemetry Agent — Service Installer ===" -ForegroundColor Cyan
Write-Host "  Binary:    $BinaryPath"
Write-Host "  Config:    $ConfigPath"
Write-Host "  Install:   $InstallDir"
Write-Host "  Service:   $ServiceName"
Write-Host ""

# ── Parse config for key paths ───────────────────────────────────────────────

# Extract paths from the TOML config (simple regex, works for standard configs)
$configContent = Get-Content $ConfigPath -Raw

$dbPathMatch = [regex]::Match($configContent, 'db_path\s*=\s*"([^"]+)"')
$logDirMatch = [regex]::Match($configContent, 'log_dir\s*=\s*"([^"]+)"')
$stateDirMatch = [regex]::Match($configContent, 'state_dir\s*=\s*"([^"]+)"')

$dbPath = if ($dbPathMatch.Success) { $dbPathMatch.Groups[1].Value } else { "$InstallDir\state\agent.db" }
$logDir = if ($logDirMatch.Success) { $logDirMatch.Groups[1].Value } else { "$InstallDir\logs" }
$stateDir = if ($stateDirMatch.Success) { $stateDirMatch.Groups[1].Value } else { "$InstallDir\state" }

# ── Create directories ───────────────────────────────────────────────────────

Write-Host "[1/4] Creating directories..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
Write-Host "  Log dir:  $logDir"
Write-Host "  State dir: $stateDir"

# ── Copy binary ──────────────────────────────────────────────────────────────

Write-Host "[2/4] Installing agent binary..." -ForegroundColor Yellow
$destBinary = "$InstallDir\agent.exe"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item -Force $BinaryPath $destBinary
Write-Host "  Copied to: $destBinary"

# ── Copy config ──────────────────────────────────────────────────────────────

Write-Host "[3/4] Installing config..." -ForegroundColor Yellow
$destConfig = "$InstallDir\config.toml"
Copy-Item -Force $ConfigPath $destConfig
Write-Host "  Copied to: $destConfig"

# ── Validate config has CHANGEME values ──────────────────────────────────────
if ($configContent -match "CHANGEME") {
    Write-Host "  WARNING: config.toml still contains CHANGEME placeholders." -ForegroundColor Magenta
    Write-Host "  Edit $destConfig before starting the service." -ForegroundColor Magenta
}

# ── Create Windows Service ───────────────────────────────────────────────────

Write-Host "[4/4] Creating Windows service..." -ForegroundColor Yellow

# Stop and remove existing service if present
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  Stopping existing service..." -ForegroundColor Gray
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Write-Host "  Removing existing service..." -ForegroundColor Gray
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 2
}

# Create the service
# The agent runs with the 'run' subcommand, pointing to the installed config
$binaryArgs = "run --config `"$destConfig`""
sc.exe create $ServiceName `
    binPath= "$destBinary $binaryArgs" `
    start= auto `
    DisplayName= "LongHorizons Telemetry Agent" `
    obj= LocalSystem 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to create service (exit code $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

# Set service description
sc.exe description $ServiceName "Windows ETW telemetry collection agent — captures, tokenizes, and exports system and security events to Elasticsearch." 2>&1 | Out-Null

# Set failure recovery: restart on failure (3 times, then stop)
sc.exe failure $ServiceName `
    reset= 86400 `
    actions= restart/60000/restart/60000/restart/60000 2>&1 | Out-Null

Write-Host "  Service created: $ServiceName" -ForegroundColor Green

# ── Start service ────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Starting service..." -ForegroundColor Yellow
Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Write-Host "  Service is RUNNING." -ForegroundColor Green
} else {
    Write-Host "  Service did not start. Check logs at: $logDir" -ForegroundColor Red
    Write-Host "  Common issues:"
    Write-Host "    - config.toml has invalid ES endpoint"
    Write-Host "    - Port $HealthPort is in use (change agent.health_port in config)"
    Write-Host "    - Check Windows Event Viewer under '$ServiceName'"
}

# ── Health check ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Testing health endpoint..." -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:$HealthPort/health" -TimeoutSec 10 -ErrorAction Stop
    Write-Host "  Status:  $($health.status)" -ForegroundColor Green
    Write-Host "  Version: $($health.version)"
    Write-Host "  Host:    $($health.host.name) ($($health.host.id))"
    Write-Host "  OS:      $($health.host.os_version)"
} catch {
    Write-Host "  Health check failed. The service may still be starting." -ForegroundColor Magenta
    Write-Host "  Try again in a few seconds: Invoke-RestMethod http://127.0.0.1:$HealthPort/health"
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Service name:  $ServiceName"
Write-Host "Config:        $destConfig"
Write-Host "Logs:          $logDir"
Write-Host "State/DB:      $stateDir"
Write-Host "Health:        http://127.0.0.1:$HealthPort/health"
Write-Host ""
Write-Host "Manage with standard Windows service commands:"
Write-Host "  sc.exe start  $ServiceName"
Write-Host "  sc.exe stop   $ServiceName"
Write-Host "  sc.exe query  $ServiceName"
Write-Host ""
Write-Host "To uninstall, run: .\uninstall.ps1"
