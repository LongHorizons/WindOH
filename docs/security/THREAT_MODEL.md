# Threat Model

## Trust Boundaries

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                               Trust Zone: Endpoint                               │
│                                                                                  │
│  ┌──────────────────────────────────────┐                                        │
│  │ LongHorizons Agent                    │  Trust: SYSTEM                        │
│  │ - DPAPI-protected master key          │  Threat: Local privilege escalation   │
│  │ - AES-256-GCM encrypted data at rest  │         could read process memory      │
│  │ - SQLite with WAL mode                │                                        │
│  └──────────────┬───────────────────────┘                                        │
│                 │                                                                 │
│  ┌──────────────▼───────────────────────┐  ┌────────────────────────────────┐    │
│  │ LessVolatile                          │  │ OneDriveStandaloneUpdaterr     │    │
│  │ Trust: Operator invoked               │  │ Trust: Operator invoked        │    │
│  │ Threat: Malicious memory image        │  │ Threat: Target endpoint may    │    │
│  │         crafted to exploit Volatility │  │         be compromised; PsExec │    │
│  │         plugin parser bugs            │  │         runs as SYSTEM on it   │    │
│  └──────────────────────────────────────┘  └────────────────────────────────┘    │
│                                                                                  │
└──────────────────────────────────────┬──────────────────────────────────────────┘
                                       │
                          TLS + API Key│
                                       │
┌──────────────────────────────────────▼──────────────────────────────────────────┐
│                              Trust Zone: Transport                                │
│                                                                                  │
│  ┌──────────────────────────────────────┐                                        │
│  │ Elasticsearch                         │  Trust: API-key authenticated         │
│  │ - events / exemplars / patterns       │  Threat: Unauthorized read of event    │
│  │ - diagnostics                         │         data; index deletion          │
│  │ - ILM: 7d hot → warm → 90d delete    │                                        │
│  └──────────────┬───────────────────────┘                                        │
│                 │                                                                 │
└─────────────────┼────────────────────────────────────────────────────────────────┘
                  │
       TLS (HTTPS)│
                  │
┌─────────────────▼────────────────────────────────────────────────────────────────┐
│                            Trust Zone: Application Host                           │
│                                                                                  │
│  ┌────────────┐  ┌─────────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐   │
│  │ WindOH API  │  │ Enrichment  │  │ MongoDB  │  │  Redis   │  │ SearXNG     │   │
│  │ (Next.js)  │  │ Worker      │  │          │  │          │  │ Client      │   │
│  │            │  │ (BullMQ)    │  │          │  │          │  │             │   │
│  │ Trust:     │  │ Trust:      │  │ Trust:   │  │ Trust:   │  │ Trust:      │   │
│  │ App logic  │  │ Job exec    │  │ DB       │  │ Queue    │  │ Metasearch  │   │
│  │            │  │             │  │          │  │          │  │             │   │
│  │ Threats:   │  │ Threats:    │  │ Threats: │  │ Threats: │  │ Threats:    │   │
│  │ SSRF,      │  │ Malicious   │  │ Unauthor-│  │ Queue    │  │ SSRF via    │   │
│  │ injxn,     │  │ LLM output  │  │ ized DB  │  │ poison   │  │ search      │   │
│  │ auth bypass│  │ in prompt   │  │ access   │  │          │  │ terms       │   │
│  └──────┬─────┘  └──────┬──────┘  └────┬─────┘  └────┬─────┘  └──────┬──────┘   │
│         │               │             │             │               │           │
└─────────┼───────────────┼─────────────┼─────────────┼───────────────┼───────────┘
          │               │             │             │               │
          ▼               ▼             ▼             ▼               ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Trust Zone: AI / External                           │
│                                                                                  │
│  ┌──────────────────────┐                   ┌──────────────────────┐             │
│  │ Local LLM             │                   │ SearXNG               │             │
│  │ (llama.cpp/Ollama)    │                   │ (metasearch engine)   │             │
│  │                       │                   │                       │             │
│  │ Trust: On-prem infra  │                   │ Trust: Public web     │             │
│  │ Threat: Prompt         │                   │ Threat: Search terms  │             │
│  │ injection via event    │                   │ could leak IOCs;     │             │
│  │ fields; model outputs  │                   │ results may contain  │             │
│  │ ingested without       │                   │ malicious content    │             │
│  │ validation             │                   │                       │             │
│  └──────────────────────┘                   └──────────────────────┘             │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Threat Catalog

### 1. Prompt Injection via Event Fields

**Surface:** LLM enrichment receives a structured prompt containing raw event data (command lines, network targets, file paths). An attacker who controls these fields (by executing specifically crafted commands) can inject text into the LLM prompt.

**Impact:** The LLM may produce attacker-influenced enrichment output (misleading descriptions, suppressed risk assessments, incorrect MITRE mappings).

**Mitigations:**
- Event fields in the enrichment prompt are JSON-escaped and delimited with explicit boundary markers (`---BEGIN EVENT DATA---` / `---END EVENT DATA---`).
- The structured JSON response format constrains the LLM to produce parseable output — free-form text injection cannot change the parsed structure.
- Enrichment output is advisory, not enforcement. An analyst reviews the enrichment, not an automated system acting on it.
- All enrichment carries provenance: the raw prompt and raw response are stored alongside the parsed output for audit.

### 2. Malicious Memory Image (Volatility Parser Exploitation)

**Surface:** LessVolatile passes a user-supplied memory image to Volatility 3 plugins. A crafted memory image could exploit parser vulnerabilities in Volatility plugins.

**Impact:** Arbitrary code execution within the LessVolatile process context, which inherits the operator's privileges.

**Mitigations:**
- LessVolatile is a launcher, not a parser. Volatility 3 runs in an embedded Python interpreter, which provides memory safety for Python-level code (but not for C extensions).
- The operator should run LessVolatile with least privilege — SYSTEM is not required for memory forensics.
- Plugin output is captured as CSV. Malformed output manifests as parsing errors, not code execution in the Rust host.
- Future mitigation: optional sandboxed Volatility execution via Windows job objects or restricted tokens.

### 3. Elasticsearch Unauthorized Access

**Surface:** Elasticsearch stores behavioral events, exemplars, and diagnostics. An attacker with network access to the ES cluster could read or delete this data.

**Impact:** Exposure of behavioral telemetry (process trees, network targets, command lines). Deletion of evidence.

**Mitigations:**
- API key authentication is mandatory for the agent → ES connection.
- ES should be deployed on an internal network, not internet-facing.
- ILM policies auto-delete data after 90 days, limiting the window of exposure.
- TLS encryption in transit (HTTPS) for all ES connections.

### 4. PsExec Remote Execution Abuse

**Surface:** OneDriveStandaloneUpdaterr uses embedded PsExec to execute on remote targets as SYSTEM. An attacker with network access could impersonate the operator and trigger remote collection.

**Impact:** Unauthorized forensic collection on arbitrary targets.

**Mitigations:**
- PsExec requires ADMIN$ share access, which requires domain admin or local admin credentials on the target.
- Remote collection is a deliberate operator action with explicit target specification. No automated or scheduled remote collection exists.
- The tool runs only when invoked by the operator; there is no persistent service or listening port.

### 5. LLM Output Poisoning

**Surface:** The enrichment worker stores LLM responses in MongoDB. A compromised or adversarially-influenced LLM could produce misleading enrichment that persists permanently in the knowledge base.

**Impact:** Persistent bad intelligence in the behavioral knowledge base. Incorrect MITRE mappings, suppressed risk assessments.

**Mitigations:**
- Enrichment runs exactly once per payload token. If bad enrichment is stored, the operator can delete the token document and re-trigger enrichment.
- All enrichment carries provenance: the raw prompt and raw response are stored alongside the parsed output. An operator can audit enrichment quality.
- The enrichment provides a suggested investigation step — it guides the analyst, it does not automate response.

### 6. Redis Queue Poisoning

**Surface:** BullMQ job queues in Redis. An attacker with Redis access could inject malicious jobs, delete pending jobs, or read queued data.

**Impact:** Lost enrichment jobs. Injection of malicious enrichment requests.

**Mitigations:**
- Redis is deployed on the application host's internal network. No external access.
- Redis AUTH password is configured.
- BullMQ jobs contain only payload token references, not the full event data. Event data is read from MongoDB.

### 7. DPAPI Key Extraction

**Surface:** The LongHorizons agent encrypts data at rest using a DPAPI-protected master key. An attacker with SYSTEM access on the endpoint can decrypt DPAPI-protected data.

**Impact:** Exposure of encrypted event data, AES keys, and configuration secrets.

**Mitigations:**
- DPAPI ties key protection to the service account. A different account (even Administrator) cannot decrypt.
- DPAPI is the strongest key protection available on Windows without a TPM or HSM. It is the standard for services running as LocalSystem.
- Encrypted SQLite data is at rest protection only. An attacker with SYSTEM access can also read process memory and intercept events before encryption.

---

## Risk Matrix

| Threat | Likelihood | Impact | Residual Risk | Mitigation Confidence |
|---|---|---|---|---|
| Prompt injection | Medium | Low | Low | High — structured parsing + human review |
| Malicious memory image | Low | Medium | Low-Medium | Medium — Python sandbox, operator privileges |
| ES unauthorized access | Low | High | Low | High — API key + internal network + TLS |
| PsExec abuse | Low | Medium | Low | High — credential requirement, no persistence |
| LLM output poisoning | Low | Medium | Low | Medium — one-time enrichment, provenance audit |
| Redis queue poisoning | Low | Medium | Low | High — internal network + AUTH |
| DPAPI key extraction | Low | Medium | Low-Medium | Medium — DPAPI is best available without HSM |
