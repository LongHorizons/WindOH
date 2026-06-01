# Mental Maps and Collaborative Refinement

---

## What a Mental Map Is

An analyst investigating a host builds a mental model: which behaviors are normal for this machine, which are suspicious, what co-occurs with what, what the most likely explanation is, and what to investigate next. This mental model is usually ephemeral -- it lives in the analyst's head, gets partially written into case notes, and is lost when the analyst moves on.

WindOH formalizes this as a **mental map**: a structured, queryable, shareable representation of an analyst's behavioral understanding.

```mermaid
graph TB
    subgraph AnalystMind["Analyst Mental Model"]
        AM1["Normal baseline<br/>for this host"]
        AM2["Suspicious anomalies<br/>ranked by priority"]
        AM3["Behavioral co-occurrence<br/>patterns observed"]
        AM4["Likely explanations<br/>for each anomaly"]
        AM5["Investigation steps<br/>taken and results"]
    end

    subgraph MentalMap["Structured Mental Map (MongoDB)"]
        MM1["Baseline profile<br/>common tokens, normal sequences,<br/>expected transitions"]
        MM2["Anomaly annotations<br/>surprising transitions +<br/>analyst verdict (TP/FP)"]
        MM3["Behavioral archetypes<br/>recurring patterns observed<br/>across multiple hosts"]
        MM4["Hypotheses<br/>formalized what-if scenarios<br/>with supporting evidence"]
        MM5["Investigation trail<br/>steps taken, queries run,<br/>findings confirmed"]
    end

    AM1 --> MM1
    AM2 --> MM2
    AM3 --> MM3
    AM4 --> MM4
    AM5 --> MM5
```

---

## Mental Map Generation

The `@windoh/mental-map` package generates and maintains structured mental maps. It draws from multiple sources:

```mermaid
graph LR
    subgraph Sources["Map Sources"]
        Markov["Markov Model<br/>normal transitions +<br/>surprise scores"]
        Clusters["Behavioral Clusters<br/>semantic groups +<br/>centroid distances"]
        Graph["Behavioral Graph<br/>cross-host correlations +<br/>shared techniques"]
        Feedback["Analyst Feedback<br/>corrections, annotations,<br/>technique overrides"]
        ART["ART Results<br/>known-technique ground truth"]
    end

    subgraph Map["Mental Map Output"]
        Baseline["Host Baseline<br/>top-N normal behaviors"]
        Anomalies["Ranked Anomalies<br/>by surprise + analyst verdict"]
        CrossHost["Cross-Host Similarity<br/>hosts with similar behavioral profiles"]
        Predictions["Hostname Predictions<br/>likely next events per host"]
        YARA["YARA Rules<br/>auto-generated behavioral signatures"]
        Suggestions["AI Suggestions<br/>investigation priors from LLM"]
    end

    Markov --> Baseline
    Markov --> Anomalies
    Markov --> Predictions
    Clusters --> CrossHost
    Clusters --> Baseline
    Graph --> CrossHost
    Graph --> Anomalies
    Feedback --> Anomalies
    Feedback --> Suggestions
    ART --> Baseline
    ART --> YARA
    Sources --> Suggestions
```

### Components of a Mental Map

**Host Baseline.** The top N most frequent tokens and transitions for a specific host, annotated with enrichment context. This answers: "What does this machine normally do?"

**Ranked Anomalies.** Surprising transitions sorted by surprise score, with analyst verdicts (true positive, false positive, under investigation). Each anomaly carries the full token link context for both the source and destination tokens.

**Cross-Host Similarity.** Hosts that share behavioral clusters, common tokens, or similar Markov transition profiles. This answers: "What other machines behave like this one?" and "Is this anomaly unique to this host or widespread?"

**Hostname Predictions.** Given a host's recent sequence history, what tokens are most likely to come next, ranked by Markov probability with the host's specific transition distribution.

**YARA Rules.** Auto-generated behavioral signatures derived from ART ground truth and analyst-confirmed anomaly patterns. These rules encode known-malicious or known-suspicious behavioral sequences in a format that can be shared and applied to other telemetry sources.

**AI-Powered Suggestions.** The LLM, given the host's baseline, recent anomalies, and cross-host context, suggests investigation priors: which anomalies to investigate first, what additional data to collect, and which ATT&CK techniques to prioritize.

---

## The Analyst-Engineer Refinement Loop

The platform is designed around a shared refinement cycle between engineers and analysts:

```mermaid
sequenceDiagram
    participant Engineer as Platform Engineer
    participant Platform as WindOH Platform
    participant Analyst as Security Analyst

    Note over Engineer,Analyst: Continuous Refinement Cycle

    Engineer->>Platform: Deploy normalizer improvements<br/>Add new origin support<br/>Tune Markov thresholds

    Platform->>Platform: Ingest telemetry<br/>Enrich tokens<br/>Build Markov model<br/>Generate embeddings

    Platform->>Analyst: Dashboard: new anomalies surfaced<br/>Surprising transitions ranked

    Analyst->>Platform: Review anomalies<br/>Mark TP/FP verdicts<br/>Correct enrichment labels<br/>Annotate token links

    Analyst->>Analyst: Build mental map:<br/>- What is normal for this host<br/>- What patterns repeat<br/>- What is worth investigating

    Analyst->>Platform: Save mental map<br/>Publish annotations<br/>Share findings via collab

    Platform->>Engineer: Anomaly feedback loop data:<br/>- FP rate by technique<br/>- Surprise threshold calibration<br/>- Normalizer gaps identified

    Engineer->>Engineer: Analyze feedback:<br/>- Reduce FP sources<br/>- Adjust thresholds<br/>- Fix normalization gaps

    Engineer->>Platform: Deploy refinements<br/>Cycle repeats with<br/>improved signal quality

    Note over Engineer,Analyst: Both parties agree on mental map updates<br/>before model refinements ship
```

**Engineers** own the pipeline: normalization quality, Markov model parameters, embedding configuration, dataset export schedules, and infrastructure health. They tune the machinery.

**Analysts** own the interpretation: behavioral baselines, anomaly verdicts, technique corrections, cross-host correlations, and investigation priorities. They supply the ground truth.

**Both agree on the mental map.** This is the critical collaboration point. When an analyst identifies a recurrent false positive pattern (for example, a particular svchost.exe transition that looks anomalous but is actually a normal Windows Update behavior), the engineer can adjust the normalizer to tag it as known-benign, or the analyst can annotate the token link so future occurrences are pre-marked as expected. When an engineer proposes a surprise threshold change, the analyst reviews the impact on the set of flagged anomalies. Neither side operates in isolation.

---

## Collaboration Gateway: Sharing Mental Maps

```mermaid
graph TB
    subgraph Analyst1["Analyst A"]
        A1["Investigates desktop-01<br/>Builds mental map"]
        A2["Finds anomaly:<br/>cmd.exe -> TCP :4444<br/>surprise = 9.2 bits"]
        A3["Verdict: True Positive<br/>Confirmed C2 beacon"]
        A4["Annotates token link<br/>with investigation notes"]
    end

    subgraph Gateway["Collab Gateway (WebSocket + Libsodium E2E)"]
        G1["Room: SOC-Investigations"]
        G2["Shared mental map artifacts"]
        G3["Encrypted message channel"]
    end

    subgraph Analyst2["Analyst B"]
        B1["Investigates desktop-07<br/>Sees same token link"]
        B2["Mental map already annotated:<br/>'C2 beacon confirmed on desktop-01'"]
        B3["Skips re-investigation<br/>Applies same verdict"]
        B4["Correlates: same C2 IP<br/>appears on 4 other hosts"]
    end

    A2 --> A3
    A3 --> A4
    A4 --> G2
    A3 --> G3
    G2 --> B2
    G3 --> B4
    B2 --> B3
    B3 --> B4
```

The collaboration gateway enables real-time, end-to-end encrypted sharing of mental map artifacts. When Analyst A confirms a true positive and annotates the token link, Analyst B sees that annotation when encountering the same token on a different host. Insight compounds instead of being rediscovered from scratch.

The gateway supports:
- **Rooms** for team-based investigation contexts
- **Presence** showing which analysts are active
- **Key distribution messages** for E2E encryption handshakes (X25519/Ed25519 via libsodium)
- **Shared mental map artifacts** persisted to MongoDB and referenced in real-time

---

## The Agreement Layer

The phrase "agreed upon by engineers and analysts" is not aspirational. It is a concrete workflow:

```mermaid
flowchart TD
    Observe["New anomaly pattern<br/>observed in Markov output"] --> Discuss["Engineer + Analyst<br/>discuss in collab room"]
    Discuss --> Investigate["Analyst investigates<br/>on source host"]
    Investigate --> Verdict{"Verdict?"}

    Verdict -->|"True Positive"| TP["Mark as TP<br/>Annotate token link<br/>Update mental map"]
    Verdict -->|"False Positive"| FP["Mark as FP<br/>Identify root cause<br/>Determine fix type"]

    TP --> Share["Share finding<br/>via collab gateway"]
    Share --> Update["Update shared mental map<br/>All analysts benefit"]

    FP --> FixType{"Fix type?"}
    FixType -->|"Normalizer gap"| EngFix["Engineer fixes normalizer<br/>Improves token extraction<br/>Adds new origin field mapping"]
    FixType -->|"Threshold issue"| Tune["Engineer + Analyst<br/>jointly agree on new threshold<br/>Review impact on TP recall"]
    FixType -->|"Benign rare event"| Annotate["Analyst annotates token<br/>as known-benign<br/>Future occurrences pre-filtered"]

    EngFix --> Deploy["Deploy fix"]
    Tune --> Deploy
    Annotate --> Update
    Deploy --> Rebuild["Rebuild Markov model<br/>Verify FP rate change"]
    Rebuild --> Observe
```

Every correction -- whether a code fix, a threshold adjustment, or a token annotation -- feeds back into the pipeline. The next rebuild reflects the agreed-upon change. The mental map is the durable artifact of that agreement.

---

## Mental Maps as Organizational Memory

Over time, the accumulated mental maps become organizational memory:

- A new analyst onboarding can load the mental map for a host and immediately understand its behavioral baseline, recent anomalies, and what has already been investigated and resolved.
- An engineer optimizing the Markov threshold can query all analyst FP verdicts across all mental maps to understand the current FP rate per technique, per origin, and per host.
- A team lead auditing investigation quality can trace the investigation trail in the mental map: what was flagged, what was investigated, what was concluded.
- A red team designing a new ART test can query mental maps to find behavioral gaps -- patterns that analysts have noted as suspicious but that have no existing ART test coverage.

The mental map is not just a tool for the current investigation. It is the durable, queryable artifact of analyst reasoning that persists across investigations, across analysts, and across time.
