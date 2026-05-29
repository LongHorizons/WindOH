# ADR-001: Cryptographic Behavioral Identity Over ML Embeddings

**Status:** Accepted
**Date:** 2025-11-01
**Deciders:** Platform architect

## Context

The platform needs to identify when the same behavior occurs across different hosts, at different times. Two approaches were considered:

1. **Cryptographic hashing (SHA-256):** Distill each event to a normalized behavioral skeleton (process lineage, operation type, key fields stripped of ephemera), hash it deterministically.

2. **Vector embeddings:** Run event fields through an embedding model, use cosine similarity or approximate nearest neighbor search to find similar behaviors.

## Decision

Cryptographic hashing was selected.

## Rationale

- **Determinism:** A hash either matches or it doesn't. There is no similarity threshold to tune, no embedding model to train, no drift to monitor.
- **Court admissibility:** SHA-256 hashes are accepted in forensic proceedings. Embedding similarity scores are not.
- **Storage efficiency:** A 32-byte hash replaces a kilobyte-scale event document. Hash joins on indexed columns are O(1); vector similarity search is O(log N) with approximations.
- **Cross-system compatibility:** A `base_token` can be queried by any SQL database, any SIEM, any log aggregator. Embeddings require specialized vector database infrastructure.
- **Adversarial robustness:** ML models can be evaded via adversarial examples. A cryptographic hash function cannot be practically inverted or collided.

## Consequences

- The `base_token` generation pipeline must be exhaustively deterministic — same behavior on any host at any time must produce the same hash. This requires careful exclusion of non-deterministic fields (timestamps, PIDs, handles).
- Payload-level variation tracking requires a separate `payload_token` mechanism, since the behavioral hash intentionally ignores command-line arguments and network targets.
- The system cannot answer fuzzy queries like "behaviors similar to X" — only exact behavioral matches. This is intentional; fuzzy matching is the analyst's domain.
