# ADR-006: Markov Chains Over Deep Learning for Sequence Prediction

**Status:** Accepted
**Date:** 2025-12-01
**Deciders:** Platform architect

## Context

The WindOH application needs to model behavioral sequences — given behavior A, what behavior typically follows? Two approaches were considered:

1. **Deep learning (LSTM / Transformer):** Train a neural sequence model on temporal event chains. Predict next behavior from learned latent representations.
2. **Markov chains:** Build explicit transition probability matrices from observed event sequences. Predict next behavior from empirical transition frequencies.

## Decision

First-order Markov chains with extension points for higher-order transitions were selected.

## Rationale

- **Interpretability:** A Markov transition matrix is directly inspectable. "After behavior X, behavior Y follows with P=0.23 based on 1,400 observations" is an analyst-actionable statement. A neural network's prediction cannot be explained in operational terms.
- **Cold start:** Markov chains work with the first observed transition. A neural model requires training data volume that may not exist for a new deployment.
- **Incremental update:** Adding a new observed transition to a Markov matrix is O(1) (increment one cell). Retraining a neural model is O(dataset × epochs).
- **Sufficient expressiveness:** For security operations, first-order behavioral transitions capture the relevant signal. An attacker's sequence `cmd.exe → whoami.exe → powershell.exe -enc` has a clear Markov signature. Higher-order transitions (looking back 2+ steps) are implemented as an optional extension, not the default model.
- **Determinism:** Given the same sequence database, the Markov model produces identical transition probabilities. Reproducibility is a platform requirement (see Principle 7).

## Consequences

- First-order models cannot capture long-range dependencies (behavior at t-5 influencing behavior at t). This is mitigated by the fact that most attack chains unfold as locally-correlated steps.
- Transition probabilities require a minimum observation count to be statistically meaningful. The system defaults to flagging P < 0.01, configurable per deployment.
- The model does not learn behavioral "themes" or abstract patterns — it only models observed transitions. This is intentional; abstraction is the analyst's role.
