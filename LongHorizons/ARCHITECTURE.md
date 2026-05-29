# Architecture — LongHorizons Telemetry Agent

## Crate Map

```mermaid
graph TB
    subgraph service ["agent-service (binary crate)"]
        main["main.rs, service.rs<br/>health.rs, diagnostic.rs<br/>Windows service wrapper + CLI"]
    end

    subgraph etw ["agent-etw"]
        etw_files["session.rs<br/>mapping.rs<br/>tdh.rs"]
    end

    subgraph core ["agent-core"]
        core_files["models.rs<br/>config.rs<br/>pipeline.rs<br/>tokenization.rs<br/>db.rs<br/>crypto.rs<br/>cms.rs<br/>reservoir.rs"]
    end

    subgraph exporter ["agent-exporter"]
        exp_files["shipper.rs<br/>(ES bulk API)<br/>outbox polling<br/>retry+deadletter"]
    end

    service --> etw
    service --> core
    service --> exporter
```

---

## Event Lifecycle

### Phase 1: ETW Capture (`agent-etw`)

```mermaid
flowchart TD
    A["StartTraceW()"] --> B["EnableTraceEx2<br/>(47 providers)"]
    B --> C["OpenTraceW()"]
    C --> D["ProcessTrace()<br/>callback"]
    D --> E["EVENT_RECORD"]
    E --> F["TdhGetEventInformation()<br/>TdhGetProperty() × N"]
    F --> G["HashMap&lt;String, Value&gt;"]
    G --> H["mapping.rs::map_event()"]
    H --> I["NormalizedEvent"]
```

**Key decisions:**
- Real-time session (EVENT_RECORD, not log-file mode)
- All 47 providers enabled in a single kernel session (where applicable) + user-mode sessions
- TDH parses provider manifests to resolve property names and types
- Semantic mapping uses event IDs and opcodes to classify events into types (`process_start`, `network_connect`, `dns_query`, etc.)

### Phase 2: Normalization & Enrichment (`agent-core/sharded_pipeline.rs`)

```mermaid
flowchart TD
    A[NormalizedEvent] --> B
    subgraph pipeline ["7-Stage Pipeline"]
        B["1. populate_process_cache_inner()<br/>Fill PID → image path, command line,<br/>modules, parent lineage, logon session"]
        C["2. populate_logon_session_cache()<br/>On user_logon events:<br/>store logon_id → (type, guid)"]
        D["3. compute_enrichments()<br/>Inter-event timing · Preceding token<br/>Tree depth · Ancestor chain hash<br/>Behavior tags (11) · Burst metrics<br/>First-seen binary · Process classification<br/>Network correlation · PE metadata<br/>Logon session · Field completeness"]
        E["4. extract_terms()<br/>Tokenize search terms<br/>from key field values"]
        F["5. build_tokens()<br/>Generate stable_hash (what)<br/>and payload_hash (exact)"]
        G["6. update_enrichment_post_tokens()<br/>Store last tokens for next-event<br/>preceding reference · Update payload<br/>deviation scores"]
        H["7. pick_shard() → shard.ingest()<br/>Route event to 1 of 8 shards<br/>by stable_hash[..8]"]
    end
    B --> C --> D --> E --> F --> G --> H
```

**Why 8 shards:** Lock contention elimination. Each shard has its own CMS, reservoir, and process cache. Tokenization runs once; the stable hash deterministically routes to one shard.

**Token determinism guarantee:** All new enrichment fields use `#[serde(skip_serializing_if = "Option::is_none")]` and are NOT added to token builders. The stable_hash and payload_hash are computed from a controlled subset of NormalizedEvent fields only.

### Phase 3: Baselining (`agent-core/pipeline.rs`)

```mermaid
flowchart TD
    A["shard.ingest_event_with_pretokenized<br/>(event, tokens)"] --> B
    subgraph baselining ["Baselining Pipeline"]
        B["db.upsert_stable_token(stable_hash)<br/>→ Returns: is_new_stable, decay_score,<br/>  rarity_band, times_seen"]
        C["cms.observe(stable_hash)<br/>Count-Min Sketch increment<br/>for global frequency"]
        D["Promoted exact counter<br/>(for payload variants)<br/>If observation count > threshold:<br/>exact counting"]
        E["reservoir.offer(stable_hash, event)<br/>Reservoir sampling with<br/>richness scoring"]
        F["If new_stable or boundary_cross or risk:<br/>Write exemplar document to outbox"]
        G["If rarity ≤ export_threshold_score:<br/>Write event document to outbox"]
    end
    B --> C --> D --> E --> F --> G
```

**Decay scoring:**
```
score = base_count × e^(-λ × days_since_last_seen)
λ = ln(2) / decay_half_life_days
```

Rarity bands are computed from the decay score against `rare_threshold` and `common_threshold`.

### Phase 4: Export (`agent-exporter`)

```mermaid
flowchart TD
    A["OutboxWorker<br/>(background thread)"] --> B
    B["SELECT * FROM outbox<br/>WHERE sent = 0<br/>ORDER BY priority, created_at"]
    B --> C["Batch assembly<br/>(up to bulk_max_docs<br/>or bulk_max_bytes)"]
    C --> D["POST /_bulk<br/>(gzip compressed)"]
    D --> E{Result}
    E -->|"Success"| F["Mark sent"]
    E -->|"Failure"| G["Increment attempt counter"]
    G --> H{"attempts > max?"}
    H -->|"Yes"| I["Dead letter"]
    H -->|"No"| J["Reschedule with backoff"]
```

---

## Database Schema (`agent.db`)

| Table | Purpose |
|---|---|
| `stable_tokens` | Decay scores, rarity bands, observation counts per stable hash |
| `payload_variants` | Exact counters for promoted payload hashes |
| `exemplar_outbox` | Queued exemplar documents awaiting export |
| `event_outbox` | Queued event documents awaiting export |
| `pattern_outbox` | Queued pattern/aggregation documents |
| `diagnostic_outbox` | Queued diagnostic documents |
| `process_cache` | Recently seen process identities (PID → metadata) |

All sensitive columns (`api_key`, `sealed_blob`) are AES-256-GCM encrypted with per-purpose HKDF-derived keys.

---

## Config Defaults Philosophy

The agent ships with **maximum data collection** defaults:

- **All 47 ETW providers enabled** — omit any in config to suppress
- **Provider mode "all"** — auto-discovers every registered ETW provider
- **All 4 export pipelines enabled** — exemplars, events, patterns, diagnostics
- **Fixed index names** — `longhorizons-events`, `longhorizons-exemplars`, `longhorizons-patterns`, `longhorizons-diagnostics`

To reduce data volume, explicitly set providers to `false` and adjust `baselining.export_threshold_score` lower.

---

## Concurrency Model

```mermaid
flowchart LR
    subgraph main ["Main Thread"]
        A["Agent::run()"]
        A1["ETW session start"]
        A2["Exporter worker (tokio)"]
        A3["Config reload watcher"]
        A4["Health HTTP server"]
    end

    subgraph callback ["ETW Callback Thread"]
        B["ProcessTrace() callback"]
        B1["TDH parse"]
        B2["map_event()"]
        B3["sender.send(event)"]
    end

    subgraph pipeline ["ShardedPipeline"]
        C["ingest_event()"]
        C1["lock(shared_process_cache)"]
        C2["lock(shared_enrichment)<br/>← parking_lot::Mutex"]
        C3["build_tokens()"]
        C4["pick_shard(hash)"]
        C5["lock(shards[idx])<br/>← Mutex per shard"]
        D["BaseliningPipeline::ingest()"]
    end

    B3 --> C
    C --> C1 --> C2 --> C3 --> C4 --> C5 --> D
```

**Key design decisions:**
- `parking_lot::Mutex` everywhere — no async locks in the hot path
- 8 shards → 8 independent locks → minimal contention
- Shared caches (process identity, enrichment state) are locked briefly for read/write then released
- Database connection pool not needed — SQLite WAL mode handles concurrent readers + single writer

---

## Security Model

```mermaid
flowchart TD
    A["Machine Boot"] --> B["Generate master_key<br/>(256-bit random)"]
    B --> C["DPAPI::Protect<br/>(LocalMachine, master_key)"]
    C --> D["Write to state_dir/<br/>master_key.bin"]
    D --> E["Derive purpose keys:"]
    E --> F1["HKDF-SHA256(master_key,<br/>salt='outbox', info='agent.db')<br/>→ outbox_key"]
    E --> F2["HKDF-SHA256(master_key,<br/>salt='patterns', info='agent.db')<br/>→ patterns_key"]
    E --> F3["..."]
    F1 --> G["Encrypt sensitive fields<br/>before DB write:"]
    F2 --> G
    F3 --> G
    G --> H["AES-256-GCM(purpose_key, nonce, plaintext)<br/>→ (ciphertext, tag)"]
```

On subsequent starts, the master key is decrypted from DPAPI and purpose keys are re-derived.

**TLS pinning** (optional): per-endpoint `tls_pins_sha256` list validates server certificate fingerprints before any data is sent.
