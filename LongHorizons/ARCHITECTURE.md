# Architecture — LongHorizons Telemetry Agent

## Crate Dependency Graph

```mermaid
graph TB
    subgraph Binary["agent-service (binary)"]
        main["main.rs — CLI + Windows Service"]
        health["health.rs — HTTP health endpoint"]
        diagnostic["diagnostic.rs — self-monitoring"]
    end

    subgraph ETW["agent-etw — ETW Capture & Parsing"]
        session["session.rs — StartTraceW, EnableTraceEx2, ProcessTrace"]
        mapping["mapping.rs — Raw event → NormalizedEvent"]
        tdh["tdh.rs — TDH property parsing, BOM-aware UTF-16 decode"]
        semantic["semantic.rs — Provider-agnostic field classifier"]
        ntstatus["ntstatus.rs — 500+ NTSTATUS/HRESULT/DNS error codes"]
        event_desc["event_descriptions.rs — Provider/event_id → human-readable names"]
        discovery["discovery.rs — Provider auto-detection"]
        provider_f["provider_fields.rs + provider_registry.rs"]
    end

    subgraph Core["agent-core — Normalization & Baselining"]
        models["models.rs — NormalizedEvent (200+ fields, 15 structs)"]
        normalization["normalization.rs — SID/IP/path/guid normalization"]
        tokenization["tokenization.rs — Deterministic base/payload token hashing"]
        pipeline["pipeline.rs — BaseliningPipeline, process cache, ES doc builder"]
        sharded["sharded_pipeline.rs — 8-way hash-sharded ingest"]
        cms["cms.rs — Count-Min Sketch"]
        reservoir["reservoir.rs — Exemplar reservoir sampling"]
        db["db.rs — SQLite WAL, AES-256-GCM encrypted blobs"]
        crypto["crypto.rs — HKDF-SHA256 key derivation"]
        process_f["process_forensics.rs — PEB command-line reader"]
        terms["terms.rs — Search term extraction"]
    end

    subgraph Export["agent-exporter — Elasticsearch Export"]
        bulk["bulk.rs — ES _bulk API, gzip, retry, mapping conflict detection"]
        worker["worker.rs — Outbox poller"]
    end

    Binary --> ETW
    Binary --> Core
    Binary --> Export
    ETW --> Core
    Core --> Export
```

---

## Event Lifecycle

```mermaid
flowchart LR
    subgraph Phase1["Phase 1: ETW Capture"]
        A["Windows Kernel"] -->|"EVENT_RECORD"| B["ProcessTrace callback"]
        B --> C["TdhGetEventInformation()"]
        C --> D["TdhGetProperty() × N"]
        D --> E["bytes_to_json_value()"]
    end

    subgraph Phase2["Phase 2: Data Sanitization"]
        E --> F{"All-zero bytes?"}
        F -->|yes| NULL1["→ Null"]
        F -->|no| G{"UTF-16 LE decode"}
        G -->|"printable?"| H["→ String"]
        G -->|"CJK/PUA >40%?"| I["UTF-16 BE fallback"]
        I --> H
        G -->|"garbage"| J{"printable ratio >50%?"}
        J -->|yes| K["→ {hex, raw}"]
        J -->|no| NULL2["→ Null"]
    end

    subgraph Phase3["Phase 3: Semantic Classification"]
        H --> L["classify_fields() — pattern match on TDH property names"]
        K --> L
        L --> M["infer_event_type() — provider-aware type inference"]
        M --> N["38 event types recognized"]
    end

    subgraph Phase4["Phase 4: Enrichment"]
        N --> O["PEB command-line backfill"]
        O --> P["NTSTATUS → human-readable"]
        P --> Q["DNS codes → names"]
        Q --> R["Integrity → name resolution"]
        R --> S["File attributes → decoded"]
        S --> T["IP class + port service names"]
        T --> U["Parent/grandparent cache backfill"]
    end

    subgraph Phase5["Phase 5: Tokenization"]
        U --> V["build_tokens() — 38 type-specific builders"]
        V --> W["sanitize_token_value() — reject AAA=, hex pointers, numeric IDs"]
        W --> X["stable_token = SHA-256(behavior skeleton)"]
        W --> Y["payload_token = SHA-256(behavior + details)"]
    end

    subgraph Phase6["Phase 6: Baselining"]
        X --> Z["CMS frequency estimation"]
        Y --> Z
        Z --> AA["Decay-weighted rarity scoring"]
        AA --> AB["Reservoir sampling for exemplars"]
        AB --> AC["Write to outbox tables"]
    end

    subgraph Phase7["Phase 7: Export"]
        AC --> AD["Bulk assembly (gzip)"]
        AD --> AE["POST /_bulk"]
        AE -->|success| AF["Mark sent"]
        AE -->|"400 mapping conflict"| AG["Log field name + reason"]
        AE -->|"429/5xx"| AH["Retry with backoff"]
    end
```

---

## Semantic Classification Pipeline

```mermaid
flowchart TD
    EVENT["Raw ETW Event\n(provider + event_id + TDH properties)"]

    EVENT --> GUESS["guess_event_type()\nProvider + event_id → type hint"]
    GUESS --> CLASSIFY["classify_fields()\nMatch TDH property names against\n15 field-type pattern sets"]

    CLASSIFY --> PROC["Process patterns\n(pid, image, cmdline, integrity, user)"]
    CLASSIFY --> NET["Network patterns\n(src_ip, dst_ip, port, protocol, state)"]
    CLASSIFY --> FILE["File patterns\n(path, name, operation, size, attributes)"]
    CLASSIFY --> REG["Registry patterns\n(key_path, value_name, hive, operation)"]
    CLASSIFY --> DNS["DNS patterns\n(query_name, query_type, response_code)"]
    CLASSIFY --> WMI["WMI patterns\n(operation, namespace, query, consumer)"]
    CLASSIFY --> IMG["Image Load patterns\n(module_path, checksum, timestamp, signature)"]
    CLASSIFY --> HOST["Host patterns\n(os_version, build)"]

    PROC --> VALIDATE["Field Validation Layer"]
    NET --> VALIDATE
    FILE --> VALIDATE
    REG --> VALIDATE
    DNS --> VALIDATE
    WMI --> VALIDATE
    IMG --> VALIDATE
    HOST --> VALIDATE

    VALIDATE --> V1{"looks_like_file_path()?\nRejects: pure numbers,\nhex pointers, GUIDs"}
    VALIDATE --> V2{"is_bogus_tdh_string()?\nRejects: AAA=, all-null base64,\nsingle-char garbage"}
    VALIDATE --> V3{"is_hex_pointer()?\nRejects: 0x... ≥10 hex digits"}
    VALIDATE --> V4{"Printable ratio check?\nRejects: <50% printable,\ncontrol characters"}

    V1 -->|yes| FIELDS["Clean NormalizedEvent Fields"]
    V2 -->|no| FIELDS
    V3 -->|no| FIELDS
    V4 -->|yes| FIELDS

    FIELDS --> INFER["infer_event_type(event, provider_hint)\n38 types: dns_query, registry, file,\nnetwork_connect, wmi, image_load,\nantimalware, com_classic, rpcss,\ncapi2, ntfs, win32k, schannel,\nappmodel, shell_core, system_trace,\nmemory_operation, power_state,\nboot_event, bits_client,\nfilter_manager, dotnet_runtime,\nwininet, winhttp, service,\nsmb_client, vbscript,\ntask_scheduler, applocker,\ndefender*, threat_intelligence,\nprocess_forensic, thread_operation,\nprocess_start/end/operation,\ngeneric"]

    FIELDS --> DESC["Description Enrichment\nevent_name = get_event_name()\nseverity = get_severity_name()\ncategory = get_category_name()\ndescription_raw = formatted summary"]
```

---

## Data Sanitization — Garbage Detection

```mermaid
flowchart LR
    subgraph Input["TDH Raw Bytes"]
        A["byte buffer from\nTdhGetProperty()"]
    end

    subgraph Checks["Sanitization Gates"]
        A --> C1{"all bytes == 0?"}
        C1 -->|yes| NULL["→ Null\n(empty UNICODE_STRING,\nnot-set fields)"]

        C1 -->|no| C2{"valid UTF-16LE string?"}
        C2 -->|"yes, printable"| STR["→ String"]

        C2 -->|"no, >40% CJK/PUA"| BE["Try UTF-16BE\nbyte-swap fallback"]
        BE --> STR

        C2 -->|"has letters but\ncontrol chars"| C3{"printable ratio\n>50%?"}
        C3 -->|yes| WRAP["→ {hex, raw}\n(no ascii field\nif <70% printable)"]
        C3 -->|no| NULL

        C2 -->|"valid GUID"| GUID["→ GUID string"]
        C2 -->|"u32/u64 number"| NUM["→ Number"]
    end

    subgraph Token["Token-Level Sanitization"]
        STR --> T1{"sanitize_token_value()"}
        WRAP --> T1
        T1 -->|"AAA= / all-null base64"| REJECT1["Reject"]
        T1 -->|"pure decimal >6 digits"| REJECT2["Reject"]
        T1 -->|"0x... hex pointer"| REJECT3["Reject"]
        T1 -->|"all-hex ≥16 chars"| REJECT4["Reject"]
        T1 -->|"control chars / U+FFFD"| REJECT5["Reject"]
        T1 -->|"valid text"| HASH["→ Token Hash"]
    end
```

---

## Token Construction

```mermaid
flowchart TD
    EV["NormalizedEvent\n(clean fields only)"] --> MATCH{"event_type?"}

    MATCH -->|"process_start"| PS["build_process_start_tokens()"]
    MATCH -->|"process_end/operation"| PE["build_process_end_tokens()"]
    MATCH -->|"network_connect"| NET["build_network_connect_tokens()"]
    MATCH -->|"dns_query"| DNS["build_dns_query_tokens()"]
    MATCH -->|"registry"| REG["build_registry_tokens()"]
    MATCH -->|"image_load/unload"| IMG["build_image_load_tokens()"]
    MATCH -->|"file"| FILE["build_file_tokens()"]
    MATCH -->|"wmi"| WMI["build_wmi_tokens()"]
    MATCH -->|"thread_*"| THR["build_thread_tokens()"]
    MATCH -->|"antimalware"| AM["build_antimalware_tokens()"]
    MATCH -->|"com_classic"| COM["build_com_classic_tokens()"]
    MATCH -->|"rpcss/capi2/schannel"| RPC["build_rpcss/capi2/schannel_tokens()"]
    MATCH -->|"win32k/ntfs/..."| SPEC["build_win32k/ntfs/etc_tokens()"]
    MATCH -->|"other"| GEN["build_generic_tokens()"]

    PS --> BASE["proc_base()\nimage_name, directory_class,\nsignature_bucket, hashes,\nparent image chain"]
    PE --> BASE
    NET --> BASE
    DNS --> BASE
    REG --> BASE
    IMG --> BASE
    FILE --> BASE
    WMI --> BASE
    THR --> BASE
    AM --> BASE
    COM --> BASE
    RPC --> BASE
    SPEC --> BASE
    GEN --> BASE

    BASE --> HASH1["SHA-256 → stable_token\n'What behavior happened?'"]
    BASE --> PAYLOAD["+ variable fields\n(command_line, specific IPs,\nvalues, SID, timestamps)"]
    PAYLOAD --> HASH2["SHA-256 → payload_token\n'What were the exact details?'"]

    HASH1 --> TOKEN["TokenPair { stable_token, payload_token,\nbase_canonical_json, payload_canonical_json }"]
    HASH2 --> TOKEN
```

---

## Database Schema

```mermaid
erDiagram
    BASE_TOKENS {
        blob stable_token PK "32-byte SHA-256"
        text event_type "process_start, dns_query, etc."
        text provider "ETW provider name"
        int event_id
        int total_count "Total observations"
        real decay_score "Decay-weighted frequency"
        text rarity_band "Rare, Uncommon, Common"
        blob base_canonical "Deterministic JSON"
        blob provider_props "Provider-specific metadata"
        int first_seen_unix
        int last_seen_unix
    }

    PAYLOAD_VARIANTS {
        blob payload_token PK "32-byte SHA-256"
        blob stable_token FK "Links to BASE_TOKENS"
        blob payload_canonical "Variable-detail JSON"
        int exact_count "Exact observation count"
        real decay_score
        int promoted_at_unix
    }

    OUTBOX {
        int id PK
        int priority "0=exemplar, 1=pattern, 2=event, 3=diagnostic"
        text dedup_key "Unique per document"
        blob document "JSON document bytes"
        int created_at_unix
        int sent "0=pending, 1=sent"
        int attempts "Retry count"
    }

    LOGWELL {
        int id PK
        text level "error, warn, info"
        text component "export, pipeline, etw, agent"
        text message
        text details
        int created_at_unix
    }

    EXPORT_STATE {
        blob stable_token PK
        int last_exemplar_unix
        blob last_exemplar_payload
        int last_pattern_unix
        text pattern_rarity_band
    }

    BASE_TOKENS ||--o{ PAYLOAD_VARIANTS : "has variants"
    BASE_TOKENS ||--o| EXPORT_STATE : "tracks export"
```

---

## Concurrency Model

```mermaid
flowchart TB
    subgraph MainThread["Main Thread"]
        SVC["Windows Service / CLI run"]
        ETW["ETW Session Start"]
        EXP["Exporter Worker (tokio)"]
        CFG["Config Reload Watcher"]
        HTTP["Health HTTP Server :8080"]
    end

    subgraph Callback["ETW Callback Thread (high frequency)"]
        CB["ProcessTrace callback"]
        TDH["TDH parse + sanitize"]
        MAP["map_event() → NormalizedEvent"]
        SEND["sender.send(event)"]
    end

    subgraph Pipeline["Pipeline Thread"]
        RECV["receiver.recv()"]
        ENRICH["compute_enrichments()"]
        TOK["build_tokens()"]
        SHARD["pick_shard(hash[..8])"]
    end

    subgraph Shards["8 Baselining Shards (independent locks)"]
        S0["Shard 0: CMS + Reservoir + DB"]
        S1["Shard 1: CMS + Reservoir + DB"]
        S2["Shard 2: CMS + Reservoir + DB"]
        S3["Shard 3: CMS + Reservoir + DB"]
        S4["Shard 4: CMS + Reservoir + DB"]
        S5["Shard 5: CMS + Reservoir + DB"]
        S6["Shard 6: CMS + Reservoir + DB"]
        S7["Shard 7: CMS + Reservoir + DB"]
    end

    CB --> TDH --> MAP --> SEND
    SEND --> RECV --> ENRICH --> TOK --> SHARD
    SHARD --> S0
    SHARD --> S1
    SHARD --> S2
    SHARD --> S3
    SHARD --> S4
    SHARD --> S5
    SHARD --> S6
    SHARD --> S7
```

**Key decisions:**
- `parking_lot::Mutex` everywhere — no async locks in the hot path
- 8 shards → 8 independent locks → minimal contention
- Shared caches (process identity, enrichment state) are locked briefly for read/write then released
- SQLite WAL mode handles concurrent readers + single writer

---

## Security Model

```mermaid
flowchart TD
    BOOT["Machine Boot / First Run"] --> GEN["Generate master_key\n(256-bit random)"]
    GEN --> DPAPI["DPAPI::Protect(LocalMachine, master_key)"]
    DPAPI --> DISK["Write to state_dir/master_key.bin"]

    DISK --> DERIVE["On restart: DPAPI::Unprotect → master_key"]
    DERIVE --> HKDF["HKDF-SHA256 derive purpose keys:"]
    HKDF --> K1["outbox_key = HKDF(master, 'outbox', 'agent.db')"]
    HKDF --> K2["patterns_key = HKDF(master, 'patterns', 'agent.db')"]
    HKDF --> K3["events_key = HKDF(master, 'events', 'agent.db')"]

    K1 --> ENC["AES-256-GCM encrypt\nsensitive DB fields before write"]
    K2 --> ENC
    K3 --> ENC
```

---

## Config Defaults

The agent ships with **maximum data collection** defaults:

| Setting | Default | Notes |
|---------|---------|-------|
| Provider mode | `all` | Auto-discovers every registered ETW provider |
| Semantic mode | `true` | Provider-agnostic field classification |
| Allow raw fields | `true` | Include raw TDH properties in ES documents |
| Gzip | `true` | Compress _bulk requests |
| Decay half-life | 30 days | Recency weighting for rarity scoring |
| Reservoir size | 100 per stable token | Exemplar samples retained |
| Shard count | 8 | Independent baselining pipelines |
| Process cache size | 2,000 | PID → identity lookups |
| Promoted payload cache | 100,000 | Exact counting threshold |

---

*Document updated 2026-05-29 — Reflects v0.1.0 architecture with data quality overhaul*
