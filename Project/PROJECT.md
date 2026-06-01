# WindOH Project Management Plan

> **Project Management Body of Knowledge (PMBOK Guide) -- Seventh Edition aligned.**  
> PMP-certified project management. Sole-author execution. Five binaries, one web application, one developer-tooling plugin.

---

## Project Charter

### Project Purpose

WindOH is a Windows security intelligence platform that answers one question with cryptographic certainty: what just happened, and have we ever seen it before? The platform spans real-time ETW telemetry capture, behavioral tokenization, local LLM enrichment, Markov chain sequence modeling, parallel memory forensics, covert forensic triage, multi-threaded Atomic Red Team execution, and structural codebase intelligence for AI coding agents.

### Business Case

Security operations is constrained by a category error: treating behavioral identity as a function of timestamp, PID, and process name, when it should be a function of the behavioral skeleton itself. Storage costs grow linearly with fleet size. Signal-to-noise degrades at the same rate. Existing tooling forces a trade-off between coverage (SIEM ingest limits), depth (manual forensic analysis), and speed (serial tool execution).

WindOH eliminates this trade-off through cryptographic behavioral tokenization (90-99% storage reduction), parallel execution (97% time reduction for memory forensics), and local LLM enrichment (zero data exfiltration risk). The platform is designed for environments where being noticed is a failure mode and where data must never leave the premises.

### High-Level Scope

| In Scope | Out of Scope |
|----------|-------------|
| Windows ETW telemetry agent (LongHorizons) | Managed SOC/SIEM service |
| Behavioral intelligence application (WindOH) | Cloud-hosted enrichment (data must stay local) |
| Memory forensics launcher (LessVolatile) | GUI-based forensic tools |
| Forensic triage tool (OneDriveStandaloneUpdaterr) | Mobile/OT/IoT platform agents (future) |
| Atomic Red Team executor (LessAtomic) | Custom test authoring (uses ART YAML) |
| Developer tooling plugin (LessToil) | IDE integrations beyond Claude Code |
| Cross-platform agent architecture (Linux, macOS, Kubernetes) | -- |
| Deterministic behavioral tokenization | ML-based anomaly detection (heuristic-free) |

### Key Stakeholders

| Stakeholder | Role | Interest |
|------------|------|----------|
| **Sole Author / PM** | Architect, developer, project manager | Full delivery of all components to defined quality standards |
| **Security Operations Teams** | End users | Detection coverage, forensic throughput, operational efficiency |
| **Red Teams** | End users | Pre-flight validation, defense baseline assessment |
| **Incident Responders** | End users | Forensic triage speed, cross-case correlation |
| **AI/ML Engineers** | End users | Local inference for behavioral enrichment, reproducible research |
| **Open-Source Community** | Contributors, adopters | Extensibility, documentation, licensing clarity |

### Milestones at a Glance

| Milestone | Deliverable | Status |
|-----------|------------|--------|
| M1 | LessAtomic Release (v0.1.0) | Done |
| M2 | LessVolatile + OneDriveStandaloneUpdaterr Release | Done |
| M3 | LessToil Public Distribution | Done |
| M4 | LongHorizons Agent Validation | In progress (80%) |
| M5 | WindOH Application Deployment | Planned |
| M6 | Platform Integration Testing | Planned |
| M7 | Cross-Platform Agent Expansion | Planned |

---

## Scope Management

### Scope Statement

Design, develop, document, and release a Windows security intelligence platform consisting of:

1. **LongHorizons Agent**: Rust binary (~8 MB) capturing real-time ETW events from 200+ kernel and user-mode providers, decomposing each event into cryptographically distinct stable token (behavioral skeleton) and payload token (instance data), with Count-Min Sketch baselining, exponential decay scoring, AES-256-GCM encryption at rest, and gzip-compressed Elasticsearch bulk export.

2. **WindOH Application**: TypeScript/Next.js 14 behavioral intelligence application with tRPC API, MongoDB persistence, BullMQ job orchestration, local LLM enrichment (OpenAI-compatible endpoint), Markov chain transition modeling with surprise scoring, Atomic Red Team coverage mapping, and SearXNG IOC enrichment.

3. **LessVolatile**: Rust binary (~129 MB) embedding Volatility 3 and Python 3.9. Runs 68 Windows (plus 29 Linux, 26 macOS) plugins in parallel with adaptive CPU utilization. Produces deterministic structural fingerprints (SHA-256) for cross-case attribution.

4. **OneDriveStandaloneUpdaterr**: Rust binary (~324 MB) embedding KAPE, PsExec, Hayabusa, and Eric Zimmerman tools. Four-dimension forensic collection (filesystem, live response, PowerShell, memory/disk) with remote orchestration via ADMIN$ share and SYSTEM execution.

5. **LessAtomic**: Rust binary (~5 MB) embedding 265 Atomic Red Team technique YAML files (752 atomic tests) at compile time. Multi-threaded execution via Rayon work-stealing with variable interpolation, dependency resolution, and structured reporting.

6. **LessToil**: Python Claude Code plugin. 40 modules, 56-language tree-sitter parsing, 26-table SQLite knowledge graph, SimHash 64-bit duplicate detection, 14-domain architectural inference, and governance enforcement via lifecycle hooks.

### Work Breakdown Structure (WBS)

```
1. WindOH Platform
   1.1 LongHorizons Agent
       1.1.1 ETW Session Management (47+ providers, kernel + user-mode)
       1.1.2 TDH Property Extraction and Semantic Event Typing
       1.1.3 Process Genealogy Reconstruction (PEB / logon session)
       1.1.4 Enrichment Computation (inter-event timing, lineage, tags, burst, PE metadata)
       1.1.5 Cryptographic Tokenization (stable token + payload token, SHA-256)
       1.1.6 Count-Min Sketch Baselining (exponential decay, rarity bands)
       1.1.7 Reservoir Sampling (exemplars per stable token)
       1.1.8 AES-256-GCM Encryption (HKDF-SHA256, DPAPI-protected master keys)
       1.1.9 SQLite Outbox with Retry and Dead-Letter
       1.1.10 Elasticsearch Bulk Export (gzip, TLS, API key)
       1.1.11 Windows Service Integration (install.ps1, config.toml, health diagnostics)
   1.2 WindOH Application
       1.2.1 Next.js 14 + tRPC API Layer
       1.2.2 MongoDB Schema Design (tokens, sequences, enrichments, coverage)
       1.2.3 BullMQ Job Orchestration (Redis-backed enrichment queue)
       1.2.4 LLM Enrichment Worker (structured JSON prompt, permanent caching)
       1.2.5 Markov Sequence Engine (transition matrices, surprise scoring)
       1.2.6 Atomic Red Team Coverage Mapper
       1.2.7 SearXNG Client (IOC enrichment, CVE lookup)
       1.2.8 windoh.us Deployment (DNS, SSL, infrastructure provisioning)
   1.3 LessVolatile
       1.3.1 Volatility 3 + Python 3.9 Embedding
       1.3.2 Parallel Plugin Execution (adaptive CPU, 80% utilization)
       1.3.3 CSV Auto-Conversion (68+ plugins)
       1.3.4 Deterministic Fingerprinting (SHA-256: processes, services, modules, network)
       1.3.5 Cross-Case Attribution (hash join across dumps)
       1.3.6 Linux and macOS Plugin Support (29 Linux, 26 macOS)
   1.4 OneDriveStandaloneUpdaterr
       1.4.1 KAPE Embedding (18 targets: event logs, registry, prefetch, LNK, SRUM, PST/OST)
       1.4.2 PsExec Remote Orchestration (ADMIN$ copy, SYSTEM execution, result retrieval)
       1.4.3 Hayabusa + Eric Zimmerman Tools Embedding
       1.4.4 PowerShell Module Collection (40+ modules)
       1.4.5 Raw Disk Imaging with Space Guard
       1.4.6 Operational Stealth (OneDrive metadata, CPU throttling <42%)
       1.4.7 SHA-256 Integrity Verification (collection -> transit -> storage)
   1.5 LessAtomic
       1.5.1 Build-Time YAML Embedding (265 techniques, walkdir + validation)
       1.5.2 AtomicYaml / AtomicTest Data Model (serde deserialization)
       1.5.3 Variable Interpolation Engine (#{arg}, PathToAtomicsFolder)
       1.5.4 Multi-Threaded Execution (Rayon work-stealing, Chase-Lev deque)
       1.5.5 Dependency Resolution (prereq check -> auto-install -> recheck -> skip)
       1.5.6 PowerShell / CMD / Manual Executors (base64 encoding, temp .bat files)
       1.5.7 Structured Reporting (text table, JSON export, per-test .log files)
       1.5.8 Safety Layer (confirmation, elevation gating, timeouts, cleanup enforcement)
   1.6 LessToil Plugin
       1.6.1 41 tree-sitter Grammar Integration
       1.6.2 26-Table SQLite Knowledge Graph
       1.6.3 SessionStart Hook (full index, architectural dashboard)
       1.6.4 PreToolUse Hook (impact analysis, duplicate detection, governance)
       1.6.5 PostToolUse Hook (incremental reindex)
       1.6.6 SimHash 64-bit Duplicate Detection
       1.6.7 14-Domain Architectural Inference with Security Boundaries
       1.6.8 Temporal Risk Scoring (git churn, bug density, ownership volatility)
       1.6.9 Architectural Drift Detection (4 axes)
       1.6.10 Cross-Platform Installers (install.ps1, install.sh)
       1.6.11 Plugin Distribution (plugin.json, repo-cognition.zip)
   1.7 Cross-Cutting
       1.7.1 Documentation (20+ markdown files, ADRs, architecture, security, operations)
       1.7.2 Visual Assets (4 GIFs, 2 PNGs)
       1.7.3 Licensing (LongHorizons Software License v1.0)
       1.7.4 HotStuff Workstation Build (hand-sourced, hand-built from bare case)
       1.7.5 Public Repository Construction and Release Management
```

### Work Breakdown Summary

| WBS | Work Package | Deliverables | Status |
|-----|-------------|-------------|--------|
| 1.1 | LongHorizons Agent | Binary, service, config, docs, Wizard.gif | Validating |
| 1.2 | WindOH Application | Web app, worker, API, windoh.us, Nice.gif | Planned |
| 1.3 | LessVolatile | Binary, fingerprinting, 68+ CSVs | Released v0.2.0 |
| 1.4 | OneDriveStandaloneUpdaterr | Binary, 4-dim collection, remote orchestration, OneDriveStandaloneUpdaterr.gif | Released |
| 1.5 | LessAtomic | Binary, 752 tests, JSON export, AtomicRedTeam.png | Released v0.1.0 |
| 1.6 | LessToil | Plugin, installers, knowledge graph, 40 modules | Released |
| 1.7 | Cross-Cutting | 20+ docs, 6 visuals, license, workstation, repo | Complete |

---

## Schedule Management

### Schedule Baseline

| Phase | Duration | Start | Finish | Predecessors |
|-------|----------|-------|--------|-------------|
| I: Foundation (LongHorizons core) | 3 months | Month 1 | Month 3 | -- |
| II: Intelligence Layer (WindOH app) | 3 months | Month 4 | Month 6 | I (partial overlap) |
| III: Forensics Toolchain | 2 months | Month 7 | Month 8 | I |
| IV: Adversary Emulation | 2 months | Month 9 | Month 10 | I |
| V: Developer Tooling | 2 months | Month 11 | Month 12 | I-IV |
| VI: Documentation and Assembly | 3 days | Month 12 | Month 12 | I-V |

### Critical Path

```
Foundation (I) --> Forensics Toolchain (III) --> Developer Tooling (V) --> Assembly (VI)
Foundation (I) --> Intelligence Layer (II) --> Developer Tooling (V)
Foundation (I) --> Adversary Emulation (IV) --> Developer Tooling (V)
```

The critical path runs through the LongHorizons Agent (Foundation) because every subsequent component either depends on the tokenization model (WindOH), was developed using the same Rust patterns (LessVolatile, OneDriveStandaloneUpdaterr, LessAtomic), or was built to manage the codebase those components produced (LessToil).

The 3-day Assembly phase leveraged LessToil for structural indexing, cross-reference validation, and documentation generation. Without LessToil, equivalent assembly effort is estimated at 2-3 weeks of manual cross-referencing and consistency checking across 20+ documents.

### Schedule Performance

| Metric | Value |
|--------|-------|
| **Original Planned Duration** | 12 months |
| **Actual Duration (through Assembly)** | 12 months |
| **Schedule Variance (SV)** | 0 (on schedule) |
| **Schedule Performance Index (SPI)** | 1.0 |

---

## Cost Management

### Cost Baseline

All costs are estimated at market rate for the multi-disciplinary skill set required. The project was executed by a single PMP-certified engineer performing all roles: systems architect, Rust developer, TypeScript developer, Python developer, AI/LLM integration engineer, cryptographic engineer, Windows kernel specialist, security operations analyst, technical writer, and project manager.

| Cost Category | Basis | Estimate |
|---------------|-------|----------|
| **I: Foundation** | 500 hrs x $200/hr | $100,000 |
| **II: Intelligence Layer** | 500 hrs x $200/hr | $100,000 |
| **III: Forensics Toolchain** | 350 hrs x $200/hr | $70,000 |
| **IV: Adversary Emulation** | 300 hrs x $200/hr | $60,000 |
| **V: Developer Tooling** | 300 hrs x $200/hr | $60,000 |
| **VI: Assembly** | 50 hrs x $200/hr | $10,000 |
| **Labor Subtotal** | 2,000 hrs | $400,000 |
| **Infrastructure (HotStuff)** | Hardware acquisition, component sourcing, assembly | $25,000-$35,000 |
| **Tooling and Services** | GitHub, domain (windoh.us), CI/CD, cloud validation infra | $3,000-$5,000 |
| **Cost Baseline Total** | | **$428,000-$440,000** |

### Cost Assumptions

- Labor rate: $200/hour. This is the market rate for a multi-disciplinary security engineer with demonstrated competency across Rust systems programming, TypeScript full-stack development, AI/LLM integration, cryptographic engineering, Windows kernel instrumentation, and security operations. The rate is consistent with the analyst rate cited in the WindOH business case ($200/hr for manual forensic analysis) and reflects the same scarcity premium for the combined skill set.
- Infrastructure: HotStuff was hand-sourced and hand-built from the bare HP Z8 G4 case. Every component (CPUs, DIMMs, GPUs, NVMe drives, SSDs, HDD, cabling, cooling) was individually selected, acquired, installed, and validated. No vendor assembly. No pre-built configuration.
- Tooling: GitHub is free for public repositories. Domain registration is nominal. Cloud infrastructure for validation testing (Elasticsearch, MongoDB, Redis) is usage-based and minimal during development.
- The cost baseline excludes: ongoing maintenance, cloud hosting for production WindOH deployment, commercial licensing fees for embedded tools (all embedded dependencies are open-source or MIT-licensed).

### Cost Performance

| Metric | Value |
|--------|-------|
| **Cost Baseline** | $428,000-$440,000 |
| **Actual Cost (labor, imputed)** | $400,000 (2,000 hrs x $200/hr) |
| **Actual Cost (infrastructure)** | $25,000-$35,000 |
| **Cost Variance (CV)** | ~$0 (on budget) |
| **Cost Performance Index (CPI)** | 1.0 |

### Earned Value Analysis (at Assembly Completion)

| Metric | Value |
|--------|-------|
| **Planned Value (PV)** | $400,000 (100% of labor baseline) |
| **Earned Value (EV)** | $400,000 (100% of scope delivered) |
| **Actual Cost (AC)** | $400,000 (2,000 hrs executed) |
| **Schedule Variance (SV = EV - PV)** | $0 |
| **Cost Variance (CV = EV - AC)** | $0 |
| **Schedule Performance Index (SPI = EV/PV)** | 1.0 |
| **Cost Performance Index (CPI = EV/AC)** | 1.0 |

---

## Quality Management

### Quality Policy

Every component must satisfy seven non-negotiable architectural principles. These principles constitute the quality baseline and are the decision framework for every feature, every PR, and every release:

| Principle | Quality Metric | Measurement |
|-----------|---------------|-------------|
| **Deterministic over heuristic** | Behavioral identity uses SHA-256 hashes, not ML embeddings | Two identical behaviors on different hosts produce identical stable tokens |
| **Local-first over cloud-dependent** | No telemetry data transits the public internet for enrichment | Code path audit: zero external API calls in enrichment pipeline |
| **Observable over opaque** | Every automated decision carries provenance | Structured diagnostics at every pipeline stage; raw LLM prompt/response stored |
| **Safe-by-default** | AES-256-GCM encryption at rest is mandatory | DPAPI-protected master keys, HKDF-derived purpose keys, no plaintext credentials |
| **Graceful degradation** | No component failure cascades into another | SQLite outbox when ES unreachable; BullMQ retry when LLM unavailable; 503 when DB down |
| **Human-overridable** | Every automated decision is an annotation, not an enforcement action | No automated blocking, quarantining, or process termination |
| **Reproducible execution** | Same input produces same output, every time | Deterministic fingerprints, idempotent enrichment, cached results |

### Quality Metrics by Component

| Component | Key Metric | Target | Actual |
|-----------|-----------|--------|--------|
| LongHorizons Agent | Event-to-token throughput | >10,000 events/sec sustained | Under validation |
| LongHorizons Agent | Storage reduction (stable token dedup) | >90% | 90-99% (measured) |
| WindOH Application | Enrichment cache hit rate (steady state) | >99% | Target (pre-deployment) |
| LessVolatile | Time reduction vs. manual (68 plugins) | >95% | 97% (3 hrs -> 5 min) |
| LessVolatile | Cost reduction vs. manual ($200/hr analyst) | >90% | 97.7% ($700 -> $16 per dump) |
| OneDriveStandaloneUpdaterr | Collection dimensions | 4 (filesystem, live, PS, memory) | 4 |
| OneDriveStandaloneUpdaterr | Remote execution supported | Yes | Yes (PsExec via ADMIN$) |
| LessAtomic | Tests embedded | 752 | 752 |
| LessAtomic | Speedup vs. sequential Invoke-Atomic (8 cores) | >5x | 6-10x |
| LessToil | Languages supported | 56 | 56 |
| LessToil | Hook lifecycle coverage | 3/3 (SessionStart, PreToolUse, PostToolUse) | 3/3 |

### Quality Assurance Approach

As a sole-author project, quality assurance relied on:

1. **Architectural invariant enforcement**: Every component was validated against the seven non-negotiable principles at design review, implementation, and release gates.
2. **Idempotency testing**: Deterministic token generation verified across multiple hosts and sessions. Fingerprint stability confirmed across repeated memory dump processing.
3. **Parallelism validation**: Rayon work-stealing throughput measured against sequential baseline. Lock contention profiled via `parking_lot::Mutex` instrumentation.
4. **Failure-mode injection**: Elasticsearch, LLM, MongoDB, and Redis unavailability simulated. Graceful degradation behavior verified for each failure mode.
5. **Cross-reference consistency**: LessToil structural index used to validate that all documented APIs, config keys, and CLI flags match their implementations.

---

## Resource Management

### Team Structure

| Role | Resource | Allocation | PMP Process |
|------|----------|-----------|-------------|
| **Project Manager** | Sole Author (PMP-certified) | 5-10% of total effort | Integration, scope, schedule, cost, quality, resource, communications, risk, procurement, stakeholder management |
| **Systems Architect** | Sole Author | 10-15% | Architecture design, ADR authorship, technology selection, interface definition |
| **Rust Developer** | Sole Author | 40-45% | LongHorizons, LessVolatile, OneDriveStandaloneUpdaterr, LessAtomic implementation |
| **TypeScript Developer** | Sole Author | 15-20% | WindOH Application (Next.js, tRPC, MongoDB, BullMQ, LLM client, Markov engine) |
| **Python Developer** | Sole Author | 10-15% | LessToil plugin (40 modules, tree-sitter, SQLite, hooks, governance) |
| **AI/LLM Engineer** | Sole Author | 5% | Prompt engineering, vLLM deployment, PartiriOne tensor-parallel configuration |
| **Technical Writer** | Sole Author | 5% | 20+ markdown documents, ADRs, API docs, runbooks, threat model |
| **DevOps/Release Manager** | Sole Author | 2-3% | GitHub repository, release packaging, CI/CD, installer scripts |

### Physical Resources

| Resource | Specification | Purpose |
|----------|-------------|---------|
| **HotStuff Workstation** | HP Z8 G4, 2x Xeon Platinum 8260 (96 logical processors), 1.5 TB ECC DDR4, 2x RTX 5090 (64 GB VRAM), NVMe/SSD/HDD | Development, local LLM inference, parallel builds, multi-VM testing |
| **Test VMs** | Windows 10/11, Windows Server 2019/2022 | Agent validation, LessAtomic execution, forensic tool testing |
| **WSL2 Environment** | Linux kernel, Docker, vLLM | LessToil development, LLM serving, cross-platform build testing |

### Resource Utilization

| Metric | Value |
|--------|-------|
| **Total labor hours** | ~2,000 |
| **Calendar duration** | 12 months |
| **Average weekly effort** | ~40 hours |
| **Peak concurrency** | Single-threaded (sole author constraint) |
| **Bottleneck** | Sole author -- all roles serialized through one engineer |

---

## Communications Management

### Communications Matrix

| Stakeholder | Information Need | Method | Frequency |
|------------|-----------------|--------|-----------|
| **End Users (SOC/IR/Red Team)** | Release notes, usage guides, quick-start | GitHub README, Google Drive distribution | Per release |
| **Open-Source Community** | Architecture, contributing, licensing | GitHub repository, documentation | Continuous |
| **Future Contributors** | Codebase structure, design rationale, ADRs | LessToil index, ARCHITECTURE.md files | On-demand |
| **Project Sponsor (Self)** | Earned value, milestone status, risk register | PROJECT.md (this document) | Per phase gate |

### Documentation Inventory

| Document | Type | Location |
|----------|------|----------|
| README.md | Project overview, manifesto, architecture | Root |
| ENGINEERING_PRINCIPLES.md | Design rationale, decision framework | Root |
| PROJECT.md | PMP project management plan | Project/ |
| COMPUTE.md | Workstation profile, hardware specifications | Compute/ |
| NOTICE.md | Legal notices, attributions | Root |
| LongHorizons/ARCHITECTURE.md | Agent architecture, event lifecycle, concurrency | LongHorizons/ |
| LongHorizons/ES-INDEX-TEMPLATES.md | Elasticsearch mappings, ILM | LongHorizons/ |
| LongHorizons/CONFIG-GUIDE.md | Configuration reference | LongHorizons/ |
| LongHorizons/WindOH.md | Application handoff, full architecture | LongHorizons/ |
| LessAtomic/QUICKSTART.md | 10-second quick-start | LessAtomic/ |
| LessAtomic/RELEASE_NOTES.md | v0.1.0 release notes | LessAtomic/ |
| LessVolatile/RELEASE.md | v0.2.0 release notes | LessVolatile/ |
| OneDriveStandaloneUpdaterr/FEATURES.md | Feature breakdown | OneDriveStandaloneUpdaterr/ |
| OneDriveStandaloneUpdaterr/USAGE.md | Usage guide (local/remote modes) | OneDriveStandaloneUpdaterr/ |
| LessToil/ARCHITECTURE.md | 26-table data model, 40 modules, 9 ADRs | LessToil/ |
| LessToil/USE_CASES.md | 12 real-world scenarios with SQL examples | LessToil/ |
| LessToil/FAQ.md | Installation, performance, customization | LessToil/ |
| LessToil/CONTRIBUTING.md | Language support, feature development | LessToil/ |
| LessToil/GETTING_STARTED.md | Complete installation and first-use guide | LessToil/ |
| docs/adr/ | Architecture Decision Records (7) | docs/adr/ |
| docs/architecture/ | Data flow, queue architecture, model abstraction | docs/architecture/ |
| docs/security/ | Threat model, security architecture | docs/security/ |
| docs/operations/ | Failure handling, runbooks | docs/operations/ |
| docs/deployment/ | Docker Compose, Kubernetes | docs/deployment/ |

---

## Risk Management

### Risk Register

| Risk ID | Risk Description | Probability | Impact | Risk Score (PxI) | Response Strategy | Mitigation |
|---------|-----------------|------------|--------|-------------------|-------------------|------------|
| R1 | Sole author -- single point of failure for all development, documentation, and project management | High (1.0) | Very High | Critical | Accept (inherent to sole-author model) | Comprehensive documentation via LessToil; architectural decisions recorded as ADRs; code structured for future contributor onboarding |
| R2 | Windows ETW API changes or deprecation across Windows versions | Low | High | Medium | Mitigate | Agent targets documented, stable ETW providers; TDH API is mature and Microsoft-maintained |
| R3 | Embedded dependencies (Volatility 3, Python 3.9, KAPE, PsExec, Hayabusa, EZ Tools) update and break embedded integration | Medium | Medium | Medium | Mitigate | Pinned versions embedded at build time; deterministic builds; integration tests per release |
| R4 | Local LLM inference becomes bottleneck for enrichment throughput | Low | Medium | Low | Mitigate | Enrichment caching ensures LLM called once per unique payload token; >99% cache hit rate at steady state; vLLM continuous batching maximizes throughput |
| R5 | Atomic Red Team YAML schema changes break LessAtomic build | Low | High | Medium | Mitigate | build.rs validates all YAML at compile time; schema changes detected at build, not runtime |
| R6 | Elasticsearch version incompatibility with bulk export format | Low | High | Medium | Mitigate | Index templates versioned; ES 8.x API compatibility layer; SQLite outbox buffering decouples agent from ES availability |
| R7 | Security vulnerability in embedded third-party tooling | Medium | High | High | Mitigate | Embedded binaries isolated; tools run in disposable VM context; deterministic SHA-256 integrity verification on collection and transit |
| R8 | Scope creep -- platform expansion beyond Windows before Windows validation complete | Medium | Medium | Medium | Mitigate | Cross-platform agent architecture documented but gated behind M4 (Windows validation); PRs prioritized against M4-M7 milestone sequence |
| R9 | Licensing conflict with embedded open-source components | Low | High | Medium | Mitigate | All embedded dependencies verified MIT/BSD/Apache 2.0; attribution maintained; no GPL/copyleft dependencies embedded |
| R10 | WindOH.us infrastructure cost exceeds self-funded budget | Medium | Medium | Medium | Mitigate | Application designed for self-hosting; windoh.us is optional managed entry point; all components operate fully locally |

### Risk Monitoring

| Metric | Current Status |
|--------|---------------|
| **Open risks** | 10 (all actively managed) |
| **Risks realized** | 0 |
| **Risk burn-down** | All risks remain open (no closures at Assembly phase) |
| **Top risk** | R1 (sole author -- accepted, documented, mitigated via comprehensive documentation) |

---

## Stakeholder Management

### Stakeholder Engagement Assessment

| Stakeholder | Current Engagement | Desired Engagement | Strategy |
|------------|-------------------|-------------------|----------|
| **Sole Author / PM** | Leading | Leading | Maintain sustainable pace; leverage LessToil for efficiency |
| **Security Operations Teams** | Unaware | Supportive | Public repository, Google Drive distribution, documented business case |
| **Red Teams** | Unaware | Supportive | LessAtomic as entry point (lowest friction, highest immediate utility) |
| **Incident Responders** | Unaware | Supportive | LessVolatile + OneDriveStandaloneUpdaterr as entry point (immediate time/cost savings) |
| **AI/ML Engineers** | Unaware | Supportive | Local LLM enrichment architecture, vLLM deployment documentation |
| **Open-Source Community** | Unaware | Supportive | MIT-licensed components, CONTRIBUTING.md, public issue tracker |

### Stakeholder Engagement Plan

1. **Phase 1 (Current -- Awareness)**: Public repository with comprehensive documentation. Google Drive distribution for large binaries. Visual assets (4 GIFs, 2 PNGs) for rapid comprehension.
2. **Phase 2 (Post-M6 -- Adoption)**: WindOH.us managed platform lowers barrier to entry. Quick-start guides for each component. Measured business case outcomes (time reduction, cost reduction, coverage metrics).
3. **Phase 3 (Post-M7 -- Community)**: Cross-platform agent development opens contributor surface. LessToil structural intelligence enables contributor onboarding. ADRs and architecture docs provide decision context.

---

## Procurement Management

### Make-or-Buy Analysis

| Capability | Decision | Rationale |
|-----------|----------|-----------|
| ETW Telemetry Agent | Make | No existing tool provides deterministic behavioral tokenization with stable/payload token separation |
| Behavioral Intelligence Application | Make | No existing platform combines local LLM enrichment, Markov sequence modeling, and ART coverage mapping |
| Memory Forensics Launcher | Make (embed Volatility 3) | Volatility 3 is open-source (Volatility Foundation); embedding eliminates Python/pip dependency; value-add is parallel execution and fingerprinting |
| Forensic Triage Tool | Make (embed KAPE, PsExec, Hayabusa, EZ Tools) | All embedded tools are open-source or freely available; embedding eliminates multi-tool staging; value-add is single-binary deployment and remote orchestration |
| Atomic Red Team Executor | Make (embed ART YAML) | ART test library is MIT-licensed by Red Canary; embedding eliminates PowerShell module dependency; value-add is multi-threaded execution and structured reporting |
| Developer Tooling Plugin | Make | No existing Claude Code plugin provides structural indexing, duplicate detection, and governance enforcement across 56 languages |
| LLM Inference Engine | Buy (vLLM, open-source) | vLLM is the leading open-source inference engine; deployed on self-managed HotStuff hardware |
| Workstation Hardware | Make (hand-built) | No pre-built configuration met requirements; every component hand-sourced and assembled from bare HP Z8 G4 case |

### Procurement Summary

| Item | Source | Cost | License |
|------|--------|------|---------|
| HotStuff Workstation Components | Various (hand-sourced) | $25,000-$35,000 | N/A (hardware) |
| Atomic Red Team YAML Definitions | Red Canary (github.com/redcanaryco/atomic-red-team) | $0 | MIT |
| Volatility 3 | Volatility Foundation | $0 | Volatility Software License |
| KAPE | Kroll / Eric Zimmerman | $0 | Free for authorized use |
| PsExec | Microsoft Sysinternals | $0 | Sysinternals EULA |
| Hayabusa | Yamato Security | $0 | GPLv3 (not embedded; invoked externally) |
| Eric Zimmerman Tools | Eric Zimmerman | $0 | Free for authorized use |
| tree-sitter Grammars | Various open-source contributors | $0 | MIT |
| vLLM | UC Berkeley / vLLM Project | $0 | Apache 2.0 |
| GitHub | Microsoft | $0 (public repo) | Free tier |
| windoh.us Domain | Namecheap | ~$15/year | N/A |

---

## Integration Management

### Integrated Change Control

All changes are evaluated against the seven non-negotiable architectural principles. A change that violates any principle is rejected regardless of scope, schedule, or cost impact.

| Change Type | Approval Authority | Evaluation Criteria |
|------------|-------------------|-------------------|
| Documentation | Sole Author / PM | Accuracy, consistency, formatting |
| Bug Fix | Sole Author / PM | Does the fix preserve deterministic behavior? |
| Feature Addition | Sole Author / PM | Does the feature violate any architectural principle? Does it preserve idempotency? |
| Architecture Change | Sole Author / PM | Requires ADR. Must not weaken any trust boundary or introduce heuristic dependency. |
| Dependency Update | Sole Author / PM | Does the update change behavior (determinism risk)? Is the license compatible? |
| Scope Change | Sole Author / PM | Evaluated against M1-M7 milestone sequence. Cross-platform expansion gated behind M4. |

### Configuration Management

| Configuration Item | Version | Baseline |
|-------------------|---------|----------|
| LongHorizons Agent | Pre-release (validating) | config.toml, 47-provider ETW session |
| WindOH Application | Pre-release (deployment pending) | Next.js 14, tRPC, MongoDB 7, BullMQ |
| LessAtomic | v0.1.0 | 265 techniques, 752 tests, Rayon thread pool |
| LessVolatile | v0.2.0 | 68 Windows, 29 Linux, 26 macOS plugins |
| OneDriveStandaloneUpdaterr | Released | 4-dimension collection, PsExec remote |
| LessToil | Released | 40 modules, 56 languages, 26 tables |
| HotStuff Workstation | Operational | 96 threads, 1.5 TB ECC, 64 GB VRAM, CUDA 13.1 |
| Project Documentation | v1.0 (Assembly complete) | 20+ markdown files, 4 GIFs, 2 PNGs |

### Lessons Learned

| ID | Category | Observation | Recommendation |
|----|----------|------------|---------------|
| LL1 | Schedule | Sole-author execution means all roles serialize through one person. Parallelism in development is limited by context-switching cost, not by task availability. | For future sole-author projects, batch similar-language work to reduce context-switching overhead. Develop the developer-tooling component (LessToil) earlier -- it accelerates all subsequent phases. |
| LL2 | Quality | Deterministic tokenization is a hard constraint that simplifies testing: same input always produces same output. This eliminated entire categories of flaky-test debugging that plague heuristic systems. | Prefer deterministic over heuristic at every architectural decision point. The testing simplification alone justifies the engineering cost. |
| LL3 | Procurement | Embedding third-party tools at compile time (Volatility 3, Python 3.9, KAPE, ART YAML) eliminates runtime dependency hell but increases build complexity and binary size. | Accept the trade-off. The user experience of "one binary, no dependencies" is worth the build engineering investment. The absence of "works on my machine" support issues is unquantifiable but real. |
| LL4 | Integration | LessToil was developed last but should have been developed first. The 3-day Assembly phase would have been a 2-3 week effort without structural codebase intelligence. | Develop codebase intelligence tooling early in any multi-component project. The index pays for itself at the first cross-reference validation. |
| LL5 | Resources | Hand-building the HotStuff workstation was a project within the project. Component sourcing, compatibility validation, and assembly added non-trivial effort outside the development schedule. | Treat infrastructure build as a formal work package with its own WBS, schedule, and cost baseline. Do not assume "buy a workstation" is a one-line procurement item when specification exceeds pre-built configurations. |
| LL6 | Communications | Sole-author projects can defer documentation without consequence during development, but generate a documentation debt cliff at release. | Maintain documentation concurrently with development. The 3-day Assembly phase was efficient but intense. Concurrent documentation would have spread this effort across 12 months at lower intensity. |
| LL7 | Risk | The sole-author risk (R1) cannot be mitigated through redundancy in a one-person project. The only viable mitigation is documentation quality and architectural clarity sufficient for a future contributor to onboard without the original author. | Invest in ADRs, architecture diagrams, and code comments as if onboarding a replacement tomorrow. LessToil structural indexing makes this investment discoverable and usable. |

---

## Appendices

### Appendix A: Key Performance Indicators

| KPI | Definition | Baseline | Target | Actual |
|-----|-----------|----------|--------|--------|
| **Time-to-detect (TTD)** | Mean time from ETW event to enriched token in MongoDB | N/A (no existing pipeline) | <30 seconds | Under validation (M4) |
| **Storage efficiency** | Reduction in stored event volume vs. raw ETW | 100% (raw events) | >90% reduction | 90-99% (measured) |
| **Enrichment efficiency** | Cache hit rate for payload token enrichment | 0% (no cache) | >99% at steady state | Target (pre-M5) |
| **Forensic throughput** | Time to process one memory dump (68 plugins) | 3 hours (manual) | <10 minutes | 5 minutes (measured) |
| **Test execution throughput** | Time to execute 752 atomic tests (8-core workstation) | 6-12 hours (Invoke-Atomic) | <2 hours | 40-90 minutes (measured) |
| **Codebase intelligence coverage** | Languages and file types indexable | 0 | >50 languages | 56 languages (measured) |

### Appendix B: PMP Process Group Mapping

| Process Group | Activities in WindOH |
|--------------|---------------------|
| **Initiating** | Project Charter, Stakeholder Identification, Business Case |
| **Planning** | Scope Statement, WBS, Schedule Baseline, Cost Baseline, Quality Metrics, Resource Plan, Communications Matrix, Risk Register, Procurement Plan |
| **Executing** | Development (Phases I-VI), Infrastructure Build, Documentation, Release Packaging |
| **Monitoring and Controlling** | Earned Value Analysis, Risk Monitoring, Quality Audits against Architectural Principles, Scope Verification against WBS |
| **Closing** | Release (M1, M2, M3 complete), Documentation Assembly (Phase VI), Lessons Learned, Stakeholder Transition to Adoption Phase |

### Appendix C: Knowledge Area Mapping

| Knowledge Area | WindOH Application |
|---------------|-------------------|
| **Integration** | LessToil structural index as integration management tool; ADR process for integrated change control |
| **Scope** | WBS (7 work packages, 50+ deliverables); scope verified against architectural principles |
| **Schedule** | 6-phase timeline; critical path through Foundation phase; 3-day Assembly enabled by LessToil |
| **Cost** | $428k-$440k total estimated investment; EVM shows on-budget delivery |
| **Quality** | 7 non-negotiable architectural principles as quality baseline; component-level metrics |
| **Resources** | 1 engineer performing 8 distinct roles; HotStuff workstation as physical resource |
| **Communications** | 24 documents across 8 directories; stakeholder-specific messaging by adoption phase |
| **Risk** | 10 identified risks; R1 (sole author) accepted; all others mitigated |
| **Procurement** | 11 third-party dependencies; all open-source or freely available; hardware hand-sourced |
| **Stakeholder** | 6 stakeholder groups; 3-phase engagement plan (Awareness -> Adoption -> Community) |

---

<div align="center">

```
+====================================================================+
|                                                                    |
|    WindOH Project Management Plan                                   |
|                                                                    |
|    PMBOK Guide Seventh Edition aligned.                            |
|    PMP-certified project management.                                |
|    Sole-author execution. Five binaries. One platform.              |
|                                                                    |
|    12 months. 2,000 hours. $428k-$440k estimated investment.       |
|    7 non-negotiable architectural principles.                       |
|    10 identified risks. 7 lessons learned.                          |
|                                                                    |
+====================================================================+
```

</div>
