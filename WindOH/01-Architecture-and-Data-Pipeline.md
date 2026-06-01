# Architecture and Data Pipeline

---

## System Topology

```mermaid
graph TB
    subgraph External["External Infrastructure"]
        ES["Elasticsearch 8.x<br/>192.168.0.50:9200<br/>API-Key Auth"]
        LLM["PartiriOne LLM<br/>192.168.0.133:31337/v1<br/>OpenAI-compatible"]
        SearX["SearXNG<br/>192.168.0.133:31340<br/>Metasearch Engine"]
    end

    subgraph Local["Local Development Services"]
        Mongo["MongoDB 7<br/>Docker Container"]
        Redis["Redis 7<br/>Docker Container"]
    end

    subgraph Processes["WindOH Processes"]
        Web["apps/web<br/>Next.js 14 Dashboard<br/>Port 3000"]
        Collab["apps/collab-gateway<br/>WebSocket Server<br/>Port 3002"]
        Agent["apps/agent-orchestrator<br/>BullMQ Worker<br/>Background Jobs"]
    end

    subgraph K8s["Kubernetes (Production)"]
        KWeb["web Deployment<br/>3-12 replicas<br/>HPA: CPU 70%"]
        KCol["collab-gateway Deployment<br/>5-30 replicas<br/>HPA: WS connections"]
        KAge["agent-orchestrator Deployment<br/>2 replicas"]
        Nginx["nginx Ingress<br/>Cloudflare Tunnel"]
    end

    Nginx --> KWeb
    Nginx --> KCol
    Redis --> KAge
    Mongo --> KWeb
    Mongo --> KAge
    ES --> KAge
    LLM --> KAge
    SearX --> KAge
```

---

## Data Pipeline: Ingest to Insight

```mermaid
sequenceDiagram
    participant Agent as LongHorizons Agent
    participant ES as Elasticsearch
    participant Poll as Ingestion Poller
    participant Norm as Normalizer
    participant Mongo as MongoDB
    participant Enrich as Enrichment Engine
    participant Valid as ATT&CK Validator
    participant Markov as Markov Model
    participant Embed as Embedding Engine
    participant Graph as Graph Builder
    participant Dataset as Dataset Factory

    Agent->>ES: ETW Telemetry Events
    Poll->>ES: Poll every 10s (cursor-based)
    ES-->>Poll: New telemetry-patterns docs
    Poll->>Norm: Raw ES documents
    Norm->>Norm: Extract payload_token from tokens.payload
    Norm->>Norm: Normalize to canonical schema
    Norm->>Norm: Within-batch dedup by token hash
    Norm->>Mongo: Check existing tokens
    Mongo-->>Norm: Existing token hashes
    Norm->>Mongo: Bulk insert new tokens
    Norm->>ES: Update checkpoint cursor
    Poll->>Enrich: New tokens queued
    Enrich->>Enrich: LLM 9-dimension analysis
    Enrich->>Enrich: SearXNG web augmentation
    Enrich->>Mongo: Write enrichment with provenance
    Enrich->>Valid: Trigger validation
    Valid->>Valid: Compare expected vs inferred techniques
    Valid->>Mongo: Write validation result
    Enrich->>Markov: Append to event sequences
    Markov->>Markov: Build first-order transitions
    Markov->>Markov: Score surprise per transition
    Markov->>Mongo: Write transitions and anomaly flags
    Enrich->>Embed: Generate embedding vector
    Embed->>Embed: Cosine similarity clustering
    Embed->>Mongo: Write clusters and centroids
    Graph->>Mongo: Build 7-type relationship edges
    Dataset->>Mongo: Export training corpora
```

---

## Canonical Normalization

Every incoming telemetry document passes through the normalizer (`@windoh/telemetry/normalizer.ts`). This is the critical bridge between raw, origin-specific event formats and the platform's unified token model.

```mermaid
graph LR
    subgraph Raw["Raw ES Document"]
        R1["tokens.payload<br/>(nested ES field)"]
        R2["@timestamp<br/>(ISO / unix ms / unix ns / FILETIME)"]
        R3["host.name<br/>(agent hostname)"]
        R4["event.provider / event.code"]
        R5["process.pid / process.ppid"]
        R6["network.* / registry.* / file.*"]
    end

    subgraph Canonical["Canonical Token"]
        C1["payload_token<br/>(deterministic hash)"]
        C2["timestamp (normalized unix ms)"]
        C3["hostname"]
        C4["event_type / provider"]
        C5["process_context (pid, ppid, cmdline)"]
        C6["typed_payload (network / registry / file / process)"]
    end

    R1 -->|"Extract and hash"| C1
    R2 -->|"Normalize to unix ms"| C2
    R3 -->|"Direct map"| C3
    R4 -->|"Map with lookup"| C4
    R5 -->|"Structured extract"| C5
    R6 -->|"Type-dispatch"| C6
```

The `payload_token` is drawn from `tokens.payload` -- this is the ES canonical fingerprint field. The normalizer handles multiple timestamp formats (ISO 8601 strings, unix milliseconds, unix nanoseconds, Windows FILETIME), multiple event provider schemas, and partial or malformed documents without crashing.

---

## Queue Architecture

Eight named BullMQ queues drive all background work:

```mermaid
graph LR
    subgraph Queues["BullMQ Queues (Redis-backed)"]
        Q1["ingestion<br/>ES polling and normalization"]
        Q2["enrichment<br/>LLM + SearXNG processing"]
        Q3["attack-validation<br/>ATT&CK matching"]
        Q4["markov-transition<br/>Sequence recording"]
        Q5["embedding<br/>Vector generation"]
        Q6["clustering<br/>Semantic grouping"]
        Q7["graph-relationships<br/>Edge construction"]
        Q8["dataset-export<br/>Training corpus generation"]
    end

    Q1 --> Q2
    Q2 --> Q3
    Q2 --> Q4
    Q2 --> Q5
    Q4 --> Q7
    Q5 --> Q6
    Q7 --> Q8
```

Each queue has its own concurrency, retry policy, and failure handling. The queues form a directed pipeline where ingestion feeds enrichment, enrichment fans out to validation, sequencing, and embedding, and those converge into graph construction and dataset export.

---

## MongoDB Collections

The platform maintains 30+ collections. The core operational collections are:

| Collection | Purpose |
|---|---|
| `tokens` | Normalized telemetry with full enrichment |
| `event_sequences` | Ordered behavioral sequences per host per session |
| `markov_transitions` | First-order transition probabilities |
| `attack_validations` | ATT&CK validation results per token |
| `behavioral_clusters` | Semantic clusters with centroids |
| `embedding_cache` | Deterministic embedding cache |
| `telemetry_relationships` | Multi-relational graph edges |
| `search_cache` | SearXNG query result cache |
| `art_observation_windows` | Active ART test windows per host |
| `ingestion_checkpoints` | ES polling cursor state per index |
| `mental_maps` | Analyst mental map artifacts |
| `analyst_feedback` | Analyst corrections and annotations |
| `training_corpus` | Exported dataset metadata |

---

## Ingestion Polling Loop

```mermaid
flowchart TD
    Start["Start Poll Cycle"] --> Fetch["Fetch docs from ES<br/>cursor-based pagination<br/>since last checkpoint"]
    Fetch --> Check{"Any new docs?"}
    Check -->|"No"| Sleep["Sleep INGEST_INTERVAL_MS<br/>(default 10,000ms)"]
    Sleep --> Start
    Check -->|"Yes"| Normalize["Normalize each doc<br/>to canonical schema"]
    Normalize --> Dedup["Within-batch dedup<br/>by payload_token"]
    Dedup --> CrossCheck["Cross-reference MongoDB<br/>for existing tokens"]
    CrossCheck --> Insert{"New tokens?"}
    Insert -->|"Yes"| BulkInsert["Bulk insert into tokens collection"]
    Insert -->|"No"| Checkpoint
    BulkInsert --> ART["Check active ART<br/>observation windows<br/>per host"]
    ART --> Tag["Tag tokens with<br/>expected_techniques"]
    Tag --> Enqueue["Enqueue new tokens<br/>to enrichment queue"]
    Enqueue --> Checkpoint["Update checkpoint cursor<br/>(timestamp + doc ID)"]
    Checkpoint --> Sleep
```

---

## Enrichment Detail

Each token flowing through enrichment receives a 9-dimension analysis from the PartiriOne LLM:

```mermaid
graph TB
    Token["payload_token + event data"] --> Prompt["System Prompt<br/>Expert Threat Intelligence Analyst<br/>MITRE ATT&CK v16, D3FEND, Windows Internals, APT Profiling"]

    Prompt --> D1["1. ATT&CK Technique Mapping<br/>Technique ID + confidence"]
    Prompt --> D2["2. D3FEND Countermeasures<br/>Defensive mitigations"]
    Prompt --> D3["3. Functional Analysis<br/>Windows APIs, syscalls, kernel objects"]
    Prompt --> D4["4. Origin Analysis<br/>LOLBin classification, signed/unsigned"]
    Prompt --> D5["5. Benign Rationale<br/>Enterprise software, normal operations"]
    Prompt --> D6["6. Malicious Rationale<br/>APT groups, malware families, campaigns"]
    Prompt --> D7["7. Attack Scenarios<br/>Step-by-step adversary playbooks"]
    Prompt --> D8["8. Investigation Steps<br/>Splunk/KQL queries, forensic actions"]
    Prompt --> D9["9. Related CVEs and Threat Groups"]

    D1 --> Provenance["Attach Provenance<br/>source_type, model_name, prompt_version,<br/>enrichment_version, confidence, validation_method"]
    D2 --> Provenance
    D3 --> Provenance
    D4 --> Provenance
    D5 --> Provenance
    D6 --> Provenance
    D7 --> Provenance
    D8 --> Provenance
    D9 --> Provenance

    Provenance --> Cache["Cache permanently<br/>by payload_token"]

    Cache --> SearXCheck{"SearXNG results<br/>available?"}
    SearXCheck -->|"Yes"| ExternalRef["Set validation_method<br/>= external_reference"]
    SearXCheck -->|"No"| LLMOnly["Set validation_method<br/>= llm_inference"]
```

---

## Ingestion Timings

| Parameter | Default | Description |
|---|---|---|
| `INGEST_INTERVAL_MS` | 10,000ms | ES poll interval |
| `MARKOV_REBUILD_INTERVAL_MS` | 3,600,000ms | Full Markov model rebuild |
| `MARKOV_ORDER` | 1 | Markov chain memory depth |
| `ANOMALY_THRESHOLD` | 3.0 bits | Surprise score threshold |
| `SEQUENCE_TIMEOUT_MS` | 300,000ms | Sequence break on inactivity |
