# ADR-002: Count-Min Sketch with Exponential Decay Over Exact Counting

**Status:** Accepted
**Date:** 2025-11-03
**Deciders:** Platform architect

## Context

The LongHorizons agent must track behavioral frequency across millions of unique base token values per endpoint to assign rarity bands. Two approaches were considered:

1. **Exact counting (hash map):** Maintain a HashMap<base_token, count> in memory. O(N) memory where N is unique behaviors seen.
2. **Count-Min Sketch (CMS):** Probabilistic data structure with configurable width × depth. O(W × D) fixed memory. Under-counts with controllable error rate.

## Decision

Count-Min Sketch with exponential decay scoring and promoted exact counters was selected.

## Rationale

- **Memory bound:** An endpoint might see 1M+ unique behaviors over its lifetime. An exact HashMap would require ~150 MB and grow unboundedly. A CMS with width=2^16 and depth=4 is ~512 KB, fixed.
- **CMS accuracy is sufficient for rarity banding:** With ε=0.001 (0.1% error at 99.9% confidence), rarity band misclassification affects only edge cases near band boundaries — and rarity exists to reduce analyst surface, not to make automated decisions.
- **Recency matters more than precision:** Raw count misrepresents normality. Exponential decay (`score = count × e^(-λ × days_since_last_seen)`) correctly surfaces dormant behaviors. The decay function operates on the CMS estimate, not an exact count — the error is negligible relative to the decay curve.
- **Promotion to exact counter:** When a CMS slot exceeds a configurable threshold, the hash graduates to an exact counter in a separate hash map. This hybrid approach gives exact counts for the top-K most frequent behaviors (which matter most for baselining) while keeping memory bounded.

## Consequences

- Rare behaviors may be slightly over-counted by CMS hash collisions. This is acceptable because: (a) rare behaviors stay rare regardless of a small over-count, and (b) exact promotion captures the important ones.
- The decay half-life is a configurable parameter per deployment. Shorter half-lives surface recent anomalies faster but require more frequent recency scoring.
- SQLite stores the canonical count for promoted tokens; the CMS is an in-memory acceleration structure, not the source of truth.
