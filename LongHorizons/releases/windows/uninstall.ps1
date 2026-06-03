# LongHorizons Telemetry Agent — Uninstall Script
# =============================================================================
# This is a convenience wrapper around wizard.exe. It delegates all work
# to the wizard, which handles service stopping, service deletion, and
# optional data removal.
#
# Usage:
#   .\uninstall.ps1                  Remove service, keep data
#   .\uninstall.ps1 -RemoveData      Remove service + all data/logs/state
#
# All arguments are forwarded to: wizard.exe uninstall <args>
# =============================================================================

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$wizard = Join-Path $scriptDir "wizard.exe"

if (-not (Test-Path $wizard)) {
    Write-Host "ERROR: wizard.exe not found at: $wizard" -ForegroundColor Red
    Write-Host "The uninstall.ps1 script requires wizard.exe in the same directory." -ForegroundColor Red
    Write-Host "Download the latest release from: <repository-url>" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "  LongHorizons Telemetry Agent — Uninstall" -ForegroundColor Cyan
Write-Host "  Using wizard at: $wizard" -ForegroundColor DarkGray
Write-Host ""

# Pass all arguments through to wizard.exe uninstall
& $wizard uninstall @RemainingArgs

$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    Write-Host ""
    Write-Host "  Uninstall did not complete successfully (exit code $exitCode)." -ForegroundColor Red
    Write-Host "  You may need to run as Administrator or manually clean up." -ForegroundColor Red
    exit $exitCode
}
