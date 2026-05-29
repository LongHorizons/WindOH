# LessToil — FAQ

> Frequently asked questions about installation, usage, performance, design, and comparison.

---

## Table of Contents

1. [General](#general)
2. [Installation and Setup](#installation-and-setup)
3. [Usage and Workflow](#usage-and-workflow)
4. [Performance and Scale](#performance-and-scale)
5. [Technical Design](#technical-design)
6. [Comparison](#comparison)
7. [Customization](#customization)
8. [Troubleshooting](#troubleshooting)
9. [Contributing](#contributing)

---

## General

### What is LessToil?

LessToil is a Claude Code plugin (v0.4.0) that builds and maintains a persistent structural knowledge base of your codebase. It indexes every file, function, class, call relationship, and architectural domain into a SQLite database (26 tables) so Claude Code can reason from explicit structure rather than keyword search. 40 Python modules power extraction, analysis, and enforcement across 56 languages.

### How is this different from Claude Code's built-in codebase understanding?

Claude Code's default understanding operates by reading files on-demand, searching by keyword or filename, and building understanding from partial context within a single session. This understanding is lost when the session ends.

LessToil adds:
- A **persistent, pre-computed index** that survives sessions, branch switches, and merges
- **Explicit knowledge** of every symbol, caller, callee, and architectural domain
- **Incremental updates** as you edit — the index stays current automatically
- **Structural query capability** — recursive CTE call graph traversal, not just grep
- **Edit-time governance** — architectural rules enforced before changes execute
- **Citation tracking** — every answer prefixed with `[index]` or `[grep]` for transparency

### Does this send my code anywhere?

**No.** All indexing happens locally on your machine. The SQLite database, JSON manifests, and `.local.md` files are stored in `.claude/index/repo-cognition/` within your project directory. Nothing is transmitted to external services. The plugin has no network access.

### Is this a replacement for Sourcegraph, Kythe, or LSIF?

No. LessToil is specifically designed to augment Claude Code's reasoning within a coding session. It is lighter-weight than a full LSIF index, requires no server, and is continuously updated as you edit code. It serves a different purpose — giving an AI coding agent structural awareness rather than powering IDE code navigation. It complements but does not replace those tools.

### What license is this under?

[LongHorizons Software License v1.0](../LICENSE) — source-available. Free for personal, research, and educational use. Commercial use, revenue-generating deployment, and use within for-profit entities require a separate commercial license. The plugin lives at `LessToil/plugin/` within the [LongHorizons/WindOH](https://github.com/LongHorizons/WindOH) monorepo.

---

## Installation and Setup

### Does the plugin modify my .gitignore?

Yes — automatically and safely. Both installers add `.claude/index/` to your project's `.gitignore` (creating the file if it doesn't exist). The SessionStart hook also verifies the entry is present on every session. This is idempotent (never creates duplicates) and non-blocking (failures are silently ignored). You never need to manually manage this — the index database is regenerated from source code and should never be committed to version control.

### Does the installer create a virtual environment?

Yes — by default, the installer creates a shared venv at `~/.claude/venv/`. This single venv is used across all your projects, so Python dependencies (tree-sitter, pyyaml, 36 grammar packages) install once and are shared everywhere. The hooks.json is automatically rewritten to use the venv Python, isolating the plugin from system Python changes and avoiding per-project reinstallation.

Use `--no-venv` / `-NoVenv` to skip venv creation and use your system Python directly.

### What are the prerequisites?

- Claude Code (CLI or IDE extension)
- Python 3.8+ on system PATH
- git (for fetching the plugin from GitHub)
- pip (bundled with Python, for installing dependencies)

Optional: tree-sitter grammar packages (36 are installed automatically), Graphviz `dot` CLI (for SVG graph rendering).

With `--accept` / `-Accept`, the installer can attempt to auto-install Python via your platform's package manager (winget/choco on Windows, apt/brew/dnf/pacman on Linux/macOS).

### How long does installation take?

Under 60 seconds for a typical setup. The sparse checkout only fetches the plugin directory (not the entire monorepo). Python dependency installation (tree-sitter, pyyaml, up to 36 grammar packages) is the longest step and depends on your network speed.

### Do I need to install it for every project?

No. The plugin installs once to `~/.claude/plugins/repo-cognition/`. The hooks fire automatically for any project opened with Claude Code. The per-project component is the CLAUDE.md template (which teaches agents how to query the index) — the installer creates this by default. Use `--plugin-only` / `-PluginOnly` to skip project setup.

### Can I install offline (without Git/GitHub access)?

Yes. Download `repo-cognition.zip` from the GitHub releases page and install from the local file:

```bash
# Bash
bash install.sh --from-zip repo-cognition.zip

# PowerShell
.\install.ps1 -FromZip repo-cognition.zip
```

### How do I verify the installation worked?

After installation, open a Claude Code session in your project. The SessionStart dashboard should appear as a system message. You can also verify manually:

```bash
ls ~/.claude/plugins/repo-cognition/core/manifest.py
python ~/.claude/plugins/repo-cognition/scripts/query-index.py --stats
```

---

## Usage and Workflow

### Do I need to manually trigger reindexing?

No. The index is maintained automatically:
- **SessionStart**: Detects changed files via SHA256 comparison and reindexes them
- **PostToolUse**: Incremental reindex after every file edit (Write/Edit/MultiEdit)
- **Branch switches**: Detected on next SessionStart via hash mismatches

You only need `/index-rebuild` if the index becomes corrupted or you want a completely fresh start (e.g., after installing new tree-sitter grammar packages).

### What happens when I switch git branches?

The SessionStart hook compares stored SHA256 hashes against the current filesystem. After a branch switch, files with different content are detected (hash mismatch) and reindexed automatically. Files present on the old branch but not the new one are removed (CASCADE delete to symbols and call edges). New files are added.

### Can I see what the plugin is doing?

Yes, in several ways:
- **SessionStart**: The dashboard system message shows index statistics
- **PreToolUse**: Impact analysis and warnings appear before edits
- `/index-status`: Full interactive dashboard at any time
- **Citation prefixes**: All agent answers show `[index]` or `[grep]`
- **SQLite queries**: Query the database directly for complete transparency (Python query helper, inline Python, or sqlite3 CLI)
- **Hook logs**: Check `.claude/logs/` for hook execution details

### Can I query the index from outside Claude Code?

Yes. The index is a standard SQLite database queryable through several methods:

**Python query helper (cross-platform, no extra tools needed):**
```bash
python ~/.claude/plugins/repo-cognition/scripts/query-index.py "SELECT * FROM files LIMIT 10;"
python ~/.claude/plugins/repo-cognition/scripts/query-index.py --symbol login
python ~/.claude/plugins/repo-cognition/scripts/query-index.py --stats
```

**Inline Python (always available, stdlib only):**
```python
python -c "
import sqlite3
conn = sqlite3.connect('.claude/index/repo-cognition/index.db')
conn.row_factory = sqlite3.Row
for row in conn.execute('SELECT * FROM files LIMIT 10'):
    print(dict(row))
"
```

**Or use the Python helper modules:**
```python
import sys
sys.path.insert(0, '~/.claude/plugins/repo-cognition')
from core.call_graph import get_callers, get_hotspots
print(get_callers('login'))
```

**sqlite3 CLI (Unix/macOS, if installed):**
```bash
sqlite3 .claude/index/repo-cognition/index.db "SELECT * FROM files LIMIT 10;"
```

The auto-generated `.claude/index/repo-cognition/CLAUDE.md` contains the full schema reference and common query examples.

### Will the PreToolUse hook slow down my editing?

For typical edits, PreToolUse adds < 1 second of latency. It runs SQL queries against an indexed SQLite database — no file I/O beyond reading the proposed edit content. The hook has a 45-second timeout; if it somehow exceeds this, it is terminated and the edit proceeds (fail-open for safety).

---

## Performance and Scale

### How much disk space does the index use?

Approximately 10-20% of your source code size. A 10 MB codebase produces a 1-2 MB SQLite database. The WAL file adds temporary overhead during writes (typically < 4 MB). The `file_manifest.json` is proportional to file count (~200 bytes per file).

### Does this work on large codebases (100K+ files)?

Yes, with graceful degradation:
- File walk + SHA256 hashing completes in 30-60 seconds for 100K files
- Symbol extraction uses the background/deferred strategy (budget-capped at 30 seconds on SessionStart)
- The SQLite database remains performant at scale (all query paths are indexed)
- Incremental reindexing stays fast (< 1 second per edit regardless of repo size)
- Advanced intelligence modules (forecasting, economics) sample rather than analyze every file

### Will this slow down Claude Code sessions?

For most repos, the impact is negligible:
- **SessionStart**: Dashboard appears in < 5 seconds for repos under 1K files; < 30 seconds for 1K-10K files
- **PreToolUse**: < 1 second before edits
- **PostToolUse**: Runs silently in background (< 1 second)
- **Large repos (>10K files)**: Initial index may take 30-60s; incremental updates remain fast

The plugin is designed with graceful degradation — every module has a time budget, and failures never block the session.

### Can I run this on a codebase with 1M+ files?

Technically yes, but the initial SessionStart will time out at 120 seconds before completing full symbol extraction. File walking and hashing will complete; symbol extraction will be deferred to incremental reindexing on first edit of each file. For extremely large monorepos, consider using `exclude_dirs` to skip generated code, vendored dependencies, and build artifacts.

### What's the memory footprint?

The Python process for hooks typically uses 50-150 MB of RAM. The SQLite database is memory-mapped for reads but doesn't load fully into memory. Peak memory during symbol extraction (tree-sitter AST parsing of large files) may reach 200-300 MB briefly.

---

## Technical Design

### Why SQLite instead of JSON files?

SQLite provides essential query capabilities that flat files cannot:
- **JOINs**: Trace call edges through files, symbols, and domains
- **Recursive CTEs**: Transitive dependency analysis in a single query
- **Indexes**: Fast lookup by name, file, kind, domain, or hash
- **WAL mode**: Concurrent read/write — PostToolUse writes while the agent reads
- **Single file**: Easy to manage — no directory of thousands of small JSON files
- **Standard tooling**: Queryable with `sqlite3` CLI, Python module, or any SQLite client

A flat JSON approach would require loading the entire graph into memory for every query.

### Why Python for hooks instead of shell scripts?

Three core dependencies require Python:
1. **tree-sitter**: AST parsing for 41 languages — no shell equivalent
2. **SQLite**: Database operations across 26 tables — shell can't do JOINs or CTEs practically
3. **Graph algorithms**: Call graph traversal, SimHash computation, recursive CTE generation

Python's `ast` module is also used for validating the plugin's own code during installation. The existing Claude Code plugin ecosystem validates the Python-in-hooks pattern.

### Why hybrid tree-sitter + regex instead of one or the other?

Tree-sitter provides accurate AST parsing that handles nested scopes, closures, decorators, generics, async/await, JSX, template literals, and other complex syntax that regex cannot reliably parse.

However, tree-sitter requires per-language grammar packages (36 installed automatically). The regex fallback ensures the plugin works immediately for all 56 languages — even if grammar installation failed, or for languages that don't have tree-sitter grammars.

The installer makes this transparent: it installs all available grammars, and the engine selects tree-sitter when available, falling back to regex otherwise, with confidence scores reflecting the extraction method used.

### How do you handle dynamic calls (reflection, getattr, eval)?

Dynamic calls are marked with `is_dynamic=True` and a reduced confidence score (0.3). The call edge is stored in the graph and included in impact analysis, but annotated as uncertain. For example, a dynamic call like `getattr(obj, method_name)()` would appear as:

```
⚠ call_edges: caller=processRequest, callee=<dynamic>, is_dynamic=1, confidence=0.3
```

The agent can see that `processRequest` makes dynamic calls but cannot statically determine the callee. This is surfaced in impact analysis so the agent knows the analysis is incomplete for that function.

### How does schema migration work?

The database auto-migrates on `init_db()`:
- **v1 → v2**: Adds confidence_scores, temporal tables, governance tables, taint analysis, profile snapshots, and new columns
- **v2 → v3**: Adds stewardship_suggestions, evidence_records, evidence_dependencies, contradictions, immune_baselines, immune_alerts, intent_records, and toolchain_audit

All migrations are additive (new tables, new columns with defaults) — existing data is preserved. The `schema_version` table tracks the current version. Run `/index-rebuild` for a clean start.

### What happens if a hook or module fails?

Every advanced module is wrapped in try/except — failures are logged but never block session start or tool execution:
- **SessionStart**: Failed modules are skipped; the dashboard still displays with partial data
- **PreToolUse**: If the hook fails entirely, the edit proceeds (fail-open)
- **PostToolUse**: If reindexing fails, the stale index entry remains; it will be corrected on the next SessionStart or edit

The plugin is designed so that no single module failure can prevent Claude Code from functioning.

---

## Comparison

### How does this compare to ctags or tree-sitter tags?

| Feature | ctags | tree-sitter tags | LessToil |
|---------|:---:|:---:|:---:|
| Symbol extraction | Yes | Yes | Yes (41 grammars + 15 regex) |
| Call graph (directed) | No | No | **Yes** |
| Transitive dependency analysis | No | No | **Yes** (recursive CTE) |
| Architectural domains | No | No | **Yes** (14 domains, security boundaries) |
| Duplicate detection | No | No | **Yes** (SimHash 64-bit) |
| Impact analysis | No | No | **Yes** (automatic pre-edit) |
| Incremental updates | No | No | **Yes** (post-edit hook) |
| SQL query interface | No | No | **Yes** (26 tables, full SQL) |
| Claude Code integration | No | No | **Yes** (hooks, commands, skill) |
| Cross-session persistence | Manual | Manual | **Automatic** |
| Temporal risk analysis | No | No | **Yes** (git history) |
| Governance enforcement | No | No | **Yes** (invariants + policies) |
| Edit-time blocking | No | No | **Yes** (dangerous edits blocked) |

### How does this compare to GitHub Copilot's codebase indexing?

**GitHub Copilot indexing**:
- Server-side — code embeddings computed on GitHub's servers
- Embedding-focused — uses semantic similarity, not structural graph relationships
- Opaque — you cannot query the index directly
- Proprietary — tied to the Copilot product

**LessToil**:
- Local — everything runs on your machine
- Structure-focused — call graphs, dependency graphs, architectural domains
- Queryable — full SQL access to the index (26 tables)
- Open — source-available (LongHorizons Software License v1.0), extensible, 40 Python modules you can modify

The two approaches are complementary. Embeddings excel at "find code semantically similar to this." Graphs excel at "who calls this" and "what is the impact of changing this." LessToil focuses on the latter.

### Does this work alongside other Claude Code plugins?

Yes. LessToil is a standard Claude Code plugin that operates through hooks, agents, commands, and skills. It does not interfere with other plugins. The hooks run independently and the SQLite database is self-contained in `.claude/index/repo-cognition/`.

---

## Customization

### Can I add custom architectural domains?

Yes. Add them to `.claude/repo-cognition.settings.local.md`:

```yaml
---
domains:
  custom_domains:
    - name: ml-pipeline
      description: Machine learning training and inference
      path_patterns: [ml/, training/, inference/, model/]
      symbol_patterns: [train, predict, inference, model, embedding]
      security_boundary: false
---
```

Or for permanent additions, add entries to `DOMAIN_DEFINITIONS` in `core/domains.py` and submit a PR.

### Can I add custom governance rules?

Yes. Create `.claude/repo-cognition.policies.local.md` with SQL-based invariants and threshold-based policies. See [GETTING_STARTED.md](GETTING_STARTED.md#custom-governance-rules) for the complete format and examples.

### Can I exclude directories from indexing?

Yes. Built-in exclusions cover `node_modules`, `__pycache__`, `.git`, `dist`, `build`, `target`, `.claude`, and similar. Add custom exclusions in `.claude/repo-cognition.settings.local.md`:

```yaml
---
exclude_dirs: [.terraform, .cache, vendor, generated, third_party]
---
```

### Can I tune the performance vs. accuracy tradeoff?

Yes. Settings in `.claude/repo-cognition.settings.local.md`:

```yaml
---
max_extraction_time_sec: 45     # More time = more symbols on first session
similarity_threshold: 0.85      # Lower = more duplicate candidates flagged
---
```

---

## Troubleshooting

### "Python was not found"

**Windows**: Use `python` (not `python3`). If Python is installed but not on PATH, reinstall from [python.org](https://python.org) and check "Add Python to PATH." Run `where.exe python` to verify.

**macOS**: `brew install python3`
**Linux**: `apt install python3` (Debian/Ubuntu) or equivalent.

### "No module named 'core'"

The `CLAUDE_PLUGIN_ROOT` environment variable must point to the plugin directory. The hooks set this automatically. To verify manually: `ls ~/.claude/plugins/repo-cognition/core/manifest.py`. If missing, re-run the installer.

### "tree-sitter module not found"

Install manually: `pip install tree-sitter pyyaml`. The plugin works without grammar packages (regex fallback), but AST-level parsing is more accurate with them. The installer installs 36 grammar packages automatically.

### "Index database is locked"

SQLite WAL mode handles concurrent access. If a lock persists after a crash, remove the stale lock file:

```bash
rm -f .claude/index/repo-cognition/indexing.lock
```

Then reopen Claude Code — the SessionStart hook will recover.

### "SessionStart hook timed out"

For very large repos (>50K files), run a manual index once:

```bash
CLAUDE_PROJECT_DIR="$(pwd)" CLAUDE_PLUGIN_ROOT="$HOME/.claude/plugins/repo-cognition" \
  python3 $HOME/.claude/plugins/repo-cognition/hooks/session_start.py <<< '{"session_id":"manual","cwd":"'"$(pwd)"'"}'
```

Subsequent sessions will use incremental updates and stay within the timeout.

### The dashboard doesn't appear

Check: (1) plugin installed at `~/.claude/plugins/repo-cognition/`, (2) `hooks.json` is valid JSON, (3) Python 3.8+ is on PATH, (4) Claude Code logs at `.claude/logs/`, (5) no stale lock file, (6) project has `.claude/CLAUDE.md`.

### Symbols not extracted for my language

Check the supported languages table in [README.md](README.md). For unsupported languages, file-level indexing still works. To add language support, see [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Contributing

### How do I add support for a new language?

See [CONTRIBUTING.md](CONTRIBUTING.md). The process involves: (1) adding extension mappings to `core/indexer.py`, (2) adding tree-sitter SCM queries to `core/symbols.py`, (3) adding grammar packages to both installers, (4) adding a regex fallback extractor, and (5) registering the language in `SUPPORTED_LANGUAGES`.

### How do I report a bug?

Open an issue at https://github.com/LongHorizons/WindOH with: your project's primary language and approximate file count, Python version (`python --version`), the error message or unexpected behavior, steps to reproduce, and whether it occurs on fresh sessions or after specific operations.

### What's the relationship between the plugin and the claude-code monorepo?

The plugin lives at `LessToil/plugin/` within the [LongHorizons/WindOH](https://github.com/LongHorizons/WindOH) monorepo. It is developed alongside Claude Code but is a standalone plugin — it does not depend on the monorepo to function. The installers fetch just the plugin directory via sparse checkout, so users never need to clone the entire monorepo.

### Can I contribute to the plugin without contributing to Claude Code?

Yes. The plugin is a self-contained directory with its own installers, documentation, and development workflow. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup and PR process.
