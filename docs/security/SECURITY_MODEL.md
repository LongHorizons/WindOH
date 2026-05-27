# Security Architecture

## Overview

The WindOH platform handles the most sensitive data in a security operations environment: process command lines, network targets, user identities, and behavioral telemetry. The security architecture is designed around the principle that this data must never leave the operational boundary in plaintext, and encryption at rest must be mandatory, not optional.

---

## Key Management

### Agent-Side (LongHorizons)

```
┌─────────────────────────────────────────────────────────────┐
│                    Key Derivation Chain                       │
│                                                              │
│  Windows DPAPI                                                │
│  (tied to LocalSystem service account)                        │
│      │                                                       │
│      ▼                                                       │
│  Master Key (256-bit)                                        │
│  DPAPI-protected, stored in agent config directory            │
│      │                                                       │
│      ├──► HKDF-SHA256(salt="events", info="aes-gcm")         │
│      │         │                                              │
│      │         ▼                                              │
│      │    Events Key → AES-256-GCM encrypt(event_json)       │
│      │                                                       │
│      ├──► HKDF-SHA256(salt="tokens", info="aes-gcm")         │
│      │         │                                              │
│      │         ▼                                              │
│      │    Tokens Key → AES-256-GCM encrypt(token_data)       │
│      │                                                       │
│      └──► HKDF-SHA256(salt="config", info="aes-gcm")         │
│                │                                              │
│                ▼                                              │
│           Config Key → AES-256-GCM encrypt(config_secrets)   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Rationale for HKDF-derived keys:**
- Compromise of one data category's key does not compromise others
- Key rotation does not require re-encrypting all data — rotate master, derive new purpose keys
- Purpose-binding via HKDF `info` parameter prevents key reuse across categories

**Why DPAPI:**
- Tied to the service account — even Administrator cannot decrypt without the service account context
- No key material stored in plaintext — the master key blob is opaque
- Standard Windows cryptographic subsystem — no custom key storage implementation

### Application-Side (WindOH)

```
┌─────────────────────────────────────────────────────────────┐
│                 Application Secrets                           │
│                                                              │
│  Environment variables (.env file or K8s secrets)            │
│      │                                                       │
│      ├── MONGODB_PASSWORD                                    │
│      ├── REDIS_PASSWORD                                      │
│      ├── ES_API_KEY                                          │
│      └── NEXT_AUTH_SECRET                                    │
│                                                              │
│  .env file: chmod 600, never committed                       │
│  K8s: Kubernetes Secrets with RBAC                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Encryption at Rest

| Store | Method | Key Source |
|---|---|---|
| Agent SQLite | AES-256-GCM per-row encryption | HKDF-derived from DPAPI master |
| MongoDB | Optional: MongoDB encrypted storage engine | MongoDB key management |
| Redis | AOF file on encrypted volume | OS-level (LUKS, BitLocker) |
| Elasticsearch | ES encrypted index feature | ES keystore |

### Agent Encryption Detail

Event data is encrypted before writing to SQLite:

```rust
// Conceptual — actual implementation in agent-core/crypto.rs
fn encrypt_event(key: &[u8; 32], event: &NormalizedEvent) -> Vec<u8> {
    let nonce = generate_nonce(); // 96-bit random
    let plaintext = serde_json::to_vec(event).unwrap();
    let ciphertext = aes_256_gcm_encrypt(key, &nonce, &plaintext);
    
    // Prepend nonce to ciphertext for decryption
    let mut output = Vec::with_capacity(12 + ciphertext.len());
    output.extend_from_slice(&nonce);
    output.extend_from_slice(&ciphertext);
    output
}
```

Fields excluded from encryption (needed for SQLite indexing): `id`, `timestamp`, `event_type`, `stable_hash`.

---

## Encryption in Transit

| Connection | Protocol | Authentication |
|---|---|---|
| Agent → Elasticsearch | HTTPS (TLS 1.2+) | ES API key in Authorization header |
| ES → WindOH API | HTTPS (TLS 1.2+) | ES API key |
| WindOH API → MongoDB | TLS (MongoDB wire protocol) | SCRAM-SHA-256 |
| WindOH API → Redis | TLS (Redis 6+ with stunnel if needed) | AUTH password |
| WindOH → LLM | HTTP (assumed local network) | None (local network boundary) |
| WindOH → SearXNG | HTTP (assumed local network) | None (local network boundary) |

**Note on LLM+SearXNG over HTTP:** These connections are assumed to be within the same network boundary (localhost or same host). If the LLM or SearXNG is on a different host, TLS should be configured.

---

## Authentication

### Agent → Elasticsearch
- API key authentication is mandatory
- API key is stored in `config.toml` (recommended: DPAPI-encrypted)
- Key has minimal privileges: `create_index`, `index`, `read` on `longhorizons-*` indices only

### WindOH API
- Current: Network isolation (API not exposed beyond application host)
- Planned: NextAuth.js OIDC for human users; API keys for service accounts

---

## Data Minimization

### What the Agent Exports

The agent exports four document types. The `events` type is the one that contains behavioral data:

**Fields included in exported events:** `stable_hash`, `payload_hash`, `event_type`, `decay_score`, `rarity_band`, `behavior_tags`, `inter_event_delta_ms`, `tree_depth`, `ancestor_chain_hash`, `field_completeness_score`

**Fields NOT exported:** Raw command lines, raw IP addresses, raw file paths, user account names. These are available in the `exemplars` index (one per behavioral pattern, not one per event) or via the `payload_hash` which can be correlated with external data.

### What the LLM Receives

The enrichment prompt contains the event data necessary for behavioral analysis, but the LLM is a local inference endpoint — no data transits the public internet. The prompt format is controlled and event fields are bounded (truncated command lines, limited to top-N network targets).

---

## Incident Response

### Credential Rotation Procedure

If any credential is suspected compromised:

1. **ES API key:** Create new key, update all agent configs, revoke old key (see [Runbook 4](../operations/RUNBOOKS.md))
2. **MongoDB password:** Rotate password, update WindOH `.env`, restart app + workers
3. **Redis password:** Rotate password, update WindOH `.env`, restart app + workers
4. **Agent DPAPI master key:** Reinstall agent service (generates new master), accept loss of historical encrypted data (events re-export from agent's in-memory pipeline buffer)

### Data Exposure Assessment

If Elasticsearch is accessed by an unauthorized party:
- Events contain `stable_hash` and `payload_hash` — not raw command lines or IPs directly
- Hash preimage attacks are computationally infeasible (SHA-256)
- Rarity bands and decay scores are aggregate statistics, not raw telemetry
- Exemplars contain one sample per behavioral pattern — not all instances
