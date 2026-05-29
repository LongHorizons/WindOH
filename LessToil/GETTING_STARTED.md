# LessToil — Getting Started

> Complete installation, configuration, verification, and first-use guide for Windows, macOS, and Linux.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Verifying Installation](#verifying-installation)
4. [First Run](#first-run)
5. [Day-to-Day Usage](#day-to-day-usage)
6. [Configuration](#configuration)
7. [Verifying Everything Works](#verifying-everything-works)
8. [Troubleshooting](#troubleshooting)
9. [Uninstalling](#uninstalling)
10. [Next Steps](#next-steps)

---

## Prerequisites

### Required

| Component | Minimum Version | Check Command |
|-----------|----------------|---------------|
| **Claude Code** | Latest | `claude --version` |
| **Python** | 3.8+ | `python --version` (Windows) / `python3 --version` (Unix) |
| **git** | 2.x+ | `git --version` |
| **pip** | Bundled with Python | `pip --version` (Windows) / `pip3 --version` (Unix) |

### Optional

| Component | Benefit |
|-----------|---------|
| tree-sitter grammar packages | AST-level parsing for 41 languages (installed automatically by installer) |
| Graphviz `dot` CLI | SVG rendering of call graphs and domain maps via `/index-graph` |

### Verify Your Environment

**Windows (PowerShell):**
```powershell
python --version          # Python 3.8 or higher required
git --version             # Git 2.x or higher required
claude --version          # Claude Code installed and working
```

**macOS / Linux (Bash):**
```bash
python3 --version         # Python 3.8 or higher required
git --version             # Git 2.x or higher required
claude --version          # Claude Code installed and working
```

If Python is not found on Windows, run `where.exe python`. If missing, install from [python.org](https://python.org) and ensure "Add Python to PATH" is checked. On macOS, use `brew install python3`. On Linux, use `apt install python3` or equivalent.

---

## Installation

### Windows (PowerShell)

#### One-Liner (Recommended)

Run from your project directory:

```powershell
irm https://raw.githubusercontent.com/LongHorizons/WindOH/master/LessToil/plugin/install.ps1 | iex
```

#### From Local Clone

```powershell
git clone https://github.com/LongHorizons/WindOH.git $env:TEMP\claude-code
Set-Location $env:TEMP\claude-code\LessToil\plugin
.\install.ps1
```

#### With Options

```powershell
# Install plugin only (no project CLAUDE.md setup)
.\install.ps1 -PluginOnly

# Install for a specific project with immediate index build
.\install.ps1 -ProjectDir C:\Users\you\projects\myapp -Reindex

# Install from a local release zip (no Git needed)
.\install.ps1 -FromZip .\repo-cognition.zip

# Non-interactive install (auto-confirm everything)
.\install.ps1 -Accept
```

### macOS / Linux (Bash)

#### One-Liner (Recommended)

Run from your project directory:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LongHorizons/WindOH/master/LessToil/plugin/install.sh)
```

#### From Local Clone

```bash
git clone https://github.com/LongHorizons/WindOH.git /tmp/claude-code
cd /tmp/claude-code/LessToil/plugin
bash install.sh
```

#### With Options

```bash
# Install plugin only (no project CLAUDE.md setup)
bash install.sh --plugin-only

# Install for a specific project with immediate index build
bash install.sh --project-dir ~/projects/myapp --reindex

# Install from a local release zip (no Git needed)
bash install.sh --from-zip repo-cognition.zip

# Non-interactive install (auto-confirm everything)
bash install.sh --accept
```

### Install Options Reference

| Bash Flag | PowerShell Flag | Purpose |
|-----------|----------------|---------|
| `--project-dir /path` | `-ProjectDir PATH` | Set up a specific project directory |
| `--plugin-only` | `-PluginOnly` | Install only the plugin files, skip project CLAUDE.md setup |
| `--reindex` | `-Reindex` | Force immediate full index build after installation |
| `--from-zip FILE` | `-FromZip FILE` | Install from a local release zip (bypasses Git/GitHub entirely) |
| `--accept` | `-Accept` | Non-interactive mode: auto-confirm all prompts, attempt Python auto-install if missing |
| `--no-venv` | `-NoVenv` | Skip creating `~/.claude/venv/`, use system Python directly |

**Source priority**: `--from-zip` > local clone > GitHub fetch. The installer auto-detects `repo-cognition.zip` in the current directory or adjacent `Presentation/plugin/` folder.

### What the Installer Does (9 Steps)

1. **Acquires** the plugin from GitHub via sparse checkout (only fetches the plugin directory, not the full monorepo), or from a local clone or release zip
2. **Copies** plugin files to `~/.claude/plugins/repo-cognition/`:
   - 40 core Python modules
   - 3 hook scripts (`session_start.py`, `pre_tool_use.py`, `post_tool_use.py`)
   - 3 slash commands (`index-status.md`, `index-rebuild.md`, `index-graph.md`)
   - 1 agent (`architecture-inferrer.md`)
   - 1 skill (`SKILL.md` — repo-cognition-query)
   - Plugin manifest (`plugin.json`) and hook registration (`hooks.json`)
3. **Creates a shared venv** at `~/.claude/venv/` (unless `--no-venv`). This single venv is shared across all your projects — pip dependencies install once, not per project. The hooks.json is rewritten to use the venv Python, isolating the plugin from system Python changes.
4. **Installs** Python dependencies into the venv via pip: `tree-sitter`, `pyyaml`, and up to 36 tree-sitter grammar packages. Missing grammars fall back to regex extraction — indexing works for all 56 languages regardless
5. **Manages** `.gitignore` — automatically adds `.claude/index/` to your project's `.gitignore` (creates the file if it doesn't exist; idempotent — won't duplicate the entry if already present)
6. **Validates** all 40 core modules using `ast.parse()` and a schema initialization check to catch syntax errors or import issues
7. **Creates** `.claude/CLAUDE.md` in your project with index-first query instructions, citation requirements (`[index]` / `[grep]`), quick-reference SQL queries, and plugin command listing
8. **Generates** `.claude/index/repo-cognition/CLAUDE.md` with full schema reference, SQL query examples, domain list, and language breakdown
9. **Optionally** runs the first index build (when `--reindex` / `-Reindex` is specified)

---

## Verifying Installation

### Check Plugin Directory

**Windows:**
```powershell
Test-Path $env:USERPROFILE\.claude\plugins\repo-cognition\core\manifest.py
# Should return True
```

**macOS / Linux:**
```bash
ls ~/.claude/plugins/repo-cognition/core/manifest.py
# Should show the file path
```

### Check Python Can Import the Plugin

```bash
python -c "
import sys
sys.path.insert(0, '${HOME}/.claude/plugins/repo-cognition')
from core.manifest import init_db, SCHEMA_VERSION
init_db()
print(f'Schema v{SCHEMA_VERSION} ready')
"
# Expected: "Schema v3 ready"
```

### Check hooks.json is Valid

```bash
python -c "import json; json.load(open('${HOME}/.claude/plugins/repo-cognition/hooks/hooks.json')); print('hooks.json valid')"
# Expected: "hooks.json valid"
```

### Verify Grammar Packages (Optional)

```bash
python -c "
import importlib
for pkg in ['tree_sitter', 'tree_sitter_python', 'tree_sitter_typescript']:
    try:
        importlib.import_module(pkg)
        print(f'  {pkg}: installed')
    except ImportError:
        print(f'  {pkg}: not installed (regex fallback will be used)')
"
```

---

## First Run

### 1. Open Your Project in Claude Code

Navigate to your project directory and start Claude Code:

```bash
cd /path/to/your/project
claude
```

### 2. Watch for the Dashboard

The SessionStart hook fires automatically. You will see a system message similar to:

```
┌──────────────────────────────────────────────────────────┐
│  ◆  REPOSITORY COGNITION  —  Index Dashboard             │
│  ●  HEALTHY  —  847 files indexed, 3,142 symbols         │
│  Last index: 2026-05-26T14:32:53Z                         │
└──────────────────────────────────────────────────────────┘

  ──  CORE METRICS
  Files: 847       Symbols: 3142       Call edges: 4891
  Domains: 14       Schema: v3

  ──  LANGUAGE DISTRIBUTION
  typescript      ████████████████ 412
  python          ████████ 201
  go              ████ 89
  ...

  ──  TEMPORAL RISK  ·  CONFIDENCE  ·  DRIFT  ·  STEWARDSHIP
  ──  GOVERNANCE  ·  IMMUNE + EPISTEMIC

  ═══════════════════════════════════════════════════════════
  /index-status  ·  /index-graph  ·  /index-rebuild
```

This confirms the plugin is active and your project has been indexed. If the dashboard does not appear, see [Troubleshooting](#troubleshooting).

### 3. Try the Slash Commands

```
/index-status
```
Displays the full dashboard: index health, file counts, language breakdown, domain map, temporal risk scores, confidence distribution, architectural drift metrics, stewardship suggestions, and governance status.

```
/index-graph --hotspots
```
Shows the 20 most-called functions in your codebase — immediately useful for identifying refactoring priorities and understanding the core dependency structure.

```
/index-graph --orphans
```
Shows functions that are defined but never called — potential dead code to evaluate for removal.

```
/index-graph <function-name>
```
Generates a call graph centered on a specific function, showing all callers (who depends on this) and callees (what this depends on).

```
/index-graph --domain-graph
```
Generates a cross-domain dependency visualization — shows which architectural domains depend on which other domains, with call edge counts.

```
/index-rebuild
```
Forces a complete reindex from scratch. Useful after large merges, branch switches, or adding new tree-sitter grammar packages.

### 4. Ask Structural Questions

The LessToil Query skill auto-activates when you ask questions about codebase structure:

| Question | What Happens | Source |
|----------|-------------|--------|
| "Where is auth handled?" | Queries `domains` table → lists auth domain files and entry points | `[index]` |
| "Who calls validateToken?" | Queries `call_edges` → lists all callers with file:line | `[index]` |
| "What depends on UserRepo?" | Recursive CTE → transitive dependency chain up to depth 10 | `[index]` |
| "Is there already a function for hashing passwords?" | Queries `similarity_groups` + `symbols` | `[index]` |
| "What domain is checkout.ts in?" | Queries `file_domains` → shows domain with confidence | `[index]` |
| "What are the riskiest files?" | Queries `temporal_metrics` → ranked by risk score | `[index]` |
| "Find unused functions" | Queries `symbols` NOT IN `call_edges` → orphaned functions | `[index]` |

All answers are prefixed with `[index]` or `[grep]` — you always know the data source.

---

## Day-to-Day Usage

### Session Start (Every Time You Open Claude Code)

- The dashboard appears as a system message with current index statistics
- Files with changed SHA256 hashes since last session are automatically reindexed
- Stewardship scans run: dead subsystems, over-complex files, hotspots, coupling, unowned paths, stale patterns
- A structural summary (~600 tokens) is injected into the agent's context, replacing ~15 minutes of manual architecture rediscovery
- Advanced intelligence modules run in the background (forecasting, drift detection, immune baseline updates)

### Before Every Edit (PreToolUse)

When you or the agent initiates a Write/Edit/MultiEdit operation:

- **Impact analysis** runs automatically: "Editing `auth.ts` affects 47 callers in 23 files across 3 domains"
- **Duplicate detection** checks if the proposed code already exists: "`validateJWT` already exists in 3 locations"
- **Confidence warnings** flag low-confidence symbols in the target file
- **Governance checks** evaluate invariants and policies against the proposed change
- **Simulation grading** classifies the change as safe, cautious, risky, or dangerous
- **Dangerous edits are blocked** with exit code 2 before they execute
- Advisory warnings (impact, duplicates, confidence) inform but do not block

### After Every Edit (PostToolUse)

Silent, under 1 second per file:

- Changed files are reindexed (SHA256, symbols, call edges)
- Confidence scores are adjusted based on edit outcome
- Temporal change counter is incremented
- Post-execute verification (TRACE + SCORE) maps changes to indexed state

### Citation Transparency

All agents (including sub-agents) are instructed via the project CLAUDE.md to prefix structural answers:

- `[index]` — Information sourced from the SQLite knowledge base
- `[grep]` — Fell back to text search (agent must explain why)

Repeated `[grep]` answers suggest the index needs attention — run `/index-rebuild`.

---

## Configuration

### Optional Settings

Create `.claude/repo-cognition.settings.local.md` in your project root:

```yaml
---
# Directories to exclude from indexing (adds to built-in exclusions)
exclude_dirs:
  - .terraform
  - .cache
  - vendor
  - generated
  - third_party

# Override default extraction time budget
max_extraction_time_sec: 45

# SimHash similarity threshold (0.0-1.0, lower = more aggressive matching)
similarity_threshold: 0.85

# Custom architectural domains
domains:
  custom_domains:
    - name: ml-pipeline
      description: Machine learning training and inference pipelines
      path_patterns: [ml/, training/, inference/, model/]
      symbol_patterns: [train, predict, inference, model, embedding]
      security_boundary: false
---
```

Note: `node_modules`, `__pycache__`, `.git`, `.claude`, `dist`, `build`, `target`, and similar directories are already excluded by default. The `exclude_dirs` setting adds additional directories.

### Custom Governance Rules

Create `.claude/repo-cognition.policies.local.md`:

```yaml
---
invariants:
  - name: no_direct_db_from_ui
    description: "UI components must not call database directly"
    check_sql: >
      SELECT s.name, f.file_path FROM symbols s
      JOIN files f ON s.file_id = f.id
      JOIN file_domains fd ON f.id = fd.file_id
      JOIN domains d ON fd.domain_id = d.id
      WHERE d.name = 'ui'
      AND s.name IN (SELECT callee_name FROM call_edges WHERE callee_name LIKE '%Repo%')
    severity: error
    enabled: true

policies:
  - name: max_function_lines
    category: complexity
    description: "Functions should not exceed 200 lines"
    threshold_value: 200
    check_sql: >
      SELECT name, file_path, (end_line - start_line) AS lines
      FROM symbols JOIN files ON symbols.file_id = files.id
      WHERE kind IN ('function', 'method')
      AND (end_line - start_line) > ?
    severity: warning
    enabled: true
---
```

### Gitignore

The plugin **automatically manages** `.claude/index/` in your project's `.gitignore`:

- **At install time**: Both installers add the entry (or create `.gitignore` if it doesn't exist)
- **Every session**: The SessionStart hook's `ensure_gitignore()` function verifies the entry is present
- **Idempotent**: No duplicate entries are ever created
- **Non-blocking**: If the filesystem is read-only or the operation fails for any reason, the session continues normally

You do not need to manually edit `.gitignore`. The index is regenerated from source code on session start — committing it creates merge conflicts on the binary SQLite file and is unnecessary.

### Shared Virtual Environment

The installer creates a shared venv at `~/.claude/venv/` by default. This single venv is used across all your projects — Python dependencies install once and are shared everywhere:

- **One-time install**: tree-sitter, pyyaml, and 36 grammar packages install into `~/.claude/venv/` — not per project
- **Isolation**: The plugin's Python environment is independent of your system Python and project venvs
- **Automatic**: `hooks.json` is rewritten to use the venv Python path — no configuration needed
- **Opt-out**: Use `--no-venv` / `-NoVenv` to skip venv creation and use your system Python directly

To verify: `~/.claude/venv/bin/python --version` (Unix) or `~/.claude/venv/Scripts/python.exe --version` (Windows).

---

## Verifying Everything Works

Run these checks from your project directory after your first session. All commands use the cross-platform Python query helper (no `sqlite3` CLI needed).

### Test 1: Index Database Created
```bash
ls -la .claude/index/repo-cognition/index.db
# Should show the SQLite database file with a recent modification time
```

### Test 2: Files Indexed
```bash
python ~/.claude/plugins/repo-cognition/scripts/query-index.py --stats
# Shows files, symbols, call_edges, and domain counts
```

### Test 3: Symbols Extracted
```bash
python ~/.claude/plugins/repo-cognition/scripts/query-index.py --languages
# Shows file counts and sizes broken down by detected language
```

### Test 4: Call Graph Populated
```bash
python ~/.claude/plugins/repo-cognition/scripts/query-index.py \
  "SELECT COUNT(*) AS edge_count FROM call_edges;"
# Function-calling languages (Python, TypeScript, Go, Rust, etc.) should show edges > 0
```

### Test 5: Domains Classified
```bash
python ~/.claude/plugins/repo-cognition/scripts/query-index.py --domains
# Shows detected architectural domains, descriptions, security boundaries, and file counts
```

### Test 6: Temporal Risk Analysis
```bash
python ~/.claude/plugins/repo-cognition/scripts/query-index.py --riskiest
# Shows the 10 files with the highest risk scores based on git history
```

### Test 7: Stewardship Suggestions
```bash
python ~/.claude/plugins/repo-cognition/scripts/query-index.py \
  "SELECT severity, category, title FROM stewardship_suggestions WHERE resolved_at IS NULL ORDER BY CASE severity WHEN 'high' THEN 0 ELSE 1 END LIMIT 5;"
# Shows outstanding stewardship concerns, prioritized by severity
```

### Test 8: Incremental Reindexing
Make a small edit to any source file, then check:
```bash
python ~/.claude/plugins/repo-cognition/scripts/query-index.py \
  "SELECT file_path, last_indexed FROM files WHERE file_path = '<your-edited-file>';"
# Should show a timestamp matching when the edit was made
```

> **No Python?** Use inline Python with the stdlib sqlite3 module (always available):
> ```bash
> python -c "import sqlite3; conn=sqlite3.connect('.claude/index/repo-cognition/index.db'); conn.row_factory=sqlite3.Row; [print(dict(r)) for r in conn.execute('SELECT COUNT(*) FROM files')]"
> ```

---

## Troubleshooting

### "Python was not found"

**Windows**: Use `python` (not `python3`). Verify Python is on PATH:
```powershell
where.exe python
```
If not found, reinstall Python from [python.org](https://python.org) and ensure "Add Python to PATH" is checked during installation.

**macOS**: `brew install python3`
**Linux**: `apt install python3` (Debian/Ubuntu) or equivalent for your distribution.

### "No module named 'core'"

The `CLAUDE_PLUGIN_ROOT` environment variable must point to the plugin directory. The hooks handle this automatically. To manually verify:
```bash
ls ~/.claude/plugins/repo-cognition/core/manifest.py
```
If the file does not exist, re-run the installer.

### "tree-sitter module not found"

The core `tree-sitter` package is required. Install manually:
```bash
pip install tree-sitter pyyaml
```

For full AST-level parsing, install grammar packages:
```bash
pip install tree-sitter-python tree-sitter-typescript tree-sitter-go tree-sitter-rust
```

The plugin works without grammar packages (regex fallback), but symbol extraction is more accurate with them. The installer automatically installs 36 grammar packages.

### "Index database is locked"

SQLite WAL mode handles concurrent access. If a lock persists after a crash:
```bash
# Remove stale lock file
rm -f .claude/index/repo-cognition/indexing.lock
# Windows equivalent:
# del .claude\index\repo-cognition\indexing.lock
```

Then reopen Claude Code — the SessionStart hook will recover automatically.

### "SessionStart hook timed out"

For very large repositories (>50K files), the initial index may exceed the 120-second hook timeout. Run a manual index:

**macOS / Linux:**
```bash
CLAUDE_PROJECT_DIR="$(pwd)" CLAUDE_PLUGIN_ROOT="$HOME/.claude/plugins/repo-cognition" \
  python3 $HOME/.claude/plugins/repo-cognition/hooks/session_start.py <<< '{"session_id":"manual","cwd":"'"$(pwd)"'"}'
```

**Windows (PowerShell):**
```powershell
$env:CLAUDE_PROJECT_DIR = (Get-Location).Path
$env:CLAUDE_PLUGIN_ROOT = "$env:USERPROFILE\.claude\plugins\repo-cognition"
'{"session_id":"manual","cwd":"' + (Get-Location).Path + '"}' | python $env:CLAUDE_PLUGIN_ROOT\hooks\session_start.py
```

After the manual index completes, subsequent sessions will use incremental updates and stay within the timeout.

### Symbols Not Extracted for My Language

Check the supported languages table in [README.md](README.md). For unsupported languages, file-level indexing (SHA256, language detection, size, line count) still works — symbol extraction, call graph, and domain inference will not be available for those files. To add support for a new language, see [CONTRIBUTING.md](CONTRIBUTING.md).

### Dashboard Not Appearing

Check each of these:
1. Plugin installed at `~/.claude/plugins/repo-cognition/` — verify `ls ~/.claude/plugins/repo-cognition/hooks/hooks.json`
2. `hooks.json` is valid JSON — run the validation check in [Verifying Installation](#verifying-installation)
3. Python 3.8+ is on PATH — run `python --version`
4. Claude Code logs for hook errors — typically in `.claude/logs/`
5. The project has CLAUDE.md — the installer creates this; if missing, re-run with `--reindex`
6. No stale lock file — check `.claude/index/repo-cognition/indexing.lock`

### "git is not recognized"

The installer requires git to fetch the plugin from GitHub. Install from [git-scm.com](https://git-scm.com/downloads). Alternatively, download the plugin ZIP from GitHub and use `--from-zip` / `-FromZip` to bypass the git requirement.

### Performance Issues on Large Repos

For repos >50K files:
- Increase `max_extraction_time_sec` in settings if you want more symbols extracted on first session
- Use `exclude_dirs` to skip generated code, vendored dependencies, and build artifacts
- The engine automatically degrades gracefully — file indexing always completes, symbols are deferred to incremental reindexes
- Run `/index-rebuild` during off-hours for the initial full extraction

---

## Uninstalling

### Windows (PowerShell)

```powershell
# Remove the plugin directory
Remove-Item -Recurse -Force $env:USERPROFILE\.claude\plugins\repo-cognition

# Remove generated index data (run from each project directory)
Remove-Item -Recurse -Force .claude\index\repo-cognition -ErrorAction SilentlyContinue
Remove-Item -Force .claude\repo-cognition.domains.local.md -ErrorAction SilentlyContinue
Remove-Item -Force .claude\repo-cognition.patterns.local.md -ErrorAction SilentlyContinue
Remove-Item -Force .claude\repo-cognition.policies.local.md -ErrorAction SilentlyContinue
Remove-Item -Force .claude\repo-cognition.knowledge.local.md -ErrorAction SilentlyContinue
Remove-Item -Force .claude\repo-cognition.settings.local.md -ErrorAction SilentlyContinue
```

### macOS / Linux (Bash)

```bash
# Remove the plugin directory
rm -rf ~/.claude/plugins/repo-cognition

# Remove generated index data (run from each project directory)
rm -rf .claude/index/repo-cognition
rm -f .claude/repo-cognition.domains.local.md
rm -f .claude/repo-cognition.patterns.local.md
rm -f .claude/repo-cognition.policies.local.md
rm -f .claude/repo-cognition.knowledge.local.md
rm -f .claude/repo-cognition.settings.local.md
```

---

## Next Steps

- Read [ARCHITECTURE.md](ARCHITECTURE.md) for deep technical details: data model, hook lifecycle, 40 modules, algorithms, and design decisions
- Read [USE_CASES.md](USE_CASES.md) for 12 real-world scenarios: refactoring, onboarding, security audits, migration planning, PR review, and more
- Read [FAQ.md](FAQ.md) for answers to common questions about usage, performance, comparison to other tools, and design rationale
- Read [CONTRIBUTING.md](CONTRIBUTING.md) to add language support, new features, bug fixes, or to set up a development environment
