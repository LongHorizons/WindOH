# LessToil

<div align="center">

> **Structural intelligence for AI-assisted development.**
>
> A persistent codebase knowledge engine that gives Claude Code genuine architectural awareness — transforming every coding session from keyword search into structured reasoning.

</div>

---

## Executive Summary

**LessToil** is a Claude Code plugin that indexes your entire codebase into a continuously maintained SQLite knowledge graph. Instead of searching for files by name and guessing at architecture from partial context, your AI coding agent queries a structured index that explicitly maps every symbol, caller, callee, architectural domain, and dependency across your project.

The engine operates through three lifecycle hooks — **SessionStart** (full index with dashboard), **PreToolUse** (impact analysis and governance before every edit), and **PostToolUse** (incremental reindex after every edit) — plus three user-facing slash commands and an auto-activating query skill. 40 Python modules power extraction, analysis, and enforcement across 56 languages.

**Key outcomes for a 5-person team on a medium codebase (~3K files):**

| Dimension | Annual Impact |
|-----------|---------------|
| Token savings | ~55K-120K tokens saved per session; 60% reduction in structural discovery overhead |
| Bugs prevented | 65-132 bugs caught before reaching production per year |
| Developer hours recovered | 550-1,210 hours/year through eliminated toil and prevented tech debt |
| Cost recovery | ~$110K-$365K in recovered engineering productivity per year |
| Install time | Under 60 seconds; zero configuration required |

Every agent answer is prefixed with `[index]` or `[grep]` so you always know where information originates.

---

## Business Intent

### Why This Exists

LLM coding assistants operate by reading a few files at a time, searching by keyword, and building understanding from whatever partial context fits in their context window. This works for isolated tasks but systematically fails at three things that determine software quality at scale:

1. **Cross-file awareness** — The agent doesn't know who calls a function, what depends on a module, or what will break if a shared interface changes.
2. **Persistent knowledge** — Every session starts from zero. Architecture learned yesterday is forgotten today. The agent rediscovers the codebase repeatedly.
3. **Structural constraints** — Codebases have rules: UI doesn't call the database directly, auth boundaries must not be bypassed, circular dependencies are forbidden. Keyword search cannot enforce these.

LessToil addresses all three by giving the agent a pre-computed, continuously updated structural map that persists across sessions.

### Who This Is For

| Role | Value |
|------|-------|
| **Engineering teams** | Fewer bugs, faster PR reviews, less time tracing dependencies manually |
| **Individual developers** | Instant answers to structural questions, no re-discovery between sessions |
| **Tech leads / architects** | Drift detection, governance enforcement, architectural oversight |
| **Security engineers** | Security boundary tracking, taint flow analysis, audit preparation |
| **New team members** | Domain maps and call flows in seconds instead of days of code reading |
| **Open-source maintainers** | Understand contributor changes' blast radius, detect duplicate implementations |

### The Problem It Solves

Claude Code and similar AI coding tools share a fundamental limitation: they have no persistent memory of your codebase. Every session they must rediscover architecture through expensive, error-prone file-by-file exploration. This causes:

- **Duplicated logic** — The agent creates a fourth JWT validator because it doesn't know three already exist
- **Hidden functionality** — Orphaned code accumulates because no one remembers it's there
- **Context loss** — Each new session restarts discovery from zero, burning tokens on re-reading unchanged files
- **Architectural drift** — New code is placed in the wrong layer because the agent lacks domain awareness
- **Breaking changes** — Functions are renamed or modified without awareness of downstream callers
- **Repeated rediscovery** — The same files are read session after session

LessToil solves this by maintaining a living index that survives sessions, branch switches, and merges. The agent queries structured data rather than re-reading source files.

---

## How It Works

### Core Mechanism

```
User opens project
  │
  ▼
SessionStart Hook (120s budget)
  ├─ Walk repository → SHA256 every file
  ├─ tree-sitter AST → extract symbols (functions, classes, methods)
  ├─ Build directed call graph (caller → callee)
  ├─ Infer architectural domains (14 domains, security boundaries)
  ├─ Compute temporal risk from git history
  ├─ Run stewardship scans (6 categories)
  ├─ Detect architectural drift (4 axes)
  ├─ Seed governance rules (3 invariants + 6 policies)
  ├─ Generate CLAUDE.md query reference for agents
  └─ Inject structural dashboard into agent context
  │
  ▼
Agent receives pre-computed structural knowledge (~600 tokens)
  │
  ▼
Agent about to edit → PreToolUse Hook (45s budget)
  ├─ 10-phase verification pipeline
  ├─ Impact analysis: who calls this? what breaks?
  ├─ Duplicate detection: does this already exist?
  ├─ Governance check: invariants + policies
  ├─ 6-verifier consensus engine grades change
  └─ Blocks dangerous edits (exit code 2) or warns
  │
Agent makes edit → PostToolUse Hook (45s budget)
  ├─ Incremental reindex of changed file(s) only
  ├─ Re-extract symbols, update call graph
  ├─ Confidence feedback loop
  └─ Temporal change counter
```

### Architecture at a Glance

```
┌──────────────────────────────────────────────────────────────┐
│                      Claude Code Session                       │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              LessToil Plugin                              │ │
│  │                (40 modules, v0.4.0)                       │ │
│  │                                                           │ │
│  │  Hooks        │  Agents           │  Commands / Skills   │ │
│  │  ──────────── │  ──────────────── │  ─────────────────── │ │
│  │  SessionStart │  architecture-    │  /index-status       │ │
│  │  PreToolUse   │  inferrer         │  /index-rebuild      │ │
│  │  PostToolUse  │                   │  /index-graph        │ │
│  │               │                   │  Query Skill (auto)  │ │
│  └───────────────────────┬─────────────────────────────────┘ │
│                          │                                     │
│                          ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │           Persistent Index (.claude/index/)              │ │
│  │                                                           │ │
│  │  index.db (SQLite v3, 26 tables, WAL mode)               │ │
│  │  ├─ Core: files, symbols, call_edges, domains            │ │
│  │  ├─ Confidence: 4-axis per-symbol scoring                │ │
│  │  ├─ Temporal: git history risk metrics                   │ │
│  │  ├─ Governance: invariants, policies, violations         │ │
│  │  ├─ Security: taint sources, taint flows                 │ │
│  │  └─ Intelligence: stewardship, evidence, immune, intent  │ │
│  │  + file_manifest.json + CLAUDE.md + unified_graph.*      │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

---

## Features

### Structural Intelligence

**Continuous Index** — Every file receives a SHA256 hash, language classification, and line count. Changes, additions, and deletions are detected automatically. 56 languages supported (41 via tree-sitter AST, 15 via regex fallback). The index is a living map, not a static snapshot.

**Symbol-Level Knowledge Base** — Every function, method, class, interface, and variable becomes a first-class database object with file location, line range, callers, callees, side effects, security sensitivity, and 4-axis confidence score. Queries resolve in microseconds instead of requiring multi-file grep-and-read cycles.

**Directed Call Graph** — All function calls mapped into a traversable graph. Recursive CTE queries answer transitive dependency questions ("show everything that depends on X, directly or indirectly") in a single SQL statement. Dynamic calls (reflection, `getattr`, `eval`) are tracked with explicit confidence annotations.

**Architectural Domain Map** — Files and symbols classified into 14 domains (authentication, payments, caching, API, UI, data-access, crypto, networking, messaging, config, logging, testing, build, system). Security boundaries marked explicitly. Custom domains definable per project.

### Edit-Time Protection

**10-Phase Verification Pipeline** — Before every edit: PLAN → SIMULATE → VERIFY → CONSTRAIN → EXECUTE → TEST → TRACE → SCORE → REPAIR → REVERIFY. Not advisory linting — dangerous changes are actively blocked.

**6-Verifier Consensus Engine** — Six independent verifiers (invariants, policies, simulation, immune, formal, confidence) weigh in on every proposed change. Disagreements are surfaced explicitly. Weighted scoring produces a unified safety grade.

**Impact Analysis** — Before any file edit, the PreToolUse hook reports: all affected callers (recursive CTE, depth ≤ 10), downstream dependencies, affected test files, security-sensitive symbols in the blast radius, and impacted architectural domains.

**Duplicate Detection** — SimHash 64-bit fingerprinting identifies duplicated business logic, near-identical utilities, shadow abstractions, and fragmented implementations. Warns before you create the fourth copy of the same function.

**Governance Enforcement** — SQL-based invariants (0 rows = satisfied) and threshold-based policies enforce architectural rules. Built-in: 3 invariants, 6 policies. Custom rules via `.local.md` files. Violations with severity "error" block the edit (exit code 2).

**Change Grading** — Every edit is graded safe / cautious / risky / dangerous. Dangerous changes are blocked before execution.

### Continuous Maintenance

**Incremental Reindexing** — After every edit, only the changed files are reindexed. Symbols re-extracted, call graph updated, confidence scores adjusted. Under 1 second per file.

**Temporal Risk Analysis** — Git history analyzed for churn rate, bug-fix density (commits mentioning "fix", "bug", "patch", "vuln"), security patch frequency, and ownership volatility. Per-file risk scores highlight the codebase areas most likely to break.

**Architectural Drift Detection** — Four drift types tracked across sessions: naming divergence, style outliers, anti-pattern emergence, and framework creep. Scores persist and accumulate, enabling trend analysis over time.

**Autonomous Stewardship** — Six scan categories at session start: dead subsystems, over-complex files, high-churn hotspots, dangerous coupling, unowned critical paths, and stale patterns. Findings persist in SQLite and are tracked to resolution.

**Self-Healing Loop** — Detect → Propose → Validate → Repair cycle across four anomaly sources. Repository immune system builds behavioral baselines and quarantines anomalies.

### Cross-Cutting Capabilities

**Confidence System** — 4-axis scoring (parser, type, runtime, purpose) with weakest-link aggregation. Low-confidence symbols flagged in pre-edit warnings. Feedback loop adjusts scores from profiling data.

**Advanced Intelligence Modules** — Epistemic evidence tracking with contradiction detection; long-horizon architectural forecasting (1x/2x/5x/10x scale); semantic compression detecting equivalent paradigms beyond literal duplication; economic modeling of build/CI/cloud/dev-hours costs; cognitive load modeling; design intent preservation; adversarial robustness; knowledge decay detection; operational sovereignty with health checks and corruption repair; reality alignment (business vs. technical correctness); meta-reasoning with blind spot tracking; toolchain auditing with trust scoring.

**Citation Transparency** — All agent answers prefixed with `[index]` (queried the structured database) or `[grep]` (fell back to text search). You always know where information comes from.

**Graph Visualization** — DOT/Graphviz call graphs, domain dependency maps, hotspot identification, and unified weighted multi-edge graphs (JSON + DOT) merging AST, type, runtime, profiling, and temporal data.

---

## Quantified Impact

### Token Efficiency

Every structural question costs tokens. The plugin replaces expensive file-reading with cheap database queries:

| Structural question | Without plugin | With plugin | Token reduction |
|---------------------|---------------|-------------|-----------------|
| "Where is X defined?" | Grep → read 3-5 files (~4K tokens) | SQL row (~80 tokens) | 97% |
| "Who calls X?" | Read caller files + trace (~7K tokens) | `call_edges` query (~150 tokens) | 97% |
| "Impact of changing X?" | Recursively read callers (~14K tokens) | Recursive CTE (~250 tokens) | 98% |
| "Find duplicates of this" | Grep + read candidates (~7K tokens) | SimHash lookup (~80 tokens) | 98% |
| "What domain is this in?" | Read files, infer (~5K tokens) | `file_domains` JOIN (~100 tokens) | 97% |
| "Find unused functions" | Manual trace all symbols (~20K tokens) | Orphan query (~150 tokens) | 99% |

Per-session token budget shift: without the plugin, codebase discovery consumes ~30% of the context window. With it, discovery drops to ~8%. Task execution rises from 40% to 70% of available tokens. Compounding across sessions (the index persists, so sessions 2+ require even less discovery), cumulative savings reach 240K tokens by session 5.

### Bug Prevention

The PreToolUse hook catches entire categories of bugs before they ship:

| Bug category | Mechanism | Est. bugs/year prevented (team of 5) |
|--------------|-----------|--------------------------------------|
| Duplicate implementations | SimHash + symbol collision detection | 15-30 |
| Breaking changes (undetected callers) | Recursive CTE impact analysis | 25-50 |
| Dead code accumulation | Orphan symbol detection | 10-20 |
| Architecture violations | Governance invariants + policies | 5-15 |
| Security boundary bypasses | Taint tracking + formal constraints | 2-5 |
| Drift into anti-patterns | Drift detection across 4 axes | 8-12 |
| **Total** | | **65-132 bugs/year** |

Each prevented bug saves 2-8 hours of developer time (reproduction, debugging, fix, review, deploy, verification). At a blended engineering rate, that's 130-1,056 developer-hours saved annually — from bugs that never happen.

### Toil and Tech-Debt Elimination

| Category | Without plugin (hours/year) | With plugin (hours/year) | Savings |
|----------|----------------------------|--------------------------|---------|
| Manual dependency tracing | 200-400 | 10-20 | 190-380 |
| Duplicate consolidation | 60-120 | 5-10 | 55-110 |
| Dead code cleanup | 40-80 | 5-10 | 35-70 |
| Security audit prep | 40-80 | 5-10 | 35-70 |
| Onboarding new team members | 80-160 | 10-20 | 70-140 |
| PR review (blast-radius assessment) | 100-200 | 20-40 | 80-160 |
| Drift remediation | 40-80 | 5-10 | 35-70 |
| Bug fixes from undetected breakages | 60-240 | 10-30 | 50-210 |
| **Total** | **620-1,360** | **70-150** | **550-1,210** |

At typical fully-loaded engineering cost, that represents roughly **$110K-$365K in recovered productivity per year** for a 5-person team.

---

## Supported Languages

### Full Support (AST + Symbol Extraction + Call Graph)

Python, TypeScript, JavaScript, Go, Rust

### Strong Support (AST + Symbol Extraction + Basic Call Graph)

Java, C, C++, C#, Ruby, PHP, Swift, Kotlin, Scala, Lua, Dart, Zig, Solidity, Elixir, Haskell, OCaml, Svelte

### Configuration & Markup (AST + Symbol Extraction)

SQL, Bash/Shell, HTML, CSS, JSON, YAML, TOML, Markdown, Dockerfile, HCL/Terraform, GraphQL, Make, CMake, PowerShell, Nix

### File Indexing Only

20+ additional languages via extension detection

---

## What to Expect

### On Session Start

A professional geometric dashboard appears as a system message confirming the plugin is active. It displays file counts, symbol counts, language distribution, temporal risk, confidence metrics, architectural drift, stewardship suggestions, and governance status. This replaces ~15 minutes of manual architecture re-discovery with ~600 tokens of pre-computed context.

### During Editing

**Before edits**: Impact analysis, duplicate detection, confidence warnings, and governance checks may surface messages. Dangerous edits are blocked with exit code 2.

**After edits**: Silent incremental reindex (< 1 second per file). Symbols re-extracted, call graph updated, confidence scores adjusted, temporal counter incremented.

### Agent Citation Behavior

All agents prefix structural answers with `[index]` or `[grep]`. This is enforced via the project's CLAUDE.md template. Repeated `[grep]` answers may indicate the index needs a rebuild (`/index-rebuild`).

### Performance

| Operation | <1K files | 1K-10K files | 10K+ files |
|-----------|-----------|--------------|------------|
| Full index (SessionStart) | < 5s | < 30s | deferred/background |
| Incremental reindex (1 file) | < 0.5s | < 0.5s | < 0.5s |
| Impact analysis | < 0.1s | < 0.2s | < 0.5s |
| Dashboard generation | < 1s | < 1s | < 2s |

### Disk Usage

Approximately 10-20% of source code size. A 10 MB codebase produces a 1-2 MB SQLite database. The WAL file adds temporary ~4 MB overhead during writes.

---

## Quick Start

### Windows (PowerShell)

```powershell
(iwr -UseBasicParsing https://raw.githubusercontent.com/LongHorizons/WindOH/master/LessToil/plugin/install.ps1).Content | iex
```

### macOS / Linux (Bash)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LongHorizons/WindOH/master/LessToil/plugin/install.sh)
```

### Post-Install

1. Restart Claude Code or open a new session in your project directory
2. The SessionStart hook fires automatically — watch for the dashboard
3. Try `/index-status` and `/index-graph --hotspots`
4. Ask structural questions — the query skill auto-activates

### Install Options

| Bash Flag | PowerShell Flag | Purpose |
|-----------|----------------|---------|
| `--project-dir /path` | `-ProjectDir PATH` | Set up a specific project |
| `--plugin-only` | `-PluginOnly` | Install plugin only, skip project setup |
| `--reindex` | `-Reindex` | Force immediate index build |
| `--from-zip FILE` | `-FromZip FILE` | Install from local release zip (no Git needed) |
| `--accept` | `-Accept` | Non-interactive: auto-confirm, auto-install Python if missing |
| `--no-venv` | `-NoVenv` | Skip shared venv, use system Python directly |

---

## Commands

```
/index-status              Professional index dashboard with all metrics
/index-graph <name>        Call graph centered on a function
/index-graph --orphans     Find functions that are never called
/index-graph --hotspots    Find most-called functions
/index-graph --domain-graph  Cross-domain dependency visualization
/index-rebuild             Force complete reindex from scratch
```

---

## Data Privacy

All indexing happens **locally** on your machine. The SQLite database, JSON manifests, and `.local.md` files reside in `.claude/index/repo-cognition/` within your project directory. No data is sent to external services. The plugin has no network access. `.claude/index/` is automatically added to `.gitignore` — both installers handle this at setup time, and the SessionStart hook enforces it on every session.

---

## Requirements

- **Claude Code** (CLI tool or IDE extension)
- **Python 3.8+** on system PATH
- **git** (for plugin installation from GitHub)
- Optional: tree-sitter language grammars for AST-level extraction (installed automatically)
- Optional: Graphviz `dot` CLI for SVG graph rendering

---

## Documentation Index

| Document | Content |
|----------|---------|
| [GETTING_STARTED.md](GETTING_STARTED.md) | Installation, configuration, first-use walkthrough, troubleshooting |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Deep technical dive: data model, hook lifecycle, 40 modules, design decisions |
| [USE_CASES.md](USE_CASES.md) | 12 real-world scenarios with before/after comparisons and SQL examples |
| [FAQ.md](FAQ.md) | Answers to common questions about usage, performance, and design rationale |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to add language support, new features, bug fixes, and development setup |

---

## License

MIT
