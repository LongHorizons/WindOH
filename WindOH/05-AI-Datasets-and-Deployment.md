# AI Datasets and Production Deployment

---

## The Dataset Factory

WindOH is not just an operations platform. It is a training data factory. Every token link, every Markov transition, every ATT&CK validation, every semantic embedding, and every analyst correction is structured for export as machine learning training corpora.

The `@windoh/datasets` package generates five dataset types:

```mermaid
graph TB
    subgraph Sources["Data Sources"]
        Tokens["tokens collection<br/>enriched + validated<br/>telemetry records"]
        Sequences["event_sequences collection<br/>ordered behavioral<br/>token arrays"]
        Markov["markov_transitions collection<br/>from_hash, to_hash,<br/>probability, surprise"]
        Clusters["behavioral_clusters collection<br/>cluster membership +<br/>centroid distances"]
        Feedback["analyst_feedback collection<br/>corrections, annotations,<br/>verdicts"]
    end

    subgraph Datasets["Exported Datasets"]
        D1["sequence_prediction<br/>Ordered token sequences<br/>Next-token prediction task<br/>Formats: jsonl, csv"]
        D2["attack_classification<br/>Tokens with technique labels<br/>Multi-label classification<br/>Formats: jsonl, csv"]
        D3["anomaly_detection<br/>Transitions with binary labels<br/>Anomaly detection task<br/>Formats: jsonl, csv"]
        D4["semantic_contrastive<br/>Tokens with enrichment descriptions<br/>Contrastive learning task<br/>Formats: jsonl, csv"]
        D5["behavioral_completion<br/>Partial sequences with targets<br/>Sequence completion task<br/>Formats: jsonl, csv"]
    end

    Tokens --> D2
    Tokens --> D4
    Sequences --> D1
    Sequences --> D5
    Markov --> D3
    Clusters --> D4
    Feedback --> D2
    Feedback --> D3
```

---

## Dataset Details

### 1. Sequence Prediction

**Task:** Given a prefix sequence of tokens [T1, T2, ... Tn-1], predict the next token Tn.

**Format:**
```json
{
  "sequence_id": "desktop-01:session-1234",
  "hostname": "desktop-01",
  "origin": "windows_etw",
  "tokens": ["abc123", "def456", "ghi789", "jkl012"],
  "token_labels": ["ProcessCreate svchost.exe", "TCP Connect :443", "DNS Query", "ProcessCreate cmd.exe"],
  "techniques": ["T1055.012", null, null, "T1059.003"],
  "timestamp_start": 1717000000000,
  "timestamp_end": 1717000300000,
  "sequence_length": 4
}
```

### 2. Attack Classification

**Task:** Given token features (event type, process context, payload), predict the ATT&CK technique(s) in play.

**Format:**
```json
{
  "payload_token": "abc123",
  "features": {
    "event_type": "process_start",
    "provider": "Microsoft-Windows-Sysmon",
    "process_name": "cmd.exe",
    "command_line": "cmd.exe /c whoami",
    "parent_process": "explorer.exe",
    "enrichment_text": "The event shows a Windows command shell...",
    "embedding_vector": [0.012, -0.034, ...]
  },
  "labels": ["T1059.003"],
  "label_confidence": 0.94,
  "validation_status": "validated",
  "analyst_correction": null
}
```

### 3. Anomaly Detection

**Task:** Given a transition (from_token, to_token) with features, predict whether it is anomalous.

**Format:**
```json
{
  "from_token": "abc123",
  "to_token": "def456",
  "features": {
    "count": 15,
    "probability": 0.001,
    "entropy": 6.8,
    "surprise_score": 9.97,
    "from_technique": "T1055.012",
    "to_technique": "T1059.003",
    "hostname": "desktop-01",
    "origin_from": "windows_etw",
    "origin_to": "windows_etw"
  },
  "label": "anomalous",
  "label_source": "threshold_3.0_bits",
  "analyst_verdict": "true_positive"
}
```

### 4. Semantic Contrastive

**Task:** Learn semantically similar token representations from pairs of tokens and their enrichment descriptions.

**Format:**
```json
{
  "anchor_token": "abc123",
  "anchor_text": "Windows command shell execution by svchost.exe...",
  "positive_token": "def456",
  "positive_text": "Suspicious parent-child process relationship...",
  "negative_token": "xyz999",
  "negative_text": "Normal DNS resolution for Windows Update...",
  "anchor_cluster": "cluster_042",
  "similarity_anchor_positive": 0.89,
  "similarity_anchor_negative": 0.12
}
```

### 5. Behavioral Completion

**Task:** Given a partial sequence with a gap, predict the missing token(s).

**Format:**
```json
{
  "sequence_id": "desktop-01:session-1234",
  "prefix": ["abc123", "def456"],
  "target": "ghi789",
  "suffix": ["jkl012"],
  "hostname": "desktop-01",
  "origin": "windows_etw",
  "target_technique": "T1071.001",
  "context_length": 5
}
```

---

## Dataset Export Pipeline

```mermaid
flowchart TD
    Trigger["Export Trigger<br/>Scheduled or manual"] --> Filter["Filter tokens by:<br/>- Date range<br/>- Origin<br/>- Validation status<br/>- Analyst verdict<br/>- Cluster membership"]
    Filter --> Split["Train/val/test split<br/>Stratified by technique<br/>and hostname"]
    Split --> Format["Format conversion<br/>jsonl + csv"]
    Format --> Validate["Schema validation<br/>Required fields check<br/>Label distribution stats"]
    Validate --> Write["Write to disk<br/>+ training_corpus metadata<br/>in MongoDB"]
    Write --> Notify["Export complete<br/>recorded in training_corpus<br/>collection with stats"]
```

Dataset exports are reproducible. The metadata written to the `training_corpus` collection records the exact filter parameters, split ratios, source collection states, and token counts so any export can be recreated or audited.

---

## The Training Flywheel

```mermaid
graph TB
    subgraph Platform["WindOH Platform"]
        Ingest["Telemetry Ingestion<br/>multi-origin normalization"]
        Enrich["Token Link Enrichment<br/>LLM + SearXNG + ART"]
        Markov["Markov Chain Modeling<br/>transitions + surprise scores"]
        Export["Dataset Factory<br/>5 training corpus types"]
    end

    subgraph Training["Downstream Training"]
        Train["Train models on<br/>exported datasets"]
        Eval["Evaluate model quality<br/>against ART ground truth<br/>and analyst verdicts"]
    end

    subgraph Refine["Human Refinement"]
        Analyst["Analyst reviews<br/>Correct labels<br/>Annotate anomalies"]
        Engineer["Engineer tunes<br/>Thresholds, normalizer,<br/>model parameters"]
    end

    Ingest --> Enrich
    Enrich --> Markov
    Markov --> Export
    Export --> Train
    Train --> Eval
    Eval -->|"Model quality metrics<br/>FP rate, recall, precision"| Refine
    Analyst -->|"Corrected labels<br/>Annotated tokens"| Enrich
    Engineer -->|"Tuned parameters<br/>New origin support"| Ingest
    Enrich -.->|"Improved enrichment<br/>Better labels"| Markov
    Markov -.->|"Better transitions<br/>Cleaner anomaly signal"| Export
```

This is the long-term thesis. The platform ingests telemetry, enriches it, models it, and exports it. Downstream models train on the exports. Their quality metrics flow back to analysts and engineers, who refine the platform. Better enrichment produces better models. Better models produce better anomaly detection. Better anomaly detection produces fewer false positives for analysts. Analyst feedback improves enrichment. The cycle accelerates.

---

## Security Architecture

```mermaid
graph TB
    subgraph Edge["Network Edge"]
        CF["Cloudflare Tunnel<br/>windoh.us"]
        Nginx["nginx Ingress<br/>TLS termination"]
        CSP["Strict CSP + HSTS<br/>X-Frame-Options DENY"]
    end

    subgraph Auth["Authentication"]
        Argon["Argon2 Password Hashing<br/>per-instance pepper"]
        JWT["JWT Sessions (jose)<br/>HttpOnly Secure SameSite"]
        TOTP["TOTP Multi-Factor<br/>otplib"]
        WebAuthn["WebAuthn Passkeys<br/>@simplewebauthn/server"]
    end

    subgraph AuthZ["Authorization"]
        RBAC["Role-Based Access Control<br/>roles, permissions, policy engine"]
        Audit["Tamper-Evident Audit Chain<br/>per-shard sequencers"]
    end

    subgraph Data["Data Protection"]
        E2E["E2E Encryption<br/>X25519/Ed25519 libsodium<br/>(collab messages)"]
        KMS["KMS Master Key<br/>32-byte hex<br/>(encryption at rest)"]
        APIKey["ES API-Key Auth<br/>(telemetry store)"]
    end

    subgraph Pod["Pod Security (K8s)"]
        NonRoot["Non-root user"]
        ReadOnly["readOnlyRootFilesystem"]
        DropCaps["All capabilities dropped"]
        NetPol["Deny-all-default<br/>NetworkPolicy"]
    end

    CF --> Nginx
    Nginx --> CSP
    Nginx --> Argon
    Argon --> JWT
    JWT --> TOTP
    JWT --> WebAuthn
    JWT --> RBAC
    RBAC --> Audit
    Audit --> E2E
    E2E --> KMS
    KMS --> APIKey
    CSP --> Pod
    RBAC --> Pod
    NetPol --> Pod
```

---

## Kubernetes Deployment

```mermaid
graph TB
    subgraph NS["namespace: windoh-core"]
        subgraph Web["web Deployment"]
            WebPod1["web pod 1"]
            WebPod2["web pod 2"]
            WebPodN["web pod N<br/>(3-12, HPA CPU 70% / Mem 75%)"]
        end

        subgraph Col["collab-gateway Deployment"]
            ColPod1["gateway pod 1"]
            ColPod2["gateway pod 2"]
            ColPodN["gateway pod N<br/>(5-30, HPA WS connections)"]
        end

        subgraph Agent["agent-orchestrator Deployment"]
            AgentPod1["orchestrator pod 1"]
            AgentPod2["orchestrator pod 2"]
        end

        subgraph PDB["Pod Disruption Budgets"]
            WebPDB["web: minAvailable=1"]
            ColPDB["collab: minAvailable=2"]
        end
    end

    Web --> Col
    Web --> Agent
    Col --> Agent
```

Images are pinned by SHA256 digest from `ghcr.io/windoh/*`. Each process carries a distinct `WINDOH_AUDIT_SHARD` (web, collab, agent) so audit event sequencers never race across process boundaries.

---

## Operational Dashboard

The Next.js 14 analyst dashboard at **windoh.us** provides:

| Panel | Content |
|---|---|
| **Intelligence Overview** | Tokens indexed, enrichment rate, sequences, transitions |
| **ATT&CK Validation** | validated / partial / mismatch / unknown breakdown |
| **Technique Heatmap** | Top 20 most common ATT&CK techniques |
| **Pipeline Status** | Docs fetched, persisted, duplicates, errors, last run |
| **Queue Health** | Waiting, active, completed, failed, delayed per queue |
| **Recent Telemetry** | Latest tokens with hostname, event type, confidence, status |
| **Surprising Transitions** | Highest surprise score Markov transitions |
| **Connection Indicators** | MongoDB, Redis, Elasticsearch status badges |

All metrics refresh every 15 seconds. The dashboard is dark-themed, built with TailwindCSS, and includes a sidebar, command palette, session/security HUD, and AI agent collaboration panel.

---

## Summary

WindOH is a platform for turning raw endpoint telemetry into structured, validated, and trainable behavioral intelligence. It operates at **windoh.us**.

It is architected around five principles:

1. **Universal behavioral fingerprinting** via deterministic payload tokens.
2. **Origin-agnostic ingestion** designed for Windows, Linux, macOS, Kubernetes, and hypervisor telemetry.
3. **Markov chain prediction** that models behavioral sequences, detects anomalies, and forecasts next events.
4. **Token links as a training ground** where enrichment, validation, embeddings, and analyst feedback accumulate into richly annotated training artifacts, refined over time through joint engineer-analyst review.
5. **Shared mental maps** that formalize analyst understanding into durable, queryable, collaborative artifacts so insight compounds across investigations and across time.
