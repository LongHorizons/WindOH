# Failure Handling

This document specifies how each component behaves under failure conditions. Every failure mode listed here is handled explicitly — the system does not rely on crash-only design or supervisor-based recovery for data integrity.

---

## Failure Mode Inventory

### LongHorizons Agent

| Failure | Detection | Immediate Behavior | Recovery | Data Loss Risk |
|---|---|---|---|---|
| ETW session lost | `ControlTrace()` returns error on health check interval | Health status → DEGRADED; pipeline continues processing buffered events | Automatic session restart with 1s/5s/15s/30s exponential backoff | Buffered events in memory may be lost (~500ms window) |
| Elasticsearch unreachable | Bulk API returns connection error or 5xx | Events buffered to SQLite outbox; health → DEGRADED | Retry with exponential backoff (1s → 5m max); dead-letter after configurable max attempts (default 100) | None — durable SQLite outbox |
| Disk full | Write to SQLite returns SQLITE_FULL | Pipeline pauses; health → CRITICAL; agent remains alive for diagnostics | Manual intervention required; space guard pre-checks prevent reaching this state under normal conditions | Events after disk full are dropped (acceptable: disk full is a CRITICAL operational failure) |
| DPAPI unavailable | Key derivation fails | Agent fails to start; logs CRITICAL error and exits | Manual intervention — indicates Windows cryptographic subsystem failure | None — agent refuses to start without encryption |
| Process cache overflow | Cache entry count exceeds configurable max | LRU eviction of oldest entries; health → DEGRADED | Automatic; evicted entries re-populated on next event from that PID | Low — evicted PIDs re-enter cache on next event |
| CMS saturation | All CMS slots filled (extremely unlikely at 2^16 width) | New hashes overwrite least-recently-incremented slot | N/A — CMS width is sized for 1M+ unique behaviors | Theoretical — in practice, CMS width provides <0.1% collision rate |

### WindOH Application

| Failure | Detection | Immediate Behavior | Recovery | Data Loss Risk |
|---|---|---|---|---|
| Elasticsearch unreachable | ES client returns connection error | Polling loop logs warning, waits for next interval; health → DEGRADED | Automatic — polling resumes on next interval | None — data remains in ES |
| MongoDB unreachable | Mongoose operation timeout | API returns HTTP 503 with `{"status":"degraded","dependency":"mongodb"}`; health → DEGRADED | Mongoose connection pool auto-reconnect; BullMQ jobs paused until DB available | None — events remain in ES; enrichment jobs remain queued |
| Redis unreachable | ioredis connection error | BullMQ pauses processing; enrichment queue backs up; health → DEGRADED | ioredis auto-reconnect with exponential backoff | None — jobs are durable in Redis (AOF persistence) |
| LLM unavailable | HTTP request to LLM endpoint times out or returns 5xx | Enrichment worker marks job as failed; BullMQ retries with backoff; health → DEGRADED | Automatic retry (configurable attempts, default 5); job dead-lettered after exhaustion | None — jobs remain queued |
| LLM returns malformed JSON | JSON parse failure in enrichment worker | Worker logs raw response, marks job as failed; stores raw output for debugging | Human review of malformed response; re-trigger enrichment | None — raw response preserved |
| Worker process crash | BullMQ heartbeat timeout | BullMQ marks active job as failed; job returns to queue | Job re-queued and picked up by another worker (or same worker after restart) | None — BullMQ job durability |
| Enrichment queue backlog > threshold | Queue depth exceeds configurable max | Health → DEGRADED; log warning with queue depth metric | Automatic — workers continue processing; manual scale-out if persistent | None |

### LessVolatile

| Failure | Detection | Immediate Behavior | Recovery | Data Loss Risk |
|---|---|---|---|---|
| Plugin execution failure | Plugin process returns non-zero exit code | Plugin marked ✗ in TUI; error output saved to `debug/<plugin>.err`; processing continues with next plugin | Manual — operator reviews `debug/` output | None — remaining plugins execute normally |
| Plugin timeout | Plugin exceeds configurable timeout (default 5 min) | Plugin killed; output captured to timeout point; marked ⏱ in TUI | Manual — operator may re-run with longer timeout | Partial — plugin output up to timeout is preserved |
| Python interpreter failure | Subprocess fails to start | Fatal — LessVolatile exits with error code | Manual — indicates corrupted embedded Python bundle | N/A |
| Disk full during CSV output | write() returns ENOSPC | Plugin output truncated; error logged; processing continues | Manual — operator frees space and re-runs | Partial — completed plugin CSVs are intact; failed plugin output is lost |
| Invalid memory image | Volatility fails to parse image header | Plugin marked ✗; specific error logged ("Invalid profile", "Corrupt header") | Manual — operator verifies image integrity | None |

### OneDriveStandaloneUpdaterr

| Failure | Detection | Immediate Behavior | Recovery | Data Loss Risk |
|---|---|---|---|---|
| KAPE target failure | KAPE returns non-zero exit code for specific target | Target failure tallied: "X/Y succeeded, Z failed"; per-target error logged; processing continues | Manual — operator reviews failed target logs | None — successful targets complete normally |
| PsExec connection failure | PsExec returns error (timeout, access denied, network unreachable) | Remote collection aborted for that target; local results preserved | Manual — operator verifies network connectivity and credentials | None — local collection is independent of remote |
| Disk full during collection | write() returns ENOSPC | Collection aborted; partial output zip preserved with warning | Manual — operator frees space; space guard pre-checks mitigate | Partial — artifacts collected before disk full are in the output zip |
| SHA-256 integrity mismatch | Post-pull hash != pre-pull hash | Warning printed to stderr; zip retained but flagged | Manual — operator re-runs remote collection | None — flagged zip preserved for investigation |
| Insufficient space for disk imaging | Pre-flight check: free space < physical disk size | Disk imaging skipped; warning printed; other collection continues | Manual — operator provides larger output target | None — all other artifacts collected normally |

---

## Health Check Endpoints

All service components expose structured health checks:

### Agent Health (SQLite `diagnostics` table)

```json
{
  "status": "healthy",
  "uptime_seconds": 82340,
  "pipeline": {
    "events_processed": 14502341,
    "events_dropped": 0,
    "shard_backpressure": [0, 0, 0, 0, 0, 0, 0, 0]
  },
  "export": {
    "status": "connected",
    "last_success_ts": "2026-05-27T12:30:00Z",
    "outbox_depth": 0,
    "dead_letter_depth": 0
  },
  "etw": {
    "session_status": "running",
    "providers_active": 47,
    "events_per_second": 142.3
  },
  "storage": {
    "sqlite_size_mb": 84,
    "disk_free_gb": 412
  }
}
```

### WindOH API Health (`GET /api/health`)

```json
{
  "status": "healthy",
  "uptime_seconds": 43200,
  "dependencies": {
    "mongodb": "connected",
    "redis": "connected",
    "elasticsearch": "connected",
    "llm": "healthy"
  },
  "queues": {
    "enrichment": {"waiting": 3, "active": 2, "failed": 0},
    "markov_rebuild": {"waiting": 0, "active": 0, "failed": 0}
  },
  "enrichment": {
    "tokens_total": 45231,
    "tokens_enriched": 44987,
    "pending_enrichment": 244,
    "cache_hit_rate": 0.995
  }
}
```

Health status values: `healthy` (all dependencies nominal), `degraded` (one or more dependencies degraded but service operational), `critical` (service unable to function).

---

## Recovery Procedures

See [docs/operations/RUNBOOKS.md](RUNBOOKS.md) for step-by-step recovery procedures for each failure mode.
