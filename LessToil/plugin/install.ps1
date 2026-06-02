#!/usr/bin/env pwsh
<#
.SYNOPSIS
    LessToil Plugin — PowerShell Installer for Windows
.DESCRIPTION
    Installs the repo-cognition plugin to ~/.claude/plugins/repo-cognition/
    by fetching the plugin from GitHub and setting up the target project.
    Supports 56 languages (41 tree-sitter + 15 regex).

.PARAMETER ProjectDir
    Path to the project to set up. Defaults to current directory.

.PARAMETER PluginOnly
    Only install the plugin files, skip project CLAUDE.md setup.

.PARAMETER Reindex
    Force immediate index rebuild after installation.

.PARAMETER FromZip
    Path to a local release zip file (repo-cognition.zip). Takes priority over GitHub.

.PARAMETER Accept
    Non-interactive mode: auto-confirm all prompts without asking.

.PARAMETER NoVenv
    Skip creating ~/.claude/venv/, use system Python directly.

.PARAMETER Branch
    Git branch to fetch from GitHub. Defaults to "main".

.PARAMETER RepoUrl
    GitHub repository URL. Defaults to "https://github.com/LongHorizons/WindOH/LessToil".

.PARAMETER Help
    Show this help message.

.EXAMPLE
    .\install.ps1
    Installs plugin and sets up the current directory.

.EXAMPLE
    .\install.ps1 -ProjectDir C:\my-project -Reindex
    Installs plugin for C:\my-project and runs first index.

.EXAMPLE
    .\install.ps1 -FromZip .\repo-cognition.zip -Accept
    Installs from a local release zip without any prompts.

.EXAMPLE
    Invoke-Expression (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/LongHorizons/WindOH/LessToil/main/plugins/repo-cognition/install.ps1").Content
    One-liner from GitHub (run from your project directory).
#>

[CmdletBinding()]
param(
    [string]$ProjectDir = (Get-Location).Path,
    [switch]$PluginOnly,
    [switch]$Reindex,
    [string]$FromZip = "",
    [switch]$Accept,
    [switch]$NoVenv,
    [string]$Branch = "main",
    [string]$RepoUrl = "https://github.com/LongHorizons/WindOH/LessToil",
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# --- Constants -----------------------------------------------------------------
$PLUGIN_NAME = "repo-cognition"
$PLUGIN_DIR = Join-Path $HOME ".claude\plugins\$PLUGIN_NAME"
$SCRIPT_DIR = Split-Path $MyInvocation.MyCommand.Path -Parent
$TEMP_CLONE = Join-Path ([System.IO.Path]::GetTempPath()) "claude-code-plugin-$PID"

# --- ANSI helpers (Windows 10+ console) ----------------------------------------
function Write-Header { Write-Host "`n==============================================" -ForegroundColor Cyan }
function Write-Step { Write-Host "[$($args[0])]" -ForegroundColor Yellow -NoNewline; Write-Host " $($args[1])" }
function Write-OK { Write-Host "      OK" -ForegroundColor Green }
function Write-Warn { Write-Host "      WARNING: $($args[0])" -ForegroundColor Yellow }
function Write-Err { Write-Host "      ERROR: $($args[0])" -ForegroundColor Red }
function Write-Detail { Write-Host "      $($args[0])" -ForegroundColor Gray }

# --- Parse arguments -----------------------------------------------------------
if ($Help -or $args -contains '-h' -or $args -contains '--help') {
    @"
Usage: .\install.ps1 [OPTIONS]

Options:
  -ProjectDir PATH    Set up this project (default: current directory)
  -PluginOnly         Only install the plugin, skip project setup
  -Reindex            Force immediate index rebuild after install
  -FromZip FILE       Install from a local release zip instead of GitHub
  -Accept             Non-interactive mode: auto-confirm all prompts
  -NoVenv             Skip creating ~/.claude/venv/, use system Python directly
  -Branch NAME        Git branch to fetch from GitHub (default: main)
  -RepoUrl URL        GitHub repository URL
  -Help               Show this help

Source priority: -FromZip > local clone > GitHub

One-liner from GitHub:
  irm https://raw.githubusercontent.com/LongHorizons/WindOH/LessToil/main/plugins/repo-cognition/install.ps1 | iex
"@ | Write-Host
    exit 0
}

if (-not $PluginOnly -and -not (Test-Path $ProjectDir)) {
    Write-Err "Project directory not found: $ProjectDir"
    Write-Err "Use -ProjectDir to specify a valid path, or -PluginOnly to skip"
    exit 1
}

# --- Detect Python -------------------------------------------------------------
$PYTHON = $null
foreach ($candidate in @("python3", "python")) {
    try {
        $ver = & $candidate --version 2>&1
        if ($ver -match "Python 3\.(\d+)") {
            $minor = [int]$Matches[1]
            if ($minor -ge 8) {
                $PYTHON = $candidate
                break
            }
        }
    } catch { }
}

if (-not $PYTHON) {
    if ($Accept) {
        Write-Host "Python 3.8+ not found. -Accept: attempting auto-install..." -ForegroundColor Yellow
        $installed = $false
        try {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-Detail "Detected winget — installing Python 3..."
                winget install Python.Python.3.12 --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                $installed = $true
            }
        } catch { }
        if (-not $installed) {
            try {
                if (Get-Command choco -ErrorAction SilentlyContinue) {
                    Write-Detail "Detected Chocolatey — installing Python 3..."
                    choco install python -y 2>&1 | Out-Null
                    $installed = $true
                }
            } catch { }
        }
        if (-not $installed) {
            Write-Detail "No package manager found (winget/choco). Install Python manually from https://python.org"
            Write-Detail "Then re-run this installer."
        }
        # Re-detect
        foreach ($candidate in @("python3", "python")) {
            try {
                $ver = & $candidate --version 2>&1
                if ($ver -match "Python 3\.(\d+)") {
                    $minor = [int]$Matches[1]
                    if ($minor -ge 8) {
                        $PYTHON = $candidate
                        break
                    }
                }
            } catch { }
        }
    }
    if (-not $PYTHON) {
        Write-Err "Python 3.8+ required but not found. Install from https://python.org and ensure it is on your PATH."
        Write-Err "Or re-run with -Accept to attempt automatic installation."
        exit 1
    }
}

$pyVer = & $PYTHON --version 2>&1

# Resolve Python to use for installation
$INSTALL_PYTHON = $PYTHON

# --- Create shared venv ---------------------------------------------------------
$VENV_DIR = Join-Path $HOME ".claude\venv"
if (-not $NoVenv) {
    if (-not (Test-Path $VENV_DIR)) {
        Write-Host "Creating shared venv at $VENV_DIR ..." -ForegroundColor Gray
        try {
            & $INSTALL_PYTHON -m venv $VENV_DIR 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "venv creation failed"
            }
        } catch {
            Write-Warn "venv creation failed — falling back to system Python."
            Write-Warn "You may need to install the Python venv module."
            $NoVenv = $true
        }
    }
    if (-not $NoVenv) {
        # Locate venv python
        $venvPythonPath = Join-Path $VENV_DIR "Scripts\python.exe"
        if (Test-Path $venvPythonPath) {
            # Upgrade pip inside the venv
            & $venvPythonPath -m pip install --quiet --upgrade pip 2>&1 | Out-Null
            $INSTALL_PYTHON = $venvPythonPath
            Write-Detail "Venv ready: $INSTALL_PYTHON"
        } else {
            Write-Warn "venv python not found — falling back to system Python."
            $NoVenv = $true
        }
    }
}

if ($NoVenv) {
    $VENV_DIR = ""
}

Write-Host ""
Write-Header
Write-Host "  LessToil Plugin v0.4.0 — Installer" -ForegroundColor Cyan
Write-Header
Write-Host "  Python:   $INSTALL_PYTHON ($(& $INSTALL_PYTHON --version 2>&1))"
if ($VENV_DIR) {
    Write-Host "  Venv:     $VENV_DIR"
}
Write-Host "  Plugin:   $PLUGIN_DIR"
Write-Host "  Project:  $ProjectDir"
Write-Host "  Source:   $RepoUrl ($Branch)"
Write-Header
Write-Host ""

# ==============================================================================
# STEP 0: Resolve plugin source (zip → local → GitHub)
# ==============================================================================
$ZIP_SOURCE = ""
$ZIP_TEMP = ""

# -FromZip takes priority
if ($FromZip) {
    if (Test-Path $FromZip) {
        $ZIP_SOURCE = $FromZip
    } else {
        Write-Err "--from-zip file not found: $FromZip"
        exit 1
    }
}

# Auto-detect zip alongside installer or relative to Presentation folder
if (-not $ZIP_SOURCE) {
    $candidates = @(
        (Join-Path $SCRIPT_DIR "repo-cognition.zip"),
        (Join-Path $SCRIPT_DIR "..\Presentation\plugin\repo-cognition.zip"),
        (Join-Path $SCRIPT_DIR "..\..\Presentation\plugin\repo-cognition.zip")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $ZIP_SOURCE = $c
            break
        }
    }
}

# Extract zip if found and we're not already in a local clone
if ($ZIP_SOURCE -and -not (Test-Path (Join-Path $SCRIPT_DIR "core\manifest.py"))) {
    $ZIP_TEMP = Join-Path ([System.IO.Path]::GetTempPath()) "repo-cognition-$PID"
    if (Test-Path $ZIP_TEMP) { Remove-Item -Recurse -Force $ZIP_TEMP -ErrorAction SilentlyContinue }
    Write-Detail "Using release zip: $ZIP_SOURCE"

    # Use .NET for zip extraction (no external dependency needed)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZIP_SOURCE, $ZIP_TEMP)
    $SCRIPT_DIR = $ZIP_TEMP
    Write-Detail "Extracted to: $ZIP_TEMP"
}

# ==============================================================================
# STEP 1: Fetch plugin from GitHub (if no local source)
# ==============================================================================
Write-Step "1/7" "Fetching plugin from GitHub..."

# Determine if we're running from a local clone or need to download
$LOCAL_PLUGIN_SRC = $null
if (Test-Path (Join-Path $SCRIPT_DIR "core\manifest.py")) {
    $LOCAL_PLUGIN_SRC = $SCRIPT_DIR
    Write-Detail "Using local plugin source: $LOCAL_PLUGIN_SRC"
} else {
    # Check for git
    $GIT = $null
    try { $GIT = (Get-Command git -ErrorAction Stop).Source } catch { }

    if ($GIT) {
        Write-Detail "Cloning plugin from $RepoUrl (branch: $Branch)..."
        Write-Detail "Using sparse checkout for plugins/repo-cognition/"

        # Clean up any previous temp clone
        if (Test-Path $TEMP_CLONE) { Remove-Item -Recurse -Force $TEMP_CLONE -ErrorAction SilentlyContinue }

        # Sparse checkout: only fetch the plugin directory
        git clone --depth 1 --filter=blob:none --sparse "$RepoUrl" "$TEMP_CLONE" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            # Fallback: full shallow clone (older git)
            Write-Detail "Sparse checkout failed, trying full shallow clone..."
            Remove-Item -Recurse -Force $TEMP_CLONE -ErrorAction SilentlyContinue
            git clone --depth 1 "$RepoUrl" "$TEMP_CLONE" 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Err "Failed to clone repository. Check your internet connection and GitHub access."
                exit 1
            }
        } else {
            Push-Location $TEMP_CLONE
            git sparse-checkout set "plugins/repo-cognition" 2>&1 | Out-Null
            Pop-Location
        }

        $LOCAL_PLUGIN_SRC = Join-Path $TEMP_CLONE "plugins\repo-cognition"
    } else {
        Write-Err "git not found on PATH. The installer requires git to fetch the plugin from GitHub."
        Write-Err ""
        Write-Err "Install git from https://git-scm.com/download/win or run this script from"
        Write-Err "a local clone of the repository."
        exit 1
    }
}

if (-not $LOCAL_PLUGIN_SRC -or -not (Test-Path (Join-Path $LOCAL_PLUGIN_SRC "core\manifest.py"))) {
    Write-Err "Plugin source not found at: $LOCAL_PLUGIN_SRC"
    exit 1
}

Write-OK

# ==============================================================================
# STEP 2: Copy plugin files
# ==============================================================================
Write-Step "2/7" "Installing plugin files..."

# Create plugin directory
if (-not (Test-Path $PLUGIN_DIR)) { New-Item -ItemType Directory -Path $PLUGIN_DIR -Force | Out-Null }

function Copy-PluginDir {
    param([string]$Name, [string]$SrcSubdir, [string]$DstSubdir)
    $src = if ($SrcSubdir) { Join-Path $LOCAL_PLUGIN_SRC $SrcSubdir } else { $LOCAL_PLUGIN_SRC }
    $dst = if ($DstSubdir) { Join-Path $PLUGIN_DIR $DstSubdir } else { $PLUGIN_DIR }

    if (Test-Path $src) {
        if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
        Copy-Item -Path "$src\*" -Destination $dst -Recurse -Force -ErrorAction SilentlyContinue
        $count = (Get-ChildItem -Path $dst -File -Recurse).Count
        Write-Detail "$Name ($count files)"
    }
}

Copy-PluginDir "core modules"       "core"              "core"
Copy-PluginDir "hooks"              "hooks"             "hooks"
Copy-PluginDir "commands"           "commands"          "commands"
Copy-PluginDir "agents"             "agents"            "agents"
Copy-PluginDir "skills"             "skills"            "skills"
Copy-PluginDir "scripts"            "scripts"           "scripts"
Copy-PluginDir "plugin metadata"    ".claude-plugin"    ".claude-plugin"
Copy-PluginDir "install scripts"    $null               "."

Write-Host ""

# Rewrite hooks.json to use the resolved Python path (venv or system).
# Prevents "python: command not found" on systems where the command name differs.
$hooksJsonPath = Join-Path $PLUGIN_DIR "hooks\hooks.json"
if (Test-Path $hooksJsonPath) {
    $pythonAbs = (Get-Command $INSTALL_PYTHON -ErrorAction SilentlyContinue).Source
    if (-not $pythonAbs) { $pythonAbs = $INSTALL_PYTHON }
    $hooksContent = Get-Content $hooksJsonPath -Raw -Encoding UTF8
    $hooksContent = $hooksContent -replace '"python "', '"' + $pythonAbs + ' "'
    Set-Content -Path $hooksJsonPath -Value $hooksContent -Encoding UTF8 -NoNewline
    Write-Detail "hooks.json: using $pythonAbs"
}

# ==============================================================================
# STEP 3: Install Python dependencies
# ==============================================================================
Write-Step "3/7" "Installing Python dependencies..."

# Core dependencies
$CORE_PACKAGES = @("tree-sitter", "pyyaml")

# Tree-sitter grammar packages: pip-name -> import-name
$GRAMMAR_PACKAGES = @(
    @{pip="tree-sitter-python";      imp="tree_sitter_python"},
    @{pip="tree-sitter-typescript";  imp="tree_sitter_typescript"},
    @{pip="tree-sitter-go";          imp="tree_sitter_go"},
    @{pip="tree-sitter-rust";        imp="tree_sitter_rust"},
    @{pip="tree-sitter-java";        imp="tree_sitter_java"},
    @{pip="tree-sitter-c";           imp="tree_sitter_c"},
    @{pip="tree-sitter-cpp";         imp="tree_sitter_cpp"},
    @{pip="tree-sitter-c-sharp";     imp="tree_sitter_c_sharp"},
    @{pip="tree-sitter-ruby";        imp="tree_sitter_ruby"},
    @{pip="tree-sitter-php";         imp="tree_sitter_php"},
    @{pip="tree-sitter-swift";       imp="tree_sitter_swift"},
    @{pip="tree-sitter-scala";       imp="tree_sitter_scala"},
    @{pip="tree-sitter-kotlin";      imp="tree_sitter_kotlin"},
    @{pip="tree-sitter-lua";         imp="tree_sitter_lua"},
    @{pip="tree-sitter-sql";         imp="tree_sitter_sql"},
    @{pip="tree-sitter-bash";        imp="tree_sitter_bash"},
    @{pip="tree-sitter-html";        imp="tree_sitter_html"},
    @{pip="tree-sitter-css";         imp="tree_sitter_css"},
    @{pip="tree-sitter-json";        imp="tree_sitter_json"},
    @{pip="tree-sitter-yaml";        imp="tree_sitter_yaml"},
    @{pip="tree-sitter-toml";        imp="tree_sitter_toml"},
    @{pip="tree-sitter-markdown";    imp="tree_sitter_markdown"},
    @{pip="tree-sitter-dockerfile";  imp="tree_sitter_dockerfile"},
    @{pip="tree-sitter-hcl";         imp="tree_sitter_hcl"},
    @{pip="tree-sitter-graphql";     imp="tree_sitter_graphql"},
    @{pip="tree-sitter-haskell";     imp="tree_sitter_haskell"},
    @{pip="tree-sitter-ocaml";       imp="tree_sitter_ocaml"},
    @{pip="tree-sitter-elixir";      imp="tree_sitter_elixir"},
    @{pip="tree-sitter-dart";        imp="tree_sitter_dart"},
    @{pip="tree-sitter-zig";         imp="tree_sitter_zig"},
    @{pip="tree-sitter-solidity";    imp="tree_sitter_solidity"},
    @{pip="tree-sitter-svelte";      imp="tree_sitter_svelte"},
    @{pip="tree-sitter-make";        imp="tree_sitter_make"},
    @{pip="tree-sitter-cmake";       imp="tree_sitter_cmake"},
    @{pip="tree-sitter-powershell";  imp="tree_sitter_powershell"},
    @{pip="tree-sitter-nix";         imp="tree_sitter_nix"}
)

# Check already-installed packages
$TO_INSTALL = @()
$ALREADY = @()
$FAILED = @()
$MISSING_IMPORTS = @()

# Core packages
foreach ($pkg in $CORE_PACKAGES) {
    $impName = $pkg -replace '-', '_'
    try {
        & $INSTALL_PYTHON -c "import $impName" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $ALREADY += $pkg } else { $TO_INSTALL += $pkg }
    } catch { $TO_INSTALL += $pkg }
}

# Grammar packages
foreach ($entry in $GRAMMAR_PACKAGES) {
    try {
        & $INSTALL_PYTHON -c "import $($entry.imp)" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $ALREADY += $entry.pip } else { $TO_INSTALL += $entry.pip }
    } catch { $TO_INSTALL += $entry.pip }
}

Write-Detail "$($ALREADY.Count) packages already installed"

if ($TO_INSTALL.Count -gt 0) {
    Write-Detail "Installing $($TO_INSTALL.Count) packages..."

    foreach ($pkg in $TO_INSTALL) {
        Write-Host -NoNewline "      $pkg ... "
        try {
            & $INSTALL_PYTHON -m pip install --quiet $pkg 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "OK" -ForegroundColor Green
            } else {
                Write-Host "FAILED" -ForegroundColor Red
                $FAILED += $pkg
                $found = $GRAMMAR_PACKAGES | Where-Object { $_.pip -eq $pkg }
                if ($found) { $MISSING_IMPORTS += $found.imp }
                else { $MISSING_IMPORTS += ($pkg -replace '-', '_') }
            }
        } catch {
            Write-Host "FAILED" -ForegroundColor Red
            $FAILED += $pkg
        }
    }

    if ($FAILED.Count -gt 0) {
        Write-Host ""
        Write-Host "      ---------------------------------------------" -ForegroundColor Gray
        Write-Warn "$($FAILED.Count) grammar package(s) could not be installed."
        Write-Warn "Regex-based symbol extraction will be used for:"
        foreach ($name in $MISSING_IMPORTS) {
            Write-Warn "  - $name"
        }
        Write-Host ""
        Write-Warn "To install manually: pip install $($FAILED -join ' ')"
        Write-Host ""
        Write-Detail "Missing grammars do NOT affect indexing -- all 56 languages"
        Write-Detail "are supported via regex fallback. Tree-sitter grammars"
        Write-Detail "provide higher-accuracy symbol extraction only."
        Write-Host "      ---------------------------------------------" -ForegroundColor Gray
    }
} else {
    Write-Detail "All packages already installed."
}

# Verify tree-sitter core
Write-Host ""
Write-Host -NoNewline "      Verifying tree-sitter core ... "
try {
    & $INSTALL_PYTHON -c "import tree_sitter; print('OK')" 2>&1 | Out-Null
    Write-Host "OK" -ForegroundColor Green
} catch {
    Write-Warn "tree-sitter core not importable"
}

# Count verified grammars
$verified = 0
foreach ($entry in $GRAMMAR_PACKAGES) {
    try {
        & $INSTALL_PYTHON -c "import $($entry.imp)" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $verified++ }
    } catch { }
}
Write-Detail "Verified grammars: $verified / $($GRAMMAR_PACKAGES.Count)"

Write-Host ""

# ==============================================================================
# STEP 4: Validate plugin
# ==============================================================================
Write-Step "4/7" "Validating core modules..."

$PASSED = 0
$MODULE_FAILURES = 0
$coreFiles = Get-ChildItem -Path (Join-Path $PLUGIN_DIR "core\*.py") -File

foreach ($mod in $coreFiles) {
    try {
        $escapedPath = $mod.FullName -replace '\\', '\\'
        & $INSTALL_PYTHON -c "import ast; ast.parse(open('$escapedPath', encoding='utf-8').read()); print('OK')" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $PASSED++ }
        else { Write-Err "FAILED: $($mod.Name)"; $MODULE_FAILURES++ }
    } catch { Write-Err "FAILED: $($mod.Name)"; $MODULE_FAILURES++ }
}
Write-Detail "$PASSED passed, $MODULE_FAILURES failed"

# Quick import check
$importTest = @"
import sys
sys.path.insert(0, r'$PLUGIN_DIR')
from core.manifest import init_db, SCHEMA_VERSION
init_db()
print(f'      Schema v{SCHEMA_VERSION} ready')
"@
$importTest | & $INSTALL_PYTHON 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Detail "Plugin verified."
} else {
    Write-Warn "Plugin import check failed -- may need manual inspection."
}
Write-Host ""

# ==============================================================================
# STEP 5: Set up project CLAUDE.md
# ==============================================================================
if (-not $PluginOnly) {
    Write-Step "5/7" "Setting up project at $ProjectDir..."

    $projectClaudeDir = Join-Path $ProjectDir ".claude"
    $projectClaudeFile = Join-Path $projectClaudeDir "CLAUDE.md"
    $projectIndexDir = Join-Path $ProjectDir ".claude\index\repo-cognition"

    if (-not (Test-Path $projectClaudeDir)) { New-Item -ItemType Directory -Path $projectClaudeDir -Force | Out-Null }
    if (-not (Test-Path $projectIndexDir)) { New-Item -ItemType Directory -Path $projectIndexDir -Force | Out-Null }

    $projectName = Split-Path $ProjectDir -Leaf

    # Detect language
    $LANG_HINT = ""
    $WORKSPACE_INFO = ""
    if (Test-Path (Join-Path $ProjectDir "Cargo.toml")) {
        $LANG_HINT = "Rust"
        $cargoContent = Get-Content (Join-Path $ProjectDir "Cargo.toml") -Raw -ErrorAction SilentlyContinue
        if ($cargoContent -match '\[workspace\]') {
            $members = [regex]::Matches($cargoContent, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
            if ($members) { $WORKSPACE_INFO = "Workspace crates: $($members -join ' ')" }
        }
    } elseif (Get-ChildItem $ProjectDir -Filter *.ts,*.tsx -ErrorAction SilentlyContinue | Select-Object -First 1) {
        $LANG_HINT = "TypeScript"
    } elseif (Get-ChildItem $ProjectDir -Filter *.py -ErrorAction SilentlyContinue | Select-Object -First 1) {
        $LANG_HINT = "Python"
    } elseif (Get-ChildItem $ProjectDir -Filter *.go -ErrorAction SilentlyContinue | Select-Object -First 1) {
        $LANG_HINT = "Go"
    }

    # Ensure .claude/index/ is in .gitignore
    $gitignoreFile = Join-Path $ProjectDir ".gitignore"
    $gitignoreEntry = ".claude/index/"
    if (Test-Path $gitignoreFile) {
        $gitignoreContent = Get-Content $gitignoreFile -Raw -ErrorAction SilentlyContinue
        if ($gitignoreContent -notmatch [regex]::Escape($gitignoreEntry)) {
            Add-Content -Path $gitignoreFile -Value "`n$gitignoreEntry" -Encoding UTF8
            Write-Detail "Added .claude/index/ to .gitignore"
        }
    } else {
        Set-Content -Path $gitignoreFile -Value $gitignoreEntry -Encoding UTF8
        Write-Detail "Created .gitignore with .claude/index/"
    }

    if (-not (Test-Path $projectClaudeFile)) {
        $langLine = if ($LANG_HINT) { "$LANG_HINT project." } else { "" }
        $wsLine = if ($WORKSPACE_INFO) { " $WORKSPACE_INFO" } else { "" }
        @"
# $projectName

$langLine$wsLine

---

## MANDATORY: Index-First Codebase Queries

**You have a repo-cognition SQLite index at `.claude/index/repo-cognition/index.db`. Use it for ALL codebase structure questions. Do NOT use Grep/Glob when the answer can come from the index.**

### CRITICAL -- Citation Requirement

**Every codebase answer you give MUST cite its data source.** This is how the user knows the plugin is working:

- When you query the index, prefix your answer with: **`[index]`**
- When you fall back to Grep/Glob, prefix with: **`[grep]`** and explain why the index couldn't answer it

Example: `[index] The function handle_event is defined in agent-core/src/events.rs:42 and is called by 3 functions across 2 files.`

This applies to ALL agents and sub-agents. If the user sees `[grep]` repeatedly, something is wrong.

### Quick Reference

| You are asked | Use |
|--------------|-----|
| "Where is X defined?" | `python ~/.claude/plugins/repo-cognition/scripts/query-index.py --symbol X` |
| "Who calls X?" | `python ~/.claude/plugins/repo-cognition/scripts/query-index.py --callers X` |
| "What does X call?" | `python ~/.claude/plugins/repo-cognition/scripts/query-index.py "SELECT ce.callee_name, ce.callee_file FROM call_edges ce JOIN symbols s ON ce.caller_id = s.id WHERE s.name = 'X'"` |
| "Impact of changing X?" | Recursive CTE -- see `.claude/index/repo-cognition/CLAUDE.md` for full query |
| "Is X dead code?" | `python ~/.claude/plugins/repo-cognition/scripts/query-index.py --orphans` then grep for X |
| "Has duplicates of X?" | `python ~/.claude/plugins/repo-cognition/scripts/query-index.py --duplicates` |
| "Hotspots / most-called?" | `python ~/.claude/plugins/repo-cognition/scripts/query-index.py --hotspots` |
| "Domain map?" | `python ~/.claude/plugins/repo-cognition/scripts/query-index.py --domains` |
| "Language breakdown?" | `python ~/.claude/plugins/repo-cognition/scripts/query-index.py --languages` |
| "Riskiest files?" | `python ~/.claude/plugins/repo-cognition/scripts/query-index.py --riskiest` |

### Plugin Commands
/index-status -- full dashboard | /index-rebuild -- force rebuild | /index-graph <name> -- call graph | /index-graph --hotspots -- most-called | /index-graph --orphans -- dead code

### Skill
LessToil Query -- auto-activates on structural questions. Follow its instructions.

### Grep/Glob
ONLY for: literal strings in source, #\[derive(...)\], constructors like X::new(), or code not tracked by the index.
"@ | Set-Content -Path $projectClaudeFile -Encoding UTF8
        Write-Detail "Created $projectClaudeFile"
    } else {
        Write-Detail "CLAUDE.md already exists -- skipping"
        $existingContent = Get-Content $projectClaudeFile -Raw -ErrorAction SilentlyContinue
        if ($existingContent -notmatch "repo-cognition") {
            @"

## LessToil Index

This project uses the repo-cognition plugin. Query `.claude/index/repo-cognition/index.db` for codebase structure questions. Run `/index-status` for a dashboard.
"@ | Add-Content -Path $projectClaudeFile -Encoding UTF8
            Write-Detail "Added index reference to existing CLAUDE.md"
        }
    }

    Write-Host ""
} else {
    Write-Step "5/7" "Skipping project setup (-PluginOnly)"
    Write-Host ""
}

# ==============================================================================
# STEP 6: Generate index CLAUDE.md
# ==============================================================================
if (-not $PluginOnly) {
    Write-Step "6/7" "Generating index query reference..."

    $claudeMdScript = Join-Path $PLUGIN_DIR "scripts\generate-claude-md.py"
    if (Test-Path $claudeMdScript) {
        $env:CLAUDE_PLUGIN_ROOT = $PLUGIN_DIR
        $env:CLAUDE_PROJECT_DIR = $ProjectDir
        & $INSTALL_PYTHON $claudeMdScript 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Detail "Generated .claude/index/repo-cognition/CLAUDE.md"
        } else {
            Write-Warn "CLAUDE.md generation skipped (will be created on first index)"
        }
    }
    Write-Host ""
} else {
    Write-Step "6/7" "Skipping (-PluginOnly)"
    Write-Host ""
}

# ==============================================================================
# STEP 7: Run first index (optional)
# ==============================================================================
if ($Reindex -and -not $PluginOnly) {
    Write-Step "7/7" "Running first index build..."

    # Clean stale state
    @(
        (Join-Path $projectIndexDir "index.db"),
        (Join-Path $projectIndexDir "index.db-wal"),
        (Join-Path $projectIndexDir "index.db-shm"),
        (Join-Path $projectIndexDir "indexing.lock")
    ) | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }

    $env:CLAUDE_PLUGIN_ROOT = $PLUGIN_DIR
    $env:CLAUDE_PROJECT_DIR = $ProjectDir
    $inputJson = "{`"session_id`":`"install-rebuild`",`"cwd`":`"$ProjectDir`"}"
    $inputJson | & $INSTALL_PYTHON (Join-Path $PLUGIN_DIR "hooks\session_start.py") 2>&1
    Write-Host ""
} else {
    Write-Step "7/7" "Skipping index build (use -Reindex to force, or restart Claude Code)"
    Write-Host ""
}

# ==============================================================================
# Cleanup
# ==============================================================================
if (Test-Path $TEMP_CLONE) {
    Remove-Item -Recurse -Force $TEMP_CLONE -ErrorAction SilentlyContinue
}
if ($ZIP_TEMP -and (Test-Path $ZIP_TEMP)) {
    Remove-Item -Recurse -Force $ZIP_TEMP -ErrorAction SilentlyContinue
}

# ==============================================================================
# Done
# ==============================================================================
$coreCount = (Get-ChildItem (Join-Path $PLUGIN_DIR "core\*.py") -File -ErrorAction SilentlyContinue).Count
$hookCount = (Get-ChildItem (Join-Path $PLUGIN_DIR "hooks\*.py") -File -ErrorAction SilentlyContinue).Count

Write-Host ""
Write-Header
Write-Host "  Installation Complete" -ForegroundColor Green
Write-Header
Write-Host "  Plugin:   $PLUGIN_DIR"
Write-Host "  Modules:  $coreCount core"
Write-Host "  Hooks:    $hookCount hook scripts"
Write-Host "  Commands: /index-status  /index-rebuild  /index-graph"
Write-Host "  Skill:    LessToil Query"
Write-Host "  Agent:    architecture-inferrer"
Write-Host "  Symbols:  56 languages ($verified/$($GRAMMAR_PACKAGES.Count) tree-sitter grammars)"
Write-Host ""

if (-not $PluginOnly) {
    Write-Host "  Project:  $ProjectDir"
    Write-Host "  CLAUDE.md: $projectClaudeDir\CLAUDE.md"
    if (-not $Reindex) {
        Write-Host ""
        Write-Host "  Restart Claude Code or open a new session." -ForegroundColor Yellow
        Write-Host "  The SessionStart hook will index this project automatically."
    }
} else {
    Write-Host ""
    Write-Host "  To set up a project:"
    Write-Host "    cd C:\path\to\your\project"
    Write-Host "    .\install.ps1"
}
Write-Host ""
Write-Header
