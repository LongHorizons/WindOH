#!/usr/bin/env bash
# LessToil Plugin — Standalone Installer
#
# Usage:
#   bash install.sh                          # Install plugin + set up current project
#   bash install.sh --project-dir /path/to/repo  # Set up a specific project
#   bash install.sh --plugin-only            # Only install the plugin, skip project setup
#   bash install.sh --reindex                # Install + force immediate index rebuild
#   bash install.sh --from-zip repo-cognition.zip  # Install from a local release zip
#   bash install.sh --accept                 # Non-interactive: auto-confirm everything
#   bash install.sh --no-venv                # Skip venv creation, use system Python directly
#
# One-liner (from GitHub):
#   bash <(curl -fsSL https://raw.githubusercontent.com/LongHorizons/WindOH/LessToil/main/plugins/repo-cognition/install.sh)
#
# Installs plugin to ~/.claude/plugins/repo-cognition/ and sets up the target project.
# Source priority: --from-zip FILE → local clone (if running from plugin dir) → GitHub clone

# Require bash — pipefail, [[, and local are bashisms not available in sh/dash
if [ -z "${BASH_VERSION:-}" ]; then
    echo "ERROR: This installer requires bash. Please run: bash install.sh"
    echo "       Avoid:  sh install.sh"
    exit 1
fi
set -euo pipefail

PLUGIN_NAME="repo-cognition"
PLUGIN_DIR="${HOME}/.claude/plugins/${PLUGIN_NAME}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ANSI formatting
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'

# --- Parse arguments ---------------------------------------------------------
PROJECT_DIR="${PWD}"
PLUGIN_ONLY=false
DO_REINDEX=false
FROM_ZIP=""
ACCEPT=false
NO_VENV=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --plugin-only) PLUGIN_ONLY=true; shift ;;
        --reindex) DO_REINDEX=true; shift ;;
        --from-zip) FROM_ZIP="$2"; shift 2 ;;
        --accept) ACCEPT=true; shift ;;
        --no-venv) NO_VENV=true; shift ;;
        --help|-h)
            echo "Usage: bash install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --project-dir DIR   Set up this project (default: current directory)"
            echo "  --plugin-only       Only install the plugin, skip project setup"
            echo "  --reindex           Force immediate index rebuild after install"
            echo "  --from-zip FILE     Install from a local release zip instead of GitHub"
            echo "  --accept            Non-interactive mode: auto-confirm all prompts"
            echo "  --no-venv           Skip creating ~/.claude/venv/, use system Python directly"
            echo "  --help              Show this help"
            echo ""
            echo "Source priority: --from-zip > local clone > GitHub"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ "$PLUGIN_ONLY" = false ] && [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: Project directory not found: $PROJECT_DIR"
    echo "       Use --project-dir to specify a valid path, or --plugin-only to skip"
    exit 1
fi

# --- Detect Python ----------------------------------------------------------
PYTHON=""
for candidate in python3 python; do
    if command -v "$candidate" &>/dev/null; then
        case "$("$candidate" --version 2>&1)" in
            "Python 3."*) PYTHON="$candidate"; break ;;
        esac
    fi
done

# Auto-install Python if missing and --accept was given
if [ -z "$PYTHON" ] && [ "$ACCEPT" = true ]; then
    echo "Python 3.8+ not found. --accept: attempting auto-install..."
    if command -v apt-get &>/dev/null; then
        echo "      Detected apt-get — installing python3..."
        sudo apt-get update -qq && sudo apt-get install -y -qq python3 python3-pip python3-venv 2>&1 || true
    elif command -v brew &>/dev/null; then
        echo "      Detected Homebrew — installing python3..."
        brew install python3 2>&1 || true
    elif command -v dnf &>/dev/null; then
        echo "      Detected dnf — installing python3..."
        sudo dnf install -y python3 python3-pip 2>&1 || true
    elif command -v pacman &>/dev/null; then
        echo "      Detected pacman — installing python3..."
        sudo pacman -S --noconfirm python python-pip 2>&1 || true
    elif command -v apk &>/dev/null; then
        echo "      Detected apk — installing python3..."
        sudo apk add python3 py3-pip 2>&1 || true
    fi
    # Re-detect
    for candidate in python3 python; do
        if command -v "$candidate" &>/dev/null; then
            case "$("$candidate" --version 2>&1)" in
                "Python 3."*) PYTHON="$candidate"; break ;;
            esac
        fi
    done
fi

if [ -z "$PYTHON" ]; then
    echo "ERROR: Python 3.8+ required but not found. Install from https://python.org"
    echo "       Or re-run with --accept to attempt automatic installation."
    exit 1
fi

PY_MAJOR=$("$PYTHON" -c "import sys; print(sys.version_info[0])" 2>/dev/null || echo 0)
PY_MINOR=$("$PYTHON" -c "import sys; print(sys.version_info[1])" 2>/dev/null || echo 0)
if [ "$PY_MAJOR" -lt 3 ] || ([ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 8 ]); then
    echo "ERROR: Python 3.8+ required, found $PY_MAJOR.$PY_MINOR"
    exit 1
fi

# All Python references from here onward use INSTALL_PYTHON (may be venv or system)
INSTALL_PYTHON="$PYTHON"

# --- Create shared venv -----------------------------------------------------
VENV_DIR="${HOME}/.claude/venv"
if [ "$NO_VENV" = false ]; then
    if [ ! -d "$VENV_DIR" ]; then
        echo "Creating shared venv at $VENV_DIR ..."
        "$INSTALL_PYTHON" -m venv "$VENV_DIR" 2>/dev/null || {
            echo "      WARNING: venv creation failed — falling back to system Python."
            echo "      You may need to install python3-venv (apt) or equivalent."
            NO_VENV=true
        }
    fi
    if [ "$NO_VENV" = false ]; then
        # Upgrade pip inside the venv
        if [ -f "${VENV_DIR}/bin/python" ]; then
            VENV_PYTHON="${VENV_DIR}/bin/python"
            VENV_PIP="${VENV_DIR}/bin/pip"
        elif [ -f "${VENV_DIR}/bin/python3" ]; then
            VENV_PYTHON="${VENV_DIR}/bin/python3"
            VENV_PIP="${VENV_DIR}/bin/pip3"
        else
            echo "      WARNING: venv python not found — falling back to system Python."
            NO_VENV=true
        fi
    fi
    if [ "$NO_VENV" = false ]; then
        "$VENV_PYTHON" -m pip install --quiet --upgrade pip 2>/dev/null || true
        echo "      Venv ready: $VENV_PYTHON"
    fi
fi

# Resolve final python/pip to use
if [ "$NO_VENV" = false ] && [ -n "${VENV_PYTHON:-}" ]; then
    INSTALL_PYTHON="$VENV_PYTHON"
else
    INSTALL_PYTHON="$PYTHON"
    VENV_DIR=""  # Clear so we don't rewrite hooks.json
fi

echo ""
echo "=============================================="
echo "  LessToil Plugin v0.4.0 — Installer"
echo "=============================================="
echo "  Python:   $INSTALL_PYTHON ($("$INSTALL_PYTHON" --version 2>&1))"
if [ -n "$VENV_DIR" ]; then
    echo "  Venv:     $VENV_DIR"
fi
echo "  Plugin:   $PLUGIN_DIR"
echo "  Project:  $PROJECT_DIR"
echo "  Languages: 56 (41 tree-sitter + 15 regex)"
echo "=============================================="
echo ""

# =============================================================================
# STEP 0: Resolve plugin source (zip → local → GitHub)
# =============================================================================
ZIP_SOURCE=""
ZIP_TEMP=""

# --from-zip takes priority
if [ -n "$FROM_ZIP" ]; then
    if [ -f "$FROM_ZIP" ]; then
        ZIP_SOURCE="$FROM_ZIP"
    else
        echo "ERROR: --from-zip file not found: $FROM_ZIP"
        exit 1
    fi
fi

# Auto-detect zip alongside installer or relative to Presentation folder
if [ -z "$ZIP_SOURCE" ]; then
    for candidate in \
        "${SCRIPT_DIR}/repo-cognition.zip" \
        "${SCRIPT_DIR}/../Presentation/plugin/repo-cognition.zip" \
        "${SCRIPT_DIR}/../../Presentation/plugin/repo-cognition.zip"; do
        if [ -f "$candidate" ]; then
            ZIP_SOURCE="$candidate"
            break
        fi
    done
fi

# Extract zip if found and we're not already in a local clone
if [ -n "$ZIP_SOURCE" ] && [ ! -f "${SCRIPT_DIR}/core/manifest.py" ]; then
    ZIP_TEMP="$(mktemp -d)"
    echo "      Using release zip: $ZIP_SOURCE"
    if command -v unzip &>/dev/null; then
        unzip -q "$ZIP_SOURCE" -d "$ZIP_TEMP"
    elif "$INSTALL_PYTHON" -c "import zipfile" 2>/dev/null; then
        "$INSTALL_PYTHON" -c "
import zipfile, os
zf = zipfile.ZipFile('$ZIP_SOURCE')
zf.extractall('$ZIP_TEMP')
print(f'Extracted {len(zf.namelist())} files')
"
    else
        echo "ERROR: Neither 'unzip' nor Python zipfile available. Install unzip or Python."
        exit 1
    fi
    SCRIPT_DIR="$ZIP_TEMP"
    echo "      Extracted to: $ZIP_TEMP"
fi

# GitHub fallback: fetch from remote if no local source found
GIT_TEMP_DIR=""
if [ ! -f "${SCRIPT_DIR}/core/manifest.py" ]; then
    if ! command -v git &>/dev/null; then
        echo "ERROR: git not found on PATH. The installer requires git to fetch the plugin."
        echo ""
        echo "Install git from https://git-scm.com/downloads or run this script"
        echo "from a local clone of the repository, or use --from-zip."
        exit 1
    fi

    GIT_TEMP_DIR="$(mktemp -d)"
    echo "      Fetching plugin from GitHub (sparse checkout)..."

    if git clone --depth 1 --filter=blob:none --sparse \
        https://github.com/LongHorizons/WindOH/LessToil.git "$GIT_TEMP_DIR" 2>/dev/null; then
        (cd "$GIT_TEMP_DIR" && git sparse-checkout set "plugins/repo-cognition" 2>/dev/null)
        SCRIPT_DIR="${GIT_TEMP_DIR}/plugins/repo-cognition"
    else
        # Fallback: full shallow clone for older git versions
        echo "      Sparse checkout not supported, trying full shallow clone..."
        rm -rf "$GIT_TEMP_DIR"
        GIT_TEMP_DIR="$(mktemp -d)"
        if git clone --depth 1 \
            https://github.com/LongHorizons/WindOH/LessToil.git "$GIT_TEMP_DIR" 2>/dev/null; then
            SCRIPT_DIR="${GIT_TEMP_DIR}/plugins/repo-cognition"
        else
            echo "ERROR: Failed to clone repository. Check your internet connection and GitHub access."
            rm -rf "$GIT_TEMP_DIR"
            exit 1
        fi
    fi
fi

if [ ! -f "${SCRIPT_DIR}/core/manifest.py" ]; then
    echo "ERROR: Plugin source not found. Ensure core/manifest.py exists in the source."
    exit 1
fi

# =============================================================================
# STEP 1: Copy plugin files
# =============================================================================
echo "[1/7] Installing plugin files..."

mkdir -p "$PLUGIN_DIR"

copy_dir() {
    local src="$1"
    local dst="$2"
    local name="$3"
    if [ -d "$src" ]; then
        mkdir -p "$dst"
        # Copy regular files (non-hidden)
        cp -r "$src"/* "$dst/" 2>/dev/null || true
        # Copy hidden files too (shell glob * skips dotfiles)
        for hidden in "$src"/.[!.]*; do
            [ -e "$hidden" ] && cp -r "$hidden" "$dst/" 2>/dev/null || true
        done
        local count
        count=$(find "$dst" -maxdepth 1 -type f | wc -l)
        echo "      $name ($count files)"
    fi
}

# Core modules
copy_dir "${SCRIPT_DIR}/core" "${PLUGIN_DIR}/core" "core modules"

# Hooks
copy_dir "${SCRIPT_DIR}/hooks" "${PLUGIN_DIR}/hooks" "hooks"

# Commands
copy_dir "${SCRIPT_DIR}/commands" "${PLUGIN_DIR}/commands" "commands"

# Agents
copy_dir "${SCRIPT_DIR}/agents" "${PLUGIN_DIR}/agents" "agents"

# Skills
if [ -d "${SCRIPT_DIR}/skills" ]; then
    for skill_dir in "${SCRIPT_DIR}/skills/"*/; do
        skill_name="$(basename "$skill_dir")"
        mkdir -p "${PLUGIN_DIR}/skills/${skill_name}"
        cp -r "$skill_dir"* "${PLUGIN_DIR}/skills/${skill_name}/" 2>/dev/null || true
    done
    echo "      skills ($(find "${PLUGIN_DIR}/skills" -name '*.md' | wc -l) files)"
fi

# Scripts
copy_dir "${SCRIPT_DIR}/scripts" "${PLUGIN_DIR}/scripts" "scripts"

# Plugin metadata
if [ -f "${SCRIPT_DIR}/.claude-plugin/plugin.json" ]; then
    mkdir -p "${PLUGIN_DIR}/.claude-plugin"
    cp "${SCRIPT_DIR}/.claude-plugin/plugin.json" "${PLUGIN_DIR}/.claude-plugin/"
fi

# README
[ -f "${SCRIPT_DIR}/README.md" ] && cp "${SCRIPT_DIR}/README.md" "${PLUGIN_DIR}/"

echo ""

# Rewrite hooks.json to use the resolved Python path (venv or system).
# This prevents "python: command not found" on Linux systems where only
# python3 exists, while also pinning the venv Python when applicable.
if [ -f "${PLUGIN_DIR}/hooks/hooks.json" ]; then
    PYTHON_ABS="$(command -v "$INSTALL_PYTHON" 2>/dev/null || echo "$INSTALL_PYTHON")"
    TEMP_HOOKS="$(mktemp)"
    sed "s|\"python \"|\"${PYTHON_ABS} \"|g" "${PLUGIN_DIR}/hooks/hooks.json" > "$TEMP_HOOKS"
    mv "$TEMP_HOOKS" "${PLUGIN_DIR}/hooks/hooks.json"
    echo "      hooks.json: using $PYTHON_ABS"
fi

# =============================================================================
# STEP 2: Install Python dependencies
# =============================================================================
echo "[2/7] Installing Python dependencies..."

# Core dependencies (required)
CORE_PACKAGES=("tree-sitter" "pyyaml")

# All available tree-sitter grammar packages — pip name → python import name
# Format: "pip-name|import-name"
GRAMMAR_PACKAGES=(
    "tree-sitter-python|tree_sitter_python"
    "tree-sitter-typescript|tree_sitter_typescript"
    "tree-sitter-go|tree_sitter_go"
    "tree-sitter-rust|tree_sitter_rust"
    "tree-sitter-java|tree_sitter_java"
    "tree-sitter-c|tree_sitter_c"
    "tree-sitter-cpp|tree_sitter_cpp"
    "tree-sitter-c-sharp|tree_sitter_c_sharp"
    "tree-sitter-ruby|tree_sitter_ruby"
    "tree-sitter-php|tree_sitter_php"
    "tree-sitter-swift|tree_sitter_swift"
    "tree-sitter-scala|tree_sitter_scala"
    "tree-sitter-kotlin|tree_sitter_kotlin"
    "tree-sitter-lua|tree_sitter_lua"
    "tree-sitter-sql|tree_sitter_sql"
    "tree-sitter-bash|tree_sitter_bash"
    "tree-sitter-html|tree_sitter_html"
    "tree-sitter-css|tree_sitter_css"
    "tree-sitter-json|tree_sitter_json"
    "tree-sitter-yaml|tree_sitter_yaml"
    "tree-sitter-toml|tree_sitter_toml"
    "tree-sitter-markdown|tree_sitter_markdown"
    "tree-sitter-dockerfile|tree_sitter_dockerfile"
    "tree-sitter-hcl|tree_sitter_hcl"
    "tree-sitter-graphql|tree_sitter_graphql"
    "tree-sitter-haskell|tree_sitter_haskell"
    "tree-sitter-ocaml|tree_sitter_ocaml"
    "tree-sitter-elixir|tree_sitter_elixir"
    "tree-sitter-dart|tree_sitter_dart"
    "tree-sitter-zig|tree_sitter_zig"
    "tree-sitter-solidity|tree_sitter_solidity"
    "tree-sitter-svelte|tree_sitter_svelte"
    "tree-sitter-make|tree_sitter_make"
    "tree-sitter-cmake|tree_sitter_cmake"
    "tree-sitter-powershell|tree_sitter_powershell"
    "tree-sitter-nix|tree_sitter_nix"
)

# Check and track each package
INSTALL_LIST=()
ALREADY_INSTALLED=()
FAILED_PACKAGES=()

# Core packages first
for pkg in "${CORE_PACKAGES[@]}"; do
    pkg_name="${pkg//-/_}"
    if ! "$INSTALL_PYTHON" -c "import ${pkg_name}" 2>/dev/null; then
        INSTALL_LIST+=("$pkg")
    else
        ALREADY_INSTALLED+=("$pkg")
    fi
done

# Grammar packages
for entry in "${GRAMMAR_PACKAGES[@]}"; do
    pip_name="${entry%%|*}"
    import_name="${entry##*|}"
    if ! "$INSTALL_PYTHON" -c "import ${import_name}" 2>/dev/null; then
        INSTALL_LIST+=("$pip_name")
    else
        ALREADY_INSTALLED+=("$pip_name")
    fi
done

echo "      ${#ALREADY_INSTALLED[@]} packages already installed"

if [ ${#INSTALL_LIST[@]} -gt 0 ]; then
    echo "      Installing ${#INSTALL_LIST[@]} packages..."
    echo ""

    # Install one at a time for clear error reporting
    INSTALLED_COUNT=0
    MISSING_GRAMMARS=()

    for pkg in "${INSTALL_LIST[@]}"; do
        echo -n "      ${pkg} ... "
        if "$INSTALL_PYTHON" -m pip install --quiet "$pkg" 2>&1; then
            echo "OK"
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
        else
            echo "FAILED"
            FAILED_PACKAGES+=("$pkg")

            # Determine the import name for reporting
            import_name=""
            for entry in "${GRAMMAR_PACKAGES[@]}"; do
                if [ "${entry%%|*}" = "$pkg" ]; then
                    import_name="${entry##*|}"
                    break
                fi
            done
            [ -z "$import_name" ] && import_name="${pkg//-/_}"
            MISSING_GRAMMARS+=("$import_name")
        fi
    done

    echo ""
    echo "      Installed: $INSTALLED_COUNT / ${#INSTALL_LIST[@]}"

    if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
        echo ""
        echo "      ─────────────────────────────────────────────"
        echo "      ${BOLD}NOTE:${RESET} ${#FAILED_PACKAGES[@]} grammar package(s) could not be installed."
        echo "      Regex-based symbol extraction will be used for:"
        for name in "${MISSING_GRAMMARS[@]}"; do
            echo "        - ${name}"
        done
        echo ""
        echo "      To install manually:"
        echo "        pip install ${FAILED_PACKAGES[*]}"
        echo ""
        echo "      ${DIM}Missing grammars do NOT affect indexing — all 56 languages"
        echo "      are supported via regex fallback. Tree-sitter grammars"
        echo "      provide higher-accuracy symbol extraction only.${RESET}"
        echo "      ─────────────────────────────────────────────"
    fi
else
    echo "      All packages already installed."
fi

# Verify core functionality
echo ""
echo -n "      Verifying tree-sitter core ... "
if "$INSTALL_PYTHON" -c "import tree_sitter; print('OK')" 2>/dev/null; then
    true
else
    echo "WARNING: tree-sitter core not importable"
fi

echo -n "      Verified grammars: "
VERIFIED_COUNT=0
for entry in "${GRAMMAR_PACKAGES[@]}"; do
    import_name="${entry##*|}"
    if "$INSTALL_PYTHON" -c "import ${import_name}" 2>/dev/null; then
        VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
    fi
done
echo "$VERIFIED_COUNT / ${#GRAMMAR_PACKAGES[@]}"

echo ""

# =============================================================================
# STEP 3: Validate plugin
# =============================================================================
echo "[3/7] Validating core modules..."

FAILED=0
PASSED=0
for mod in "${PLUGIN_DIR}/core/"*.py; do
    [ ! -f "$mod" ] && continue
    if "$INSTALL_PYTHON" -c "import ast; ast.parse(open('$mod').read()); print('OK')" 2>/dev/null; then
        PASSED=$((PASSED + 1))
    else
        echo "      FAILED: $(basename "$mod")"
        FAILED=$((FAILED + 1))
    fi
done
echo "      $PASSED passed, $FAILED failed"

# Quick import check
VERIFY_SCRIPT="
import sys
sys.path.insert(0, '${PLUGIN_DIR}')
from core.manifest import init_db, SCHEMA_VERSION
init_db()
print(f'      Schema v{SCHEMA_VERSION} ready')
"
if "$INSTALL_PYTHON" -c "$VERIFY_SCRIPT" 2>/dev/null; then
    echo "      Plugin verified."
else
    echo "      WARNING: Plugin import check failed — may need manual inspection."
fi
echo ""

# =============================================================================
# STEP 4: Generate project CLAUDE.md (if setting up a project)
# =============================================================================
if [ "$PLUGIN_ONLY" = false ]; then
    echo "[4/7] Setting up project at $PROJECT_DIR..."

    PROJECT_CLAUDE_DIR="${PROJECT_DIR}/.claude"
    PROJECT_CLAUDE_FILE="${PROJECT_CLAUDE_DIR}/CLAUDE.md"
    PROJECT_INDEX_DIR="${PROJECT_DIR}/.claude/index/repo-cognition"

    mkdir -p "$PROJECT_CLAUDE_DIR"
    mkdir -p "$PROJECT_INDEX_DIR"

    # Detect project name from directory
    PROJECT_NAME="$(basename "$PROJECT_DIR")"

    # Detect language
    LANG_HINT=""
    if [ -f "${PROJECT_DIR}/Cargo.toml" ]; then
        LANG_HINT="Rust"
        WORKSPACE_INFO=""
        if grep -q '\[workspace\]' "${PROJECT_DIR}/Cargo.toml" 2>/dev/null; then
            MEMBERS=$(grep -oP '"\K[^"]+' "${PROJECT_DIR}/Cargo.toml" 2>/dev/null | tr '\n' ' ' || echo "")
            [ -n "$MEMBERS" ] && WORKSPACE_INFO="Workspace crates: $MEMBERS"
        fi
    elif ls "${PROJECT_DIR}"/*.ts "${PROJECT_DIR}"/*.tsx &>/dev/null 2>&1; then
        LANG_HINT="TypeScript"
    elif ls "${PROJECT_DIR}"/*.py &>/dev/null 2>&1; then
        LANG_HINT="Python"
    elif ls "${PROJECT_DIR}"/*.go &>/dev/null 2>&1; then
        LANG_HINT="Go"
    fi

    # Ensure .claude/index/ is in .gitignore
    GITIGNORE_FILE="${PROJECT_DIR}/.gitignore"
    GITIGNORE_ENTRY=".claude/index/"
    if [ -f "$GITIGNORE_FILE" ]; then
        if ! grep -qF "$GITIGNORE_ENTRY" "$GITIGNORE_FILE"; then
            echo "" >> "$GITIGNORE_FILE"
            echo "$GITIGNORE_ENTRY" >> "$GITIGNORE_FILE"
            echo "      Added .claude/index/ to .gitignore"
        fi
    else
        echo "$GITIGNORE_ENTRY" > "$GITIGNORE_FILE"
        echo "      Created .gitignore with .claude/index/"
    fi

    # Only create CLAUDE.md if it doesn't already exist
    if [ ! -f "$PROJECT_CLAUDE_FILE" ]; then
        cat > "$PROJECT_CLAUDE_FILE" << CLAUDEEOF
# ${PROJECT_NAME}

${LANG_HINT:+${LANG_HINT} project.}${WORKSPACE_INFO:+ ${WORKSPACE_INFO}}

---

## MANDATORY: Index-First Codebase Queries

**You have a repo-cognition SQLite index at \`.claude/index/repo-cognition/index.db\`. Use it for ALL codebase structure questions. Do NOT use Grep/Glob when the answer can come from the index.**

### How to Query the Index

**Always use Python** — Python's \`sqlite3\` module is in the standard library and works on every platform. The plugin also provides a query helper:

\`\`\`bash
# Primary: Query helper script (predefined queries)
python ~/.claude/plugins/repo-cognition/scripts/query-index.py --symbol X
python ~/.claude/plugins/repo-cognition/scripts/query-index.py --callers X
python ~/.claude/plugins/repo-cognition/scripts/query-index.py --hotspots

# Primary: Query helper script (any SQL)
python ~/.claude/plugins/repo-cognition/scripts/query-index.py "SELECT * FROM files LIMIT 5"

# Inline Python (always available, no script needed)
python -c "
import sqlite3
conn = sqlite3.connect('.claude/index/repo-cognition/index.db')
conn.row_factory = sqlite3.Row
for row in conn.execute('SELECT ...'):
    print(dict(row))
"
\`\`\`

If the \`sqlite3\` CLI happens to be available: \`sqlite3 .claude/index/repo-cognition/index.db "SELECT ..."\`

### CRITICAL — Citation Requirement

**Every codebase answer you give MUST cite its data source.** This is how the user knows the plugin is working:

- When you query the index, prefix your answer with: **\`[index]\`**
- When you fall back to Grep/Glob, prefix with: **\`[grep]\`** and explain why the index couldn't answer it

Example: \`[index] The function \`handle_event\` is defined in agent-core/src/events.rs:42 and is called by 3 functions across 2 files.\`

This applies to ALL agents and sub-agents. If the user sees \`[grep]\` repeatedly, something is wrong.

### Quick Reference

| You are asked | Use |
|--------------|-----|
| "Where is X defined?" | \`python ~/.claude/plugins/repo-cognition/scripts/query-index.py --symbol X\` |
| "Who calls X?" | \`python ~/.claude/plugins/repo-cognition/scripts/query-index.py --callers X\` |
| "What does X call?" | \`python ~/.claude/plugins/repo-cognition/scripts/query-index.py "SELECT ce.callee_name, ce.callee_file FROM call_edges ce JOIN symbols s ON ce.caller_id = s.id WHERE s.name = 'X'"\` |
| "Impact of changing X?" | Recursive CTE — see \`.claude/index/repo-cognition/CLAUDE.md\` for full query |
| "Is X dead code?" | \`python ~/.claude/plugins/repo-cognition/scripts/query-index.py --orphans\` then grep for X |
| "Has duplicates of X?" | \`python ~/.claude/plugins/repo-cognition/scripts/query-index.py --duplicates\` |
| "Hotspots / most-called?" | \`python ~/.claude/plugins/repo-cognition/scripts/query-index.py --hotspots\` |
| "Domain map?" | \`python ~/.claude/plugins/repo-cognition/scripts/query-index.py --domains\` |
| "Language breakdown?" | \`python ~/.claude/plugins/repo-cognition/scripts/query-index.py --languages\` |
| "Riskiest files?" | \`python ~/.claude/plugins/repo-cognition/scripts/query-index.py --riskiest\` |

### Plugin Commands
\`/index-status\` — full dashboard | \`/index-rebuild\` — force rebuild | \`/index-graph <name>\` — call graph | \`/index-graph --hotspots\` — most-called | \`/index-graph --orphans\` — dead code

### Skill
\`LessToil Query\` — auto-activates on structural questions. Follow its instructions.

### Grep/Glob
ONLY for: literal strings in source, \`#\[derive(...)\]\`, constructors like \`X::new()\`, or code not tracked by the index.
CLAUDEEOF
        echo "      Created ${PROJECT_CLAUDE_FILE}"
    else
        echo "      CLAUDE.md already exists — skipping"
        # Check if it references the index; if not, append a note
        if ! grep -q "repo-cognition" "$PROJECT_CLAUDE_FILE" 2>/dev/null; then
            echo "" >> "$PROJECT_CLAUDE_FILE"
            echo "## LessToil Index" >> "$PROJECT_CLAUDE_FILE"
            echo "" >> "$PROJECT_CLAUDE_FILE"
            echo "This project uses the repo-cognition plugin. Query \`.claude/index/repo-cognition/index.db\` for codebase structure questions. Run \`/index-status\` for a dashboard." >> "$PROJECT_CLAUDE_FILE"
            echo "      Added index reference to existing CLAUDE.md"
        fi
    fi

    echo ""
else
    echo "[4/7] Skipping project setup (--plugin-only)"
    echo ""
fi

# =============================================================================
# STEP 5: Generate index CLAUDE.md template
# =============================================================================
if [ "$PLUGIN_ONLY" = false ]; then
    echo "[5/7] Generating index query reference..."

    # Run the generate script if available
    CLAUDE_MD_SCRIPT="${PLUGIN_DIR}/scripts/generate-claude-md.py"
    if [ -f "$CLAUDE_MD_SCRIPT" ]; then
        CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" CLAUDE_PROJECT_DIR="$PROJECT_DIR" \
            "$INSTALL_PYTHON" "$CLAUDE_MD_SCRIPT" 2>/dev/null && \
            echo "      Generated .claude/index/repo-cognition/CLAUDE.md" || \
            echo "      NOTE: CLAUDE.md generation skipped (will be created on first index)"
    fi
    echo ""
else
    echo "[5/7] Skipping (--plugin-only)"
    echo ""
fi

# =============================================================================
# STEP 6: Run first index (if requested)
# =============================================================================
if [ "$DO_REINDEX" = true ] && [ "$PLUGIN_ONLY" = false ]; then
    echo "[6/7] Running first index build..."

    # Remove any stale state
    rm -f "${PROJECT_INDEX_DIR}/index.db" \
          "${PROJECT_INDEX_DIR}/index.db-wal" \
          "${PROJECT_INDEX_DIR}/index.db-shm" \
          "${PROJECT_INDEX_DIR}/indexing.lock" 2>/dev/null || true

    CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" CLAUDE_PROJECT_DIR="$PROJECT_DIR" \
        "$INSTALL_PYTHON" "${PLUGIN_DIR}/hooks/session_start.py" <<< '{"session_id":"install-rebuild","cwd":"'"$PROJECT_DIR"'"}'
    echo ""
else
    echo "[6/7] Skipping index build (use --reindex to force, or restart Claude Code)"
    echo ""
fi

# =============================================================================
# Cleanup temp zip extraction
# =============================================================================
if [ -n "$ZIP_TEMP" ] && [ -d "$ZIP_TEMP" ]; then
    rm -rf "$ZIP_TEMP"
fi
if [ -n "$GIT_TEMP_DIR" ] && [ -d "$GIT_TEMP_DIR" ]; then
    rm -rf "$GIT_TEMP_DIR"
fi

# =============================================================================
# STEP 7: Done
# =============================================================================
echo "[7/7] Done!"
echo ""
echo "=============================================="
echo "  Installation Complete"
echo "=============================================="
echo "  Plugin:   ~/.claude/plugins/repo-cognition/"
echo "  Modules:  $(ls "${PLUGIN_DIR}/core/"*.py 2>/dev/null | wc -l) core"
echo "  Hooks:    $(ls "${PLUGIN_DIR}/hooks/"*.py 2>/dev/null | wc -l) hook scripts"
echo "  Commands: /index-status  /index-rebuild  /index-graph"
echo "  Skill:    LessToil Query"
echo "  Agent:    architecture-inferrer"
echo "  Symbols:  56 languages (${VERIFIED_COUNT:-0}/$((${#GRAMMAR_PACKAGES[@]})) tree-sitter grammars)"
echo ""

if [ "$PLUGIN_ONLY" = false ]; then
    echo "  Project:  $PROJECT_DIR"
    echo "  CLAUDE.md: ${PROJECT_CLAUDE_DIR}/CLAUDE.md"
    if [ "$DO_REINDEX" = false ]; then
        echo ""
        echo "  Restart Claude Code or open a new session."
        echo "  The SessionStart hook will index this project automatically."
    fi
else
    echo ""
    echo "  To set up a project:"
    echo "    cd /path/to/your/project"
    echo "    bash $(dirname "$0")/install.sh"
fi
echo ""
echo "=============================================="
