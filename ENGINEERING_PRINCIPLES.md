# Engineering Principles

This document records the design principles that govern all components of the WindOH platform. Each principle includes the rationale for why it was adopted and the observable consequences it imposes on the system.

---

## 1. Deterministic Over Heuristic

**Rule:** Behavioral identity, forensic fingerprints, and structural analysis use cryptographic hashes (SHA-256), not machine learning embeddings or probabilistic models.

**Rationale:** A hash either matches or it doesn't. There is no confidence score to tune, no threshold to argue about, no training distribution to drift from. Two memory captures either share a process fingerprint or they don't. Two ETW events either represent the same behavior or they don't. This is court-admissible, SIEM-ingestible, and immune to adversarial evasion that targets ML models.

**Consequences:**
- `base_token` generation must be fully deterministic — same inputs, same hash, across any host, at any time
- All enrichment fields that are non-deterministic (timestamps, counters, PIDs) are excluded from hash computation via `#[serde(skip_serializing_if)]`
- Cross-host behavioral comparison is a hash join, not a similarity search
- No embedding vectors, no vector databases, no cosine similarity thresholds

---

## 2. Local-First Over Cloud-Dependency

**Rule:** All inference, enrichment, and analysis that can run locally must run locally. External services are optional transport layers, not operational dependencies.

**Rationale:** Security telemetry contains the most sensitive data an organization possesses — process trees, command lines, network targets, user identities. Routing this through cloud APIs creates an exfiltration surface. Local LLM inference (llama.cpp, Ollama, vLLM) provides the enrichment capability without the data sovereignty risk. The agent runs fully independently even when Elasticsearch is unreachable.

**Consequences:**
- LLM enrichment targets a configurable OpenAI-compatible endpoint (default: localhost)
- No telemetry data transits the public internet for enrichment under any configuration
- The agent operates indefinitely without network connectivity — buffers to local SQLite
- Elasticsearch is an export target, not a runtime dependency

---

## 3. Observable Over Opaque

**Rule:** Every automated decision must carry provenance — the inputs that produced it, the logic that transformed them, and the confidence or probability associated.

**Rationale:** Security analysts cannot act on black-box outputs. "Risk score: 0.87" is useless. "Risk: HIGH because this process lineage (cmd.exe → wmic.exe → powershell.exe -enc) matches a known LOLBin pattern with rarity 0.2% across the fleet" is actionable.

**Consequences:**
- Rarity bands include the decay score, observation count, and half-life parameters
- Markov anomaly flags include the transition probability, observation count, and the expected next behavior
- LLM enrichment includes the full prompt template and raw response before parsing
- Every diagnostic document in Elasticsearch carries a `diagnostic_version` and field-level provenance

---

## 4. Safe-By-Default

**Rule:** Sensitive data is encrypted at rest. Authentication is mandatory at trust boundaries. The default configuration must be secure even if the operator changes nothing.

**Rationale:** Default configurations ship to production. "You can enable encryption" means it won't be enabled.

**Consequences:**
- AES-256-GCM encryption at rest is mandatory, not optional
- Master key protected by DPAPI (Windows Data Protection API) — tied to the service account
- Purpose-specific encryption keys derived via HKDF-SHA256 (one per data category)
- Elasticsearch connections require API key authentication
- Config file contains no plaintext credentials (DPAPI-encrypted secrets or environment variables)

---

## 5. Graceful Degradation

**Rule:** No component failure cascades. Every subsystem must operate in a degraded mode when dependencies are unavailable, and recover automatically when they return.

**Rationale:** In security operations, partial data is better than no data. A telemetry gap of 10 minutes is better than a crash loop that loses hours.

**Consequences:**
- Agent: Elasticsearch unavailable → buffer to SQLite outbox → retry with exponential backoff → dead-letter after N attempts
- WindOH: LLM unavailable → enrichment jobs remain queued in BullMQ → retry with backoff
- WindOH: MongoDB unavailable → API returns 503 with health check failure → connection pool auto-reconnect
- LessVolatile: Plugin failure → marked ✗ in output → processing continues → fingerprint built from successful plugins
- All components: structured health check endpoints return dependency status (healthy / degraded / critical)

---

## 6. Human-Overridable

**Rule:** Every automated decision is an annotation, not an enforcement action. The system recommends; the analyst decides.

**Rationale:** Automated blocking in security contexts produces false positives that interrupt legitimate operations. The platform's role is to reduce the investigation surface from "every event" to "rare and surprising events," then provide the analyst with all available context — not to take action on their behalf.

**Consequences:**
- No automated blocking, quarantining, or process termination
- Rarity bands and anomaly flags are annotations on events, not routing rules
- The Markov anomaly detector flags transitions for review; it does not suppress or escalate them
- All automated risk assessments include explicit rationale the analyst can evaluate

---

## 7. Reproducible Execution

**Rule:** Given the same inputs, the system must produce identical outputs. Idempotency is a design constraint, not an optimization.

**Rationale:** Incident response findings must be reproducible to be court-admissible. Detection coverage measurements must be repeatable to be auditable. LLM enrichment must be cached to be cost-effective and consistent.

**Consequences:**
- Same memory dump → same SHA-256 fingerprint for processes, services, modules, network profiles
- Same ETW behavior → same `base_token` independent of host, time, or session
- Same `base_token` → same LLM enrichment (enrich once, cache permanently, never re-enrich)
- Same git commit → same LessToil index (deterministic tree-sitter parsing + SHA-256 file identity)

---

## 8. Explicit Boundaries

**Rule:** Service boundaries, trust boundaries, and ownership domains are explicitly defined and documented. Components communicate through well-defined interfaces, not shared state.

**Rationale:** Sprawling systems with implicit coupling are impossible to operate, debug, or secure. Each component should be understandable in isolation, with clear contracts at every boundary.

**Consequences:**
- Agent → Elasticsearch: gzip-compressed JSON bulk API, configurable batch size and flush interval
- Elasticsearch → WindOH: polling with configurable interval, idempotent upsert by `base_token`
- WindOH → LLM: OpenAI-compatible chat completions API, structured JSON response format
- All cross-component communication uses explicit schemas, not ad-hoc formats
- Each component can be developed, tested, and deployed independently

---

## Decision Framework

When a design decision is disputed or unclear, defer to these principles in order:

1. **Safety** (principle 4) — does this change create a security risk?
2. **Determinism** (principle 1) — does this change make behavior non-reproducible?
3. **Observability** (principle 3) — can an operator inspect what happened and why?
4. **Graceful degradation** (principle 5) — does this change create a cascading failure risk?
5. **Local-first** (principle 2) — does this change create a cloud dependency?

If a decision satisfies all five, it is architecturally sound. If it violates any of the first three, it requires explicit justification documented as an ADR.
