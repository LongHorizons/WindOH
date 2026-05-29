# Queue Architecture

## Overview

WindOH uses BullMQ (backed by Redis) for asynchronous job processing. Three queue families handle the application's primary workloads: enrichment, Markov rebuild, and ART execution.

## Queue Topology

```
┌──────────────────────────────────────────────────────────────────┐
│                          Redis (BullMQ)                          │
│                                                                   │
│  ┌─────────────────────┐  ┌─────────────────────┐                │
│  │ enrichment          │  │ markov-rebuild      │                │
│  │                     │  │                     │                │
│  │ Concurrency: 2-8    │  │ Concurrency: 1      │                │
│  │ Rate limit: 10/s    │  │ Repeatable: hourly  │                │
│  │ Retry: 5x, backoff  │  │ Retry: 3x, backoff  │                │
│  │ Timeout: 60s        │  │ Timeout: 300s       │                │
│  │                     │  │                     │                │
│  │ Priority:           │  │ Priority:           │                │
│  │  Normal = 0         │  │  Low = -10          │                │
│  └─────────────────────┘  └─────────────────────┘                │
│                                                                   │
│  ┌─────────────────────┐  ┌─────────────────────┐                │
│  │ art-execution       │  │ dead-letter (DLQ)   │                │
│  │                     │  │                     │                │
│  │ Concurrency: 1      │  │ Manual inspection   │                │
│  │ Retry: 2x           │  │ required before     │                │
│  │ Timeout: 600s       │  │ re-queue or discard │                │
│  └─────────────────────┘  └─────────────────────┘                │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

## Queue Design Decisions

### Enrichment Queue

**Why BullMQ over direct LLM calls:** The enrichment pipeline has variable latency (LLM response time) and the LLM endpoint has finite concurrency. BullMQ provides:

- **Backpressure:** When LLM is saturated, jobs queue rather than fail. Queue depth is a natural load metric.
- **Retry with backoff:** Transient LLM failures (timeout, OOM) retry automatically with exponential backoff (1s → 2s → 4s → 8s → 16s, max 5 attempts).
- **Rate limiting:** Configurable `rateLimiter` prevents overwhelming the LLM endpoint (default: max 10 jobs/second).
- **Concurrency control:** `concurrency: 2` (configurable) ensures at most N LLM requests in flight simultaneously.

**Job data minimization:** Enrichment jobs contain only the payload token — not the full event data. The worker reads event data from MongoDB at execution time. This avoids storing potentially large event documents in Redis.

**Idempotency:** Workers check if a token already has `enrichment.description` before calling the LLM. If enrichment was completed by another worker between queue and dequeue, the job is a no-op.

### Markov Rebuild Queue

**Why queued and not streaming:** The Markov transition matrix is rebuilt from the full `event_sequences` collection. This requires an aggregation pipeline over potentially millions of sequences — a batch operation, not a streaming one.

**Schedule:** Hourly repeatable job via BullMQ `repeatable`. Configurable interval. The rebuild is a full recomputation, not incremental (sequence data grows continuously; incremental update would require tracking which sequences changed).

**Singleton:** `concurrency: 1` ensures only one rebuild runs at a time. Subsequent scheduled jobs while a rebuild is in progress are discarded (not queued).

### Dead-Letter Queue (DLQ)

**When jobs enter DLQ:**
- Exhausted all retry attempts (configurable per queue)
- Job-specific permanent failure (e.g., token event data exceeds LLM context window)

**DLQ operations:**
- Jobs remain in Redis until manually inspected
- Bull Board UI provides inspection interface at `/admin/queues`
- Operator can: re-queue with reset retry count, inspect job data, or discard

## Retry Semantics

```
Job Failure
    │
    ▼
Is retryable error? (timeout, connection refused, 5xx)
    │
    ├── No → DLQ immediately
    │
    └── Yes
          │
          ▼
    Attempts < max_attempts?
          │
          ├── No → DLQ after logging exhaustion
          │
          └── Yes
                │
                ▼
          backoff = min(base_delay × 2^attempt, max_delay)
          Wait(backoff)
          Re-queue
```

**Retryable errors:** Network timeouts, connection refused, HTTP 5xx, LLM OOM responses.

**Non-retryable errors:** HTTP 4xx (bad request — prompt is malformed), JSON parse failure (LLM response is unparseable), token context exceeds LLM limit.

## Event-Driven Workflow: Enrichment

```
ES Poll Loop
    │
    ▼
New payload token detected (not yet enriched)
    │
    ▼
API enqueues job: { payload_token: "abc123..." }
    │
    ▼
Worker dequeues job
    │
    ▼
Worker reads full event data from MongoDB tokens collection
    │
    ▼
Worker constructs structured JSON prompt
    │
    ▼
Worker POSTs to LLM endpoint
    │
    ├── Success (2xx, valid JSON response)
    │       │
    │       ▼
    │   Worker parses response → stores in tokens collection
    │       │
    │       ▼
    │   Job marked complete
    │
    ├── Retryable failure (timeout, 5xx)
    │       │
    │       ▼
    │   Job re-queued with backoff (up to 5 attempts)
    │
    └── Permanent failure (4xx, parse error, context overflow)
            │
            ▼
        Job enters DLQ
        Raw response stored for inspection
```

## Queue Configuration Reference

```yaml
# docker-compose.yml excerpt
services:
  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3

  enrichment-worker:
    build: .
    command: node worker/enrichment.worker.js
    environment:
      - REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379
      - LLM_ENDPOINT=${LLM_ENDPOINT}
      - LLM_TIMEOUT_MS=60000
    deploy:
      replicas: 2
    depends_on:
      redis:
        condition: service_healthy
```

## Monitoring

Key metrics exported for dashboards:

| Metric | Source | Description |
|---|---|---|
| `queue.enrichment.waiting` | BullMQ | Jobs not yet started |
| `queue.enrichment.active` | BullMQ | Jobs currently executing |
| `queue.enrichment.failed` | BullMQ | Jobs in DLQ |
| `queue.enrichment.completed` | BullMQ | Jobs completed (cumulative) |
| `queue.enrichment.latency.p50` | Custom | Median job duration |
| `queue.enrichment.latency.p99` | Custom | 99th percentile job duration |
| `queue.markov-rebuild.duration` | Custom | Last rebuild duration (seconds) |
| `redis.memory_used` | Redis INFO | Redis memory consumption |
