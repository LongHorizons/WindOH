# LessToil

A persistent structural cognition layer for Claude Code that indexes your repository into a continuously maintained knowledge graph (SQLite + JSON), enforces architectural governance through a 10-phase verification pipeline, and gives AI coding agents genuine codebase awareness across 56 languages.

## What It Does

### Structural Intelligence
- **Indexes** every file (SHA256, language, size, line count) across 56 languages (41 tree-sitter + 15 regex)
- **Extracts** symbols (functions, classes, methods, variables) via tree-sitter AST with regex fallback
- **Builds** a weighted, directed call graph with static and dynamic edge tracking
- **Infers** 14 architectural domains (auth, payments, caching, API, UI, etc.) with security boundary marking
- **Detects** duplicated code blocks via SimHash 64-bit fingerprinting
- **Analyzes** git history for temporal risk scoring (churn, bug density, ownership volatility)

### Edit-Time Protection
- **10-Phase Verification Pipeline**: PLAN → SIMULATE → VERIFY → CONSTRAIN → EXECUTE → TEST → TRACE → SCORE → REPAIR → REVERIFY
- **Impact analysis**: recursive CTE call graph traversal shows exactly what will break before you edit
- **Duplicate detection**: warns before you create the fourth copy of the same function
- **Governance enforcement**: SQL-based invariants and threshold-based policies — blocks dangerous edits (exit code 2)
- **6-verifier consensus engine**: invariants, policies, simulation, immune, formal, and confidence verifiers grade every change
- **Change grading**: safe / cautious / risky / dangerous — dangerous changes blocked before execution

### Continuous Maintenance
- **Incremental reindexing**: only changed files reindexed after edits (< 1 second per file)
- **Confidence system**: 4-axis scoring (parser, type, runtime, purpose) with weakest-link aggregation and feedback loop
- **Autonomous stewardship**: 6 scan categories detect dead subsystems, over-complex files, hotspots, coupling, unowned paths, stale patterns
- **Architectural drift detection**: naming divergence, style outliers, anti-patterns, framework creep — tracked across sessions
- **Self-healing loop**: Detect → Propose → Validate → Repair across 4 anomaly sources
- **Repository immune system**: behavioral baseline → anomaly detection → quarantine

### Advanced Intelligence (18 modules)
Epistemic evidence tracking, long-horizon forecasting (1x-10x scale), semantic compression, economic cost modeling, cognitive load analysis, design intent preservation, adversarial robustness, knowledge decay detection, operational sovereignty, reality alignment, meta-reasoning, toolchain auditing, refactor scoring, and more.

## Architecture

```
SessionStart Hook (120s)
  ├─ Walk repo → SHA256 → SQLite
  ├─ tree-sitter AST → symbols + call graph
  ├─ Domain inference + confidence scoring
  ├─ Temporal risk + drift detection
  ├─ Stewardship + self-healing
  └─ Inject structural summary into agent context

PreToolUse Hook (45s, Write/Edit/MultiEdit)
  ├─ 10-phase verification pipeline
  ├─ Impact analysis + duplicate detection
  ├─ Governance invariants + policies check
  └─ Block dangerous edits (exit 2) or warn

PostToolUse Hook (45s, Write/Edit/MultiEdit)
  ├─ Incremental reindex of changed files
  ├─ Confidence feedback loop
  └─ Temporal change counter
```

## Database — 26 Tables Across 8 Categories

| Category | Tables |
|----------|--------|
| Core Index | `files`, `symbols`, `call_edges`, `domains`, `file_domains` |
| Similarity | `similarity_groups` |
| Confidence | `confidence_scores` |
| Temporal | `temporal_metadata`, `temporal_metrics`, `temporal_change_log` |
| Governance | `invariants`, `invariant_violations`, `policies`, `policy_violations` |
| Security | `taint_sources`, `taint_flows` |
| Profiling | `profile_snapshots` |
| Intelligence | `stewardship_suggestions`, `evidence_records`, `evidence_dependencies`, `contradictions`, `immune_baselines`, `immune_alerts`, `intent_records`, `toolchain_audit` |
| Meta | `schema_version` |

## 40 Core Modules

**Foundation**: manifest, indexer, symbols, call_graph, domains, similarity, impact, dot_gen, formatting

**Confidence & Temporal**: confidence (4-axis + feedback loop), temporal (git churn/risk/volatility)

**Governance & Security**: governance (invariants + policies + simulation), security_provenance (taint analysis), intent_planner

**Analysis & Detection**: drift_detection (4 axes), refactor_scoring, minimalism, simulation, mutation_sandbox

**Runtime & Visualization**: runtime_profiling (cProfile/pprof/node-prof), unified_graph (AST + type + runtime + temporal merged), knowledge_distillery

**Stewardship & Healing**: stewardship (6 scan categories), self_healing (Detect → Propose → Validate → Repair)

**Verification & Consensus**: verification (10-phase orchestrator), consensus (6-verifier engine), formal_constraints (9 structural rules)

**Epistemic & Immune**: epistemic (evidence provenance + contradiction detection), immune_system (baseline + anomaly + quarantine)

**Advanced Intelligence**: forecasting (1x-10x), semantic_compression, economics, cognitive_load, intent_preservation, adversarial, knowledge_decay, operational_sovereignty, reality_alignment, meta_reasoning, toolchain_auditor

## Commands

- `/index-status` — Full professional dashboard: index health, language distribution, domains, risk, drift, stewardship
- `/index-rebuild` — Force complete reindex from scratch
- `/index-graph <name>` — Call graph centered on a function
- `/index-graph --domain-graph` — Cross-domain dependency visualization
- `/index-graph --hotspots` — Most-called functions
- `/index-graph --orphans` — Functions never called (potential dead code)

## Skill

The `LessToil Query` skill auto-activates on structural questions: "Where is X called from?", "What depends on Y?", "What's the impact of changing Z?", "Find similar code to this", "What domain does this belong to?", "Is this code used anywhere?", "What are the riskiest files?"

All answers are prefixed with `[index]` (queried the database) or `[grep]` (fell back to text search).

## Supported Languages

**Full AST + Call Graph**: Python, TypeScript, JavaScript, Go, Rust

**AST + Basic Call Graph**: Java, C, C++, C#, Ruby, PHP, Swift, Kotlin, Scala, Lua, Dart, Zig, Solidity, Elixir, Haskell, OCaml, Svelte

**AST Extraction**: SQL, Bash, HTML, CSS, JSON, YAML, TOML, Markdown, Dockerfile, HCL, GraphQL, Make, CMake, PowerShell, Nix

**File Indexing Only**: 20+ additional languages via extension detection

## Install

### Windows (PowerShell)
```powershell
(iwr -UseBasicParsing https://raw.githubusercontent.com/LongHorizons/WindOH/master/LessToil/plugin/install.ps1).Content | iex
```

### macOS / Linux (Bash)
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LongHorizons/WindOH/master/LessToil/plugin/install.sh)
```

### Offline (from release zip)
```bash
bash install.sh --from-zip repo-cognition.zip
```

### Options
| Bash Flag | PowerShell Flag | Purpose |
|-----------|----------------|---------|
| `--project-dir /path` | `-ProjectDir PATH` | Set up a specific project |
| `--plugin-only` | `-PluginOnly` | Install plugin only, skip project setup |
| `--reindex` | `-Reindex` | Force immediate index build |
| `--from-zip FILE` | `-FromZip FILE` | Install from local zip (no Git needed) |
| `--accept` | `-Accept` | Non-interactive: auto-confirm all prompts |
| `--no-venv` | `-NoVenv` | Skip creating ~/.claude/venv/ |

## Performance

| Repo Size | Full Index | Incremental | Disk Usage |
|-----------|-----------|-------------|------------|
| <1K files | < 5s | < 0.5s/file | ~10-20% of source |
| 1K-10K files | < 30s | < 0.5s/file | ~10-20% of source |
| 10K+ files | deferred | < 0.5s/file | ~10-20% of source |

All advanced modules wrapped in try/except — failures never block the session.

## Configuration

Optional settings in `.claude/repo-cognition.settings.local.md`:
```yaml
---
exclude_dirs: [".terraform", ".cache", "vendor"]
max_extraction_time_sec: 30
similarity_threshold: 0.85
---
```

Custom governance rules in `.claude/repo-cognition.policies.local.md`. Custom domains in settings under `domains.custom_domains`.

## Data Privacy

Everything runs locally. SQLite database and all index files stored in `.claude/index/repo-cognition/`. No network access. No telemetry. `.claude/index/` is automatically added to `.gitignore` by the installer and enforced by the SessionStart hook — no manual configuration needed.

## Requirements

- Claude Code (CLI or IDE extension)
- Python 3.8+
- git (for installation)

## Documentation

- [Presentation/README.md](../README.md) — Executive summary, business case, features, quantified impact
- [Presentation/GETTING_STARTED.md](../GETTING_STARTED.md) — Complete installation and first-use guide
- [Presentation/ARCHITECTURE.md](../ARCHITECTURE.md) — Deep technical reference (data model, hooks, modules, ADRs)
- [Presentation/USE_CASES.md](../USE_CASES.md) — 12 real-world scenarios with SQL examples
- [Presentation/FAQ.md](../FAQ.md) — Frequently asked questions
- [Presentation/CONTRIBUTING.md](../CONTRIBUTING.md) — How to contribute

## License

MIT
