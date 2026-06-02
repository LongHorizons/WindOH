# GIF Creation Guide — WindOH Platform Walkthrough

Six GIFs covering the full platform. Each section below specifies what to capture, suggested length, resolution, and tools. Create these in order — each GIF builds on what the viewer learned in the previous one.

---

## General Specs

| Parameter | Value |
|---|---|
| Resolution | 1920×1080 (all GIFs) |
| Frame rate | 15-24 fps (smooth but file-size conscious) |
| Format | GIF (or MP4 with GIF fallback) |
| Color | Dark theme (platform default) |
| Cursor | Visible, smooth movement (no jitter) |
| Browser | Chrome or Firefox, incognito window, no bookmarks bar |

### Recommended Tools

- **ScreenToGif** (Windows) — best free option for GIF recording/editing
- **LICEcap** (macOS/Windows) — simple frame capture
- **Kap** (macOS) — MP4/GIF with good quality
- **OBS Studio** → **ffmpeg** — for high-quality MP4 → GIF conversion:
  ```bash
  ffmpeg -i capture.mp4 -vf "fps=15,scale=1920:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" -loop 0 output.gif
  ```
- **Peek** (Linux) — simple GIF recorder

### Before Recording

1. Start the platform: `pnpm dev` (web + collab-gateway) and `docker compose up -d` (MongoDB + Redis)
2. Ensure Elasticsearch is reachable and has recent telemetry data
3. Ensure LLM endpoint is reachable for enrichment demos
4. Open the dashboard at `http://localhost:3000`
5. Log in with a demo account (not admin) to show realistic permissions
6. Clear any sensitive data from view
7. Set browser zoom to 100%

---

## GIF 1: Dashboard Overview

**File:** `dashboard-overview.gif`
**Duration:** 30-45 seconds
**Resolution:** 1920×1080

### Script

| Time | Action | What to Show |
|---|---|---|
| 0:00-0:05 | Login screen, enter credentials, submit | Login → dashboard transition |
| 0:05-0:10 | Dashboard loads, metrics animate in | Intelligence overview: tokens indexed counter, enrichment rate percentage, sequences count, transitions count |
| 0:10-0:15 | Scroll to ATT&CK Validation section | Pie/donut chart: validated / partial / mismatch / unknown breakdown. Numbers animating. |
| 0:15-0:20 | Scroll to Technique Heatmap | Top 20 ATT&CK techniques as horizontal bars. Highlight T1059.003 (Windows Command Shell) as the most common. |
| 0:20-0:25 | Scroll to Pipeline Status | Docs fetched, persisted, duplicates, errors, last run timestamp. All status badges green. |
| 0:25-0:30 | Scroll to Queue Health | 8 queues: waiting, active, completed, failed, delayed per queue. Show ingestion queue with most activity. |
| 0:30-0:35 | Scroll to Recent Telemetry table | Latest 10 tokens: hostname, event_type, payload_token (truncated), confidence badge, status badge. One row highlighted. |
| 0:35-0:40 | Scroll to Surprising Transitions | Top 5 high-surprise transitions ranked by surprise score. Top entry showing 9+ bits in red. |
| 0:40-0:45 | Sidebar: show Connection Indicators | MongoDB green, Redis green, Elasticsearch green. Hover over each to show tooltip with connection details. |

### Key Visual Details
- Sidebar navigation visible throughout
- Command palette hint at bottom (⌘K)
- Session/security HUD in top-right corner
- All counters should animate upward when they first appear
- Use smooth scrolling between sections

---

## GIF 2: Telemetry Ingestion Pipeline

**File:** `ingestion-pipeline.gif`
**Duration:** 20-30 seconds
**Resolution:** 1920×1080

### Script

| Time | Action | What to Show |
|---|---|---|
| 0:00-0:05 | Pipeline Status panel at top | Show "Polling Elasticsearch..." status. Docs fetched counter at some number (e.g., 12,847). |
| 0:05-0:10 | New poll cycle begins | Status changes to "Fetching docs since checkpoint 2026-06-03T...". Docs fetched increments. |
| 0:10-0:15 | Normalization | Side panel or overlay showing a raw ES document on the left, canonical token on the right. Highlight `tokens.payload` field being extracted. Show timestamp normalization (ISO → unix ms). Show `payload_token` hash being computed. |
| 0:15-0:20 | Deduplication | Show "Checking 47 new docs against 12,847 existing tokens." Counter: "New: 12, Duplicates: 35." |
| 0:20-0:25 | Bulk insert | MongoDB tokens collection count increments from 12,847 → 12,859. Show the new documents appearing in the Recent Telemetry table. |
| 0:25-0:30 | Checkpoint update | Status: "Checkpoint updated. Next poll in 10s." Queue health: ingestion queue shows 12 new jobs enqueued to enrichment queue. |

### Key Visual Details
- Show the `payload_token` field being extracted and hashed — this is the "aha moment" for viewers
- Make the normalization step clear: raw → canonical
- The dedup counter is important — shows the "enrich once" principle at the ingestion level

---

## GIF 3: LLM Enrichment and ATT&CK Validation

**File:** `enrichment-validation.gif`
**Duration:** 30-40 seconds
**Resolution:** 1920×1080

### Script

| Time | Action | What to Show |
|---|---|---|
| 0:00-0:05 | Open a specific token detail view | Click on a token from the Recent Telemetry table. Token detail panel opens showing payload_token hash, event_type, hostname, timestamp. |
| 0:05-0:10 | Trigger enrichment (or show auto-trigger) | If enrichment is already cached, show "Enrichment loaded from cache (enriched 2026-06-02)". If new, show "Enqueued for LLM enrichment..." → spinner → results appear. |
| 0:10-0:25 | Show 9-dimension analysis appearing | Animate each dimension appearing one by one with a subtle fade-in:<br>1. ATT&CK Technique Mapping: T1059.003 (Windows Command Shell), confidence 0.94<br>2. D3FEND Countermeasures: Process monitoring, command-line analysis<br>3. Functional Analysis: cmd.exe invoked by explorer.exe, typical user-driven execution<br>4. Origin Analysis: Signed Microsoft binary, LOLBin classification: medium risk<br>5. Benign Rationale: Administrative tasks, software installation scripts<br>6. Malicious Rationale: APT29, FIN7 — cmd.exe used for discovery and execution<br>7. Attack Scenarios: Step-by-step adversary playbook for T1059.003<br>8. Investigation Steps: Splunk queries, KQL queries, forensic artifact locations<br>9. Related CVEs and Threat Groups: APT29 (Cozy Bear), FIN7 |
| 0:25-0:30 | Show provenance block | Scroll to bottom. Highlight the provenance fields: source_type=llm, model_name=PartiriOne, prompt_version=v3.2, enrichment_version=1.4.0, confidence=0.94, validation_method=external_reference. |
| 0:30-0:35 | Show ATT&CK validation result | Adjacent panel: technique=T1059.003, match_quality=match, confidence=0.94, validated_against=SearXNG external references (3 sources cited). |
| 0:35-0:40 | Show SearXNG augmentation | If applicable: "3 external references found. Validation method upgraded from llm_inference → external_reference." Show the reference links. |

### Key Visual Details
- The 9 dimensions should appear in sequence, not all at once
- Use a subtle highlight/border animation on each dimension as it appears
- The provenance block should pulse briefly to draw attention — this is the trust mechanism
- If enrichment is cached, make that visibly clear: "Cached" badge with the original enrichment date

---

## GIF 4: Markov Prediction Engine

**File:** `markov-prediction.gif`
**Duration:** 30-40 seconds
**Resolution:** 1920×1080

### Script

| Time | Action | What to Show |
|---|---|---|
| 0:00-0:05 | Navigate to Surprising Transitions panel | Dashboard → scroll to Surprising Transitions. Show the ranked list of high-surprise transitions. |
| 0:05-0:10 | Select the top surprise transition | Click on a transition with surprise 9.97 bits (the most anomalous). Detail panel opens. |
| 0:10-0:20 | Show the transition context | Left side: from_token (ProcessCreate svchost.exe) with its token link summary. Right side: to_token (TCP Connect :4444) with its token link summary. Center: the transition itself — count=15, probability=0.001, entropy=6.8, surprise=9.97 bits. |
| 0:20-0:25 | Show the prediction comparison | Animated diagram: "Given Token_A (svchost.exe ProcessCreate), model predicts:"<br>→ Token_B (TCP :443): 83% (12,450 occurrences) — normal Windows Update<br>→ Token_C (DNS Query): 15% (2,200 occurrences) — normal DNS resolution<br>→ Token_D (Registry Set): 2% (280 occurrences) — less common but benign<br>→ **Token_E (TCP :4444): 0.1%** (15 occurrences) — **ANOMALOUS**<br>Highlight Token_E in red. |
| 0:25-0:35 | Show the sequence diagram | Timeline visualization: events on desktop-01 over a 5-minute window. Normal sequence (Token_A → Token_B → Token_C) shown in green. Divergent sequence (Token_A → Token_E) shown in red. Animated arrow from the normal path to the anomalous path with the surprise score callout. |
| 0:35-0:40 | Show the per-host vs global comparison | Split panel: "Host desktop-01: P(Token_E | Token_A) = 0.001" vs "Global (all hosts): P(Token_E | Token_A) = 0.0001". Both flagged as anomalous. Note: "This host has seen this transition 15 times. All other hosts combined: 8 times. Still anomalous at the 3.0 bit threshold." |

### Key Visual Details
- The surprise score should visually pop — red gradient for high surprise, yellow for medium, green for low
- The prediction comparison is the key visual — make it clear that the model predicted A→B (83%) but what actually happened was A→E (0.1%)
- Use a branching tree or flow diagram for the prediction alternatives
- Include the bit value explanation somewhere: "9.97 bits ≈ 1 in 1,000 probability"

---

## GIF 5: Analyst Mental Map and Collaboration

**File:** `mental-map-collab.gif`
**Duration:** 40-50 seconds
**Resolution:** 1920×1080

### Script

| Time | Action | What to Show |
|---|---|---|
| 0:00-0:05 | Analyst A logs in, opens desktop-01 | Dashboard → host selector → desktop-01. Show the host's behavioral summary. |
| 0:05-0:10 | Analyst A reviews a surprising transition | The same anomalous transition from GIF 4: svchost.exe → TCP :4444. Analyst examines the token link details, enrichment, and ATT&CK validation. |
| 0:10-0:20 | Analyst A investigates and marks verdict | Analyst opens the token detail for the destination token (TCP :4444). Scrolls through enrichment. Clicks "Mark as True Positive." A confirmation dialog appears. Analyst types investigation notes: "Confirmed C2 beacon to known-malicious IP 192.168.1.100:4444. Correlated with 3 other hosts showing same destination. Beaconing pattern: every 300s for 48 hours." Clicks "Save Verdict." |
| 0:20-0:25 | Analyst A annotates the token link | Clicks "Annotate Token Link." Adds: "Associated with APT29 infrastructure based on IP reputation and beacon timing. Recommend blocking outbound :4444 at firewall and investigating all hosts with this transition in the last 7 days." Clicks "Save Annotation." |
| 0:25-0:30 | Analyst A saves mental map | Clicks "Save Mental Map." The map now includes: the TP verdict, the annotation, the cross-host correlation note, and the investigation trail. A notification appears: "Mental map saved. Shared with SOC-Investigations room." |
| 0:30-0:35 | Switch to Analyst B's view | Split screen transition. Analyst B is investigating desktop-07. Dashboard loads. A surprising transition appears: same from_token → same to_token (svchost.exe → TCP :4444). |
| 0:35-0:40 | Analyst B sees Analyst A's annotations | When Analyst B clicks on the token, the token link detail panel shows Analyst A's annotation and TP verdict already visible with a badge: "Reviewed by Analyst A — 2026-06-03 14:22 UTC." |
| 0:40-0:45 | Analyst B applies the same verdict | Analyst B clicks "Apply Existing Verdict." One click. The token is marked TP with the same reasoning. A notification appears in the collab gateway: "Analyst B confirmed Analyst A's verdict on desktop-07." |
| 0:45-0:50 | Show the collab gateway room | Open the collab gateway panel. Show the SOC-Investigations room with presence indicators (Analyst A and Analyst B both active). Show the shared mental map artifact in the room's artifact list. Show the message thread where Analyst A shared the initial finding. |

### Key Visual Details
- Use a split screen for the Analyst A → Analyst B transition — makes the sharing benefit immediately visible
- The "Apply Existing Verdict" button should pulse or highlight — this is the key UX moment
- Show presence indicators in the collab gateway (green dot = active)
- The annotation badge on the token link should be prominent — "Already reviewed" is the value prop

---

## GIF 6: AI Dataset Export

**File:** `dataset-export.gif`
**Duration:** 25-35 seconds
**Resolution:** 1920×1080

### Script

| Time | Action | What to Show |
|---|---|---|
| 0:00-0:05 | Navigate to Dataset Export panel | Sidebar → Datasets. Show the export configuration page with filter options: date range picker, origin selector (all/Windows/Linux/macOS/K8s), validation status checkboxes, analyst verdict checkboxes, cluster membership selector. |
| 0:05-0:10 | Configure and trigger export | Select filters: "Last 30 days," "All origins," "Validated + Analyst-reviewed only." Click "Generate Datasets." A progress indicator appears. |
| 0:10-0:20 | Show the 5 dataset types being generated | Animate a grid of 5 panels, each representing a dataset type. Each panel populates with a sample row as it completes:<br>1. **sequence_prediction:** Token sequence array with labels and techniques<br>2. **attack_classification:** Token features + multi-label technique vector<br>3. **anomaly_detection:** Transition features + binary anomaly label + analyst verdict<br>4. **semantic_contrastive:** Anchor/positive/negative triplets with similarity scores<br>5. **behavioral_completion:** Partial sequence + target token + context window |
| 0:20-0:25 | Show the train/val/test split | A bar chart appears: 70% train, 15% validation, 15% test. Annotated: "Stratified by technique and hostname to prevent data leakage." Show the per-technique split detail. |
| 0:25-0:30 | Show export metadata | training_corpus collection entry appears in MongoDB: export_id, timestamp, filter parameters, split ratios, token counts per split, file paths for jsonl + csv exports. |
| 0:30-0:35 | Show the training flywheel | Animated diagram: Ingest → Enrich → Markov → Export → Train → Evaluate → (feedback) → Ingest. Each node pulses in sequence. End on the flywheel with the caption: "Better enrichment → Better models → Better detection → Better enrichment." |

### Key Visual Details
- Each dataset type should show a realistic sample row — use the example JSON from `05-AI-Datasets-and-Deployment.md`
- The train/val/test split chart should be clear and annotated
- The training flywheel should animate as a loop — this is the closing visual of the entire walkthrough
- End with the windoh.us URL and a subtle fade to the platform logo

---

## After Recording

1. Review each GIF for:
   - Smooth cursor movement (no jitter or hesitation)
   - No sensitive data visible (hostnames, IPs, tokens can be shown but use demo data)
   - Consistent dark theme throughout
   - Readable text at the recorded resolution
   - No browser chrome (URL bar, bookmarks) visible
2. Optimize file size: target 2-5 MB per GIF for reasonable load times
3. Place completed GIFs in `Presentation/gifs/` directory
4. Update `README.md` to replace the ASCII placeholders with actual image embeds:
   ```markdown
   ![Dashboard Overview](./gifs/dashboard-overview.gif)
   ```
5. Delete this file once all GIFs are created and embedded — it's a production guide, not a permanent document

---

## Quick Reference Card

| # | GIF File | Duration | Key Moment |
|---|---|---|---|
| 1 | `dashboard-overview.gif` | 30-45s | Full dashboard tour ending on surprising transitions |
| 2 | `ingestion-pipeline.gif` | 20-30s | Raw ES doc → payload_token hash → MongoDB insert |
| 3 | `enrichment-validation.gif` | 30-40s | 9-dimension analysis appearing + provenance block |
| 4 | `markov-prediction.gif` | 30-40s | Prediction comparison: 83% expected vs 0.1% actual |
| 5 | `mental-map-collab.gif` | 40-50s | Analyst A marks TP → Analyst B sees annotation → one click |
| 6 | `dataset-export.gif` | 25-35s | 5 datasets generated → train/val/test split → flywheel |
