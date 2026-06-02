# WindOH — Presentation Deck

**A behavioral telemetry intelligence platform that turns raw endpoint events into structured, validated, queryable, and trainable behavioral intelligence.**

<p align="center">
  <img src="WindOH.gif" alt="WindOH Platform">
</p>

---

## READ THIS FIRST

WindOH is not a SIEM. It is not an EDR. It is not a SOAR. It is a fundamentally different category of platform -- one built around the idea that every observable action on an endpoint can be deterministically fingerprinted, permanently enriched, sequenced into a prediction model, and exported as AI training data.

If you only read two things, read this README and `WHY-WINDOH.md`.

---

## What WindOH Does (The 30-Second Version)

```
Raw ETW telemetry → Deterministic fingerprint → LLM enrichment → ATT&CK validation
                                                       ↓
                                         Markov chain prediction model
                                                       ↓
                                         Embeddings + semantic clustering
                                                       ↓
                                         Behavioral graph + analyst mental maps
                                                       ↓
                                         AI training dataset export
```

Every event becomes a `payload_token`. Every token accumulates a permanent, growing record called a **Token Link** — enrichment, validation, sequence context, embedding, cluster membership, graph edges, and analyst feedback. The Token Link is the atomic unit of everything.

The Markov model learns what normally follows what. When the actual next event diverges from the prediction, the platform quantifies the surprise. Analysts review, correct, and annotate. Engineers tune thresholds and add new telemetry origins. The platform gets better with every cycle.

---

## Why WindOH Is Different

| Conventional Approach | WindOH Approach |
|---|---|
| **SIEM:** Ingest logs, write rules, alert on matches | **Deterministic fingerprinting:** Every event hashes to a stable identity. No rules needed to recognize a pattern you've seen before. |
| **EDR:** Vendor-defined detection logic, opaque scoring | **Transparent enrichment:** Every enrichment carries provenance — source, model version, confidence, validation method. You can audit why something was flagged. |
| **SOAR:** Playbooks triggered by alerts, linear automation | **Prediction engine:** Markov chains model behavioral sequences. The platform forecasts what comes next and flags divergence, not just known-bad patterns. |
| **Threat Intel:** Feed-driven, external IoC matching | **Token Link as training ground:** Enrichment, validation, embeddings, and analyst feedback accumulate on every token. This is labeled training data, not just an alert feed. |
| **Analyst workflow:** Individual investigation, notes in tickets | **Mental maps:** Structured, queryable, shareable analyst reasoning. Insight compounds across investigations instead of being rediscovered from scratch. |

### The Five Core Principles

1. **Universal Behavioral Fingerprinting** — `payload_token` is a content-addressable hash derived from event type, provider, process context, and payload data. Same pattern on two different hosts = same token. Same pattern at two different times = same token. This is what makes the whole platform cohere.

2. **Origin-Agnostic Telemetry** — The canonical schema is deliberately origin-neutral. Windows ETW today. Linux auditd, macOS Endpoint Security, Kubernetes audit logs, and hypervisor events are architected as first-class targets. A behavioral event is a behavioral event.

3. **Markov Chain Prediction** — First-order Markov chains model every behavioral transition. Given a current token, the model predicts what comes next. Transitions that deviate from established norms are quantified as surprise (in bits) and surfaced to analysts.

4. **Token Link as Training Ground** — Every token accumulates a permanent, growing record. This is not metadata. This is a richly annotated training artifact. The dataset factory exports five structured training corpus types from the accumulated token links.

5. **Shared Mental Maps** — Analysts build mental models of the behavioral landscape. WindOH formalizes these as structured, queryable artifacts shared across the team via the E2E-encrypted collaboration gateway.

> **Read the full differentiation argument:** [`WHY-WINDOH.md`](./WHY-WINDOH.md)

---

## Platform Walkthrough (GIF Placeholders)

### 1. Dashboard Overview

<!-- GIF_PLACEHOLDER: dashboard-overview.gif -->
<!-- CAPTION: The analyst dashboard showing intelligence overview, ATT&CK validation breakdown, technique heatmap, pipeline status, queue health, recent telemetry, and surprising transitions. All metrics refresh every 15 seconds. -->
<!-- HOW TO CREATE: Record a 30-45 second tour starting from login. Show the sidebar navigation, the intelligence overview panel with token/indexed counts animating upward, the technique heatmap bars, pipeline status badges turning green, and the surprising transitions table populating. End on the full dashboard. Resolution: 1920x1080. -->
```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│                                                         │
│                  [ dashboard-overview.gif ]             │
│                                                         │
│          Analyst dashboard walkthrough, 30-45s          │
│                                                         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 2. Telemetry Ingestion Pipeline

<!-- GIF_PLACEHOLDER: ingestion-pipeline.gif -->
<!-- CAPTION: Real-time telemetry flowing from Elasticsearch through normalization, deduplication, bulk insert into MongoDB, and enqueue to enrichment. Shows the ingestion polling loop in action. -->
<!-- HOW TO CREATE: Open two panels side by side — left shows the ES polling logs / pipeline status panel, right shows MongoDB tokens collection count incrementing. Highlight a single document flowing through: raw ES doc → normalized canonical token → payload_token hash → insert into tokens collection. Add a subtle highlight on the payload_token field as it gets hashed. 20-30 seconds. -->
```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│                                                         │
│                [ ingestion-pipeline.gif ]               │
│                                                         │
│     ES document → Normalizer → Token → MongoDB, 20-30s  │
│                                                         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 3. LLM Enrichment and ATT&CK Validation

<!-- GIF_PLACEHOLDER: enrichment-validation.gif -->
<!-- CAPTION: A single token receiving 9-dimension LLM enrichment, SearXNG web augmentation, and ATT&CK technique validation. Shows the provenance chain being attached. -->
<!-- HOW TO CREATE: Show a token detail view. Trigger enrichment on a new token. Animate the 9 dimensions appearing one by one (technique mapping, D3FEND countermeasures, functional analysis, origin analysis, benign rationale, malicious rationale, attack scenarios, investigation steps, related CVEs). Show the provenance block appearing at the bottom with source_type, model_name, confidence. Then show the ATT&CK validation result: technique ID + confidence + validation status. 30-40 seconds. -->
```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│                                                         │
│              [ enrichment-validation.gif ]              │
│                                                         │
│    9-dimension LLM analysis + ATT&CK validation, 30-40s │
│                                                         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 4. Markov Prediction Engine

<!-- GIF_PLACEHOLDER: markov-prediction.gif -->
<!-- CAPTION: The Markov chain model in action — event sequences being built, transitions being recorded, probabilities being computed, and surprise scores flagging anomalous transitions. -->
<!-- HOW TO CREATE: Show the surprising transitions panel on the dashboard. Animate a sequence diagram: events flowing in, grouping into sequences by host:session, transitions being extracted (Token_A → Token_B with probability), then highlight one transition with a high surprise score (9.97 bits) turning red. Show the prediction: "Given Token_A, model predicts Token_B (83%), Token_C (15%), Token_D (2%). Actual next event was Token_E (0.1%)." 30-40 seconds. -->
```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│                                                         │
│               [ markov-prediction.gif ]                 │
│                                                         │
│   Sequence → Transition → Probability → Surprise, 30-40s│
│                                                         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 5. Analyst Mental Map and Collaboration

<!-- GIF_PLACEHOLDER: mental-map-collab.gif -->
<!-- CAPTION: An analyst building a mental map — reviewing anomalies, marking TP/FP verdicts, annotating token links, and sharing findings with another analyst via the collaboration gateway. -->
<!-- HOW TO CREATE: Split screen — left shows Analyst A on desktop-01 reviewing a surprising transition, marking it as True Positive, annotating the token link with investigation notes, and saving the mental map. Right shows Analyst B on desktop-07 seeing the same token appear with Analyst A's annotation already visible. Show the collab gateway room with presence indicators and the shared mental map artifact appearing in real time. 40-50 seconds. -->
```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│                                                         │
│              [ mental-map-collab.gif ]                  │
│                                                         │
│    Analyst A reviews → Annotates → Analyst B benefits   │
│                                                         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 6. AI Dataset Export

<!-- GIF_PLACEHOLDER: dataset-export.gif -->
<!-- CAPTION: The dataset factory exporting five training corpus types from accumulated token links, Markov transitions, and analyst feedback. -->
<!-- HOW TO CREATE: Show the dataset export panel. Animate the five dataset types being generated: sequence_prediction, attack_classification, anomaly_detection, semantic_contrastive, behavioral_completion. Show a sample row from each type appearing. Show the train/val/test split ratios. Show the training_corpus metadata being written to MongoDB with export stats. End on the training flywheel diagram. 25-35 seconds. -->
```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│                                                         │
│                [ dataset-export.gif ]                   │
│                                                         │
│   5 training corpus types exported from token links     │
│                                                         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## The Training Flywheel

This is the long-term thesis in one diagram:

```
  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
  │  Ingest  │ ──► │  Enrich  │ ──► │  Markov  │ ──► │  Export  │
  │Telemetry │     │Token Link│     │  Model   │     │ Datasets │
  └──────────┘     └──────────┘     └──────────┘     └──────────┘
       ▲                  ▲                │                │
       │                  │                │                ▼
       │            ┌─────┴─────┐          │          ┌──────────┐
       │            │  Analyst  │          │          │  Train   │
       └────────────│  Reviews  │◄─────────┘          │  Models  │
                    └───────────┘                      └──────────┘
                                                             │
                                                             ▼
                                                      ┌──────────┐
                                                      │ Evaluate │
                                                      │ Quality  │
                                                      └──────────┘
```

Better enrichment → Better models → Better anomaly detection → Fewer false positives → Analyst feedback improves enrichment → Cycle accelerates.

---

## Deck Navigation

| # | Document | What You'll Learn |
|---|---|---|
| 0 | **[README.md](./README.md)** ← you are here | Executive summary, GIF walkthrough, training flywheel |
| ★ | **[WHY-WINDOH.md](./WHY-WINDOH.md)** | Deep-dive on what makes WindOH novel vs. SIEM/EDR/SOAR |
| 1 | **[00-WindOH-Platform-Overview.md](./00-WindOH-Platform-Overview.md)** | Full platform architecture, core concepts, stack |
| 2 | **[01-Architecture-and-Data-Pipeline.md](./01-Architecture-and-Data-Pipeline.md)** | Data flow, queue architecture, normalization, enrichment |
| 3 | **[02-Telemetry-Origins.md](./02-Telemetry-Origins.md)** | Origin-agnostic design, multi-OS telemetry, cross-origin correlation |
| 4 | **[03-Token-Link-and-Markov-Prediction.md](./03-Token-Link-and-Markov-Prediction.md)** | Token Link as training ground, Markov modeling, prediction engine |
| 5 | **[04-Mental-Maps-and-Collaboration.md](./04-Mental-Maps-and-Collaboration.md)** | Analyst mental models, collaboration gateway, agreement layer |
| 6 | **[05-AI-Datasets-and-Deployment.md](./05-AI-Datasets-and-Deployment.md)** | Dataset factory, export pipeline, security architecture, K8s deployment |
| 🎬 | **[GIF-PLACEHOLDERS.md](./GIF-PLACEHOLDERS.md)** | Full GIF creation guide — scripts, resolutions, durations |

---

## Who This Deck Is For

- **Security engineers** evaluating behavioral telemetry platforms
- **Analysts** who want to understand how their workflow changes with deterministic fingerprinting and Markov prediction
- **ML engineers** looking at the dataset factory and training flywheel
- **Platform architects** considering origin-agnostic telemetry ingestion
- **Anyone** who has ever been frustrated by SIEM rule fatigue, EDR opacity, or the gap between detection and training data

---

## Quick Start: Read in This Order

1. Start here (this README)
2. Read [`WHY-WINDOH.md`](./WHY-WINDOH.md) — understand what makes this different
3. Watch the GIFs (or read the placeholders to know what to expect)
4. Read the deck documents in order (00 → 01 → 02 → 03 → 04 → 05)
5. Come back to this README and the training flywheel will make sense

---

**windoh.us**
