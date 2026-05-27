# ADR-005: Elasticsearch as Transport Layer, Not System of Record

**Status:** Accepted
**Date:** 2025-11-20
**Deciders:** Platform architect

## Context

The LongHorizons agent produces behavioral events, exemplars, patterns, and diagnostics. These need to be queryable by the WindOH application and by external SIEM/log aggregation systems. Two approaches were considered:

1. **Elasticsearch as system of record:** Agent writes directly to ES. WindOH reads from ES. All querying happens through ES.
2. **Elasticsearch as transport layer:** Agent exports to ES. WindOH polls ES and persists enriched data to MongoDB (the system of record). ES serves external consumers and acts as a buffer between agent and application.

## Decision

Elasticsearch was designated as a transport layer, not the system of record.

## Rationale

- **Schema flexibility:** MongoDB's document model accommodates the variable-depth enrichment that the LLM produces (nested JSON with optional fields per token). Elasticsearch mappings are stricter and migration is costlier.
- **Query patterns differ:** External SIEM queries are time-range scans and keyword searches (ES-optimal). WindOH queries are hash lookups, graph traversals, and sequence aggregations (MongoDB-optimal with Atlas Search).
- **Separation of concerns:** ES handles the operational burden of ingesting at wire speed from potentially thousands of agents. MongoDB handles the analytical burden of enrichment caching, sequence modeling, and coverage mapping. Neither database is a bottleneck for the other's workload.
- **Independent scaling:** ES can be scaled for agent ingest volume independently of MongoDB scaling for enrichment throughput.
- **Resilience:** If ES is unreachable, the agent buffers to SQLite outbox. If MongoDB is unreachable, enrichment pauses but event polling continues. The decoupling prevents cascading failures.

## Consequences

- Two databases to operate (ES + MongoDB) instead of one. Operational complexity increases.
- Polling introduces latency between event export and enrichment. Configurable polling interval trades off freshness vs. ES query load.
- ES ILM policies manage retention (7d hot → warm → 90d delete). MongoDB retains enriched tokens permanently — this is the knowledge base.
