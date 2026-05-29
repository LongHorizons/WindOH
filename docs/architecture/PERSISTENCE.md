# Persistence Architecture

## Storage Landscape

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              STORAGE MAP                                  │
│                                                                           │
│  ┌──────────────────────────┐   ┌──────────────────────────┐             │
│  │ Agent (per endpoint)     │   │ Application              │             │
│  │                          │   │                          │             │
│  │ SQLite                   │   │ MongoDB                  │             │
│  │ ├── tokens               │   │ ├── tokens               │             │
│  │ │   base_token (PK)     │   │ │   base_token (unique)  │             │
│  │ │   count, decay_score   │   │ │   enrichment (cached)   │             │
│  │ │   rarity_band          │   │ │   payload_tokenes[]      │             │
│  │ │   last_seen_at         │   │ │   rarity                │             │
│  │ ├── events               │   │ ├── events               │             │
│  │ │   base_token (FK)     │   │ │   agent.id + ts         │             │
│  │ │   payload_token         │   │ │   full event document   │             │
│  │ │   full event json      │   │ ├── event_sequences       │             │
│  │ ├── outbox               │   │ │   agent.id (unique)     │             │
│  │ │   payload              │   │ │   sequence[] (ordered)  │             │
│  │ │   created_at           │   │ ├── markov_transitions    │             │
│  │ ├── outbox_dead_letter   │   │ │   from_hash → to_hash   │             │
│  │ │   payload, error       │   │ │   count, probability    │             │
│  │ └── diagnostics          │   │ ├── atomic_tests          │             │
│  │                          │   │ │   technique → hashes[]  │             │
│  └──────────────────────────┘   │ └── search_cache          │             │
│                                  │     query_hash → results  │             │
│                                  │                          │             │
│  ┌──────────────────────────┐   │ Redis                    │             │
│  │ Elasticsearch (transport)│   │ ├── BullMQ queues         │             │
│  │                          │   │ ├── Session store         │             │
│  │ ├── longhorizons-events  │   │ └── Rate limiter state    │             │
│  │ ├── longhorizons-exemp.  │   │                          │             │
│  │ ├── longhorizons-patterns│   │                          │             │
│  │ └── longhorizons-diag.   │   │                          │             │
│  └──────────────────────────┘   └──────────────────────────┘             │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

## Agent-Side Storage (SQLite)

**Why SQLite on the endpoint:**
- Zero-configuration — no database server to install or manage on 1,000+ endpoints
- WAL mode provides concurrent read (exporter) and write (pipeline) access with single-writer semantics
- Atomic writes — the outbox pattern requires that event insert and outbox insert commit together or not at all
- A single file is easy to backup, vacuum, and delete when retention expires
- Encryption at rest via SQLCipher or application-layer AES-256-GCM before write

**Data lifecycle:**
```
Event Received → Tokenized → Inserted into events + tokens tables (same TX)
    │
    ▼
Outbox: INSERT INTO outbox (payload) VALUES (serialized_batch)
    │
    ▼
Exporter: SELECT batch → gzip → ES bulk API → DELETE FROM outbox WHERE id IN (batch)
    │
    ▼
Retention: DELETE FROM events WHERE timestamp < now() - retention_days
              (tokens table persists — it's the behavioral baseline)
```

**Table sizing (per endpoint, 1-year estimate):**
- `tokens`: ~10K-100K rows, ~5-50 MB (one per unique `base_token`)
- `events`: ~10M-50M rows, ~500 MB-2 GB (one per event, 90-day retention)
- `outbox`: typically 0-500 rows, <10 MB

## Application-Side Storage (MongoDB)

**Why MongoDB for the intelligence application:**
- Document-native — enrichment produces variable-depth nested JSON; relational normalization would fragment it
- Schema flexibility — new enrichment fields, flags, and metadata can be added without migration
- Atlas Search provides full-text search on token descriptions without a separate search engine
- Aggregation pipeline directly computes the Markov transition matrix, avoiding application-level ETL

**Collection design:**

### `tokens` — The Core Knowledge Base

One document per unique `base_token`. This is the permanent behavioral knowledge base.

```
{
  _id: ObjectId,
  base_token: "abc123...",     // Unique index
  first_seen: ISODate,
  last_seen: ISODate,
  observation_count: 1423,
  decay_score: 0.87,
  rarity_band: "common",
  payload_tokenes: ["def456...", "ghi789..."],  // Top K variants
  enrichment: {
    description: "...",
    mitre_techniques: [{id: "T1059.001", name: "PowerShell", confidence: 0.9}],
    risk_assessment: {level: "medium", rationale: "..."},
    flags: {lolbin: true, exfiltration: false, ...},
    investigation_steps: ["...", "..."],
    model_name: "llama-3-8b-instruct",
    enriched_at: ISODate,
    raw_prompt: "...",
    raw_response: "{...}"
  }
}
```

### `event_sequences` — Temporal Chains

One document per agent, maintaining an ordered sequence of `base_token` values.

```
{
  _id: ObjectId,
  agent_id: "host-001",
  sequence: [
    {hash: "abc123...", ts: ISODate, inter_event_delta_ms: 0},
    {hash: "def456...", ts: ISODate, inter_event_delta_ms: 1450},
    ...
  ],
  sequence_length: 50000,   // Rolling window (configurable)
  updated_at: ISODate
}
```

Sequence documents use a rolling window — oldest entries are trimmed when sequence exceeds configurable max length. The Markov model uses the window as its training corpus.

### `markov_transitions` — Pre-Computed Transition Matrix

Computed hourly via aggregation pipeline on `event_sequences`.

```
{
  _id: ObjectId,
  from_hash: "abc123...",
  to_hash: "def456...",
  count: 1400,
  probability: 0.23,
  avg_inter_event_delta_ms: 3240,
  host_count: 87,            // Cross-host prevalence
  updated_at: ISODate
}
```

**Aggregation pipeline:**
```javascript
db.event_sequences.aggregate([
  {$unwind: {path: "$sequence", includeArrayIndex: "idx"}},
  {$sort: {"agent_id": 1, "idx": 1}},
  {$group: {
    _id: "$agent_id",
    transitions: {
      $push: {
        from: "$sequence.hash",
        to: {$arrayElemAt: ["$sequence.hash", {$add: ["$idx", 1]}]}
      }
    }
  }},
  // Unwind transitions, group by (from, to), compute probabilities
]);
```

## Cache Strategy

| Cache | Store | TTL | Invalidation |
|---|---|---|---|
| LLM enrichment | MongoDB tokens | Permanent | Explicit operator action |
| Markov transition matrix | MongoDB markov_transitions | Rebuilt hourly | Full rebuild on schedule |
| SearXNG results | MongoDB search_cache | Configurable (default 24h) | TTL index |
| Token rarity bands | Agent SQLite | Score recalculated per-event | Decay function applied at query time |
| Process cache | Agent in-memory HashMap | LRU eviction | Re-populated from next event per PID |

## Session Durability

**Agent:** The SQLite database is the agent's durable state. If the agent process crashes:
- Outbox events are durable (committed to SQLite before export)
- Token baselines persist across restarts
- CMS state is in-memory only and lost on restart — reconstructed from SQLite tokens table on startup

**WindOH:** BullMQ job state is durable in Redis (AOF persistence enabled). Worker crashes do not lose jobs — BullMQ re-queues active jobs on worker heartbeat timeout. MongoDB connection pool auto-reconnects.

## Backups

| Store | Method | Frequency |
|---|---|---|
| Agent SQLite | File copy (WAL checkpoint first) or `sqlite3 .backup` | Agent deployment script |
| MongoDB | `mongodump` to `/backups/mongodb/` | Daily (cron) |
| Redis | AOF file (appendonly yes) | Continuous |
| Elasticsearch | Snapshot API to S3/shared storage | Daily (ES snapshot lifecycle) |
