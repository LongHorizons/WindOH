# WindOH — Behavioral Telemetry Enrichment & Intelligence Platform

**Handoff Document v1.0 — Design, Architecture, and Implementation Plan**

---

## 1. Overview

WindOH is a TypeScript/MongoDB web application that consumes telemetry from the LongHorizons agent (exported to Elasticsearch), enriches each behavioral token with AI-generated context via a local LLM, builds Markov-style behavioral sequence models for prediction, maps Atomic Red Team test executions against captured telemetry, and integrates with a SearXNG metasearch stack for external threat intelligence correlation.

### 1.1 Core Value Proposition

The LongHorizons agent produces cryptographically stable behavioral tokens (`stable_hash` and `payload_hash`) at wire speed. But a hash alone doesn't tell an analyst *what the behavior means*. WindOH closes that gap:

```
stable_hash: a1b2c3... → "cmd.exe spawned whoami.exe from a temp directory
                           with encoded command line — this is a classic
                           Living-off-the-Land (LOLBin) reconnaissance pattern"
```

Every token in the system gets enriched once by the LLM, cached in MongoDB, and never needs re-enrichment. Over time, WindOH builds a behavioral knowledge base where 99% of tokens have pre-computed descriptions, MITRE ATT&CK mappings, risk assessments, and predicted next behaviors.

### 1.2 Technology Stack

| Component | Technology | Rationale |
|---|---|---|
| **Frontend** | Next.js 14 (App Router) + React 18 + TailwindCSS | Server-side rendering, fast dev iteration, large ecosystem |
| **API Layer** | Next.js API routes + tRPC | Type-safe RPC between frontend and backend, auto-generated types |
| **Database** | MongoDB 7.x with Atlas Search | Document-native for variable-depth event enrichment, full-text search on token descriptions |
| **ORM/ODM** | Mongoose 8.x | Schema validation, middleware hooks for enrichment pipeline |
| **Queue** | BullMQ + Redis | Job queues for LLM enrichment, Atomic Red Team orchestration, SearXNG scraping |
| **LLM Client** | OpenAI SDK (pointed at 192.168.0.133:31337) | Drop-in compatible with local LLM (llama.cpp, Ollama, vLLM, text-generation-webui) |
| **Elasticsearch Client** | @elastic/elasticsearch 8.x | Pull telemetry from LongHorizons ES indexes |
| **Markov Engine** | Custom TypeScript (in-memory + MongoDB persistence) | Behavioral sequence modeling, next-token prediction |
| **SearXNG Integration** | HTTP client to SearXNG JSON API | Threat intel correlation, IOC enrichment |
| **Atomic Red Team** | invoke-atomicredteam + PowerShell wrapper | Test execution, telemetry capture, coverage mapping |

---

## 2. System Architecture

```
                     ┌──────────────────────────────────────────────┐
                     │                 WindOH (Next.js)              │
                     │                                              │
   Elasticsearch     │  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
   (LongHorizons)    │  │ Enrich-  │  │ Markov   │  │ Atomic    │  │
   ──────────────────▶│  │ ment     │  │ Engine   │  │ Mapper    │  │
   events            │  │ Pipeline │  │          │  │           │  │
   exemplars         │  └────┬─────┘  └────┬─────┘  └─────┬─────┘  │
   patterns          │       │             │              │         │
                     │       ▼             ▼              ▼         │
   Local LLM         │  ┌──────────────────────────────────────┐   │
   192.168.0.133     │  │            MongoDB                    │   │
   :31337            │  │  ┌────────┐ ┌────────┐ ┌─────────┐  │   │
   ◀─────────────────│──│ tokens  │ │sequences│ │coverage │  │   │
   enrichment        │  │ └────────┘ └────────┘ └─────────┘  │   │
                     │  │  ┌────────┐ ┌────────┐              │   │
   SearXNG           │  │  │threat  │ │search  │              │   │
   metasearch        │  │  │intel   │ │cache   │              │   │
   ◀─────────────────│──│ └────────┘ └────────┘              │   │
   IOC lookup        │  └──────────────────────────────────────┘   │
                     │                                              │
   Atomic Red Team   │  ┌──────────┐  ┌──────────┐                 │
   (PowerShell)      │  │ Test     │  │ Coverage │                 │
   ◀─────────────────│──│ Runner   │  │ Reporter │                 │
   execution         │  └──────────┘  └──────────┘                 │
                     └──────────────────────────────────────────────┘
```

### 2.1 Data Flow

1. **Ingest**: WindOH polls Elasticsearch `longhorizons-events`, `longhorizons-exemplars`, and `longhorizons-patterns` indexes for new documents
2. **Token Extraction**: Extract `stable_hash`, `payload_hash`, and all enrichment fields from each event
3. **MongoDB Upsert**: Each unique `stable_hash` gets a document in the `tokens` collection. Known tokens update counters; unknown tokens trigger enrichment
4. **LLM Enrichment** (new tokens only): The enrichment pipeline sends a structured prompt to the local LLM. Response is parsed and stored
5. **Sequence Recording**: Each `agent.id` has an event sequence. Tokens are appended in temporal order for Markov modeling
6. **Markov Training**: Periodic background job rebuilds transition probability matrices from sequence data
7. **Atomic Red Team Mapping**: When ART tests run, their telemetry is cross-referenced by `stable_hash` to measure detection coverage
8. **SearXNG Integration**: IOCs (IPs, domains, hashes) extracted from events are enriched via SearXNG metasearch

---

## 3. MongoDB Schema Design

### 3.1 `tokens` Collection

The central collection. One document per unique `stable_hash`.

```typescript
// models/Token.ts
interface IToken {
  _id: ObjectId;

  // ── Identity ──
  stable_hash: string;            // Indexed, unique — the behavioral fingerprint
  payload_hashes: string[];       // Top K payload variants seen

  // ── LLM Enrichment (cached) ──
  enrichment: {
    short_description: string;    // 1-liner: "cmd.exe spawning whoami.exe"
    behavioral_meaning: string;   // 2-3 sentences: what this pattern means
    mitre_attack: string[];       // e.g. ["T1059.001", "T1033"]
    risk_level: 'low' | 'medium' | 'high' | 'critical';
    risk_rationale: string;       // Why this risk level
    lolbin_flag: boolean;         // Living-off-the-land binary involved
    data_exfil_potential: boolean;
    privilege_escalation_potential: boolean;
    persistence_potential: boolean;
    lateral_movement_potential: boolean;

    // Agentic analysis
    suggested_investigation_steps: string[];
    common_parent_processes: string[];
    common_child_processes: string[];
    related_cves: string[];
    references: string[];         // URLs or knowledge base references
  } | null;                       // null = not yet enriched

  enrichment_status: 'pending' | 'in_progress' | 'complete' | 'failed';
  enrichment_timestamp: Date | null;
  enrichment_model: string | null;  // Which LLM model produced this
  enrichment_attempts: number;

  // ── Telemetry Statistics ──
  first_seen: Date;
  last_seen: Date;
  total_occurrences: number;
  host_count: number;              // How many unique agents have seen this
  host_ids: string[];              // Last N host IDs
  rarity_band: 'Rare' | 'Uncommon' | 'Common';
  decay_score: number;
  avg_daily_frequency: number;

  // ── Event Metadata ──
  event_type: string;              // process_start, network_connect, etc.
  provider: string;                // ETW provider name
  telemetry_event_id: number;      // Normalized event ID

  // ── Key Fields (extracted for search) ──
  process_name: string | null;
  image_path_normalized: string | null;
  network_dst_ip_class: string | null;
  registry_key_path: string | null;
  behavioral_tags: string[];

  // ── SearXNG Enrichment ──
  threat_intel: {
    ioc_matches: {
      ioc_type: 'ip' | 'domain' | 'hash' | 'url';
      ioc_value: string;
      search_results: {
        title: string;
        url: string;
        snippet: string;
        source: string;
      }[];
      last_checked: Date;
    }[];
  } | null;

  // ── Timestamps ──
  created_at: Date;
  updated_at: Date;
}

// Indexes
// { stable_hash: 1 } — unique
// { 'enrichment.mitre_attack': 1 } — search by technique
// { enrichment_status: 1 } — find unenriched tokens
// { event_type: 1, rarity_band: 1 } — browse by type + rarity
// { behavioral_tags: 1 } — tag-based search
// { 'enrichment.risk_level': 1 } — filter by risk
// { $text: { 'enrichment.short_description': 'text', 'enrichment.behavioral_meaning': 'text' } } — full-text search
```

### 3.2 `event_sequences` Collection

Temporal sequences of events per host for Markov modeling.

```typescript
// models/EventSequence.ts
interface IEventSequence {
  _id: ObjectId;
  agent_id: string;               // Which host
  timestamp: Date;                // Event timestamp
  stable_hash: string;            // Which behavior
  payload_hash: string;           // Exact details
  process_pid: number;
  process_name: string;
  event_type: string;
  telemetry_event_id: number;

  // Link to enrichment
  token_id: ObjectId;             // FK → tokens collection

  // Sequence context
  prev_stable_hash: string | null;
  next_stable_hash: string | null;
  delta_ms_since_prev: number | null;
  delta_ms_to_next: number | null;

  created_at: Date;
}

// Indexes
// { agent_id: 1, timestamp: 1 } — sequence queries
// { stable_hash: 1 } — "where does this behavior appear in sequences"
// { agent_id: 1, prev_stable_hash: 1, stable_hash: 1 } — Markov transition lookup
```

### 3.3 `markov_transitions` Collection

Pre-computed transition probabilities.

```typescript
// models/MarkovTransition.ts
interface IMarkovTransition {
  _id: ObjectId;
  from_stable_hash: string;
  to_stable_hash: string;
  transition_count: number;
  probability: number;             // P(to | from)
  avg_delta_ms: number;
  stddev_delta_ms: number;
  host_count: number;              // How many hosts exhibit this transition
  last_observed: Date;

  // Chain depth
  from_token_description: string;  // Denormalized for fast display
  to_token_description: string;    // Denormalized for fast display

  updated_at: Date;
}

// Indexes
// { from_stable_hash: 1, probability: -1 } — top next predictions
// { from_stable_hash: 1, to_stable_hash: 1 } — unique transition
// { host_count: -1 } — most widespread transitions
```

### 3.4 `atomic_tests` Collection

Atomic Red Team test definitions and execution history.

```typescript
// models/AtomicTest.ts
interface IAtomicTest {
  _id: ObjectId;
  technique_id: string;            // e.g. "T1059.001"
  technique_name: string;          // e.g. "PowerShell"
  test_name: string;               // e.g. "Mimikatz"
  test_guid: string;               // ART test GUID
  test_description: string;
  test_platform: string;           // windows, linux, etc.

  // Executions
  executions: {
    execution_id: string;
    started_at: Date;
    completed_at: Date | null;
    status: 'running' | 'success' | 'failed' | 'timeout';
    agent_id: string;              // Which host ran it
    captured_event_count: number;
    captured_stable_hashes: string[];
    token_ids: ObjectId[];         // FK → tokens
  }[];

  // Coverage
  coverage: {
    events_captured: number;       // How many ETW events fired
    tokens_generated: number;      // Unique stable hashes observed
    tokens_pre_enriched: number;   // How many tokens already existed (known behavior)
    tokens_new: number;            // How many tokens were unknown (new behavior)
    detection_gap: boolean;        // true if any expected behavior was NOT captured
    gap_details: string | null;
  } | null;

  created_at: Date;
  updated_at: Date;
}

// Indexes
// { technique_id: 1 }
// { 'executions.agent_id': 1, 'executions.started_at': -1 }
```

### 3.5 `search_cache` Collection

Cached SearXNG results for IOCs and threat queries.

```typescript
// models/SearchCache.ts
interface ISearchCache {
  _id: ObjectId;
  query: string;
  query_type: 'ip' | 'domain' | 'hash' | 'cve' | 'technique' | 'general';
  results: {
    title: string;
    url: string;
    snippet: string;
    source: string;
    published_date: string | null;
  }[];
  result_count: number;
  searched_at: Date;
  ttl_days: number;               // How long before re-search
}
```

---

## 4. LLM Enrichment Pipeline

### 4.1 Prompt Template

The enrichment prompt sent to the local LLM is designed to produce structured, parseable output:

```
You are a Windows security behavioral analyst. Analyze the following ETW telemetry
token and provide a structured assessment.

## Event Token Data
- Event Type: {event_type}
- Provider: {provider}
- Telemetry Event ID: {telemetry_event_id}
- Process Name: {process_name}
- Process Path: {image_path}
- Parent Process: {parent_process_name}
- Command Line (normalized): {cmdline_normalized}
- Command Line (original): {cmdline_original}
- Network Destination IP: {dst_ip}
- Network Destination Port: {dst_port}
- Network Protocol: {protocol}
- DNS Query Name: {dns_query_name}
- Registry Key Path: {registry_key_path}
- Registry Operation: {registry_operation}
- File Path: {file_path}
- File Operation: {file_operation}
- Behavioral Tags: {behavioral_tags}
- Integrity Level: {integrity_level}
- Signed: {signed}
- Signature Publisher: {signature_publisher}
- Logon Type: {logon_type}

## Output Format
Respond with a JSON object ONLY (no markdown, no explanation):

{
  "short_description": "<one-line behavioral summary>",
  "behavioral_meaning": "<2-3 sentence analysis of what this behavior indicates>",
  "mitre_attack": ["<TXXXX.XXX>", ...],
  "risk_level": "low|medium|high|critical",
  "risk_rationale": "<why this risk level>",
  "lolbin_flag": true|false,
  "data_exfil_potential": true|false,
  "privilege_escalation_potential": true|false,
  "persistence_potential": true|false,
  "lateral_movement_potential": true|false,
  "suggested_investigation_steps": ["<step 1>", "<step 2>", ...],
  "common_parent_processes": ["<process.exe>", ...],
  "common_child_processes": ["<process.exe>", ...],
  "related_cves": ["<CVE-YYYY-XXXXX>", ...],
  "references": ["<URL or reference>", ...]
}
```

### 4.2 Enrichment Worker

```typescript
// workers/enrichment-worker.ts
import { Queue, Worker, Job } from 'bullmq';
import OpenAI from 'openai';
import Token from '@/models/Token';
import { connection } from '@/lib/redis';

const llm = new OpenAI({
  baseURL: 'http://192.168.0.133:31337/v1',
  apiKey: 'not-needed', // Local LLM typically doesn't require auth
});

const enrichmentQueue = new Queue('token-enrichment', { connection });

const worker = new Worker('token-enrichment', async (job: Job) => {
  const { tokenId, stableHash } = job.data;

  const token = await Token.findById(tokenId);
  if (!token || token.enrichment_status === 'complete') return;

  // Mark in progress
  await Token.updateOne(
    { _id: tokenId },
    { $set: { enrichment_status: 'in_progress' } }
  );

  try {
    const prompt = buildEnrichmentPrompt(token);
    const response = await llm.chat.completions.create({
      model: 'local-model', // Adjust to your local model name
      messages: [
        { role: 'system', content: 'You are a Windows security behavioral analyst.' },
        { role: 'user', content: prompt },
      ],
      temperature: 0.3,
      max_tokens: 2000,
      response_format: { type: 'json_object' },
    });

    const parsed = JSON.parse(response.choices[0].message.content);

    await Token.updateOne(
      { _id: tokenId },
      {
        $set: {
          enrichment: {
            short_description: parsed.short_description,
            behavioral_meaning: parsed.behavioral_meaning,
            mitre_attack: parsed.mitre_attack || [],
            risk_level: parsed.risk_level || 'medium',
            risk_rationale: parsed.risk_rationale || '',
            lolbin_flag: parsed.lolbin_flag || false,
            data_exfil_potential: parsed.data_exfil_potential || false,
            privilege_escalation_potential: parsed.privilege_escalation_potential || false,
            persistence_potential: parsed.persistence_potential || false,
            lateral_movement_potential: parsed.lateral_movement_potential || false,
            suggested_investigation_steps: parsed.suggested_investigation_steps || [],
            common_parent_processes: parsed.common_parent_processes || [],
            common_child_processes: parsed.common_child_processes || [],
            related_cves: parsed.related_cves || [],
            references: parsed.references || [],
          },
          enrichment_status: 'complete',
          enrichment_timestamp: new Date(),
          enrichment_model: 'local-model',
        },
      }
    );
  } catch (error) {
    await Token.updateOne(
      { _id: tokenId },
      {
        $set: { enrichment_status: 'failed' },
        $inc: { enrichment_attempts: 1 },
      }
    );
    throw error; // BullMQ will retry
  }
}, {
  connection,
  concurrency: 4, // Adjust based on LLM throughput
  limiter: {
    max: 20,        // Max 20 jobs
    duration: 60000, // Per 60 seconds
  },
});

export { enrichmentQueue, worker };
```

### 4.3 Enrichment Trigger: Polling Elasticsearch

```typescript
// jobs/poll-elasticsearch.ts
import { Client } from '@elastic/elasticsearch';
import Token from '@/models/Token';
import { enrichmentQueue } from '@/workers/enrichment-worker';

const es = new Client({ node: process.env.ES_ENDPOINT });

async function pollNewEvents() {
  const lastPoll = await getLastPollTimestamp(); // Stored in MongoDB or Redis

  const result = await es.search({
    index: 'longhorizons-events',
    body: {
      query: {
        bool: {
          must: [
            { range: { '@timestamp': { gt: lastPoll } } },
          ],
        },
      },
      size: 1000,
      sort: [{ '@timestamp': 'asc' }],
    },
  });

  const seenHashes = new Set<string>();

  for (const hit of result.hits.hits) {
    const src = hit._source as any;
    const stableHash = src.stable_hex || src.stable_hash;

    if (!stableHash || seenHashes.has(stableHash)) continue;
    seenHashes.add(stableHash);

    // Upsert token document
    const token = await Token.findOneAndUpdate(
      { stable_hash: stableHash },
      {
        $setOnInsert: {
          stable_hash: stableHash,
          payload_hashes: [],
          enrichment_status: 'pending',
          enrichment_attempts: 0,
          first_seen: new Date(),
          event_type: src.event_type || 'unknown',
          provider: src.etw?.provider || 'unknown',
          telemetry_event_id: src.telemetry_event_id || 0,
          process_name: src.process?.image_name || null,
          image_path_normalized: src.process?.image_path || null,
          behavioral_tags: src.behavioral_tags || [],
          created_at: new Date(),
        },
        $set: {
          last_seen: new Date(),
          rarity_band: src.rarity_band || 'Common',
          decay_score: src.decay_score || 0,
          updated_at: new Date(),
        },
        $inc: { total_occurrences: 1 },
        $addToSet: {
          payload_hashes: { $each: [src.payload_hex || src.payload_hash].filter(Boolean) },
          host_ids: src.agent?.id,
        },
      },
      { upsert: true, new: true }
    );

    // Queue for enrichment if new or previously failed
    if (
      token.enrichment_status === 'pending' ||
      token.enrichment_status === 'failed'
    ) {
      await enrichmentQueue.add('enrich-token', {
        tokenId: token._id.toString(),
        stableHash: stableHash,
      }, {
        jobId: `enrich-${stableHash}`,
        removeOnComplete: true,
        removeOnFail: 100,
      });
    }

    // Append to event sequence for Markov
    await appendToSequence(src);
  }

  await setLastPollTimestamp(new Date().toISOString());
}

// Run every 10 seconds
setInterval(pollNewEvents, 10_000);
```

---

## 5. Markov-Style Behavioral Sequence Engine

### 5.1 Concept

Each agent produces a temporally ordered sequence of `stable_hash` values. Over thousands of endpoints and millions of events, these sequences reveal predictable behavioral chains:

```
A → B → C with P=0.74  (e.g., cmd.exe start → whoami.exe → net.exe localgroup)
A → D → C with P=0.12  (e.g., cmd.exe start → powershell.exe → net.exe localgroup)
A → E     with P=0.08  (e.g., cmd.exe start → tasklist.exe)
```

WindOH builds a first-order Markov chain (bigram transitions) with optional N-order extension (trigram+). When an analyst queries a token, the system shows:

1. **What typically comes next** (top 5 predictions with probabilities)
2. **What typically came before** (reverse transitions)
3. **How typical this exact sequence is** (chain probability score)
4. **Anomaly flag**: if the observed next token has probability < 1%, flag it

### 5.2 Sequence Recording

```typescript
// lib/sequence-recorder.ts
import EventSequence from '@/models/EventSequence';
import Token from '@/models/Token';

async function appendToSequence(event: any) {
  const agentId = event.agent?.id;
  const stableHash = event.stable_hex || event.stable_hash;
  const payloadHash = event.payload_hex || event.payload_hash;

  if (!agentId || !stableHash) return;

  // Get the previous event for this agent to link
  const prev = await EventSequence.findOne(
    { agent_id: agentId },
    {},
    { sort: { timestamp: -1 } }
  );

  const deltaMs = prev
    ? new Date(event['@timestamp']).getTime() - prev.timestamp.getTime()
    : null;

  const seq = await EventSequence.create({
    agent_id: agentId,
    timestamp: new Date(event['@timestamp']),
    stable_hash: stableHash,
    payload_hash: payloadHash || '',
    process_pid: event.process?.pid || 0,
    process_name: event.process?.image_name || '',
    event_type: event.event_type || '',
    telemetry_event_id: event.telemetry_event_id || 0,
    prev_stable_hash: prev?.stable_hash || null,
    delta_ms_since_prev: deltaMs,
  });

  // Update previous event's next pointer
  if (prev) {
    await EventSequence.updateOne(
      { _id: prev._id },
      {
        $set: {
          next_stable_hash: stableHash,
          delta_ms_to_next: deltaMs,
        },
      }
    );
  }
}
```

### 5.3 Transition Matrix Builder

```typescript
// jobs/build-markov.ts
import EventSequence from '@/models/EventSequence';
import MarkovTransition from '@/models/MarkovTransition';
import Token from '@/models/Token';

async function buildMarkovTransitions() {
  // Aggregate bigram transitions from all sequences
  const pipeline = [
    {
      $match: {
        next_stable_hash: { $ne: null },
      },
    },
    {
      $group: {
        _id: {
          from: '$stable_hash',
          to: '$next_stable_hash',
        },
        count: { $sum: 1 },
        deltas: { $push: '$delta_ms_to_next' },
        hosts: { $addToSet: '$agent_id' },
        lastSeen: { $max: '$timestamp' },
      },
    },
  ];

  const transitions = await EventSequence.aggregate(pipeline);

  // Group by "from" to compute probabilities
  const fromGroups = new Map<string, { totalCount: number; transitions: any[] }>();
  for (const t of transitions) {
    const from = t._id.from;
    if (!fromGroups.has(from)) {
      fromGroups.set(from, { totalCount: 0, transitions: [] });
    }
    const group = fromGroups.get(from)!;
    group.totalCount += t.count;
    group.transitions.push(t);
  }

  const bulkOps: any[] = [];

  for (const [fromHash, group] of fromGroups) {
    for (const t of group.transitions) {
      const probability = t.count / group.totalCount;
      const deltas = t.deltas.filter((d: any) => d !== null);
      const avgDelta = deltas.length > 0
        ? deltas.reduce((a: number, b: number) => a + b, 0) / deltas.length
        : 0;
      const variance = deltas.length > 1
        ? deltas.reduce((s: number, d: number) => s + Math.pow(d - avgDelta, 2), 0) / deltas.length
        : 0;

      bulkOps.push({
        updateOne: {
          filter: { from_stable_hash: fromHash, to_stable_hash: t._id.to },
          update: {
            $set: {
              from_stable_hash: fromHash,
              to_stable_hash: t._id.to,
              transition_count: t.count,
              probability: Math.round(probability * 10000) / 10000,
              avg_delta_ms: Math.round(avgDelta),
              stddev_delta_ms: Math.round(Math.sqrt(variance)),
              host_count: t.hosts.length,
              last_observed: t.lastSeen,
              updated_at: new Date(),
            },
          },
          upsert: true,
        },
      });
    }
  }

  if (bulkOps.length > 0) {
    await MarkovTransition.bulkWrite(bulkOps, { ordered: false });
  }

  // Denormalize token descriptions for display speed
  await denormalizeDescriptions();
}

async function denormalizeDescriptions() {
  const tokens = await Token.find({
    'enrichment.short_description': { $exists: true },
  }).select('stable_hash enrichment.short_description').lean();

  const descMap = new Map(tokens.map(t => [t.stable_hash, t.enrichment?.short_description || 'Unknown']));

  for (const [hash, desc] of descMap) {
    await MarkovTransition.updateMany(
      { from_stable_hash: hash, from_token_description: { $exists: false } },
      { $set: { from_token_description: desc } }
    );
    await MarkovTransition.updateMany(
      { to_stable_hash: hash, to_token_description: { $exists: false } },
      { $set: { to_token_description: desc } }
    );
  }
}

// Run every 5 minutes
setInterval(buildMarkovTransitions, 5 * 60_000);
```

### 5.4 Prediction API

```typescript
// app/api/predict-next/route.ts
import { NextRequest, NextResponse } from 'next/server';
import MarkovTransition from '@/models/MarkovTransition';

export async function GET(req: NextRequest) {
  const stableHash = req.nextUrl.searchParams.get('stable_hash');
  if (!stableHash) {
    return NextResponse.json({ error: 'stable_hash required' }, { status: 400 });
  }

  const predictions = await MarkovTransition.find({ from_stable_hash: stableHash })
    .sort({ probability: -1 })
    .limit(10)
    .lean();

  const totalProbability = predictions.reduce((s, p) => s + p.probability, 0);

  return NextResponse.json({
    from_stable_hash: stableHash,
    predictions: predictions.map(p => ({
      to_stable_hash: p.to_stable_hash,
      description: p.to_token_description,
      probability: p.probability,
      transition_count: p.transition_count,
      avg_delta_ms: p.avg_delta_ms,
      host_count: p.host_count,
      last_observed: p.last_observed,
    })),
    total_probability: totalProbability,
    chain_entropy: computeEntropy(predictions.map(p => p.probability)),
  });
}

function computeEntropy(probs: number[]): number {
  return -probs.reduce((s, p) => s + (p > 0 ? p * Math.log2(p) : 0), 0);
}
```

### 5.5 Anomaly Detection via Markov Surprise

When a new event arrives, compare its `(prev_stable_hash, current_stable_hash)` transition against the Markov model:

```typescript
// lib/anomaly-detector.ts
export async function scoreSequenceAnomaly(
  prevHash: string,
  currentHash: string
): Promise<{
  is_anomalous: boolean;
  transition_probability: number;
  surprise_score: number; // -log2(P), higher = more surprising
  expected_next: string[];
}> {
  if (!prevHash) {
    return { is_anomalous: false, transition_probability: 1, surprise_score: 0, expected_next: [] };
  }

  const transition = await MarkovTransition.findOne({
    from_stable_hash: prevHash,
    to_stable_hash: currentHash,
  }).lean();

  const probability = transition?.probability || 0;
  // Surprise = -log2(probability). A 1% probability = ~6.64 bits of surprise
  const surpriseScore = probability > 0 ? -Math.log2(probability) : 15; // Cap at 15 bits

  // Get top 5 expected transitions
  const expected = await MarkovTransition.find({ from_stable_hash: prevHash })
    .sort({ probability: -1 })
    .limit(5)
    .lean();

  return {
    is_anomalous: probability < 0.01, // Less than 1% chance = anomalous
    transition_probability: probability,
    surprise_score: Math.round(surpriseScore * 100) / 100,
    expected_next: expected.map(e => e.to_token_description),
  };
}
```

---

## 6. Atomic Red Team Integration

### 6.1 Architecture

The Atomic Red Team integration has three phases:

1. **Test Discovery**: Parse the ART YAML definitions (`atomics/` directory) to build a test catalog
2. **Test Execution**: Run selected tests via PowerShell on a target Windows endpoint running the LongHorizons agent
3. **Telemetry Capture**: Cross-reference captured ETW events against test definitions to measure detection coverage

### 6.2 Test Runner

```typescript
// workers/atomic-runner.ts
import { exec } from 'child_process';
import { promisify } from 'util';
import { Queue, Worker } from 'bullmq';
import AtomicTest from '@/models/AtomicTest';
import Token from '@/models/Token';
import { Client } from '@elastic/elasticsearch';

const execAsync = promisify(exec);
const es = new Client({ node: process.env.ES_ENDPOINT });

const atomicQueue = new Queue('atomic-execution', { connection });

const worker = new Worker('atomic-execution', async (job) => {
  const { testGuid, techniqueId, agentId, targetHost } = job.data;

  const executionId = crypto.randomUUID();

  // Create or update test record
  await AtomicTest.findOneAndUpdate(
    { test_guid: testGuid },
    {
      $setOnInsert: {
        test_guid: testGuid,
        technique_id: techniqueId,
        test_name: job.data.testName,
        test_description: job.data.testDescription,
        test_platform: 'windows',
        created_at: new Date(),
      },
      $push: {
        executions: {
          execution_id: executionId,
          started_at: new Date(),
          status: 'running',
          agent_id: agentId,
          captured_event_count: 0,
          captured_stable_hashes: [],
          token_ids: [],
        },
      },
    },
    { upsert: true, new: true }
  );

  // Record the pre-execution timestamp for ES query window
  const startTime = new Date();

  try {
    // Execute Atomic Red Team test via PowerShell on target
    // invoke-atomicredteam must be installed on the target
    const psCommand = `
      Import-Module "C:\\AtomicRedTeam\\invoke-atomicredteam\\invoke-atomicredteam.psd1" -Force;
      Invoke-AtomicTest ${testGuid} -CheckPrereqs -GetPrereqs;
      Invoke-AtomicTest ${testGuid};
    `;

    // If running remotely, wrap in Invoke-Command
    let command: string;
    if (targetHost && targetHost !== 'localhost') {
      command = `Invoke-Command -ComputerName ${targetHost} -ScriptBlock { ${psCommand} }`;
    } else {
      command = `powershell.exe -Command "${psCommand.replace(/"/g, '\\"')}"`;
    }

    const { stdout, stderr } = await execAsync(command, {
      timeout: 300_000, // 5 minute timeout
      maxBuffer: 10 * 1024 * 1024,
    });

    // Wait a few seconds for events to flush through the pipeline
    await new Promise(r => setTimeout(r, 10_000));

    const endTime = new Date();

    // Query Elasticsearch for events during the test window
    const events = await es.search({
      index: 'longhorizons-events',
      body: {
        query: {
          bool: {
            must: [
              { term: { 'agent.id': agentId } },
              { range: { '@timestamp': { gte: startTime.toISOString(), lte: endTime.toISOString() } } },
            ],
          },
        },
        size: 10000,
        sort: [{ '@timestamp': 'asc' }],
      },
    });

    const stableHashes: string[] = [];
    const seenHashes = new Set<string>();

    for (const hit of events.hits.hits) {
      const src = hit._source as any;
      const hash = src.stable_hex || src.stable_hash;
      if (hash && !seenHashes.has(hash)) {
        seenHashes.add(hash);
        stableHashes.push(hash);
      }
    }

    // Cross-reference with existing tokens
    const tokens = await Token.find({
      stable_hash: { $in: stableHashes },
    }).select('_id stable_hash enrichment_status').lean();

    const tokenIds = tokens.map(t => t._id);
    const preEnriched = tokens.filter(t => t.enrichment_status === 'complete').length;
    const newTokens = tokens.filter(t => t.enrichment_status === 'pending').length;

    // Update coverage
    await AtomicTest.findOneAndUpdate(
      {
        test_guid: testGuid,
        'executions.execution_id': executionId,
      },
      {
        $set: {
          'executions.$.completed_at': new Date(),
          'executions.$.status': 'success',
          'executions.$.captured_event_count': (events.hits.total as any)?.value || 0,
          'executions.$.captured_stable_hashes': stableHashes,
          'executions.$.token_ids': tokenIds,
          coverage: {
            events_captured: (events.hits.total as any)?.value || 0,
            tokens_generated: stableHashes.length,
            tokens_pre_enriched: preEnriched,
            tokens_new: newTokens,
            detection_gap: newTokens > 0,
            gap_details: newTokens > 0
              ? `${newTokens} tokens had no prior enrichment — detection gap exists`
              : 'All behaviors were previously cataloged',
          },
        },
      }
    );

  } catch (error: any) {
    await AtomicTest.findOneAndUpdate(
      {
        test_guid: testGuid,
        'executions.execution_id': executionId,
      },
      {
        $set: {
          'executions.$.completed_at': new Date(),
          'executions.$.status': error.message?.includes('timeout') ? 'timeout' : 'failed',
        },
      }
    );
    throw error;
  }
}, { connection });

export { atomicQueue, worker };
```

### 6.3 Coverage Dashboard Logic

```typescript
// lib/coverage-report.ts
export async function generateCoverageReport() {
  // MITRE ATT&CK enterprise techniques (Windows-applicable)
  const totalTechniques = 232; // Approximate count of Windows-applicable techniques

  const tests = await AtomicTest.aggregate([
    { $unwind: '$executions' },
    { $match: { 'executions.status': 'success' } },
    {
      $group: {
        _id: '$technique_id',
        technique_name: { $first: '$technique_name' },
        test_count: { $sum: 1 },
        total_events: { $sum: '$executions.captured_event_count' },
        total_tokens: { $sum: '$coverage.tokens_generated' },
        has_detection_gap: { $max: '$coverage.detection_gap' },
      },
    },
  ]);

  const coveredTechniques = tests.length;
  const techniquesWithGaps = tests.filter(t => t.has_detection_gap).length;

  return {
    total_techniques: totalTechniques,
    covered_techniques: coveredTechniques,
    coverage_percentage: (coveredTechniques / totalTechniques * 100).toFixed(1),
    techniques_with_detection_gaps: techniquesWithGaps,
    gap_percentage: (techniquesWithGaps / coveredTechniques * 100).toFixed(1),
    by_technique: tests.sort((a, b) => a._id.localeCompare(b._id)),
  };
}
```

---

## 7. SearXNG Integration

### 7.1 Integration Points

WindOH uses SearXNG (running on the same stack) for:

1. **IOC Enrichment**: When a token contains an external IP, domain, or file hash, automatically search for threat intel
2. **CVE Lookup**: When the LLM tags a token with a CVE, pull the latest advisory details
3. **Technique Research**: For MITRE ATT&CK techniques, pull recent threat reports and detection guidance
4. **Investigation Assistant**: Free-text search integrated into the token detail page for analyst research

### 7.2 SearXNG Client

```typescript
// lib/searxng-client.ts
interface SearXNGResult {
  title: string;
  url: string;
  content: string;
  engine: string;
  score: number;
  publishedDate: string | null;
}

async function searxngSearch(
  query: string,
  options: {
    categories?: string[];     // e.g. ['news', 'it', 'science']
    engines?: string[];        // e.g. ['google', 'duckduckgo', 'bing']
    timeRange?: 'day' | 'week' | 'month' | 'year';
    limit?: number;
  } = {}
): Promise<SearXNGResult[]> {
  const params = new URLSearchParams({
    q: query,
    format: 'json',
    language: 'en',
    safesearch: '1',
  });

  if (options.categories) params.set('categories', options.categories.join(','));
  if (options.engines) params.set('engines', options.engines.join(','));
  if (options.timeRange) params.set('time_range', options.timeRange);
  if (options.limit) params.set('limit', options.limit.toString());

  const response = await fetch(
    `${process.env.SEARXNG_URL}/search?${params.toString()}`
  );

  if (!response.ok) {
    throw new Error(`SearXNG search failed: ${response.status}`);
  }

  const data = await response.json();
  return data.results || [];
}

// Specialized search functions
export async function searchIOC(iocType: string, iocValue: string) {
  const queries: Record<string, string> = {
    ip: `${iocValue} threat intelligence malware`,
    domain: `${iocValue} site:virustotal.com OR site:abuseipdb.com OR site:urlscan.io`,
    hash: `${iocValue} malware analysis virustotal`,
    url: `${iocValue} phishing malware analysis`,
  };

  const query = queries[iocType] || `${iocValue} threat intelligence`;
  return searxngSearch(query, {
    categories: ['it', 'news'],
    timeRange: 'year',
    limit: 10,
  });
}

export async function searchCVE(cveId: string) {
  return searxngSearch(`${cveId} vulnerability advisory`, {
    categories: ['it'],
    engines: ['google', 'duckduckgo'],
    limit: 5,
  });
}

export async function searchTechnique(techniqueId: string, techniqueName: string) {
  return searxngSearch(
    `MITRE ${techniqueId} ${techniqueName} detection threat hunting`,
    {
      categories: ['it'],
      timeRange: 'year',
      limit: 8,
    }
  );
}

export async function investigationSearch(query: string) {
  return searxngSearch(query, {
    categories: ['general', 'it', 'news'],
    limit: 15,
  });
}
```

### 7.3 Automatic IOC Enrichment Flow

```typescript
// jobs/enrich-iocs.ts
export async function enrichTokensWithIOCs() {
  // Find tokens that have network IPs/domains but no threat intel yet
  const tokens = await Token.find({
    'enrichment_status': 'complete',
    'network_dst_ip_class': { $in: ['Public', 'Private'] },
    'threat_intel.ioc_matches': { $exists: false },
  }).limit(50); // Batch size

  for (const token of tokens) {
    const iocMatches: any[] = [];

    // Extract IOCs from the original event (we'd need to store these in the token)
    // This is a placeholder — in practice, store IPs/domains/hashes in the token doc
    if (token.process_name) {
      const results = await searchIOC('general', token.process_name);
      if (results.length > 0) {
        iocMatches.push({
          ioc_type: 'general',
          ioc_value: token.process_name,
          search_results: results.map(r => ({
            title: r.title,
            url: r.url,
            snippet: r.content,
            source: r.engine,
          })),
          last_checked: new Date(),
        });
      }
    }

    if (iocMatches.length > 0) {
      await Token.updateOne(
        { _id: token._id },
        { $set: { 'threat_intel.ioc_matches': iocMatches } }
      );
    }
  }
}

// Run every 5 minutes — low volume, respects SearXNG rate limits
setInterval(enrichTokensWithIOCs, 5 * 60_000);
```

### 7.4 SearXNG Features to Add to the Stack

The following SearXNG enhancements make WindOH more powerful:

| Feature | Description | Implementation |
|---|---|---|
| **Security engine pack** | Curated SearXNG engines for threat intel | Add `virustotal`, `abuseipdb`, `urlscan`, `alienvault`, `threatcrowd` engines to SearXNG `settings.yml` |
| **CVE auto-search** | When LLM tags a CVE, auto-enrich from NVD, MITRE, exploit-db | Triggered from enrichment pipeline completion hook |
| **News monitoring** | Persistent searches for emerging threats related to captured behaviors | BullMQ repeatable jobs: search technique names daily |
| **Cache layer** | MongoDB-backed cache to avoid re-searching identical queries | `search_cache` collection with TTL indexes |
| **API endpoint** | `/api/search?q=...` for frontend investigation panel | tRPC route proxying to SearXNG |

---

## 8. Frontend Design

### 8.1 Pages

| Route | Purpose | Key Components |
|---|---|---|
| `/` | Dashboard | Token stats, enrichment queue depth, recent anomalies, coverage gauge |
| `/tokens` | Token browser | Searchable/sortable table with rarity, risk, MITRE filters |
| `/tokens/[hash]` | Token detail | Full enrichment, Markov predictions, event timeline, IOC intel |
| `/sequences` | Sequence explorer | Sankey diagram of behavioral chains, anomaly timeline |
| `/atomic` | ART coverage matrix | MITRE heatmap, test catalog, run-test button |
| `/atomic/[technique]` | Technique detail | Test history, captured tokens, coverage gaps |
| `/search` | Investigation console | Combined token search + SearXNG metasearch side-by-side |
| `/llm` | LLM management | Queue stats, prompt preview, manual re-enrich, model selection |

### 8.2 Key Components

**Token Detail Page** — The core analytical view:

```
┌─────────────────────────────────────────────────────────────┐
│ Token: a1b2c3d4...                    [RARE] [HIGH RISK]    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ "cmd.exe spawned whoami.exe from a temp directory with      │
│  encoded PowerShell command line"                           │
│                                                             │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐             │
│ │ MITRE       │ │ Risk        │ │ First Seen  │             │
│ │ T1059.001   │ │ HIGH        │ │ 2026-05-15  │             │
│ │ T1033       │ │ LoLBin +    │ │ 847 times   │             │
│ │ T1027       │ │ Recon       │ │ 23 hosts    │             │
│ └─────────────┘ └─────────────┘ └─────────────┘             │
│                                                             │
│ ── Markov Predictions ───────────────────────────────────── │
│ 74% → net.exe localgroup (T1069)                            │
│ 12% → powershell.exe -enc ... (T1059.001)                   │
│  8% → tasklist.exe (T1057)                                  │
│  3% → nltest.exe /domain_trusts (T1482)                     │
│  1% → reg.exe save hklm\sam (T1003)                         │
│                                                             │
│ ⚠ Sequence anomaly: observed next token has P < 1%          │
│                                                             │
│ ── Threat Intel (SearXNG) ──────────────────────────────────│
│ • CVE-2024-XXXXX — Command injection in...                  │
│ • 3 IOC matches found across AlienVault, URLScan            │
│                                                             │
│ ── Event Timeline ─────────────────────────────────────────│
│ [2026-05-27 14:02:01] host-042 → ... → ... → THIS TOKEN    │
│ [2026-05-27 13:58:23] host-017 → ... → ... → THIS TOKEN    │
│ ...                                                         │
└─────────────────────────────────────────────────────────────┘
```

### 8.3 Search Functionality

```typescript
// app/api/tokens/search/route.ts
export async function GET(req: NextRequest) {
  const q = req.nextUrl.searchParams.get('q') || '';
  const riskLevel = req.nextUrl.searchParams.get('risk');
  const rarity = req.nextUrl.searchParams.get('rarity');
  const mitreTechnique = req.nextUrl.searchParams.get('mitre');
  const eventType = req.nextUrl.searchParams.get('event_type');
  const page = parseInt(req.nextUrl.searchParams.get('page') || '1');
  const limit = 50;

  const filter: any = {};

  if (riskLevel) filter['enrichment.risk_level'] = riskLevel;
  if (rarity) filter['rarity_band'] = rarity;
  if (mitreTechnique) filter['enrichment.mitre_attack'] = mitreTechnique;
  if (eventType) filter['event_type'] = eventType;

  if (q) {
    // Use MongoDB Atlas Search for full-text
    filter.$text = { $search: q };
  }

  const [tokens, total] = await Promise.all([
    Token.find(filter)
      .select('stable_hash enrichment.short_description enrichment.risk_level rarity_band event_type total_occurrences')
      .sort({ total_occurrences: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
    Token.countDocuments(filter),
  ]);

  return NextResponse.json({
    tokens,
    total,
    page,
    totalPages: Math.ceil(total / limit),
  });
}
```

---

## 9. API Design (tRPC Routes)

```typescript
// server/trpc/routers/tokens.ts
export const tokenRouter = router({
  search: publicProcedure
    .input(z.object({
      q: z.string().optional(),
      risk: z.enum(['low', 'medium', 'high', 'critical']).optional(),
      rarity: z.enum(['Rare', 'Uncommon', 'Common']).optional(),
      mitre: z.string().optional(),
      eventType: z.string().optional(),
      page: z.number().default(1),
      limit: z.number().default(50),
    }))
    .query(async ({ input }) => { /* ... */ }),

  getByHash: publicProcedure
    .input(z.object({ hash: z.string() }))
    .query(async ({ input }) => { /* ... */ }),

  getPredictions: publicProcedure
    .input(z.object({ hash: z.string(), limit: z.number().default(5) }))
    .query(async ({ input }) => { /* ... */ }),

  getSequenceAnomalies: publicProcedure
    .input(z.object({ agentId: z.string(), hours: z.number().default(24) }))
    .query(async ({ input }) => { /* ... */ }),

  reEnrich: protectedProcedure
    .input(z.object({ hash: z.string() }))
    .mutation(async ({ input }) => { /* reset and re-queue enrichment */ }),
});

export const atomicRouter = router({
  listTests: publicProcedure
    .input(z.object({ technique: z.string().optional(), page: z.number().default(1) }))
    .query(async ({ input }) => { /* ... */ }),

  runTest: protectedProcedure
    .input(z.object({
      testGuid: z.string(),
      agentId: z.string(),
      targetHost: z.string().optional(),
    }))
    .mutation(async ({ input }) => { /* queue test execution */ }),

  getCoverage: publicProcedure.query(async () => { /* ... */ }),

  getTechniqueDetail: publicProcedure
    .input(z.object({ techniqueId: z.string() }))
    .query(async ({ input }) => { /* ... */ }),
});

export const searchRouter = router({
  tokensAndIntel: publicProcedure
    .input(z.object({ q: z.string() }))
    .query(async ({ input }) => {
      // Run token search and SearXNG search in parallel
      const [tokenResults, intelResults] = await Promise.all([
        Token.find({ $text: { $search: input.q } }).limit(20).lean(),
        investigationSearch(input.q),
      ]);
      return { tokenResults, intelResults };
    }),
});
```

---

## 10. Deployment & Environment

### 10.1 Docker Compose Stack

```yaml
# docker-compose.yml
version: '3.8'

services:
  windoh:
    build: .
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=mongodb://mongo:27017/windoh
      - REDIS_URL=redis://redis:6379
      - ES_ENDPOINT=http://elasticsearch:9200
      - LLM_ENDPOINT=http://192.168.0.133:31337/v1
      - SEARXNG_URL=http://searxng:8080
    depends_on:
      - mongo
      - redis

  mongo:
    image: mongo:7
    ports:
      - "27017:27017"
    volumes:
      - mongo_data:/data/db
    environment:
      MONGO_INITDB_DATABASE: windoh

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  searxng:
    image: searxng/searxng:latest
    ports:
      - "8080:8080"
    volumes:
      - ./searxng/settings.yml:/etc/searxng/settings.yml:ro
      - ./searxng/limiter.toml:/etc/searxng/limiter.toml:ro
    environment:
      - SEARXNG_BASE_URL=http://localhost:8080

  # The LongHorizons agent and Elasticsearch run on the Windows endpoint
  # This stack can run on Linux or Windows

volumes:
  mongo_data:
  redis_data:
```

### 10.2 Environment Variables

```bash
# .env.local
DATABASE_URL=mongodb://localhost:27017/windoh
REDIS_URL=redis://localhost:6379
ES_ENDPOINT=http://192.168.0.100:9200     # Elasticsearch on Windows endpoint
ES_API_KEY=your-es-api-key
LLM_ENDPOINT=http://192.168.0.133:31337/v1
LLM_MODEL=local-model                       # Model name as reported by the LLM API
SEARXNG_URL=http://localhost:8080
ENRICHMENT_CONCURRENCY=4                    # How many parallel LLM enrichment calls
ENRICHMENT_MAX_PER_MINUTE=20               # Rate limit for LLM calls
MARKOV_REBUILD_INTERVAL_MINUTES=5
ES_POLL_INTERVAL_SECONDS=10
```

---

## 11. Implementation Phases

### Phase 1 — Foundation (Week 1-2)
- [ ] Next.js project scaffold with TypeScript, TailwindCSS, tRPC
- [ ] MongoDB connection, Mongoose models (all 5 collections)
- [ ] Redis + BullMQ setup
- [ ] Elasticsearch client and polling loop
- [ ] Token ingestion: ES → MongoDB upsert pipeline
- [ ] Basic token browser UI (list + search)

### Phase 2 — LLM Enrichment (Week 2-3)
- [ ] LLM client configured for 192.168.0.133:31337
- [ ] Enrichment prompt template with structured JSON output
- [ ] BullMQ enrichment worker with concurrency/rate limiting
- [ ] Enrichment status UI: pending queue, success rate, retry
- [ ] Token detail page with enrichment display

### Phase 3 — Markov Engine (Week 3-4)
- [ ] Sequence recording on event ingest
- [ ] Transition matrix builder (aggregation pipeline)
- [ ] Prediction API endpoint
- [ ] Anomaly detection via surprise scoring
- [ ] Sequence visualization (Sankey diagram)

### Phase 4 — Atomic Red Team (Week 4-5)
- [ ] ART YAML parser → test catalog in MongoDB
- [ ] Test execution worker (PowerShell + invoke-atomicredteam)
- [ ] ES query window for telemetry capture
- [ ] Coverage matrix dashboard
- [ ] Detection gap reporting

### Phase 5 — SearXNG Integration (Week 5-6)
- [ ] SearXNG client with specialized search functions
- [ ] Auto-enrichment pipeline: IOCs → SearXNG → MongoDB
- [ ] Search cache with TTL
- [ ] Investigation console (dual-pane: tokens + metasearch)
- [ ] SearXNG security engine pack configuration

### Phase 6 — Polish & Production (Week 6-7)
- [ ] Authentication (NextAuth.js)
- [ ] Role-based access (admin vs analyst)
- [ ] Export reports (PDF coverage matrix, enrichment stats)
- [ ] Performance optimization (indexing, aggregation pipeline tuning)
- [ ] Monitoring (BullMQ dashboard, enrichment success rate alerts)
- [ ] Documentation

---

## 12. Key Design Decisions & Rationale

| Decision | Rationale |
|---|---|
| **MongoDB over PostgreSQL** | Token enrichment is deeply nested and variable-depth — one stable_hash may have 2 MITRE techniques while another has 6. Document model avoids EAV pattern or sparse columns. Atlas Search provides built-in full-text search without Elasticsearch dependency for the web app itself. |
| **BullMQ over in-process queues** | LLM enrichment can take 5-30 seconds per token. 47 providers × thousands of events = many unique tokens on first run. Redis-backed queues survive restarts, provide dashboards, and support rate limiting to avoid overwhelming the local LLM. |
| **Poll Elasticsearch, don't stream** | The LongHorizons agent already deduplicates and batches. Polling every 10 seconds is simpler than maintaining a persistent ES scroll, handles ES restarts gracefully, and the 10s latency is acceptable for enrichment (which itself takes seconds). |
| **Markov first-order with N-order extension path** | First-order (bigram) captures 80% of predictive value at a fraction of the state space. The architecture supports N-order extension via the `prev_stable_hash` chain in event sequences — the transition builder can be upgraded without schema changes. |
| **Enrich once, cache forever** | The stable_hash is cryptographically deterministic. The same hash always means the same behavior. Enriching it once and caching in MongoDB means the LLM cost per token is fixed, regardless of how many millions of times the behavior occurs. This is the central design insight of the entire system. |
| **Separate search_cache collection** | SearXNG results change over time. A 7-day TTL with re-search ensures threat intel stays fresh without hammering the metasearch engine. |

---

## 13. Next Steps After Handoff

1. **Verify LLM connectivity**: `curl http://192.168.0.133:31337/v1/models` — confirm the endpoint is reachable and see available models
2. **Verify Elasticsearch connectivity**: Confirm `longhorizons-events` index exists and has data
3. **Stand up MongoDB + Redis**: Docker Compose in section 10.1
4. **Scaffold Next.js project**: `npx create-next-app@latest windoh --typescript --tailwind --app`
5. **Begin Phase 1 implementation**: Models → ES poll → Token ingestion → Basic UI
6. **Test enrichment prompt with local LLM**: Run the prompt template from section 4.1 manually against a few real tokens to validate response quality and JSON parsing

---

*Document version 1.0 — Ready for implementation handoff*
