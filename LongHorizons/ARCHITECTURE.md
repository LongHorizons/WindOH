# Architecture — LongHorizons Telemetry Agent

## Crate Map

```
┌────────────────────────────────────────────────────────────────┐
│ agent-service (binary crate)                                    │
│   main.rs, service.rs, health.rs, diagnostic.rs                 │
│   Windows service wrapper + CLI (install / run / test /         │
│   uninstall). Orchestrates all other crates.                    │
└──────────┬──────────┬──────────────┬────────────────────────────┘
           │          │              │
    ┌──────▼───┐ ┌───▼──────┐ ┌─────▼──────────┐
    │agent-etw  │ │agent-core│ │agent-exporter   │
    │           │ │          │ │                 │
    │session.rs │ │models.rs │ │shipper.rs       │
    │mapping.rs │ │config.rs │ │(ES bulk API)    │
    │tdh.rs     │ │pipeline  │ │outbox polling   │
    │           │ │tokenizat.│ │retry+deadletter │
    └───────────┘ │db.rs     │ └─────────────────┘
                  │crypto.rs │
                  │cms.rs    │
                  │reservoir │
                  └──────────┘
```

---

## Event Lifecycle

### Phase 1: ETW Capture (`agent-etw`)

```
StartTraceW() → EnableTraceEx2(47 providers) → OpenTraceW()
                                                    │
                    ProcessTrace() ◄── callback ────┘
                         │
                    EVENT_RECORD
                         │
                    TdhGetEventInformation()
                    TdhGetProperty() × N
                         │
                    HashMap<String, Value>
                         │
                    mapping.rs::map_event()
                         │
                    NormalizedEvent
```

**Key decisions:**
- Real-time session (EVENT_RECORD, not log-file mode)
- All 47 providers enabled in a single kernel session (where applicable) + user-mode sessions
- TDH parses provider manifests to resolve property names and types
- Semantic mapping uses event IDs and opcodes to classify events into types (`process_start`, `network_connect`, `dns_query`, etc.)

### Phase 2: Normalization & Enrichment (`agent-core/sharded_pipeline.rs`)

```
NormalizedEvent
      │
  ┌───▼────────────────────────────────────────────────────┐
  │ 1. populate_process_cache_inner()                       │
  │    Fill PID → image path, command line, modules,        │
  │    parent lineage, logon session from shared cache       │
  ├────────────────────────────────────────────────────────┤
  │ 2. populate_logon_session_cache()                       │
  │    On user_logon events: store logon_id → (type, guid)  │
  ├────────────────────────────────────────────────────────┤
  │ 3. compute_enrichments()                                │
  │    • Inter-event timing (delta from prev/start)         │
  │    • Preceding token reference (what did this PID do?)  │
  │    • Tree depth (parent → grandparent chain depth)      │
  │    • Ancestor chain hash (SHA-256 of image chain)       │
  │    • Behavior tags (11 boolean heuristics)              │
  │    • Burst metrics (events in 5s/60s windows)           │
  │    • First-seen binary detection (HashSet)              │
  │    • Process classification (signed/unsigned/etc.)      │
  │    • Network cross-process correlation                  │
  │    • PE metadata (compile timestamp, sections, imports) │
  │    • Logon session metadata lookup                      │
  │    • Field completeness score                           │
  ├────────────────────────────────────────────────────────┤
  │ 4. extract_terms()                                      │
  │    Tokenize search terms from key field values          │
  ├────────────────────────────────────────────────────────┤
  │ 5. build_tokens()                                       │
  │    Generate stable_hash (what) and payload_hash (exact) │
  ├────────────────────────────────────────────────────────┤
  │ 6. update_enrichment_post_tokens()                      │
  │    Store last tokens for next-event preceding reference │
  │    Update payload deviation scores                      │
  ├────────────────────────────────────────────────────────┤
  │ 7. pick_shard() → shard.ingest()                        │
  │    Route event to 1 of 8 shards by stable_hash[..8]     │
  └────────────────────────────────────────────────────────┘
```

**Why 8 shards:** Lock contention elimination. Each shard has its own CMS, reservoir, and process cache. Tokenization runs once; the stable hash deterministically routes to one shard.

**Token determinism guarantee:** All new enrichment fields use `#[serde(skip_serializing_if = "Option::is_none")]` and are NOT added to token builders. The stable_hash and payload_hash are computed from a controlled subset of NormalizedEvent fields only.

### Phase 3: Baselining (`agent-core/pipeline.rs`)

```
shard.ingest_event_with_pretokenized(event, tokens)
      │
  ┌───▼─────────────────────────────────────────────┐
  │ db.upsert_stable_token(stable_hash)              │
  │   → Returns: is_new_stable, decay_score,         │
  │     rarity_band, times_seen                     │
  ├─────────────────────────────────────────────────┤
  │ cms.observe(stable_hash)                          │
  │   Count-Min Sketch increment for global frequency │
  ├─────────────────────────────────────────────────┤
  │ Promoted exact counter (for payload variants)     │
  │   If observation count > threshold: exact counting │
  ├─────────────────────────────────────────────────┤
  │ reservoir.offer(stable_hash, event)               │
  │   Reservoir sampling with richness scoring        │
  ├─────────────────────────────────────────────────┤
  │ If new_stable || boundary_cross || risk:         │
  │   Write exemplar document to outbox               │
  ├─────────────────────────────────────────────────┤
  │ If rarity ≤ export_threshold_score:              │
  │   Write event document to outbox                  │
  └─────────────────────────────────────────────────┘
```

**Decay scoring:**
```
score = base_count × e^(-λ × days_since_last_seen)
λ = ln(2) / decay_half_life_days
```

Rarity bands are computed from the decay score against `rare_threshold` and `common_threshold`.

### Phase 4: Export (`agent-exporter`)

```
OutboxWorker (background thread)
      │
      ▼
  SELECT * FROM outbox WHERE sent = 0
  ORDER BY priority, created_at
      │
      ▼
  Batch assembly (up to bulk_max_docs or bulk_max_bytes)
      │
      ▼
  POST /_bulk (gzip compressed)
      │
  ┌───┴───┐
  │       │
Success  Failure
  │       │
  ▼       ▼
Mark    Increment attempt counter
sent    If attempts > max: dead letter
        Else: reschedule with backoff
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

```
Main Thread                    ETW Callback Thread
─────────────                  ────────────────────
Agent::run()                   ProcessTrace() callback
  │                              │
  ├─ ETW session start           ├─ TDH parse
  ├─ Exporter worker (tokio)     ├─ map_event()
  ├─ Config reload watcher       └─ sender.send(event)
  └─ Health HTTP server                │
                                       ▼
                              ShardedPipeline::ingest_event()
                                │
                                ├─ lock(shared_process_cache)
                                ├─ lock(shared_enrichment)  ← parking_lot::Mutex
                                ├─ build_tokens()
                                ├─ pick_shard(hash)
                                └─ lock(shards[idx])        ← Mutex per shard
                                     │
                                     ▼
                              BaseliningPipeline::ingest()
```

**Key design decisions:**
- `parking_lot::Mutex` everywhere — no async locks in the hot path
- 8 shards → 8 independent locks → minimal contention
- Shared caches (process identity, enrichment state) are locked briefly for read/write then released
- Database connection pool not needed — SQLite WAL mode handles concurrent readers + single writer

---

## Security Model

```
Machine Boot
      │
      ▼
  Generate master_key (256-bit random)
      │
      ▼
  DPAPI::Protect(LocalMachine, master_key)
      │
      ▼
  Write to state_dir/master_key.bin
      │
      ▼
  Derive purpose keys:
    HKDF-SHA256(master_key, salt="outbox",   info="agent.db") → outbox_key
    HKDF-SHA256(master_key, salt="patterns", info="agent.db") → patterns_key
    ...
      │
      ▼
  Encrypt sensitive fields before DB write:
    AES-256-GCM(purpose_key, nonce, plaintext) → (ciphertext, tag)
```

On subsequent starts, the master key is decrypted from DPAPI and purpose keys are re-derived.

**TLS pinning** (optional): per-endpoint `tls_pins_sha256` list validates server certificate fingerprints before any data is sent.
