# Token Link and Markov Prediction

---

## The Payload Token: Atomic Unit of Identity

Every observable action on an endpoint hashes into a deterministic, stable `payload_token`. This is not a random UUID. It is a content-addressable fingerprint derived from the normalized event fields: event type, provider, process context, and payload data. The same behavioral pattern on two different hosts produces the same token. The same pattern at two different times produces the same token. This is the property that makes the entire platform cohere.

```
payload_token = hash(
    event_type || provider_name || process_context_hash || payload_signature
)
```

The token is drawn from `tokens.payload` in the Elasticsearch document at ingest time. It is validated to be present and non-empty before the document enters the pipeline.

---

## The Token Link: Everything Orbiting a Single Token

```mermaid
graph TB
    Token["payload_token<br/>abc123def456..."]
    
    Token --> Enrich["LLM Enrichment<br/>9-dimension analysis<br/>permanent cache"]
    Token --> Valid["ATT&CK Validation<br/>technique match/partial/mismatch<br/>confidence score"]
    Token --> ART["ART Ground Truth<br/>(if from ART test)<br/>observed techniques<br/>IOC coverage"]
    Token --> Seq["Sequence Context<br/>position in host sessions<br/>preceding and following tokens"]
    Token --> Markov["Markov Transition<br/>from_token -> to_token<br/>probability + surprise score"]
    Token --> Embed["Semantic Embedding<br/>1536-dimension vector<br/>cached by source_hash"]
    Token --> Cluster["Cluster Membership<br/>cosine similarity group<br/>centroid distance"]
    Token --> Graph["Graph Edges<br/>parent_child, sequence_transition,<br/>semantic_similarity, shared_technique,<br/>host_correlation, anomaly_link,<br/>cluster_member"]
    Token --> Feedback["Analyst Feedback<br/>corrections, annotations,<br/>technique overrides"]
    Token --> Dataset["Dataset Inclusion<br/>sequence_prediction,<br/>attack_classification,<br/>anomaly_detection,<br/>semantic_contrastive,<br/>behavioral_completion"]

    Enrich --> Provenance["Provenance Chain<br/>source_type, model_name,<br/>prompt_version, confidence,<br/>validation_method"]
    Valid --> Provenance
    Feedback --> Provenance
```

The Token Link is the complete, permanently accumulating record orbiting a single `payload_token`. Every time the platform encounters a token -- whether on its first observation or its ten-thousandth -- it consults and augments this record.

**This is the training ground.**

Each token link is a self-contained training artifact. The enrichment is a label. The ATT&CK validation is a ground-truth calibration. The sequence context is a temporal label. The embedding is a semantic feature vector. The analyst feedback is a human correction signal. The cluster membership is a weak supervision signal. Together, these form a richly annotated behavioral dataset where each row is a token and each column is a different modality of intelligence.

---

## How the Token Link Improves Over Time

```mermaid
sequenceDiagram
    participant ES as Elasticsearch
    participant Ingest as Ingestion
    participant LLM as PartiriOne LLM
    participant Analyst as Human Analyst
    participant TokenLink as Token Link Record
    participant Dataset as Dataset Factory

    Note over TokenLink: Initial state: token hash only, no enrichment

    ES->>Ingest: New event pattern observed
    Ingest->>Ingest: Hash to payload_token
    Ingest->>TokenLink: Create token link (hash only)
    Ingest->>LLM: Enqueue for enrichment

    LLM->>TokenLink: Write enrichment (9 dimensions + provenance)
    Note over TokenLink: Enriched: has ATT&CK inference, functional analysis

    LLM->>TokenLink: Write ATT&CK validation result
    Note over TokenLink: Validated: has technique match quality, confidence

    Analyst->>TokenLink: Review enrichment, correct technique mapping
    Note over TokenLink: Analyst-corrected: higher quality labels

    Analyst->>TokenLink: Annotate with domain context
    Note over TokenLink: Annotated: business context, environment-specific notes

    Ingest->>TokenLink: Same token observed again on different host
    Note over TokenLink: Cross-host: sequence context expanded

    Dataset->>TokenLink: Export as training row
    Note over TokenLink: Exported: part of structured training corpus

    Note over TokenLink: Next rebuild: model trains on analyst-corrected labels,<br/>cross-host sequences, multi-modal features
```

The token link is never finished. It starts as a bare hash, acquires LLM enrichment on first observation, gets validation against ATT&CK, receives analyst review and correction, accumulates cross-host sequence data with each new observation, and eventually feeds into dataset exports. Each cycle through the pipeline -- each new observation, each analyst review, each model rebuild -- tightens the quality of the linked data.

---

## Markov Chain Modeling

### First-Order Transitions

WindOH models behavioral sequences as first-order Markov chains. The order is configurable (`MARKOV_ORDER`), and the current production setting is 1-state memory. This means the model tracks the probability of transitioning from any observed token A to any observed token B.

```mermaid
stateDiagram-v2
    direction LR
    
    state "Token A\nProcessCreate\nsvchost.exe" as A
    state "Token B\nTCP Connect\noutbound :443" as B
    state "Token C\nDNS Query\nwindowsupdate.com" as C
    state "Token D\nRegistry Set\nRun key" as D
    state "Token E\nProcessCreate\ncmd.exe /c whoami" as E

    A --> B: count=12,450<br/>P=0.83<br/>surprise=0.27 bits
    A --> C: count=2,200<br/>P=0.15<br/>surprise=2.74 bits
    A --> D: count=280<br/>P=0.02<br/>surprise=5.64 bits
    A --> E: count=15<br/>P=0.001<br/>surprise=9.97 bits
```

Each transition records:
- `count` -- how many times A led to B
- `probability` -- count(A->B) / sum of all transitions from A
- `entropy` -- Shannon entropy of the distribution from A
- `surprise_score` -- -log2(probability) -- the information content of this specific transition

A transition that happens 83% of the time carries 0.27 bits of surprise. A transition that happens 0.1% of the time carries nearly 10 bits. The anomaly threshold is set at 3.0 bits of surprise -- anything rarer than a 1-in-8 occurrence is flagged.

### Sequence Construction

```mermaid
graph TB
    subgraph Raw["Raw Events on Host 'desktop-01'"]
        E1["Event 1: ProcessCreate svchost.exe<br/>t=0ms"]
        E2["Event 2: TCP Connect outbound :443<br/>t=12ms"]
        E3["Event 3: DNS Query windowsupdate.com<br/>t=45ms"]
        E4["Event 4: ProcessCreate cmd.exe<br/>t=8,200ms"]
        E5["Event 5: TCP Connect outbound :4444<br/>t=8,350ms"]
    end

    subgraph Sequences["Sequences (session PID 1234)"]
        S1["Token_A -> Token_B -> Token_C<br/>(grouped: events within 5 min window)"]
        S2["Token_D -> Token_E<br/>(new group after 5 min gap)"]
    end

    subgraph Transitions["Extracted Transitions"]
        T1["Token_A -> Token_B"]
        T2["Token_B -> Token_C"]
        T3["Token_D -> Token_E"]
    end

    E1 --> S1
    E2 --> S1
    E3 --> S1
    E4 --> S2
    E5 --> S2
    S1 --> T1
    S1 --> T2
    S2 --> T3
```

Events are grouped into sequences keyed by `hostname:sessionOrPid`. A sequence breaks when no events are observed for 5 minutes (configurable via `SEQUENCE_TIMEOUT_MS`). Within a sequence, every adjacent pair of tokens generates a transition record. The `hostname` is stored on the transition so the model can compute per-host statistics and global fallbacks.

### Prediction: What Comes Next

```mermaid
graph LR
    Current["Current Token<br/>ProcessCreate svchost.exe"]
    
    Current --> P1["Token B<br/>TCP Connect :443<br/>P=0.83 | host desktop-01"]
    Current --> P2["Token C<br/>DNS Query update.com<br/>P=0.15 | host desktop-01"]
    Current --> P3["Token D<br/>Registry Set Run<br/>P=0.02 | global fallback"]
    Current --> P4["Token X<br/>unseen transition<br/>P=0.0001 | smoothing prior"]
```

Given a current token, `getNextTokenPredictions()` returns the most likely next tokens ranked by probability. The model first looks for per-host transitions (host-specific behavior is a stronger signal) and falls back to global transitions if the host has no data for this token.

This is a prediction engine. As the model accumulates transitions across all hosts and all origins, it learns what normally follows what. When an event fires, the model forecasts the continuation. When the actual next event diverges from the forecast, the surprise score quantifies the anomaly.

---

## Markov as a Prediction and Training Ground

The Markov model serves two purposes that compound each other:

### 1. Real-Time Anomaly Detection

Every new event is scored against the current model. Transitions with surprise >= 3.0 bits surface on the dashboard as "Surprising Transitions." This is the operational detection use case: flagging behavior that deviates from the established norm.

### 2. Training Data Generation

Markov transitions are exported as two dataset types:
- **anomaly_detection**: Each transition is a row with features (from_token, to_token, count, probability, entropy, surprise_score) and a binary label (anomalous/normal at the 3.0 bit threshold).
- **sequence_prediction**: Each sequence is a row with an ordered token array. Models learn to predict the next token in a sequence.

The prediction task is: given a prefix sequence [T1, T2, ... Tn-1], predict Tn. The Markov model provides a strong baseline (first-order transition probabilities). Downstream models trained on the exported datasets can learn higher-order dependencies, cross-host patterns, and multi-origin correlations that a first-order Markov model cannot capture.

### Model Refinement Cycle

```mermaid
graph TB
    subgraph Observe["1. Observe"]
        O1["New telemetry arrives<br/>from all origins"]
        O2["Events sequenced<br/>by hostname:session"]
        O3["New transitions recorded<br/>counts incremented"]
    end

    subgraph Rebuild["2. Rebuild"]
        R1["Full Markov rebuild<br/>every 60 minutes"]
        R2["Probabilities recomputed<br/>from all historical data"]
        R3["Surprise scores updated<br/>entropy recalculated"]
    end

    subgraph Review["3. Review"]
        Rev1["Surprising transitions<br/>surface on dashboard"]
        Rev2["Analysts review,<br/>annotate, correct"]
        Rev3["Analyst feedback<br/>written to token links"]
    end

    subgraph Export["4. Export"]
        Exp1["Anomaly detection corpus<br/>binary-labeled transitions"]
        Exp2["Sequence prediction corpus<br/>ordered token arrays"]
        Exp3["Behavioral completion corpus<br/>partial sequences + targets"]
    end

    subgraph Train["5. Train"]
        Tr1["Downstream models<br/>trained on exported data"]
        Tr2["Higher-order dependencies<br/>learned from sequences"]
        Tr3["Model quality metrics<br/>tracked over time"]
    end

    subgraph Improve["6. Improve"]
        Imp1["Corrections from analyst<br/>reviews incorporated"]
        Imp2["New origins add<br/>transition diversity"]
        Imp3["Threshold tuning<br/>false positive reduction"]
    end

    Observe --> Rebuild
    Rebuild --> Review
    Review --> Export
    Export --> Train
    Train --> Improve
    Improve -.->|"Next cycle"| Observe
```

Each cycle through this loop tightens the model. New telemetry adds transition data. Rebuilds incorporate the latest counts. Analyst reviews correct enrichment labels, which improves technique mapping on the tokens that feed transition features. Dataset exports capture the current state. Downstream training produces better models. Corrections and threshold tuning reduce noise. Then the next cycle begins.

---

## Cross-Origin Markov Sequences

When telemetry arrives from multiple origins, the Markov model captures transitions that span operating system boundaries:

```
[Windows ETW: ProcessCreate cmd.exe] --> [Windows ETW: TCP Connect 192.168.1.100:445]
                                    --> [Linux auditd: SOCKET_ACCEPT 192.168.1.100:445]
                                    --> [Linux auditd: EXECVE /bin/bash]
                                    --> [K8s Audit: Pod Create alpine:latest]
```

A lateral movement campaign that starts on Windows, pivots through a Linux jump host, and lands in a Kubernetes cluster generates a single behavioral sequence in the Markov model. The transitions from a Windows token to a Linux token to a K8s token are recorded with probabilities and surprise scores just like any other transition. Over time, cross-origin transitions that are common (legitimate cross-platform services) become low-surprise baselines, while rare cross-origin transitions (unusual lateral movement paths) remain high-surprise anomalies.

This is the destination of the multi-origin architecture. The Markov model becomes a cross-platform behavioral prediction engine that learns what is normal across the entire infrastructure, not just within a single OS silo.

---

## Token Link + Markov: The Compound Effect

The Token Link and the Markov model reinforce each other:

| Token Link Provides | Markov Model Uses |
|---|---|
| ATT&CK technique labels | Labels on transition nodes (technique-aware prediction) |
| Analyst corrections | Higher-quality ground truth for anomaly labels |
| Enrichment behavioral descriptions | Features for similarity-aware transition grouping |
| Embedding vectors | Cosine distance between tokens in transition space |
| Cross-origin provenance | Multi-origin transition probability estimation |
| ART ground truth validation | Known-technique transitions (calibration set) |

The Markov model, in turn, enriches the token link:
- Sequence position (where this token sits in behavioral flows)
- Transition probabilities (what normally precedes and follows this token)
- Surprise score (how unusual this token is in its current context)
- Predicted next tokens (what the model expects to see next)

Each token link grows richer with every cycle. Each Markov rebuild produces better predictions. The platform is a flywheel.

---

## Engineers and Analysts: The Human Layer

The refinement cycle depends on human judgment at the review stage:

- **Engineers** maintain the model: tuning thresholds, adjusting sequence timeouts, verifying transition integrity, monitoring rebuild performance, and ensuring the normalizer correctly maps new origin events into canonical tokens.

- **Analysts** review the output: inspecting surprising transitions, determining whether a flagged anomaly is a true positive or a benign but rare event, correcting enrichment labels when the LLM misclassifies a technique, and annotating token links with domain context.

- **Both agree** on the mental map: the shared understanding of what behaviors are normal, what is suspicious, what co-occurs with what, and what the most likely explanation is. This shared mental map is formalized and persisted, so the next analyst who encounters a similar pattern benefits from the previous analyst's reasoning.

The Markov model is a statistical engine. The token link is a data record. The mental map is the human layer that interprets, corrects, and guides both. Together, they form a system that gets better with every observation and every review.
