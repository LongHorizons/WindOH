# LongHorizons Telemetry Agent — Windows Service Uninstaller
# Run from an Administrator PowerShell prompt.
#
# Usage:
#   .\uninstall.ps1
#   .\uninstall.ps1 -RemoveData  # Also delete logs and state database

param(
    [switch]$RemoveData,
    [string]$ServiceName = "LongHorizonsTelemetryAgent",
    [string]$InstallDir = "C:\ProgramData\LongHorizonsAgent"
)

$ErrorActionPreference = "Continue"

# ── Check Administrator ──────────────────────────────────────────────────────

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

Write-Host "=== LongHorizons Telemetry Agent — Service Uninstaller ===" -ForegroundColor Cyan

# ── Stop service ─────────────────────────────────────────────────────────────

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "Stopping service..." -ForegroundColor Yellow
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Kill agent process if still running (stubborn service)
    $proc = Get-Process -Name agent -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "  Killing orphaned agent process..." -ForegroundColor Gray
        Stop-Process -Name agent -Force -ErrorAction SilentlyContinue
    }

    Write-Host "  Service stopped." -ForegroundColor Green
} else {
    Write-Host "  Service '$ServiceName' not found." -ForegroundColor Gray
}

# ── Delete service ───────────────────────────────────────────────────────────

Write-Host "Removing service..." -ForegroundColor Yellow
sc.exe delete $ServiceName 2>&1 | Out-Null
Write-Host "  Service deleted." -ForegroundColor Green

# ── Optionally remove data ───────────────────────────────────────────────────

if ($RemoveData) {
    Write-Host ""
    Write-Host "Removing data directory: $InstallDir" -ForegroundColor Yellow
    if (Test-Path $InstallDir) {
        Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
        Write-Host "  Data removed." -ForegroundColor Green
    } else {
        Write-Host "  Directory not found." -ForegroundColor Gray
    }
} else {
    Write-Host ""
    Write-Host "Data preserved at: $InstallDir" -ForegroundColor Gray
    Write-Host "To also remove data, run: .\uninstall.ps1 -RemoveData" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== Uninstall Complete ===" -ForegroundColor Cyan
