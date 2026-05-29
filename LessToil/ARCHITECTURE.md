# LessToil — Architecture

> Complete technical reference covering plugin internals, data model, component interactions, hook lifecycle, algorithms, and design rationale.

---

## Table of Contents

1. [High-Level Design](#high-level-design)
2. [Extension Points](#extension-points)
3. [Component Map](#component-map)
4. [Data Model](#data-model)
5. [Hook Lifecycle](#hook-lifecycle)
6. [Symbol Extraction Pipeline](#symbol-extraction-pipeline)
7. [Call Graph Construction](#call-graph-construction)
8. [Architectural Domain Inference](#architectural-domain-inference)
9. [Duplicate Detection](#duplicate-detection)
10. [Impact Analysis](#impact-analysis)
11. [Verification Pipeline](#verification-pipeline)
12. [Governance System](#governance-system)
13. [Confidence System](#confidence-system)
14. [Temporal Risk Analysis](#temporal-risk-analysis)
15. [Architectural Drift Detection](#architectural-drift-detection)
16. [Stewardship and Self-Healing](#stewardship-and-self-healing)
17. [Advanced Intelligence Modules](#advanced-intelligence-modules)
18. [Incremental Reindexing](#incremental-reindexing)
19. [Cross-Session Persistence](#cross-session-persistence)
20. [Performance Characteristics](#performance-characteristics)
21. [Security Model](#security-model)
22. [Design Decisions (ADR)](#design-decisions-adr)

---

## High-Level Design

### Architectural Philosophy

LessToil treats the codebase as a **graph**, not a folder tree. Every file, symbol, call relationship, and architectural domain is a first-class node in a structured knowledge base. Natural-language task execution becomes a thin layer on top of structural repository intelligence.

The engine behaves closer to a **compiler frontend**, **Ghidra**, or **Sourcegraph** than a chatbot — it builds and maintains an explicit, queryable model of the codebase that survives across sessions and evolves as code changes.

### Core Principles

```
├── Every file must be known explicitly (SHA256, language, size, purpose).
├── Every symbol must be a first-class indexed object (function, class, interface).
├── Every call relationship must be mapped (caller → callee, with confidence).
├── Every architectural domain must be inferred and persisted.
├── Structural adjacency outranks text similarity.
├── All modifications must update the index automatically.
├── Dangerous operations must be blocked, not just warned about.
└── The system must degrade gracefully — no module failure blocks the session.
```

### Plugin Constraints

LessToil operates as a **Claude Code plugin** — it extends the engine's behavior through four well-defined extension points. It cannot modify the core context injection pipeline, embedding system, or built-in tool set. All intelligence is delivered through hooks, agents, commands, and skills.

---

## Extension Points

| Mechanism | Trigger | Implementation | Budget |
|-----------|---------|---------------|--------|
| **SessionStart Hook** | Every session open | `session_start.py` — Python | 120s |
| **PreToolUse Hook** | Before Write/Edit/MultiEdit | `pre_tool_use.py` — Python | 45s |
| **PostToolUse Hook** | After Write/Edit/MultiEdit | `post_tool_use.py` — Python | 45s |
| **Agents** | User invokes or system routes | `.md` system prompts | Per Claude Code |
| **Commands** | User types slash command | `.md` command files | Per Claude Code |
| **Skills** | User asks structural question | `SKILL.md` with trigger phrases | Auto-activates |

### Data Flow

```
User opens project
  │
  ▼
SessionStart Hook fires
  │
  ├─► ensure_gitignore()          → add .claude/index/ to .gitignore
  ├─► Health check (existing index? lock file?)
  ├─► walk_repository()           → file list with SHA256
  ├─► upsert_file()               → SQLite: files table
  ├─► parse_file()                → tree-sitter / regex fallback
  ├─► upsert_symbols_batch()      → SQLite: symbols table
  ├─► insert_call_edges_batch()   → SQLite: call_edges table
  ├─► classify_all_files()        → SQLite: domains, file_domains
  ├─► compute_confidence()        → SQLite: confidence_scores
  ├─► compute_temporal_risk()     → SQLite: temporal_metrics
  ├─► detect_architectural_drift()→ SQLite: files.drift_score
  ├─► run_stewardship_scans()     → SQLite: stewardship_suggestions
  ├─► run_self_healing()          → Detect → Propose → Validate
  ├─► seed_governance()           → 3 invariants + 6 policies (idempotent)
  ├─► generate_claude_md()        → .claude/index/repo-cognition/CLAUDE.md
  └─► inject additionalContext    → agent session context (~600 tokens)
  │
  ▼
Agent receives structural summary + CLAUDE.md query reference
  │
  ▼
Agent about to edit → PreToolUse hook fires
  ├─► Verification Pipeline: PLAN → SIMULATE → VERIFY → CONSTRAIN
  ├─► Governance checks: invariants + policies (can exit 2 to block)
  ├─► Impact analysis: affected callers, downstream deps, tests, domains
  ├─► Duplicate detection: SimHash + symbol name collision
  └─► Output warnings or block (exit 2 for dangerous/governance violations)

Agent makes edits → PostToolUse hook fires
  ├─► Incremental reindex of changed files
  ├─► Re-extract symbols + rebuild call edges
  ├─► Confidence feedback loop (adjust from profiling signals)
  ├─► Temporal change counter increment
  └─► Post-execute verification (TRACE + SCORE phases)
```

---

## Component Map

### Source Tree

```
LessToil/plugin/
│
├── hooks/                          # Runtime lifecycle hooks
│   ├── hooks.json                  # Hook registration
│   ├── session_start.py            # Full index on session open (120s)
│   ├── pre_tool_use.py             # Impact analysis + governance (45s)
│   └── post_tool_use.py            # Incremental reindex (45s)
│
├── core/                           # 40 Python library modules
│   ├── __init__.py                 # Path constants (INDEX_DIR, DB_PATH, etc.)
│   ├── manifest.py                 # SQLite DDL, CRUD, schema migrations
│   ├── indexer.py                  # File walker, SHA256, language detection
│   ├── symbols.py                  # tree-sitter + regex symbol extraction
│   ├── call_graph.py               # Call graph construction + query functions
│   ├── domains.py                  # Architectural domain inference
│   ├── similarity.py               # SimHash 64-bit duplicate detection
│   ├── impact.py                   # Transitive impact analysis (recursive CTE)
│   ├── dot_gen.py                  # DOT/Graphviz graph generation
│   ├── formatting.py               # Dashboard and output formatting
│   ├── confidence.py               # 4-axis scoring + feedback loop
│   ├── temporal.py                 # Git history churn/risk analysis
│   ├── governance.py               # Invariants + policies + simulation
│   ├── security_provenance.py      # Taint analysis, trust boundaries
│   ├── simulation.py               # Multi-file change simulation grading
│   ├── mutation_sandbox.py         # Sandboxed code mutation testing
│   ├── drift_detection.py          # Naming/style/anti-pattern/framework creep
│   ├── stewardship.py              # 6-category autonomous scanning
│   ├── self_healing.py             # Detect → Propose → Validate → Repair
│   ├── verification.py             # 10-phase pipeline orchestrator
│   ├── consensus.py                # 6-verifier consensus engine
│   ├── formal_constraints.py       # 9 machine-enforced structural rules
│   ├── epistemic.py                # Evidence provenance, contradiction detection
│   ├── immune_system.py            # Behavioral baseline + anomaly quarantine
│   ├── unified_graph.py            # AST + type + runtime + temporal merged graph
│   ├── runtime_profiling.py        # cProfile/pprof/node-prof integration
│   ├── knowledge_distillery.py     # Domain summaries + canonical patterns
│   ├── forecasting.py              # 1x/2x/5x/10x architectural projection
│   ├── semantic_compression.py     # Equivalent paradigm detection
│   ├── economics.py                # Build/CI/cloud/dev-hours cost estimation
│   ├── cognitive_load.py           # Understandability + debugging difficulty
│   ├── intent_preservation.py      # Design intent tracking + drift detection
│   ├── intent_planner.py           # Intent → ConstraintSet → ExecutionPlan
│   ├── adversarial.py              # Deceptive pattern + hidden path detection
│   ├── knowledge_decay.py          # Stale belief detection
│   ├── operational_sovereignty.py  # Health checks + corruption repair
│   ├── reality_alignment.py        # Business vs. technical correctness
│   ├── meta_reasoning.py           # Self-modeling failure + blind spot tracking
│   ├── toolchain_auditor.py        # Tool invocation audit + trust scoring
│   ├── refactor_scoring.py         # Weighted refactor scoring
│   └── minimalism.py               # Abstraction density + simplicity scoring
│
├── agents/                         # LLM-driven analysis
│   └── architecture-inferrer.md    # Infers architectural domains from index
│
├── commands/                       # User slash commands
│   ├── index-status.md             # /index-status — full dashboard
│   ├── index-rebuild.md            # /index-rebuild — force full reindex
│   └── index-graph.md              # /index-graph — call graphs + sub-commands
│
├── skills/                         # Auto-activating contextual skills
│   └── repo-cognition-query/
│       └── SKILL.md                # Triggers on structural queries, 15 SQL recipes
│
├── scripts/
│   ├── generate-claude-md.py       # Generates CLAUDE.md from schema
│   └── query-index.py              # Cross-platform Python CLI for index queries
│
├── .claude-plugin/
│   └── plugin.json                 # Plugin manifest (v0.4.0)
│
├── install.sh                      # Bash installer
└── install.ps1                     # PowerShell installer
```

### Runtime Output (per project)

```
.claude/index/repo-cognition/
├── index.db                        # SQLite (26 tables, WAL mode)
├── index.db-wal                    # Write-Ahead Log
├── index.db-shm                    # Shared memory segment
├── file_manifest.json              # Flat manifest with SHA256
├── CLAUDE.md                       # Auto-generated query reference
├── last_index.txt                  # ISO-8601 timestamp
├── indexing.lock                   # PID lock during indexing
├── unified_graph.json              # Weighted multi-edge graph (JSON)
└── unified_graph.dot               # Weighted multi-edge graph (DOT)

.claude/
├── CLAUDE.md                       # Project CLAUDE.md with index-first instructions
├── repo-cognition.domains.local.md     # Architectural domains (persistent)
├── repo-cognition.patterns.local.md    # Learned patterns (persistent)
├── repo-cognition.policies.local.md    # Custom governance policies
├── repo-cognition.knowledge.local.md   # Distilled architectural knowledge
└── repo-cognition.settings.local.md    # Optional plugin settings
```

---

## Data Model

### SQLite Schema v3 — 26 Tables Across 8 Categories

#### Core Tables

```
┌──────────────────────────────────────────────────────────────────┐
│                          files                                    │
├──────────────┬──────────┬────────────────────────────────────────┤
│ id           │ INTEGER  │ Primary key (auto)                     │
│ file_path    │ TEXT     │ UNIQUE, relative from project root     │
│ sha256       │ TEXT     │ SHA-256 hash of file contents          │
│ language     │ TEXT     │ Detected language                      │
│ file_size    │ INTEGER  │ Size in bytes                          │
│ line_count   │ INTEGER  │ Number of lines                        │
│ last_indexed │ TEXT     │ ISO-8601 timestamp                     │
│ version      │ INTEGER  │ Monotonic index version                │
│ drift_score  │ REAL     │ Architectural drift score              │
└──────────────┴──────────┴────────────────────────────────────────┘
        │
        │ 1:N (ON DELETE CASCADE)
        ▼
┌──────────────────────────────────────────────────────────────────┐
│                         symbols                                   │
├─────────────────┬──────────┬─────────────────────────────────────┤
│ id              │ INTEGER  │ Primary key (auto)                  │
│ file_id         │ INTEGER  │ FK → files.id                       │
│ name            │ TEXT     │ Symbol name                         │
│ kind            │ TEXT     │ function, class, method, variable, …│
│ signature       │ TEXT     │ Full signature string               │
│ start_line      │ INTEGER  │ Starting line number                │
│ end_line        │ INTEGER  │ Ending line number                  │
│ docstring       │ TEXT     │ Documentation string                │
│ is_exported     │ INTEGER  │ 1 if publicly exported              │
│ security_sensitive│ INTEGER│ 1 if touches auth/crypto/secrets    │
│ side_effects    │ INTEGER  │ 1 if mutates state or does I/O      │
└─────────────────┴──────────┴─────────────────────────────────────┘
        │
        │ 1:N (caller_id, ON DELETE CASCADE)
        ▼
┌──────────────────────────────────────────────────────────────────┐
│                        call_edges                                 │
├──────────────┬──────────┬────────────────────────────────────────┤
│ id           │ INTEGER  │ Primary key (auto)                     │
│ caller_id    │ INTEGER  │ FK → symbols.id                        │
│ callee_name  │ TEXT     │ Name of called function                │
│ callee_file  │ TEXT     │ File where callee is defined (nullable)│
│ call_line    │ INTEGER  │ Line number of the call                │
│ is_dynamic   │ INTEGER  │ 1 for reflection/dynamic calls         │
│ confidence   │ REAL     │ 0.0–1.0 resolution confidence          │
└──────────────┴──────────┴────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                         domains                                   │
├──────────────┬──────────┬────────────────────────────────────────┤
│ id           │ INTEGER  │ Primary key (auto)                     │
│ name         │ TEXT     │ UNIQUE: auth, payments, caching, …     │
│ description  │ TEXT     │ Human-readable description             │
│ entry_points │ TEXT     │ JSON array of "file:line" strings      │
│ sec_boundary │ INTEGER  │ 1 if security-sensitive boundary       │
└──────────────┴──────────┴────────────────────────────────────────┘
        │
        │ M:N
        ▼
┌──────────────────────────────────────────────────────────────────┐
│                       file_domains                                │
├──────────────┬──────────┬────────────────────────────────────────┤
│ file_id      │ INTEGER  │ FK → files.id                          │
│ domain_id    │ INTEGER  │ FK → domains.id                        │
│ confidence   │ REAL     │ 0.0–1.0                                 │
│ PRIMARY KEY  │          │ (file_id, domain_id)                    │
└──────────────┴──────────┴────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                     similarity_groups                             │
├──────────────┬──────────┬────────────────────────────────────────┤
│ id           │ INTEGER  │ Primary key (auto)                     │
│ simhash      │ TEXT     │ 64-bit SimHash fingerprint (hex)       │
│ file_path    │ TEXT     │ File containing the code block         │
│ symbol_name  │ TEXT     │ Function/symbol name (nullable)        │
│ start_line   │ INTEGER  │ Start line of the code block           │
│ end_line     │ INTEGER  │ End line of the code block             │
│ norm_code    │ TEXT     │ Normalized code (identifiers replaced) │
│ language     │ TEXT     │ Programming language                   │
└──────────────┴──────────┴────────────────────────────────────────┘
```

#### Complete Table Inventory

| Category | Table | Purpose |
|----------|-------|---------|
| **Core** | `files` | File metadata, SHA256, language, size |
| **Core** | `symbols` | Functions, classes, methods, variables |
| **Core** | `call_edges` | Directed caller → callee relationships |
| **Core** | `domains` | Architectural domain definitions |
| **Core** | `file_domains` | File-to-domain M:N mapping with confidence |
| **Similarity** | `similarity_groups` | SimHash duplicate groups |
| **Confidence** | `confidence_scores` | 4-axis per-symbol confidence |
| **Temporal** | `temporal_metadata` | Git repository metadata |
| **Temporal** | `temporal_metrics` | Per-file risk scores (churn, bugs, security, volatility) |
| **Temporal** | `temporal_change_log` | Edit frequency tracking across sessions |
| **Governance** | `invariants` | SQL-based must-satisfy rules |
| **Governance** | `invariant_violations` | Recorded invariant violations |
| **Governance** | `policies` | Threshold-based advisory rules |
| **Governance** | `policy_violations` | Recorded policy violations |
| **Security** | `taint_sources` | Security-sensitive entry points |
| **Security** | `taint_flows` | Tracked data flows from source to sink |
| **Profiling** | `profile_snapshots` | Runtime profiling data snapshots |
| **Intelligence** | `stewardship_suggestions` | Autonomous scan findings with resolution tracking |
| **Intelligence** | `evidence_records` | Epistemic evidence for every inference |
| **Intelligence** | `evidence_dependencies` | Evidence dependency graph |
| **Intelligence** | `contradictions` | Detected belief contradictions |
| **Intelligence** | `immune_baselines` | Behavioral baselines for anomaly detection |
| **Intelligence** | `immune_alerts` | Anomaly alerts with severity |
| **Intelligence** | `intent_records` | Design intent preservation records |
| **Intelligence** | `toolchain_audit` | Tool invocation verification trail |
| **Meta** | `schema_version` | Current schema version (migration tracking) |

### Index Strategy

```sql
-- File lookup
CREATE INDEX idx_files_language ON files(language);
CREATE INDEX idx_files_sha256   ON files(sha256);
CREATE INDEX idx_files_path     ON files(file_path);

-- Symbol resolution
CREATE INDEX idx_symbols_name   ON symbols(name);
CREATE INDEX idx_symbols_file   ON symbols(file_id);
CREATE INDEX idx_symbols_kind   ON symbols(kind);

-- Call graph traversal
CREATE INDEX idx_call_edges_caller ON call_edges(caller_id);
CREATE INDEX idx_call_edges_callee ON call_edges(callee_name);

-- Similarity queries
CREATE INDEX idx_similarity_simhash ON similarity_groups(simhash);
CREATE INDEX idx_similarity_path    ON similarity_groups(file_path);

-- Domain joins
CREATE INDEX idx_file_domains_file   ON file_domains(file_id);
CREATE INDEX idx_file_domains_domain ON file_domains(domain_id);
```

SQLite **WAL mode** is enabled for concurrent read/write — the PostToolUse hook can write to the database while the agent reads query results.

### Schema Migrations

Automatically applied on `init_db()`:
- **v1 → v2**: Adds `confidence_scores`, temporal tables, governance tables, taint analysis, profile snapshots, new columns on `files` and `symbols`
- **v2 → v3**: Adds `stewardship_suggestions`, `evidence_records`, `evidence_dependencies`, `contradictions`, `immune_baselines`, `immune_alerts`, `intent_records`, `toolchain_audit`

All migrations preserve existing data. Run `/index-rebuild` for a clean start.

---

## Hook Lifecycle

### Hook Registration (`hooks/hooks.json`)

```json
{
  "description": "LessToil hooks",
  "hooks": {
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "python \"${CLAUDE_PLUGIN_ROOT}/hooks/session_start.py\"",
        "timeout": 120
      }]
    }],
    "PostToolUse": [{
      "matcher": "Write|Edit|MultiEdit",
      "hooks": [{
        "type": "command",
        "command": "python \"${CLAUDE_PLUGIN_ROOT}/hooks/post_tool_use.py\"",
        "timeout": 45
      }]
    }],
    "PreToolUse": [{
      "matcher": "Write|Edit|MultiEdit",
      "hooks": [{
        "type": "command",
        "command": "python \"${CLAUDE_PLUGIN_ROOT}/hooks/pre_tool_use.py\"",
        "timeout": 45
      }]
    }]
  }
}
```

During installation, the `python` command in hooks.json is rewritten to use an absolute path to `~/.claude/venv/bin/python` (Unix) or `~/.claude/venv/Scripts/python.exe` (Windows). This isolates the plugin from system Python changes and ensures all dependencies are resolved from a single shared venv. Use `--no-venv` / `-NoVenv` to keep `python` as-is and use the system interpreter.

### SessionStart Hook — Detailed Flow

```
SessionStart hook fires
  │
  ├─ ensure_gitignore() — idempotent, non-critical (never blocks)
  │
  ├─ Check for existing lock file (indexing.lock)
  │   └─ YES (another indexer is running) → return current stats, exit
  │   └─ NO → continue
  │
  ├─ Write lock file with current PID
  │
  ├─ walk_repository() with exclusion patterns
  │   └─ For each file: detect language, compute SHA256, count lines
  │
  ├─ Compare against previous state (SHA256 in files table)
  │   ├─ New files → INSERT into files table
  │   ├─ Changed files (SHA256 mismatch) → UPDATE, re-extract symbols
  │   └─ Deleted files → DELETE FROM files (CASCADE to symbols, call_edges)
  │
  ├─ Symbol extraction loop (time-budgeted: 30 seconds)
  │   └─ For new/changed files with supported languages:
  │       parse_file() → upsert_symbols_batch() → insert_call_edges_batch()
  │       If budget exceeded → defer remaining to incremental reindexing
  │
  ├─ Domain inference
  │   ├─ classify_all_files() via heuristic pattern matching
  │   └─ Import from .claude/repo-cognition.domains.local.md if present
  │
  ├─ Confidence scoring (4-axis: parser, type, runtime, purpose)
  ├─ Temporal risk analysis (git log → churn, bug density, volatility)
  ├─ Architectural drift detection (4 drift types, scores persist)
  ├─ Stewardship scans (6 categories)
  ├─ Self-healing pass (Detect → Propose → Validate)
  ├─ Governance seeding (3 invariants + 6 policies, idempotent INSERT OR IGNORE)
  │
  ├─ Advanced intelligence (all wrapped in try/except — never block):
  │   ├─ Unified graph generation
  │   ├─ Knowledge distillation
  │   ├─ Immune baseline update
  │   ├─ Epistemic evidence collection
  │   ├─ Forecasting (1x/2x/5x/10x)
  │   ├─ Semantic compression
  │   ├─ Economics estimation
  │   ├─ Cognitive load modeling
  │   ├─ Intent preservation check
  │   ├─ Adversarial robustness scan
  │   ├─ Knowledge decay detection
  │   ├─ Operational sovereignty health checks
  │   ├─ Reality alignment verification
  │   ├─ Meta-reasoning calibration
  │   └─ Toolchain audit verification
  │
  ├─ Write file_manifest.json
  ├─ Write last_index.txt timestamp
  ├─ Generate CLAUDE.md query reference
  │
  ├─ Remove lock file
  │
  └─ Output JSON to stdout → injects into agent context
```

**Timeout Strategy**: File walking and hashing complete in < 15 seconds for 10K files. Symbol extraction is capped at 30 seconds — remaining files are deferred. All advanced modules are wrapped in try/except and never block the session. For very large repos (>50K files), the hook returns immediately with partial results and spawns background processing.

### PreToolUse Hook — Detailed Flow

```
PreToolUse hook fires (before Write/Edit/MultiEdit)
  │
  ├─ Extract file_path(s) and proposed content from tool_input
  │
  ├─ Impact analysis (impact.py):
  │   ├─ Find symbols defined in target files
  │   ├─ Count direct callers via call_edges (recursive CTE, depth ≤ 10)
  │   ├─ Identify affected architectural domains via file_domains JOIN
  │   ├─ Identify security-sensitive symbols (security_sensitive = 1)
  │   ├─ Find affected test files (path pattern: *test*, *spec*, *__tests__*)
  │   └─ Report: "Editing N file(s) affects X callers in Y files across Z domains"
  │
  ├─ Duplicate detection (similarity.py):
  │   ├─ Extract function/class names from new content
  │   ├─ Query symbols table for existing definitions with same name
  │   ├─ Query similarity_groups via SimHash for near-identical code
  │   └─ Warn if matches found: "`validateJWT` already exists in 3 locations"
  │
  ├─ Confidence check (confidence.py):
  │   └─ Flag symbols in target files with aggregate confidence < 0.5
  │
  ├─ Governance enforcement (governance.py):
  │   ├─ Evaluate all enabled invariants (SQL → 0 rows = satisfied)
  │   ├─ Evaluate all enabled policies (threshold comparisons)
  │   └─ If violation.severity == "error" → exit code 2 (BLOCK)
  │
  ├─ Formal constraint check (formal_constraints.py):
  │   ├─ Circular import detection
  │   ├─ Dynamic eval detection
  │   ├─ Security boundary enforcement
  │   ├─ Max call depth check
  │   └─ If critical constraint violated → exit code 2 (BLOCK)
  │
  ├─ Simulation (simulation.py):
  │   ├─ Grade proposed change: safe / cautious / risky / dangerous
  │   └─ If grade == "dangerous" → exit code 2 (BLOCK)
  │
  ├─ 6-verifier consensus (consensus.py):
  │   ├─ Collect grades from all 6 verifiers
  │   ├─ Detect disagreements → flag for human review
  │   └─ Output unified verdict
  │
  └─ Output systemMessage with consolidated warnings or block
```

### PostToolUse Hook — Detailed Flow

```
PostToolUse hook fires (after Write/Edit/MultiEdit)
  │
  ├─ Extract file_path(s) from tool_input
  │
  ├─ For each file:
  │   ├─ File deleted? → DELETE FROM files (CASCADE to symbols, call_edges)
  │   ├─ Binary or unsupported language? → skip
  │   └─ Reindex:
  │       ├─ compute_sha256()
  │       ├─ upsert_file() (INSERT OR REPLACE)
  │       ├─ DELETE old symbols for this file
  │       ├─ parse_file() → extract symbols + calls
  │       ├─ upsert_symbols_batch() (batch INSERT)
  │       └─ insert_call_edges_batch() (batch INSERT)
  │
  ├─ Confidence feedback (confidence.py):
  │   ├─ Successful edit → +0.05 to runtime axis
  │   ├─ Test failure detected → -0.10 to purpose axis
  │   └─ Profiling data available → runtime axis set to 0.8
  │
  ├─ Temporal counter increment (temporal.py):
  │   └─ UPDATE temporal_change_log SET edit_count = edit_count + 1
  │
  ├─ Post-execute verification:
  │   └─ TRACE: map actual changes to indexed symbols
  │   └─ SCORE: assign verification score
  │
  └─ Output minimal systemMessage: "Indexed N file(s)" (silent, <1s per file)
```

---

## Symbol Extraction Pipeline

### Two-Tier Architecture

```
                    ┌──────────────┐
                    │  Source File  │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │ tree-sitter   │  ← Primary: AST-level parsing
                    │ grammar       │     41 languages
                    │ installed?    │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │ YES        │            │ NO
              ▼            │            ▼
    ┌─────────────────┐    │    ┌─────────────────┐
    │ tree-sitter AST  │    │    │  regex fallback │
    │ • Nested scopes  │    │    │ • Function defs  │
    │ • Closures       │    │    │ • Class defs     │
    │ • Decorators     │    │    │ • Call patterns  │
    │ • Generics       │    │    │ • Import patterns│
    │ • Async/await    │    │    │ • 15 languages   │
    │ • JSX/templates  │    │    │                  │
    │ • 41 languages   │    │    │                  │
    └────────┬────────┘    │    └────────┬────────┘
             │              │             │
             └──────────────┼─────────────┘
                            │
                    ┌───────▼────────┐
                    │   Annotation    │
                    │  • security     │
                    │  • side effects │
                    │  • exports      │
                    │  • confidence   │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │  Store in       │
                    │  SQLite         │
                    │  (batch INSERT) │
                    └────────────────┘
```

### Tree-sitter Query Examples (SCM Patterns)

**Python:**
```scheme
(function_definition name: (identifier) @function.name) @function.def
(class_definition name: (identifier) @class.name) @class.def
(call function: (identifier) @call.name) @call.expr
(import_statement) @import
```

**TypeScript/JavaScript:**
```scheme
(function_declaration name: (identifier) @function.name) @function.def
(arrow_function) @function.arrow
(class_declaration name: (type_identifier) @class.name) @class.def
(method_definition name: (property_identifier) @method.name) @method.def
(call_expression function: (identifier) @call.name) @call.expr
```

**Go:**
```scheme
(function_declaration name: (identifier) @function.name) @function.def
(method_declaration name: (field_identifier) @function.name) @function.def
(call_expression function: (identifier) @call.name) @call.expr
```

**Rust:**
```scheme
(function_item name: (identifier) @function.name) @function.def
(struct_item name: (type_identifier) @class.name) @class.def
(impl_item) @impl
(call_expression function: (identifier) @call.name) @call.expr
```

### Regex Fallback Extractors

For languages without tree-sitter grammars, compiled regex patterns capture common declaration patterns. The fallback is less precise (flat regex cannot handle nested scopes or closures) but provides useful symbol extraction for all 56 supported languages.

Example — Go regex fallback:
```python
FUNC_PATTERN = re.compile(
    r'func\s+(?:\(\w+\s+\*?\w+\)\s+)?(\w+)\s*\(([^)]*)\)',
    re.MULTILINE
)
```

---

## Call Graph Construction

### Resolution Strategy

For each function body, call expressions are resolved against known symbols:

1. **Same-file calls**: Direct name match against symbols in the same file → confidence 0.95
2. **Cross-file calls**: Match imported names to exports of imported modules → confidence 0.85
3. **Unresolved calls**: Stored with `callee_name` set and `callee_file=NULL` → confidence 0.7
4. **Dynamic calls**: `getattr(obj, name)`, `eval()`, reflection → `is_dynamic=1`, confidence 0.3

### Key Queries

**Find caller for a specific line:**
```sql
SELECT id FROM symbols
WHERE file_id = ? AND kind IN ('function', 'method')
  AND start_line <= ? AND end_line >= ?
LIMIT 1
```

**Transitive dependents (recursive CTE, depth-limited):**
```sql
WITH RECURSIVE dependents AS (
    SELECT s.id, s.name, f.file_path, 1 AS depth
    FROM call_edges ce
    JOIN symbols s ON ce.caller_id = s.id
    JOIN files f ON s.file_id = f.id
    WHERE ce.callee_name = '<function_name>'
    UNION ALL
    SELECT s.id, s.name, f.file_path, d.depth + 1
    FROM call_edges ce
    JOIN symbols s ON ce.caller_id = s.id
    JOIN files f ON s.file_id = f.id
    JOIN dependents d ON ce.callee_name = d.name
    WHERE d.depth < 10
)
SELECT DISTINCT file_path, name, depth FROM dependents
ORDER BY depth, file_path LIMIT 200;
```

**Orphaned functions (defined but never called):**
```sql
SELECT s.name, s.kind, f.file_path, s.start_line
FROM symbols s
JOIN files f ON s.file_id = f.id
WHERE s.kind IN ('function', 'method')
  AND s.name NOT IN (
    SELECT DISTINCT ce.callee_name FROM call_edges
    WHERE ce.callee_name IS NOT NULL
  )
ORDER BY f.file_path, s.start_line;
```

**Hotspots (most-called functions):**
```sql
SELECT ce.callee_name, COUNT(*) AS call_count,
       COUNT(DISTINCT ce.caller_id) AS unique_callers
FROM call_edges ce
WHERE ce.callee_name IS NOT NULL
GROUP BY ce.callee_name
ORDER BY call_count DESC
LIMIT 20;
```

---

## Architectural Domain Inference

### Two-Phase Approach

**Phase 1 — Heuristic Classification (fast, no LLM)**

The `domains.py` module uses regex pattern matching against file paths and symbol names. Each of the 14 built-in domains has path patterns and symbol patterns with weighted scoring:

```python
DOMAIN_DEFINITIONS = {
    'authentication': {
        'path_patterns': [r'auth', r'login', r'token', r'oauth', r'session', r'jwt'],
        'symbol_patterns': [r'auth', r'jwt', r'authorize', r'login', r'logout', r'verify'],
        'security_boundary': True,
    },
    'payments': {
        'path_patterns': [r'billing', r'payment', r'checkout', r'invoice', r'stripe'],
        'symbol_patterns': [r'pay', r'charge', r'invoice', r'checkout', r'billing'],
        'security_boundary': True,
    },
    # ... 12 more domains
}
```

**Confidence scoring per match:**
- Exact directory name match → 0.90
- Path pattern match → 0.70 × match_ratio
- Symbol name match → 0.50 × match_ratio
- Combined → max of all individual scores

Files can belong to up to 3 domains (top confidence scores above 0.2 threshold).

**Phase 2 — Agent-based Refinement (LLM, session-persistent)**

The `architecture-inferrer` agent reads heuristically classified files, identifies misclassifications and gaps, validates domain assignments, and writes refined data to `.claude/repo-cognition.domains.local.md`. Results are imported into SQLite on next SessionStart.

### Domain Definitions

| Domain | Security Boundary | Path Examples |
|--------|:---:|---------|
| authentication | Yes | `src/auth/`, `middleware/auth.py`, `oauth/` |
| payments | Yes | `src/billing/`, `stripe/`, `checkout/` |
| crypto | Yes | `src/crypto/`, `pkg/encryption/`, `tls/` |
| api | Yes | `src/controllers/`, `api/routes.go`, `handlers/` |
| config | Yes | `src/config/`, `.env`, `settings.py`, `config/` |
| ui | No | `src/components/`, `templates/`, `pages/` |
| caching | No | `src/cache/`, `pkg/cache/`, `redis/` |
| data-access | No | `src/models/`, `migrations/`, `repos/`, `dao/` |
| logging | No | `src/logger/`, `pkg/telemetry/`, `trace/` |
| messaging | No | `src/queue/`, `pkg/events/`, `kafka/`, `rabbitmq/` |
| testing | No | `__tests__/`, `spec/`, `test/`, `fixtures/` |
| build | No | `Dockerfile`, `.github/workflows/`, `Makefile` |
| networking | No | `src/network/`, `pkg/proxy/`, `gateway/` |
| system | No | OS-level, process management, daemons |

### Custom Domains

Define additional domains in `.claude/repo-cognition.settings.local.md`:

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

---

## Duplicate Detection

### SimHash Algorithm

1. **Normalize**: Strip comments, normalize whitespace, replace identifiers with placeholders (`ID0`, `ID1`, …), preserve language keywords and structure
2. **Tokenize**: Extract 3-grams from the normalized token stream
3. **Hash**: Compute a 64-bit SimHash fingerprint
4. **Store**: Insert into `similarity_groups` table with file path, symbol name, line range, normalized code, and language
5. **Query**: Find pairs with Hamming distance below threshold (default: ≤ 6 for "similar", ≤ 3 for "near-identical")

### Normalization Example

```
Input:
def calculate_total(items: list[Item]) -> float:
    """Sum the prices of all items."""
    return sum(item.price for item in items)

Normalized:
def ID0(ID1 ID2 ID3) ID4 return ID5(ID6 ID7 ID8 ID9 ID1 ID10 ID11)
```

This normalization makes the SimHash robust to variable renaming, comment changes, docstring variations, and whitespace formatting — while preserving the structural fingerprint of the code's control flow and operation sequence.

### Duplicate Categories Detected

| Type | Detection Method | Example |
|------|-----------------|---------|
| **Exact name collision** | `symbols.name` equality | Two `validateJWT` functions |
| **Near-identical logic** | SimHash Hamming distance ≤ 3 | Same algorithm, different variable names |
| **Structural similarity** | SimHash Hamming distance ≤ 6 | Similar control flow, different types |
| **Shadow abstraction** | SimHash + cross-domain check | Same pattern implemented in different layers |

---

## Impact Analysis

### What Gets Analyzed

For each file about to be edited, the PreToolUse hook queries:

1. **Direct callers**: Functions that call symbols defined in the target file
2. **Affected files**: Distinct files containing those callers
3. **Affected domains**: Architectural domains of affected files
4. **Security-sensitive symbols**: Callers that touch auth, crypto, or secrets
5. **Affected tests**: Test files whose symbols call into the target
6. **Transitive dependents**: Full dependency chain via recursive CTE (depth ≤ 10)

### Impact Report Format

```
Impact: Editing 3 file(s) affects 89 callers in 34 files across domains: auth, api, middleware, caching.

Security-sensitive symbols affected: refreshToken, validateSession, hashPassword

Tests potentially affected:
  - src/auth/__tests__/session.test.ts
  - src/auth/__tests__/jwt.test.ts
  - src/middleware/__tests__/auth-middleware.test.ts
  - src/api/__tests__/user-routes.test.ts

Transitive dependents (depth 1-3):
  - UserController.getProfile (src/api/controllers/user.ts) [depth 1]
  - AdminMiddleware.requireAuth (src/middleware/admin.ts) [depth 1]
  - WebSocketAuth.upgrade (src/ws/auth.ts) [depth 2]

Stewardship note: src/auth/session.ts already flagged as over-complex (1,247 lines).
```

---

## Verification Pipeline

### 10-Phase Pipeline

```
PLAN → SIMULATE → VERIFY → CONSTRAIN → EXECUTE → TEST → TRACE → SCORE → REPAIR → REVERIFY
```

| Phase | Budget | Description | Owner |
|-------|--------|-------------|-------|
| **PLAN** | 5s | Analyze change intent, identify affected symbols and domains | Hook |
| **SIMULATE** | 5s | Multi-file impact simulation, grade computation | Hook |
| **VERIFY** | 5s | Run governance invariants and policies against proposed state | Hook |
| **CONSTRAIN** | 5s | Check 9 formal structural constraints | Hook |
| **EXECUTE** | — | The actual edit, performed by Claude Code | Engine |
| **TEST** | — | Post-edit test execution (if applicable) | Engine |
| **TRACE** | 3s | Map actual changes to indexed symbols, detect drift | Hook |
| **SCORE** | 2s | Assign post-execute verification score | Hook |
| **REPAIR** | 5s | Generate self-healing proposals if verification failed | Hook |
| **REVERIFY** | 3s | Confirm repairs resolved the issue | Hook |

### 6-Verifier Consensus Engine

| Verifier | Type | Weight | Responsibility |
|----------|------|--------|----------------|
| **Invariants** | SQL-based | 0.25 | Architectural rules (0 rows = satisfied) |
| **Policies** | Threshold-based | 0.20 | Complexity, depth, size limits |
| **Simulation** | Multi-file impact | 0.20 | Change scope and blast radius |
| **Immune** | Anomaly detection | 0.15 | Behavioral deviation from baseline |
| **Formal** | 9 constraints | 0.10 | Circular imports, eval, boundaries |
| **Confidence** | Symbol quality | 0.10 | Parser, type, runtime, purpose scores |

**Disagreement handling**: When verifiers disagree, the contradiction is recorded in the `contradictions` table and flagged in the system message for human review. The most conservative (safety-prioritizing) verifier's grade is used.

### Change Grading

| Grade | Criteria | Hook Behavior |
|-------|----------|---------------|
| **safe** | Single file, low callers, no security symbols | Silent pass |
| **cautious** | 2-5 files, moderate callers, non-security domains | Advisory warning |
| **risky** | >5 files, cross-domain, security symbols present | Prominent warning with impact report |
| **dangerous** | Multi-domain, security boundary crossing, high caller count | **Blocked** (exit code 2) |

---

## Governance System

### Invariants (SQL-based, 0 rows = satisfied)

Built-in invariants (idempotent, seeded on every SessionStart):

1. **Auth domain isolation**: Authentication domain must not import from UI domain
2. **No direct DB from UI**: UI components must not directly access database symbols
3. **No circular domains**: Architectural domains must not have circular dependencies

### Policies (Threshold-based)

Built-in policies:

| Policy | Default Threshold | Severity |
|--------|-------------------|----------|
| Max function complexity | 80 lines | warning |
| Max dependency depth | 5 levels | warning |
| Max file size | 1000 lines | warning |
| Require tests for security paths | Security symbols must have tests | error |
| Max function parameters | 6 parameters | warning |
| Forbid circular dependencies | Any circular import detected | error |

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

### Blocking Behavior

- Invariant violations with `severity: error` → **exit code 2** (block)
- Policy violations with `severity: error` → **exit code 2** (block)
- `severity: warning` → advisory message only, exit code 0 (allow)
- Dangerous simulation grade → **exit code 2** (block)
- Impact analysis, duplicate detection, confidence warnings → advisory only, exit code 0 (allow)

---

## Confidence System

### 4-Axis Scoring

| Axis | Source | Range | Meaning |
|------|--------|-------|---------|
| **parser** | tree-sitter (0.9) vs regex (0.5) vs extension-only (0.2) | 0.0–1.0 | Extraction method reliability |
| **type** | Type annotations, type hints, typed parameters | 0.0–1.0 | Type safety confidence |
| **runtime** | Profiling data available, test coverage observed | 0.0–1.0 | Runtime behavior verification |
| **purpose** | Docstring presence, signature clarity, naming quality | 0.0–1.0 | Intent understandability |

**Aggregation**: Weakest-link — the aggregate confidence is the **minimum** of all four axes. A symbol with perfect parser extraction (0.9) but no type annotations (0.2) receives an aggregate of 0.2. This deliberately pessimistic strategy ensures that genuinely low-confidence symbols are not hidden by high scores on other axes.

### Feedback Loop

PostToolUse adjusts confidence scores based on observed outcomes:
- Successful edit of symbol → +0.05 to runtime axis
- Test failure involving symbol → -0.10 to purpose axis
- Profiling data captured → runtime axis set to max(0.8, current)
- Symbol unused for 30+ days → -0.02 to purpose axis (knowledge decay)

---

## Temporal Risk Analysis

### Risk Model

Git history is analyzed (`git log`) to compute per-file risk scores:

| Metric | Source | Weight | Rationale |
|--------|--------|--------|-----------|
| **Churn rate** | Commit frequency (last 90 days) | 0.35 | Frequently changed files are more likely to break |
| **Bug-fix density** | Commits mentioning fix/bug/patch/vuln | 0.35 | Files with many bug fixes indicate fragility |
| **Security patches** | Commits mentioning security/vuln/CVE | 0.15 | Security-sensitive files need extra scrutiny |
| **Ownership volatility** | Unique authors / total commits | 0.15 | Files touched by many authors lack stable expertise |

Risk score is a weighted composite from 0.0 (stable, unchanged for 90+ days) to 1.0 (critical, frequent security patches).

| Risk Range | Classification | Action |
|------------|---------------|--------|
| > 0.9 | Critical | Security-sensitive, frequent patches — flag in every session |
| > 0.7 | High-risk | High churn + bug density — review before editing |
| > 0.4 | Moderate | Elevated churn or bug density — monitor |
| < 0.4 | Nominal | Stable files — normal operation |

---

## Architectural Drift Detection

### Four Drift Axes

| Axis | Detection Method | Example |
|------|-----------------|---------|
| **Naming divergence** | Analyze convention dominance vs. outliers | `snake_case` functions in a `camelCase` TypeScript project |
| **Style outliers** | Detect pattern mismatch per language | Class-based component in functional React codebase |
| **Anti-pattern emergence** | Structural heuristics | God object (>20 methods, >1000 lines), shotgun surgery |
| **Framework creep** | Detect competing libraries/frameworks | 3 different HTTP clients: axios, fetch, got |

Drift scores persist in the `files` table across sessions. They are computed as delta from the project's dominant convention, so they meaningfully track whether drift is improving or worsening over time.

---

## Stewardship and Self-Healing

### Stewardship — 6 Scan Categories

| Category | Detection | Example |
|----------|-----------|---------|
| **Dead subsystems** | Orphaned files/folders with no incoming calls or imports | `legacy/billing-v1/` — 23 files, 0 callers in 6 months |
| **Over-complex files** | Line count, method count, cyclomatic complexity | `payment/handler.ts` — 1,247 lines, 47 methods |
| **High-churn hotspots** | Temporal metrics + stewardship threshold | `auth/session.ts` — 43 commits in 90 days |
| **Dangerous coupling** | Cross-domain call density, circular dependencies | `shared-ui` ↔ `shared-utils` bidirectional imports |
| **Unowned critical paths** | No consistent author, security boundary, high churn | `crypto/signing.ts` — 6 authors, 0 with >30% commits |
| **Stale patterns** | Deprecated patterns still in use, old framework versions | Class components in codebase that migrated to hooks |

Suggestions are stored in `stewardship_suggestions` with `resolved_at` tracking.

### Self-Healing Loop

```
DETECT anomaly (stewardship scan, immune alert, drift spike, constraint failure)
  │
  ▼
PROPOSE fix (generate candidate repair: extract method, split file, remove dead code)
  │
  ▼
VALIDATE proposal (simulate against governance, check impact, verify constraints)
  │
  ▼
REPAIR (apply validated fix, reindex, update confidence scores)
```

The self-healing loop runs at session start and optionally after edits that trigger anomaly thresholds.

---

## Advanced Intelligence Modules

### Intelligence Module Summary

| Module | Function | Trigger |
|--------|----------|---------|
| `forecasting.py` | Projects architecture at 1x/2x/5x/10x scale with risk assessment | SessionStart |
| `semantic_compression.py` | Detects equivalent paradigms beyond literal duplication | SessionStart |
| `economics.py` | Estimates build/CI/cloud/dev-hours costs with optimization suggestions | SessionStart |
| `cognitive_load.py` | Models understandability, debugging difficulty, conceptual compression | SessionStart |
| `intent_preservation.py` | Tracks WHY abstractions exist, detects intent drift across refactors | SessionStart + PreToolUse |
| `intent_planner.py` | Translates Intent → ConstraintSet → ExecutionPlan | PreToolUse |
| `adversarial.py` | Detects deceptive patterns, semantic mismatch, hidden execution paths | SessionStart |
| `knowledge_decay.py` | Flags stale beliefs when source data changes | SessionStart + PostToolUse |
| `operational_sovereignty.py` | Health checks, corruption repair, graceful degradation management | SessionStart |
| `reality_alignment.py` | Business vs. technical correctness, Pareto optimization | SessionStart |
| `meta_reasoning.py` | Self-modeling failure tracking, blind spot detection, confidence calibration | SessionStart |
| `toolchain_auditor.py` | Every tool invocation recorded with verification trail, trust scoring | PostToolUse |
| `refactor_scoring.py` | Weighted refactor scoring (duplication, maintenance, dependency, migration risk) | SessionStart |
| `minimalism.py` | Abstraction density, dependency entropy, state surface area, simplicity scoring | SessionStart |
| `mutation_sandbox.py` | Sandboxed code mutation testing and verification | PreToolUse |
| `unified_graph.py` | AST + type + runtime + profiling + temporal merged into weighted multi-edge graph | SessionStart |
| `knowledge_distillery.py` | Domain summaries, approved primitives, canonical patterns, forbidden abstractions | SessionStart |

All advanced modules are wrapped in try/except — failures are logged but never block the session or hook execution.

---

## Incremental Reindexing

### Process

After every Write/Edit/MultiEdit tool call:

1. Extract `file_path` from `tool_input`
2. Check if file still exists on disk (handle deletion)
3. Compute new SHA256 hash
4. Compare with stored hash in `files` table
5. If changed: UPDATE file, DELETE old symbols (CASCADE), re-extract, INSERT new symbols and call edges
6. If deleted: DELETE FROM files (CASCADE to symbols, call_edges)
7. If unchanged: skip

**Only the changed file(s) are reindexed** — the rest of the index is untouched. Batch INSERT operations keep the overhead under 1 second per file.

### Change Detection Chain

```
Edit occurs → PostToolUse fires → extract file_path → file still exists? → SHA256 changed?
  → YES: reindex symbols + call edges → update confidence → increment temporal counter → done
  → NO (deleted): CASCADE delete → done
  → NO (unchanged SHA256): skip → done
```

---

## Cross-Session Persistence

### What Persists (survives session end)

- SQLite database (all 26 tables, all structured data)
- Architectural domain assignments and security boundary designations
- Stewardship suggestions (tracked to resolution via `resolved_at`)
- Architectural drift scores (accumulate across sessions)
- Learned patterns and knowledge distillation (`.local.md` files)
- Custom governance rules (`.local.md` files)
- Immune system baselines and alert history
- Evidence records and contradiction history
- Intent records
- Toolchain audit trail

### What Is Recomputed (fresh each session)

- SHA256 hashes (recomputed against current filesystem)
- File manifests (regenerated from walk)
- Call graphs (rebuilt from current symbol extraction)
- Confidence scores (recomputed with fresh data and profiling signals)
- Temporal risk metrics (regenerated from current git history)
- Advanced intelligence analysis (forecasting, economics, drift — always current)

### .local.md Persistence Pattern

Following Claude Code plugin conventions, architectural knowledge persists in markdown files with YAML frontmatter. LLM agents can both read and write this format, making it the bridge between deterministic Python extraction and LLM-driven analysis:

```markdown
---
domains:
  - name: authentication
    description: User authentication and session management
    security_boundary: true
    entry_points:
      - src/auth/login.ts:42
    key_directories:
      - src/auth/
      - src/middleware/auth/
last_updated: "2026-05-26T12:00:00Z"
---
```

On SessionStart, YAML frontmatter is parsed and imported into SQLite.

---

## Performance Characteristics

### Benchmark Table

| Operation | <1K files | 1K-10K files | 10K-50K files | 50K+ files |
|-----------|-----------|--------------|---------------|------------|
| File walk + SHA256 | < 2s | < 15s | < 30s | < 60s |
| Symbol extraction (tree-sitter) | < 3s | 10-30s | budget-capped | deferred |
| Symbol extraction (regex fallback) | < 1s | < 10s | < 30s | < 60s |
| Full index (all modules) | < 5s | < 30s | partial | deferred |
| Incremental reindex (1 file) | < 0.5s | < 0.5s | < 0.5s | < 0.5s |
| Impact analysis (1 file) | < 0.1s | < 0.2s | < 0.5s | < 1s |
| Duplicate check | < 0.1s | < 0.1s | < 0.1s | < 0.2s |
| CLAUDE.md generation | < 0.5s | < 1s | < 2s | < 3s |
| Dashboard generation | < 1s | < 1s | < 2s | < 3s |

### Optimization Techniques

| Technique | Purpose |
|-----------|---------|
| **SQLite WAL mode** | Concurrent read/write — PostToolUse writes while agent reads |
| **Prepared statements** | All SQL uses parameterized queries — no recompilation |
| **Exclusion filtering** | In-place `dirnames` modification in `os.walk` — never enters excluded directories |
| **SHA256 comparison** | Unchanged files skip symbol re-extraction entirely |
| **Batch operations** | Symbols and call edges inserted in `executemany()` batches |
| **Time budgeting** | Symbol extraction capped at 30s; advanced modules capped individually |
| **Sparse checkout** | Installer fetches only plugin directory, not full monorepo |
| **Graceful degradation** | Every module wrapped in try/except — failure logs and continues |
| **Deferred processing** | Large repos get partial indexing on SessionStart with catch-up on incremental reindex |

### Disk Footprint

| Codebase Size | Index Size (approx.) | Ratio |
|---------------|---------------------|-------|
| 1 MB | 100-200 KB | 10-20% |
| 10 MB | 1-2 MB | 10-20% |
| 100 MB | 10-20 MB | 10-20% |
| 1 GB | 100-200 MB | 10-20% |

WAL file adds temporary overhead of ~4 MB during writes. Overall disk impact is proportional to source code volume, not file count.

---

## Security Model

### Data Locality

**Everything runs locally.** All data resides on the user's machine:
- `.claude/index/repo-cognition/index.db` — SQLite database
- `.claude/index/repo-cognition/*.json` — JSON manifests and graphs
- `.claude/repo-cognition.*.local.md` — YAML-based persistence files

No network access. No telemetry. No external service calls.

### Hook Permissions

| Hook | Filesystem | SQLite | External |
|------|-----------|--------|----------|
| SessionStart | Read + Write (.claude/index/) | Read/Write | None |
| PreToolUse | Read-only | Read-only | None |
| PostToolUse | Read + Write (.claude/index/) | Read/Write | None |

### Blocking Limitations

- Advisory warnings (impact analysis, duplicate detection, confidence) exit 0 — they inform but never block
- Only governance violations with `severity: error` and dangerous simulation grades exit 2 — actively blocking
- Cannot modify Claude Code engine permissions, settings, or hook configuration
- Cannot access files outside the project directory
- Cannot spawn subprocesses beyond the Python interpreter

### What Should Be Gitignored

```
.claude/index/
```

The index is regenerated from source code on session start. Committing it to version control is unnecessary and creates merge conflicts on the binary SQLite file.

**This is managed automatically** — both installers add `.claude/index/` to `.gitignore` at setup time, and the SessionStart hook enforces it on every session via `ensure_gitignore()`. No manual `.gitignore` editing is required.

---

## Design Decisions (ADR)

### ADR-001: Python for Hooks
**Decision**: Use Python for all hook implementations.
**Rationale**: tree-sitter AST parsing, SQLite database operations, and graph algorithms (call graph traversal, recursive CTEs) are impractical in bash. Python's ecosystem provides mature bindings for all three core dependencies.
**Alternatives**: Shell scripts (no AST parsing, no SQLite), Node.js/Bun (tree-sitter Python bindings more mature), Go (compilation step adds complexity).

### ADR-002: SQLite as Canonical Store
**Decision**: Single SQLite database (WAL mode) for all structured index data.
**Rationale**: JOINs, recursive CTEs, indexes, and concurrent read/write are essential for call graph traversal and impact analysis. A flat file approach would require loading the entire graph into memory for every query. WAL mode enables concurrent reads during writes.
**Alternatives**: JSON files (no query capability), DuckDB (heavier dependency), PostgreSQL (requires server).

### ADR-003: PreToolUse Advisory vs. Blocking
**Decision**: PreToolUse blocks only on governance errors and dangerous simulation grades. Impact analysis, duplicate detection, and confidence warnings are advisory (exit 0).
**Rationale**: Unlike hard security violations, structural concerns like duplication are code quality matters — the agent should be informed but not prevented from proceeding. Blocking on all warnings would be too intrusive for legitimate prototyping and exploration.
**Alternatives**: Block on all warnings (too intrusive), never block (governance becomes toothless).

### ADR-004: Hybrid Tree-sitter + Regex
**Decision**: tree-sitter as primary extraction (41 grammars), regex as automatic fallback (15 additional patterns).
**Rationale**: Maximizes accuracy when grammars are installed (nested scopes, closures, generics, async/await) while ensuring the plugin works without them. The installer automatically installs 36 grammar packages; the fallback handles edge cases.
**Alternatives**: tree-sitter only (fragile, dependency-heavy), regex only (misses complex syntax).

### ADR-005: .local.md for Cross-Session Persistence
**Decision**: Markdown files with YAML frontmatter for persistent architectural knowledge.
**Rationale**: Follows established Claude Code plugin patterns. LLM agents can both read and write this format natively. Human-readable and version-control friendly. Serves as the bridge between deterministic extraction and LLM-driven refinement.
**Alternatives**: Additional SQLite tables (harder for agents to write), JSON (less human-readable, harder for agents to author correctly).

### ADR-006: Sparse Checkout for Installation
**Decision**: Both installers use `git sparse-checkout` with `--filter=blob:none` to fetch only `LessToil/plugin/` from the monorepo.
**Rationale**: The monorepo is large; sparse checkout makes installation fast (< 10 seconds). The `--filter=blob:none` flag avoids downloading any file contents until checkout.
**Alternatives**: Download individual raw files (fragile, 48+ files to track), git submodule (adds complexity), separate repo (plugin co-developed with monorepo).

### ADR-007: PowerShell Installer
**Decision**: Native PowerShell installer alongside Bash installer.
**Rationale**: Windows developers deserve a first-class installation experience. The PS1 script handles Windows path conventions, Python detection (`python` vs `python3`), and uses `Invoke-WebRequest` for the one-liner pattern.
**Alternatives**: WSL-only (excludes native Windows users), Git Bash only (not universally installed on Windows).

### ADR-008: Weakest-Link Confidence Aggregation
**Decision**: Aggregate confidence is the minimum of all four axes.
**Rationale**: A symbol with perfect parser extraction (0.9) but zero type information (0.2) is genuinely low-confidence for most query types — the weakest link determines practical reliability. This pessimistic strategy ensures low-confidence symbols are surfaced rather than hidden.
**Tradeoff**: Can be overly conservative for dynamic languages where type annotations are rare (Python, JavaScript). Acceptable because the feedback loop gradually improves scores as runtime profiling data is collected.

### ADR-009: Background Indexing with Graceful Degradation
**Decision**: Hybrid approach — fast file walk in foreground (120s budget), symbol extraction time-budgeted (30s), remainder deferred. All advanced modules wrapped in try/except.
**Rationale**: Users should never wait for indexing. The dashboard and basic structural data are available immediately. Symbol extraction catches up incrementally. Advanced modules that fail silently don't block anything.
**Alternatives**: Full blocking index (bad UX for large repos), fully async (no symbols on first session), persistent daemon (complexity, cross-platform issues).
