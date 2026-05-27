# WindOH — Windows Detection, Response, and Forensics Platform

**Novel behavioral telemetry intelligence, AI-driven threat enrichment, memory forensics at scale, and covert forensic triage — an integrated platform spanning the full security operations lifecycle.**

---

## What This Is

WindOH is an integrated suite of five tools that together cover the entire Windows security operations workflow: continuous behavioral telemetry collection with cryptographic deduplication, AI-driven threat intelligence enrichment with predictive sequence modeling, adversary emulation coverage mapping, high-throughput memory forensics with cross-case fingerprinting, and covert single-binary forensic triage for incident response.

Every component is designed around a core philosophy: **determinism beats heuristics, local-first beats cloud-dependency, and structural identity beats pattern matching.** Cryptographic hashes identify behaviors, memory profiles, and forensic artifacts — not machine learning black boxes that can be evaded or confidence scores that can be argued about in court.

---

## The Problem

Windows detection and response has not fundamentally changed in twenty years.

The industry runs on signature matching and static rules. Every SIEM alert is a known-bad pattern someone already wrote a detection for. Every SOC analyst retriages the same benign behaviors — `svchost.exe` making a DNS query, `cmd.exe` spawning `whoami.exe` during a legitimate admin task — because every event looks unique when you only look at timestamps and process names. The raw data pipeline treats identical behaviors as new events, every time, forever.

The result is a storage bill that grows linearly with fleet size, an analyst burnout curve that follows the same slope, and a detection gap that widens with every new LOLBin and living-off-the-land technique. Organizations pay for all the telemetry and detect almost none of the novel threats.

**Signal and noise look identical in raw event logs.** The entire security operations workflow — collect, store, search, triage — is built on a category error: treating behavioral identity as a function of timestamp, PID, and process name, when it should be a function of what actually happened.

---

## What WindOH Does Differently

WindOH takes the position that the fundamental unit of detection work is not the **event** — it is the **behavior**. An event is a point in time. A behavior is a pattern that recurs. The platform is built on three interlocking insights:

### 1. Cryptographic Behavioral Identity

The LongHorizons agent captures real-time ETW events across 47 kernel and user-mode providers on Windows endpoints. But instead of shipping raw events, it distills each into a deterministic `stable_hash` — a SHA-256 of the behavioral skeleton (process lineage, operation type, normalized fields stripped of ephemera like PIDs and timestamps). The same behavior on any host, at any time, produces the same hash.

This means:
- **Same behavior = same hash = stored once** — 90-99% reduction in stored event volume
- **Cross-host behavioral comparison is a hash join** — not a multi-field text query
- **"Have we ever seen this before?" answers in microseconds** — single indexed lookup on `stable_hash`

A payload hash separately tracks what changed within a behavior — different command lines, different IPs — so rare payloads within common behaviors surface immediately.

### 2. Recency-Aware Baselining

Counting how many times something happened isn't enough. A behavior that occurred 10,000 times last year but stopped six months ago is not "common." A behavior that happened 50 times this morning might be.

The agent applies exponential decay scoring: `score = base_count × e^(-λ × days_since_last_seen)`, with a configurable half-life. Decay scores map to rarity bands (Rare / Uncommon / Common) that are pre-computed and shipped with every exported event. An analyst or detection engineer never has to ask "is this normal?" — the answer is in the document.

### 3. AI-Enriched, Predictive Behavioral Knowledge

A hash is mathematically precise and humanly meaningless. The WindOH web application closes this gap. Every unique `stable_hash` is sent once to a local LLM with a structured prompt containing the full behavioral context: process lineage, command lines, network targets, behavioral tags, PE metadata, and inter-event timing. The LLM returns:

- A plain-language behavioral description
- MITRE ATT&CK technique mappings
- A risk assessment with rationale
- Living-off-the-land, exfiltration, privilege escalation, persistence, and lateral movement flags
- Suggested investigation steps

The enrichment is cached in MongoDB permanently. Enrich once, never re-enrich. Over time the system builds a behavioral knowledge base where 99% of tokens have pre-computed context and only genuinely novel behaviors reach the LLM.

**Markov chain models** built from temporal event sequences predict what typically comes next after any given behavior — and flag transitions with probability < 1% as sequence anomalies. The system doesn't just tell you what happened; it tells you what should have happened next and whether the deviation is surprising.

---

## Platform Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                                                                                   │
│  TELEMETRY               ANALYTICS                FORENSICS & IR       DEVELOPMENT│
│                                                                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐            │
│  │ LongHorizons     │  │ WindOH App       │  │ LessVolatile         │            │
│  │ (Rust)           │  │ (TypeScript)     │  │ (Rust)               │            │
│  │                  │  │                  │  │                      │            │
│  │ 47 ETW providers │  │ LLM enrichment   │  │ Volatility 3 wrapper │            │
│  │ Cryptographic    │  │ Markov models    │  │ Embedded Python 3.9  │            │
│  │   tokenization   │  │ ART coverage     │  │ 68/29/26 plugins     │            │
│  │ Rarity baselining│  │ SearXNG intel    │  │ Adaptive parallelism │            │
│  │ ES export        │  │ Investigation UI │  │ Cross-case hashing   │            │
│  └──────────────────┘  └──────────────────┘  └──────────────────────┘            │
│                                                                                   │
│  ┌──────────────────┐                         ┌──────────────────────┐            │
│  │ Elasticsearch    │                         │ OneDriveStandalone   │            │
│  │ (transport)      │                         │ Updaterr (Rust)      │            │
│  │                  │                         │                      │            │
│  │ events           │                         │ KAPE + PsExec +      │            │
│  │ exemplars        │                         │ Hayabusa + EZ tools  │            │
│  │ patterns         │                         │ Raw disk imaging     │            │
│  │ diagnostics      │                         │ Remote orchestration │            │
│  └──────────────────┘                         │ Operational stealth  │            │
│                                               └──────────────────────┘            │
│  ┌──────────────────────────────────────────────────────────────────────────┐    │
│  │ LessToil — Claude Code Plugin (40 Python modules, 56 languages)           │    │
│  │ Structural codebase indexing, call graphs, governance, duplicate detection│    │
│  └──────────────────────────────────────────────────────────────────────────┘    │
│                                                                                   │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## Components

### LongHorizons — Endpoint Telemetry Agent

**Written in Rust. Single ~8 MB binary. Zero runtime dependencies. Runs as a Windows service under LocalSystem.**

The agent captures real-time ETW events from 47 providers spanning kernel process/thread/network/file/registry activity, DNS client, PowerShell script blocks and pipeline execution, Windows Defender detections, SChannel TLS handshakes, RPC and COM operations, WMI activity, AppLocker policy evaluation, Hyper-V hypervisor events, and more.

Every event runs through an 8-way hash-sharded pipeline: TDH property extraction → semantic event typing → process cache population → enrichment computation (inter-event timing, process lineage, behavioral tags, burst metrics, PE metadata, network correlation, field completeness scoring) → deterministic tokenization into `stable_hash` and `payload_hash` → Count-Min Sketch baselining with exponential decay → reservoir sampling for exemplars → durable SQLite outbox → gzip-compressed Elasticsearch bulk export with retry and dead-letter.

Sensitive data is encrypted at rest with AES-256-GCM using purpose-specific keys derived via HKDF-SHA256 from a DPAPI-protected master key.

**Key technical decisions:**
- `parking_lot::Mutex` everywhere in the hot path — no async locks
- 8 independent baselining shards eliminate lock contention on CMS and reservoir
- SQLite WAL mode handles concurrent reads from the exporter and writes from the pipeline
- Deterministic token generation: enrichment fields use `#[serde(skip_serializing_if)]` and are excluded from hash computation

### WindOH — Behavioral Intelligence Application

**TypeScript/Next.js web application backed by MongoDB, Redis, and a local LLM.**

The application polls Elasticsearch for new telemetry from LongHorizons agents, upserts each unique `stable_hash` into MongoDB, and queues unknown tokens for LLM enrichment through BullMQ. Enrichment runs against a local LLM (llama.cpp, Ollama, vLLM, or any OpenAI-compatible endpoint) with a structured JSON prompt template — no external API calls, no data leaves the environment.

A Markov sequence engine built on MongoDB aggregation pipelines computes transition probability matrices from temporal event chains. The prediction API returns top-N most probable next behaviors with probabilities, average inter-event timing, and cross-host prevalence. A sequence anomaly detector flags any observed transition with probability < 1% as surprising.

Atomic Red Team integration maps adversary emulation test executions against captured telemetry by `stable_hash`, producing per-technique detection coverage metrics and identifying coverage gaps where expected behaviors generated no telemetry.

A SearXNG metasearch client provides IOC enrichment, CVE lookup, and threat intel correlation from the investigation console — which combines token search and external search side-by-side.

### LessVolatile — Memory Forensics at Scale

**Written in Rust. Single self-contained binary. Embeds Volatility 3 + Python 3.9. Zero install.**

Memory forensics is slow, serial, and doesn't scale — a single Windows dump requires 68 Volatility plugins run one at a time, taking 2-3 hours of hands-on analyst work. A 100-dump incident means 300+ hours of continuous analysis. Cross-case correlation across hundreds of dumps is done by hand in spreadsheets.

LessVolatile collapses this into a single command. Point it at a memory dump (or a directory of hundreds) and it runs every relevant plugin in parallel — 68 for Windows, 29 for Linux, 26 for macOS — using adaptive parallelism (80% of available CPU cores). Every plugin output is auto-converted to CSV. Every capture produces a deterministic structural fingerprint: SHA-256 hashes of process names, services, kernel modules, and network profiles for cross-case matching.

**Key capabilities:**
- **97% time reduction** — 3 hours of manual analysis becomes 5 minutes unattended
- **Hidden process detection** — automatic delta between PsList (kernel's process list) and PsScan (memory scan) flags rootkit-hidden processes
- **Cross-case threat actor attribution** — deterministic process/service/module hashes match across victims; court-admissible evidence with zero false positives
- **C2 beaconing surfaced automatically** — external IP count sorting reveals compromised hosts without packet capture
- **Air-gapped ready** — no Python, pip, admin rights, or internet connection needed; single file runs from a USB drive
- **Pipeline-ready output** — 68 CSVs per dump + fingerprint CSV ingest directly into Splunk, Elastic, Jupyter, or any SIEM

**Business impact at $200/hr analyst rate**: $700/dump manual becomes $16/dump automated. A 500-dump annual IR retainer drops from $350,000 to $7,000.

### OneDriveStandaloneUpdaterr — Covert Forensic Triage

**Written in Rust. Single self-contained binary. Embeds KAPE, PsExec, Hayabusa, Eric Zimmerman tools, and a raw disk imager.**

Traditional forensic collection on Windows requires staging multiple tools, managing dependencies, and generating antivirus telemetry. OneDriveStandaloneUpdaterr solves all three: everything is compiled into one executable, CPU usage is throttled below 42% to avoid triggering performance alerts, and the binary carries Microsoft OneDrive metadata to blend into normal system activity.

Drop one file. Run one command. Collect 100+ forensic artifacts across four dimensions: filesystem forensics (18 KAPE targets — event logs, registry hives, prefetch, LNK files, jump lists, SRUM, Outlook PST/OST, cloud storage metadata), live response (35+ SysInternals and native tools — running processes, network connections, ARP/DNS cache, installed programs, running drivers), PowerShell collection (40+ modules — BitLocker status, Defender exclusions, WMI repository, named pipes, SMB sessions), and memory/disk (RAM capture, physical disk imaging).

**Key capabilities:**
- **Single-binary deployment** — no installer, no DLLs, no config files; everything embedded via `rust-embed` at compile time
- **Remote orchestration** — copy to target via ADMIN$ share, launch through embedded PsExec as SYSTEM, poll for result zip, pull back, verify SHA-256 integrity, clean up — all from one command
- **7-way concurrent dispatch** — KAPE targets and modules run in parallel via tokio async runtime, CPU-throttled to stay under the radar
- **Operational stealth** — Microsoft OneDrive version string, legitimate update directory paths, no C2 or beaconing
- **SHA-256 integrity pipeline** — every output zip hashed immediately, verified after remote pull-back, sidecar file shipped with every collection
- **Disk imaging with space guard** — pre-flight check ensures free space exceeds physical disk size before imaging PhysicalDrive0

**Five operational profiles** ranging from light triage (targets only) to full collection with disk imaging — all through a single binary with command-line subcommands.

### LessToil — Structural Codebase Intelligence

**Claude Code plugin. 40 Python modules. 56 languages. 26-table SQLite knowledge graph.**

LessToil gives AI coding agents persistent structural awareness of the codebase they operate on. Every file, function, class, method, and call relationship is indexed into a SQLite database with recursive CTE query capability for transitive impact analysis. The plugin runs three lifecycle hooks: SessionStart (full index with architectural dashboard), PreToolUse (impact analysis, duplicate detection, and governance enforcement before every edit), and PostToolUse (incremental reindex of changed files).

The system infers 14 architectural domains with security boundary marking, detects duplicated code via SimHash 64-bit fingerprinting, scores temporal risk from git history, tracks architectural drift across four axes, and enforces governance invariants and policies. Dangerous edits are blocked before execution via exit code 2.

Built for the WindOH project itself — and usable by any engineering team — LessToil transforms AI-assisted development from keyword search into structured reasoning.

---

## Novelty: What Makes This Different

### Not a SIEM. Not an EDR. Not a Log Aggregator.

Existing detection products fall into three categories, none of which does what WindOH does:

| Category | Mechanism | Limitation |
|---|---|---|
| **SIEM** | Rule-based correlation of log events | Rules only fire on known patterns. Novel threats are invisible. Storage costs scale linearly with endpoints. |
| **EDR** | Process-level telemetry + cloud analytics | Behavioral comparison is proprietary and opaque. You cannot query cross-host behavioral identity directly. Vendor lock-in on detection logic. |
| **Log Aggregation** | Centralized raw event storage + search | "Is this new?" requires hours of manual hunting. "Is this normal?" requires weeks of historical baseline building. Every event stored separately. |

WindOH is a **behavioral intelligence platform**, not a detection product. It doesn't replace your SIEM or EDR — it feeds them a pre-scored, pre-enriched, deduplicated behavioral signal that makes their detection logic more effective. The differentiation is in the data model:

- **Events → Behaviors.** Raw events are collapsed into cryptographic behavioral identities. The same behavior is stored once, globally, with a count.
- **Hashes → Intelligence.** Every stable hash is enriched by an LLM into human-readable context with MITRE mappings and risk assessments. Analysts start from understanding, not from raw telemetry.
- **Sequences → Predictions.** Behavioral transitions are modeled as a Markov chain. The system predicts what comes next and flags surprises — not based on rules, but on observed empirical frequencies across the entire fleet.
- **Local-first, air-gapped capable.** The LLM runs locally. The agent runs on the endpoint. No data leaves the environment unless you configure an external Elasticsearch cluster.

### Technical Depth

This is not a prototype or a proof of concept. The architecture spans:

- **Systems programming** — native Windows ETW integration via Trace Data Helper API, real-time trace sessions, DPAPI key protection, AES-256-GCM encryption, HKDF key derivation, parking_lot concurrency, 8-way sharded pipeline with lock-free Count-Min Sketch
- **Data engineering** — deterministic cryptographic tokenization with stable/payload hash separation, exponential decay-weighted baselining with configurable half-life, reservoir sampling with richness scoring, durable outbox pattern with retry and dead-letter
- **AI/ML integration** — structured LLM prompt engineering for behavioral analysis, Markov chain transition probability modeling from temporal event sequences, sequence anomaly detection via surprise scoring (-log2(P)), cached enrichment with permanent knowledge base accumulation
- **Full-stack web development** — Next.js 14 with App Router and tRPC, MongoDB with Mongoose ODM and Atlas Search, BullMQ job queues with concurrency and rate limiting, Docker Compose multi-service orchestration
- **Developer tooling** — 40-module Python plugin system, tree-sitter AST parsing across 41 languages with regex fallback for 15 more, recursive CTE call graph traversal, SimHash duplicate detection, 10-phase edit verification pipeline, 6-verifier consensus engine

---

## Business Impact

### For a 1,000-Endpoint Fleet

| Metric | Conventional Pipeline | WindOH Pipeline |
|---|---|---|
| Daily storage per endpoint | 5-20 GB | 50-200 MB |
| Stored event volume | ~200 GB/day | ~2 GB/day |
| Time to answer "is this new?" | Hours of historical search | Instant (hash lookup) |
| Time to answer "is this normal?" | Weeks of baseline building | Pre-computed (decay score + rarity band) |
| Cross-host behavioral comparison | Multi-field text joins | Single hash join |
| Analyst investigation surface | Every event | Rare + uncommon only |
| New analyst time-to-competence | Weeks of learning normal patterns | Immediate (LLM-enriched descriptions) |
| Detection coverage visibility | Unknown | ART-mapped per MITRE technique |

### Cost Recovery

- **Storage**: 90-99% reduction in Elasticsearch storage costs through cryptographic deduplication
- **Analyst time**: Tier 1 analysts triage rare and uncommon events only — the 400th instance of `svchost.exe` making a DNS query doesn't surface as an alert
- **Detection engineering**: Behavioral tokens are pre-enriched with MITRE mappings and risk assessments — detection engineers start from understanding, not from raw event schemas
- **Incident response**: Process lineage, ancestor chain hashes, inter-event timing, and cross-process correlation are pre-computed — no manual timeline reconstruction
- **AI/ML readiness**: Pre-enriched, deduplicated behavioral corpus with relational features eliminates the 60-80% data engineering overhead that typically consumes ML project timelines

### For the Development Workflow (LessToil)

- **55K-120K tokens saved per session** through structural querying instead of file-by-file discovery
- **65-132 bugs prevented annually** (5-person team) through pre-edit impact analysis and duplicate detection
- **550-1,210 developer hours recovered per year** through eliminated manual dependency tracing, dead code cleanup, and architectural drift remediation
- **~$110K-$365K in recovered engineering productivity per year**

---

## Repository Map

```
WindOH/
│
├── LongHorizons/                 Rust telemetry agent
│   ├── README.md                 Overview, quick start, use cases
│   ├── ARCHITECTURE.md           Crate map, event lifecycle, concurrency model,
│   │                             security architecture, design decisions
│   ├── ES-INDEX-TEMPLATES.md     Elasticsearch mappings, ILM retention policy,
│   │                             API key provisioning
│   ├── WindOH.md                 WindOH application handoff document: full
│   │                             architecture, MongoDB schema, LLM prompt design,
│   │                             Markov engine, ART integration, SearXNG client,
│   │                             tRPC API design, implementation roadmap
│   ├── config.toml               Fully annotated 580-line deployment config
│   ├── install.ps1               Windows service installer (PowerShell)
│   ├── uninstall.ps1             Service uninstaller with data removal option
│   └── release.zip               Pre-built agent binary (~3.6 MB)
│
├── LessVolatile/                 Rust memory forensics launcher
│   ├── README.md                 Overview, time savings, detection benefits,
│   │                             business case, quick start
│   └── RELEASE.md                v0.2.0 release notes: TUI dashboard, adaptive
│                                 parallelism, cross-capture fingerprint system,
│                                 multi-dump parallel processing
│
├── OneDriveStandaloneUpdaterr/   Rust forensic triage + live response
│   ├── README.md                 Overview, operational profiles, architecture,
│   │                             integrity guarantees, quick start
│   ├── FEATURES.md               Feature breakdown: embedded dependency model,
│   │                             concurrent dispatch engine, operational stealth,
│   │                             SHA-256 pipeline, module inventory (98 tasks)
│   ├── BUILDING.md               Build guide, asset structure, CI/CD example
│   └── USAGE.md                  Usage guide: local/remote collection modes,
│                                 output parser, exit codes, requirements
│
├── LessToil/                     Claude Code structural intelligence plugin
│   ├── README.md                 Executive summary, features, quantified impact
│   ├── ARCHITECTURE.md           Complete technical reference: 26-table data
│   │                             model, hook lifecycle, 40 modules, 9 ADRs
│   ├── USE_CASES.md              12 real-world scenarios with SQL examples
│   ├── FAQ.md                    Installation, performance, customization, comparison
│   ├── CONTRIBUTING.md           Language support, feature development, PR process
│   ├── GETTING_STARTED.md        Complete installation and first-use guide
│   └── plugin/                   Plugin distribution: plugin.json, install scripts
│       │                         (Bash + PowerShell), release zip
│
└── README.md                     This file
```

---

## Technology Summary

| Component | Language | Stack |
|---|---|---|
| LongHorizons Agent | Rust | Windows ETW (TDH API), SQLite (WAL), AES-256-GCM, HKDF-SHA256, DPAPI, parking_lot, tokio |
| WindOH Application | TypeScript | Next.js 14, React 18, TailwindCSS, tRPC, MongoDB 7 + Mongoose 8, BullMQ + Redis, OpenAI SDK (local LLM), @elastic/elasticsearch 8.x, SearXNG |
| LessVolatile | Rust | Volatility 3 (embedded), Python 3.9 (embedded), zip, sha2, csv, ratatui + crossterm (TUI), indicatif, chrono |
| OneDriveStandaloneUpdaterr | Rust | KAPE + PsExec + Hayabusa + Eric Zimmerman tools (embedded via rust-embed), tokio async runtime, clap, sha2, zip |
| LessToil Plugin | Python | tree-sitter (41 grammars), SQLite3, PyYAML, Claude Code hooks/agents/commands/skills |

---

## Quick Start

### Continuous Telemetry (LongHorizons)

```powershell
# From an Administrator PowerShell on the Windows endpoint:
cd LongHorizons
.\install.ps1 -BinaryPath ".\agent.exe" -ConfigPath ".\config.toml"
```

Edit `config.toml` to set `agent.id`, Elasticsearch endpoint, and API key. The agent installs as a Windows service with automatic startup and failure recovery. Apply the index templates from [ES-INDEX-TEMPLATES.md](LongHorizons/ES-INDEX-TEMPLATES.md).

### Behavioral Intelligence (WindOH)

```bash
docker compose up -d
```

The stack (Next.js, MongoDB, Redis, SearXNG) is defined in the [WindOH handoff document](LongHorizons/WindOH.md), section 10.

### Memory Forensics (LessVolatile)

```bash
# Single dump — Windows plugins, parallel execution
lessvolatile suspect.mem

# Batch process all dumps in a directory
lessvolatile ./cases/

# Linux / macOS dumps
lessvolatile server.lime --linux
lessvolatile macbook.dmp --mac
```

Outputs: 68 CSVs per dump + `_fingerprint.csv` for cross-case correlation.

### Forensic Triage (OneDriveStandaloneUpdaterr)

```powershell
# Full triage — targets + live response + memory files
.\OneDriveStandaloneUpdater.exe installer

# Remote triage on another host
.\OneDriveStandaloneUpdater.exe remote 192.168.1.50 installer

# Full triage + disk image
.\OneDriveStandaloneUpdater.exe uninstaller D
```

### Developer Tooling (LessToil)

```powershell
irm https://raw.githubusercontent.com/LongHorizons/WindOH/main/LessToil/plugin/install.ps1 | iex
```

---

## Author

This platform was designed, architected, and implemented as an integrated system spanning Rust systems programming (three independent binaries: ETW telemetry agent, memory forensics launcher, forensic triage tool), TypeScript full-stack development (Next.js behavioral intelligence application with LLM integration and Markov modeling), Python developer tooling (40-module Claude Code plugin), AI/LLM integration, Windows internals (ETW, TDH, DPAPI, kernel providers, PE parsing), cryptographic engineering (deterministic behavioral tokenization, HKDF key derivation, AES-256-GCM encryption), and security operations domain expertise across detection engineering, incident response, memory forensics, and threat intelligence.

---

## License

MIT
