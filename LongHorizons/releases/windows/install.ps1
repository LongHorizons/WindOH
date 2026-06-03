# LongHorizons Telemetry Agent — Install Script
# =============================================================================
# This is a convenience wrapper around wizard.exe. It delegates all work
# to the wizard, which handles admin checks, config validation, directory
# creation, service registration, and service start.
#
# Usage:
#   .\install.ps1                  Installs using .\config.toml
#   .\install.ps1 my-config.toml   Installs using a specific config
#   .\install.ps1 -Force           Overwrite an existing installation
#   .\install.ps1 -InstallDir "D:\Agent" config.toml
#
# All arguments are forwarded to: wizard.exe install <args>
# =============================================================================

param(
    [Parameter(Position = 0)]
    [string]$ConfigPath = ".\config.toml",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$wizard = Join-Path $scriptDir "wizard.exe"

if (-not (Test-Path $wizard)) {
    Write-Host "ERROR: wizard.exe not found at: $wizard" -ForegroundColor Red
    Write-Host "The install.ps1 script requires wizard.exe in the same directory." -ForegroundColor Red
    Write-Host "Download the latest release from: <repository-url>" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "  LongHorizons Telemetry Agent — Install" -ForegroundColor Cyan
Write-Host "  Using wizard at: $wizard" -ForegroundColor DarkGray
Write-Host ""

# Pass all arguments through to wizard.exe install
if ($RemainingArgs) {
    & $wizard install $ConfigPath @RemainingArgs
} else {
    & $wizard install $ConfigPath
}

$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    Write-Host ""
    Write-Host "  Installation did not complete successfully (exit code $exitCode)." -ForegroundColor Red
    Write-Host "  Review the output above for details." -ForegroundColor Red
    exit $exitCode
}

Write-Host ""
Write-Host "  Quick status check:" -ForegroundColor Cyan
Write-Host "    wizard.exe status" -ForegroundColor White
Write-Host "    Get-Service LongHorizonsTelemetryAgent" -ForegroundColor White
Write-Host "    Get-Content C:\ProgramData\LongHorizonsAgent\logs\*.log -Tail 30" -ForegroundColor White
