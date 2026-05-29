# ADR-003: 8-Way Hash-Sharded Pipeline Over Actor Model

**Status:** Accepted
**Date:** 2025-11-07
**Deciders:** Platform architect

## Context

The LongHorizons agent processes ETW events at kernel-provider throughput (potentially thousands per second). Each event must traverse: normalization → enrichment → tokenization → baselining → outbox persistence. The pipeline must not drop events under load.

Two concurrency models were considered:

1. **Actor model (e.g., Actix):** Each pipeline stage is an actor. Events flow through message passing between actors. Backpressure via mailbox capacity.
2. **Hash-sharded pipeline:** Pre-compute `base_token`, route to one of N independent shards by hash prefix. Each shard owns its own CMS, reservoir, and process cache. Shards share nothing.

## Decision

8-way hash-sharded pipeline was selected.

## Rationale

- **Lock elimination:** In the actor model, any shared state (CMS, process cache) requires either message-passing overhead or internal locks. Sharding eliminates both: each shard owns its state exclusively. The only synchronization point is the initial hash computation, which is read-only on shared event data.
- **Deterministic routing:** `shard_id = base_token[0..8]` routes the same behavior to the same shard every time, on every host. This means CMS counters, reservoir samples, and process cache entries for a given behavior are always in the same shard — no cross-shard coordination needed.
- **Linear scalability:** 8 shards on an 8-core machine achieves near-linear throughput scaling. The actor model's message-passing overhead grows with pipeline depth; sharding's overhead is constant (one hash computation + one channel send).
- **Simplicity:** The shard boundary is the only concurrency primitive. No supervision trees, no mailbox tuning, no backpressure propagation across stages.

## Consequences

- Load imbalance is possible if hash distribution is skewed (unlikely with SHA-256, but theoretically possible). Mitigated by the hash function's uniformity guarantee.
- Shard count is fixed at compile time (8). Dynamic resharding would require migrating CMS state, which is not implemented.
- Each shard independently writes to SQLite. WAL mode handles concurrent writers; no shard-level database contention.
