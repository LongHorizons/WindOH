# Validation and Test Coverage

This document catalogs the validation strategies, test cases, and coverage status across every WindOH component. It serves as the single source of truth for what has been verified, what is currently under test, and where gaps remain.

---

## Table of Contents

1. [Validation Philosophy](#validation-philosophy)
2. [LongHorizons Agent](#longhorizons-agent)
3. [WindOH Application](#windoh-application)
4. [LessAtomic (Atomic Red Team Executor)](#lessatomic)
5. [LessVolatile (Memory Forensics)](#lessvolatile)
6. [OneDriveStandaloneUpdaterr (Forensic Triage)](#onedrivestandaloneupdaterr)
7. [LessToil (Codebase Intelligence)](#lesstoil)
8. [Cross-Component Integration Tests](#cross-component-integration-tests)
9. [Performance Benchmarks](#performance-benchmarks)
10. [Known Gaps and Planned Tests](#known-gaps-and-planned-tests)

---

## Validation Philosophy

WindOH is built on seven non-negotiable architectural principles. Validation flows from these: each component is tested against the principles that govern it, at design review, implementation gate, and release gate.

The platform's commitment to determinism simplifies testing significantly. Same input always produces same output. This property eliminates entire categories of flaky-test debugging that plague heuristic systems. The following invariants hold across every component:

1. **Deterministic token generation.** Same ETW event trace, same eBPF probe payload, same CloudTrail record produces the identical stable_token and payload_token, independent of host, time, or session.
2. **Deterministic forensic fingerprinting.** Same memory dump produces the same SHA-256 structural fingerprint for every process, service, module, and network profile.
3. **Idempotent enrichment.** Same payload_token produces the same cached enrichment result. The LLM is called exactly once per unique payload_token.
4. **Reproducible builds.** Same source commit produces bit-for-bit identical binaries (excepting embedded timestamps where unavoidable).

Four methods of validation are applied across components:

| Method | Description | Applied To |
|--------|-------------|------------|
| **Adversary emulation** | Execute known techniques against instrumented endpoints and verify detection | LongHorizons Agent, WindOH ART Mapper |
| **Deterministic replay** | Feed identical inputs and assert identical outputs across runs | Tokenization, fingerprinting, enrichment |
| **Failure-mode injection** | Simulate component unavailability and verify graceful degradation | Agent outbox, BullMQ retry, API health checks |
| **Parallelism benchmarking** | Measure throughput against sequential baseline and verify linear scaling | LessAtomic, LessVolatile |

---

## LongHorizons Agent

**Status:** Validating against Atomic Red Team coverage matrix (M4, 80% complete)

### Test Surface

The agent spans five platforms. Each platform has its own validation profile.

#### Windows ETW

**47 kernel and user-mode providers active.** The primary validation mechanism is the ART coverage matrix: every Atomic Red Team technique with a detectable ETW footprint must produce a corresponding stable_token. Gaps are identified and documented.

| Provider Category | Providers | Test Approach |
|-------------------|-----------|---------------|
| **Kernel** | Process/Thread/Image Load/Network TCP-UDP/File I/O/Registry/Disk I/O | ART T1003 (Credential Dumping) touches process, file, and registry providers; T1059 (Command and Scripting Interpreter) touches process creation and PowerShell providers |
| **PowerShell** | Script Block Logging (4104), Module Logging (4103), Pipeline Execution (800) | ART T1059.001 (PowerShell) executes obfuscated scripts; LessAtomic's base64 encoding path (`UTF-16LE -> base64 -> -EncodedCommand`) mirrors real attacker behavior |
| **DNS Client** | Query/Response (3008), Winsock (MSAFD) | ART T1071.004 (DNS) generates known-bad DNS queries |
| **SChannel** | TLS Handshake (event 36880) | ART T1573 (Encrypted Channel) exercises TLS connections |
| **Defender** | Detection (1116/1117), State Change (1150/1151) | ART T1562.001 (Disable or Modify Tools) triggers Defender tampering events |
| **WMI** | Activity (5857/5858/5859/5860/5861) | ART T1047 (WMI) generates WMI process creation events |
| **COM/RPC** | COM object creation, RPC calls | ART T1175 (Distributed Component Object Model) exercises COM lateral movement |
| **AppLocker** | EXE/DLL/Script/MSI/Packaged App evaluation (8003/8004/8005/8006/8007) | ART T1562.012 (Disable or Modify Cloud Logging) exercises policy evaluation |

**Additional collection surfaces under validation:**

| Surface | What Is Collected | Validation |
|---------|-------------------|------------|
| PE Metadata | Compile timestamp, section count, import table entropy, debug/PDB path, subsystem, DLL characteristics | Validated against known binaries from Windows\System32 and Sysinternals suite |
| Process Forensics | PEB walking (NtQueryInformationProcess class 33, fallback to VM_READ), module enumeration, TCP table snapshot, process genealogy reconstruction | Cross-referenced against Task Manager, Process Explorer, and `netstat -ano` |
| Browser Artifacts | Chrome/Firefox/Edge history and downloads (SQLite databases) | Validated against manual browser history inspection |
| Registry Diff | Hive snapshots with ROT-13 heuristic for obfuscated key names | Validated against known persistence locations (Run keys, Services, Winlogon) |

#### Linux eBPF

**12 kernel probes across a 5-tier adaptive ladder.** Probe auto-selection is validated at startup (~50ms system probe) by checking kernel version, BTF availability, CAP_BPF, auditd presence, and init system.

| Probe | Tracepoint/kprobe | Validation |
|-------|-------------------|------------|
| `trace_exec` | sched:sched_process_exec | exec() syscall generates process_start event with PID lineage |
| `trace_exit` | sched:sched_process_exit | exit() generates process_end with exit code |
| `trace_fork` | sched:sched_process_fork | fork() generates process_fork with parent PID |
| `trace_execve` | syscalls:sys_enter_execve | execve() generates process_start with full argv |
| `trace_tcp_connect` | kprobe:tcp_v4_connect | connect() generates network_connect with dst IP:port |
| `trace_tcp_accept` | kprobe:inet_csk_accept | accept() generates network_accept with src IP:port |
| `trace_dns_query` | kprobe:udp_sendmsg (port 53 filter) | DNS query generates dns_query with qname |
| `trace_file_open` | syscalls:sys_enter_openat | openat() generates file_open with path |
| `trace_file_write` | syscalls:sys_enter_write | write() generates file_write with fd |
| `trace_file_delete` | syscalls:sys_enter_unlinkat | unlinkat() generates file_delete with path |
| `trace_module_load` | module:module_load | insmod/modprobe generates module_load with name |
| `trace_capability` | kprobe:cap_capable | capability check generates capability_check for non-root |
| `trace_mount` | syscalls:sys_enter_mount | mount() generates mount with device/target/fstype |

**Tier fallback validation:** Each of the 5 tiers is tested by provisioning VMs at the target kernel level. When the preferred tier's prerequisites are absent, the agent must auto-select the correct fallback tier within the 50ms probe window.

#### Firewall

**22+ vendors across 6 ingestion methods.** Validation focuses on syslog format auto-detection and REST API poller correctness.

| Ingestion Method | Test Approach |
|------------------|---------------|
| nftables/nflog netlink | Generate known traffic (curl, netcat) and verify conntrack event capture with correct 5-tuple |
| iptables kern.log | Configure iptables LOG target, generate traffic, verify kern.log tail parsing |
| pf pflog0 | Generate traffic through pf rules, verify pflog0 reader event capture |
| syslog UDP 514 | Replay known syslog messages from 18 vendor formats, verify auto-detector selects correct parser |
| REST API pollers | Mock Palo Alto Panorama, Fortinet FortiGate, Cisco FMC endpoints; verify correct API calls and response parsing |
| Cloud flow logs | Replay known AWS VPC Flow Log, Azure NSG Flow Log, and GCP Firewall log records; verify correct normalization |

**GeoIP/ASN enrichment:** Validated against MaxMind GeoLite2 test database with known IP addresses. Correct country/city/ASN mapped for IPv4 and IPv6.

#### Cloud (AWS / Azure / GCP / Oracle / Kubernetes)

**24 services across 5 providers.** Validation uses mock API endpoints returning recorded responses.

| Provider | Service | Validation |
|----------|---------|------------|
| **AWS** | CloudTrail | Replay recorded CloudTrail events (management + data), verify tokenization of IAM role assumption, S3 GetObject, EC2 RunInstances, Lambda Invoke, Bedrock InvokeModel |
| **AWS** | VPC Flow Logs | Replay S3-stored flow log records, verify 5-tuple extraction, ACCEPT/REJECT parsing, pkt-srcaddr handling |
| **AWS** | GuardDuty | Replay recorded findings (CryptoCurrency, Backdoor, Recon, CredentialCompromise, Stealth, Impact types), verify severity extraction and MITRE tactic mapping |
| **AWS** | Security Hub | Replay ASFF 1.0 findings across CIS, Foundational, and PCI DSS standards |
| **AWS** | S3 Access Logs | Replay bucket logging records, verify requester/operation/status extraction |
| **AWS** | WAF Logs | Replay WebACL rule matches, verify rate-based-rule threshold extraction and BotControl label parsing |
| **AWS** | Route53 Resolver | Replay DNS query logs from CloudWatch, verify qtype/qname extraction |
| **AWS** | ELB Access Logs | Replay ALB access log records from S3, verify ssl_cipher/ssl_protocol/chosen-cert SNI extraction |
| **AWS** | Config Rules | Replay ComplianceChangeNotification events, verify compliance status mapping |
| **Azure** | Activity Log | Replay Administrative, Security, ServiceHealth, ResourceHealth, Alert, Autoscale events via Azure Monitor REST |
| **Azure** | NSG Flow Logs | Replay v2 flow tuples from Blob Storage, verify FlowState (B/C/E) and TrafficDecision parsing |
| **Azure** | Sentinel | Replay scheduled/ML Behavior/Fusion/NRT alert records, verify incident grouping |
| **Azure** | AD Sign-in Logs | Replay Microsoft Graph signIn records, verify ConditionalAccessStatus, MfaResult, error code mapping |
| **Azure** | Key Vault | Replay AuditEvent records from EventHub, verify SecretGet/KeySign/CertificateImport operation tracking |
| **Azure** | Azure Policy | Replay policyStates records, verify complianceState and initiative mapping |
| **GCP** | Cloud Audit Logs | Replay Admin Activity + Data Access + System Event + Policy Denied log entries |
| **GCP** | VPC Flow Logs | Replay per-subnet flow samples, verify metadata fields (src/dst instance, VPC, location) |
| **GCP** | Security Command Center | Replay findings across all categories (XSS_SCRIPTING through KUBERNETES_OVERPRIVILEGED), verify severity assignment |
| **GCP** | Cloud Logging | Replay log entries across resource.types, verify severity and payload type (text/json/proto) detection |
| **GCP** | Access Transparency | Replay access transparency log entries, verify accessReason and product_performed_asserter parsing |
| **Oracle** | OCI Audit Logs | Replay recorded audit events (objectstorage.getobject, computeapi.launchinstance, identity.user.create), verify request.action mapping |
| **Oracle** | VCN Flow Logs | Replay flow log parquet files, verify tcp_flags parsing and service gateway traffic identification |
| **Oracle** | Cloud Guard | Replay problem records (InstancePubliclyAccessible, ObjectStorageBucketPubliclyAccessible, etc.), verify risk level assignment |
| **Oracle** | Events Service | Replay event rule matching records, verify Notifications/Streaming/Functions action routing |
| **Kubernetes** | API Server Audit Logs | Replay audit.k8s.io/v1 events at all stages/levels, verify authorization annotations and pod-security labels |
| **Kubernetes** | Pod Security Contexts | Replay Pod specs with varied securityContext, verify privileged/runAsNonRoot/capabilities/seccomp extraction |
| **Kubernetes** | Admission Reviews | Replay AdmissionReview records from OPA/Gatekeeper, Kyverno, Istio, verify response.allowed parsing |
| **Kubernetes** | Network Policies | Replay Calico Felix iptables counter increments and Cilium Hubble eBPF verdict logs |

### Shared Pipeline Validation

| Pipeline Stage | What Is Tested | Method |
|----------------|----------------|--------|
| **Tokenization** | Same raw event on two different hosts produces identical stable_token | Deterministic replay across Windows 10, Windows 11, Windows Server 2019, Windows Server 2022 VMs |
| **Token Sanitization** | Garbage patterns (base64 null artifacts `AAA=`, hex pointers, pure numeric IDs, Unicode replacement chars, control characters) are rejected, not hashed | Feed instrumented garbage strings; assert rejection |
| **Count-Min Sketch** | Four independent hash functions; rarity bands (Rare <= 2, Uncommon 3-20, Common >20) assigned correctly | Known-frequency synthetic event stream; assert correct band assignment |
| **Exemplar Reservoir** | Fixed-size reservoir (default 3) maintained per base token; replacement based on richness score | Inject events with known richness; assert reservoir state |
| **SQLite Outbox** | Three priority tiers respected (exemplars first, patterns second, events third); WAL mode concurrent read/write | Inject events at all priority levels; assert export order |
| **ES Bulk Export** | Gzip compression applied; exponential backoff retry triggers on connection failure; dead-letter after N attempts | Inject connection failures; assert retry behavior and dead-letter count |
| **Encryption at Rest** | AES-256-GCM with purpose-specific keys derived via HKDF-SHA256 from DPAPI-protected master key (Windows) or filesystem-protected key (Linux) | Verify ciphertext with known plaintext; assert HKDF key derivation with known IKM/salt/info |

### Agent Resilience Tests

| Failure Mode | Expected Behavior | Validated |
|--------------|-------------------|-----------|
| Elasticsearch unreachable | Events buffer to SQLite outbox; exponential backoff retry triggers; dead-letter after N attempts | Yes |
| ETW session loss | Agent detects session stop via ControlTrace; automatic restart with configurable backoff | Yes |
| Disk full | Pipeline pauses; health check reports CRITICAL; space guard checks pre-allocate | Yes |
| ES credential rotation | Agent re-reads config and applies new API key without restart (config hot-reload via file watcher) | Yes |
| Partial event (TDH parsing failure) | Event discarded with structured diagnostic; pipeline continues | Yes |
| Memory pressure | Configurable memory ceiling enforced; ETW session buffer sizes bounded | Yes |

---

## WindOH Application

**Status:** Enrichment pipeline validated; windoh.us launch pending (M5)

### Enrichment Pipeline

| Stage | What Is Tested | Method |
|-------|----------------|--------|
| **Elasticsearch Polling** | New documents polled at configurable interval; no duplicate polling of already-seen tokens | Insert known documents; assert poller picks up new, skips seen |
| **Canonical Normalization** | Events from all origins (ETW, eBPF, CloudTrail, syslog) normalized to identical schema | Feed representative events from each origin; assert normalized fields match |
| **Token Deduplication** | Already-enriched payload_tokens return cached result from MongoDB; new tokens enqueue | Feed mix of known and unknown tokens; assert cache hits and queue insertions |
| **BullMQ Job Orchestration** | 8 named queues; jobs dequeued in priority order; no data loss on worker restart | Inject jobs; kill worker; restart; assert all jobs complete |
| **LLM Enrichment** | Structured JSON prompt (9-dimension analysis) returns correct schema; raw prompt/response stored for provenance | Feed known payloads; assert response schema validity and provenance storage |
| **Enrichment Caching** | Once per payload_token, cached permanently; subsequent encounters return cached result | Query same token twice; assert single LLM call, identical responses |
| **ATT&CK Validation** | Enrichment results validated against ART ground truth; Match/Partial/Mismatch classification | Execute ART technique, capture token, check enrichment against known technique ID |

### Markov Sequence Engine

| Test | Method |
|------|--------|
| First-order transition matrix built from temporal event sequences across all hosts | Feed known event sequences; assert matrix entries match expected transition counts |
| Surprise scoring (-log2(P)) computed for observed transitions; threshold at 3.0 bits for anomaly flag | Feed known-probability transitions; assert surprise score matches -log2 calculation |
| Prediction API returns top-N most probable next behaviors | Query with known prefix; assert predictions match expected next events |
| Per-host and global fallback probabilities | Query with host that has local data; assert host-specific predictions returned; query with new host; assert global fallback |

### ART Coverage Mapper

| Test | Method |
|------|--------|
| Stable token extracted from ART execution telemetry matches expected technique | Execute ART test; capture ETW token; assert technique mapping |
| Per-technique detection coverage percentage computed | Execute all tests for a technique; count tokens captured; assert coverage percentage |
| Gap identification: techniques with 0% detection coverage flagged | Run coverage analysis across all 265 techniques; assert gap report lists undetected techniques |

### SearXNG Client

| Test | Method |
|------|--------|
| IOC enrichment: known-bad IP returns threat intel context | Query SearXNG with known IOC; assert structured response |
| CVE lookup returns vulnerability details | Query known CVE; assert CVSS score, description, references |
| Client degrades gracefully when SearXNG unreachable | Stop SearXNG; query; assert timeout without API crash, structured error logged |

---

## LessAtomic (Atomic Red Team Executor)

**Status:** Released v0.1.0. 752 tests embedded, 265 techniques covered.

### Build-Time Validation

The `build.rs` script validates all embedded YAML at compile time:

- **337 technique YAML files walked** at build time via `walkdir`
- **265 Windows-compatible techniques** extracted (techniques without Windows executors are filtered)
- **YAML deserialization** validates every field against the `AtomicYaml` schema
- **Unused variable arguments** produce compile warnings
- **Missing required arguments** produce compile errors (build fails)
- **`embedded.rs` regenerated** on any YAML change

A schema change in the Atomic Red Team YAML format is detected at build time, not at runtime. The build fails with a specific error identifying the malformed YAML file and the field that failed deserialization.

### Runtime Test Execution

| Test Phase | What Is Validated |
|------------|-------------------|
| **Discovery** | 752 Windows tests discovered; technique filters (prefix match) correctly narrow test set; elevation gating skips admin-required tests when not elevated |
| **Resolution** | `#{variable}` interpolation in command lines and cleanup commands; dependency prerequisite commands resolved; auto-install flag triggers `apt-get`/`choco`/`powershell` installers |
| **Execution** | Command executed with configurable timeout (default 300s); exit code captured; stdout/stderr buffered; process killed if timeout exceeded via `wait-timeout` crate |
| **Cleanup** | Cleanup command executed after test (unless `--no-cleanup` flag); cleanup result logged independent of test result |
| **Reporting** | Pass/Fail/Skip/Timeout with progress bar (indicatif::ProgressBar); JSON export with per-test structured log; terminal table with technique-level summaries |

### Test Execution Matrix

| Result | Condition | Example |
|--------|-----------|---------|
| **PASS** | Exit code 0, no timeout | T1003.001 credential dumping via `procdump.exe -ma lsass.exe` |
| **FAIL** | Non-zero exit code | T1059.001 PowerShell script blocked by execution policy |
| **SKIP (DEP_UNMET)** | Dependency not found and --auto-install not set | T1557.001 requires `ettercap` not installed |
| **SKIP (DEP_FAILED)** | Dependency install command returned non-zero | --auto-install attempted but `choco install` failed |
| **SKIP (MANUAL)** | Test has manual dependency steps | T1003.004 "manual memory dump via task manager" |
| **SKIP (ELEVATED)** | Test requires admin, user is not admin, --include-elevated not set | T1562.001 requires SYSTEM privileges |
| **TIMEOUT** | Test exceeded per-test timeout | T1003.001 `mimikatz` hangs waiting for user input |

### Performance Benchmarks (Measured)

| Machine | Workers | Full Suite (752 tests) | vs Sequential Baseline |
|---------|---------|------------------------|------------------------|
| 4-core laptop | 4 | ~120-180 minutes | ~3.5x faster |
| 8-core desktop | 7 | ~40-90 minutes | ~6x faster |
| 16-core workstation | 13 | ~20-50 minutes | ~10-12x faster |

Sequential baseline (Invoke-AtomicRedTeam): ~6-12 hours for 752 tests on an 8-core machine.

### Safety Gates (All Verified)

| Gate | Mechanism |
|------|-----------|
| Interactive confirmation | Must type 'y' to proceed unless `--danger-accept` explicitly passed |
| Elevation gating | Tests requiring admin are skipped by default when not elevated (override: `--include-elevated`) |
| Per-test timeouts | Default 300s; test process killed via `wait-timeout` crate on expiry |
| Cleanup enforcement | Cleanup commands run after every test (unless `--no-cleanup`) |
| Exit code semantics | 0 = all passed or skipped; 1 = at least one failed or timed out |

---

## LessVolatile (Memory Forensics)

**Status:** Released v0.2.0. 68 Windows plugins, 29 Linux, 26 macOS.

### Plugin Coverage

| OS | Plugins | Categories |
|----|---------|------------|
| **Windows** | 68 | processes, dlls, handles, services, drivers, network, registry, users, malware, strings, yarascan, timeliner |
| **Linux** | 29 | processes, libraries, system calls, network, kernel modules, mount points, bash history |
| **macOS** | 26 | processes, kexts, network, system configuration, unified logs |

### OS Auto-Detection

The `OsTarget` enum auto-selects the correct plugin set at startup. Validation: point at a known Windows dump, assert 68 Windows plugins queued. Point at a known Linux dump, assert 29 Linux plugins queued. Point at a known macOS dump, assert 26 macOS plugins queued. Point at an unrecognized format, assert immediate error with structured diagnostic.

### Deterministic Fingerprinting

Each capture produces a structural fingerprint: SHA-256 hashes of process names, services, kernel modules, and network profiles.

| Test | Method |
|------|--------|
| Same dump processed twice produces identical fingerprint | Run twice; assert SHA-256 match on all fingerprint components |
| Different dumps from same OS produce different fingerprints | Run on two known-different dumps; assert fingerprints differ |
| Fingerprint stable across plugin execution order | Randomize plugin execution order; assert fingerprint unchanged |
| Cross-case correlation: same threat actor's tools detected across dumps | Inject same malware across two dumps; fingerprint should match on injected module hash |

### Hidden Process Detection

The `pslist_vs_psscan_delta` is computed automatically in every fingerprint. PsList shows processes via the kernel's process list; PsScan finds them by scanning memory directly. A non-zero delta flags processes actively hiding from the OS.

| Test | Method |
|------|--------|
| Clean system produces zero delta | Process known-clean dump; assert delta == 0 |
| Hidden process produces non-zero delta | Inject process via DKOM (Direct Kernel Object Manipulation) from known tool; assert delta > 0, hidden process identified |
| False positive rate | Process 100 clean dumps from diverse Windows versions; assert 0 false positives |

### Parallelism Scaling

| Machine | Dumps Processed Simultaneously | Plugins per Dump in Parallel | Time for 100 Dumps |
|---------|-------------------------------|------------------------------|---------------------|
| 8-core desktop | 6 dumps at once | 12 plugins in parallel | ~45 min |
| 16-core workstation | 12 dumps at once | 16 plugins in parallel | ~20 min |
| Manual (baseline) | 1 dump | 1 plugin at a time | ~170 hours |

---

## OneDriveStandaloneUpdaterr (Forensic Triage)

**Status:** Released. 4-dimension collection (filesystem, live response, PowerShell, memory/disk).

### Collection Dimensions

| Dimension | Tools | Artifacts Collected | Validation |
|-----------|-------|---------------------|------------|
| **Filesystem (18 KAPE targets)** | KAPE | Event logs, registry hives, prefetch, LNK files, jump lists, SRUM, Outlook PST/OST, cloud storage metadata | Run against known artifact set; verify all expected files collected |
| **Live Response (35+ tools)** | PsExec, netstat, tasklist, sc, arp, ipconfig, etc. | Running processes, network connections, ARP/DNS cache, installed programs, running drivers | Compare against manual collection; assert completeness |
| **PowerShell (40+ modules)** | Get-BitLockerVolume, Get-MpPreference, Get-WmiObject, etc. | BitLocker status, Defender exclusions, WMI repository, named pipes, SMB sessions | Run on instrumented endpoint with known state; assert all values captured |
| **Memory/Disk** | Raw disk imager, RAM capturer | RAM capture, physical disk imaging with space guard | Verify SHA-256 integrity of captured image; assert space guard prevents disk-full condition |

### Remote Orchestration (via embedded PsExec)

| Test | Method |
|------|--------|
| Binary copies to target via ADMIN$ share | Execute remote collection; verify binary present on target |
| Executes as SYSTEM on target | Verify process runs as NT AUTHORITY\SYSTEM |
| Result zip polled and pulled back | Verify zip SHA-256 integrity matches source files |
| Target cleaned up after collection | Verify no agent binary or artifacts remain on target |
| CPU throttled below 42% | Monitor CPU during collection; assert sustained utilization below threshold |

### Operational Stealth

| Test | Method |
|------|--------|
| Binary carries Microsoft OneDrive metadata | Inspect PE resource section; assert version info matches OneDrive |
| No GUI, no tray icon, no console window | Run in test VM; assert no visible windows created |
| Service name blends with system activity | Run `sc query`; assert no suspicious service names |

---

## LessToil (Codebase Intelligence)

**Status:** Released. 56 languages, 14 architectural domains, 26-table SQLite knowledge graph.

### Index Correctness

| Metric | Value |
|--------|-------|
| Languages supported | 56 |
| Architectural domains inferred | 14 (with security boundary marking) |
| SQLite tables | 26 |
| Python modules | 40 |
| Hook lifecycle coverage | 3/3 (SessionStart, PreToolUse, PostToolUse) |

### Validation Methods

| Test | Method |
|------|--------|
| Symbol detection | Index known codebases with documented symbol lists; assert every symbol found and correctly typed |
| Call edge detection | Compare call graph against manual code review of sample files; assert all call edges present, no false edges |
| SimHash duplicate detection | Insert known duplicate with minor whitespace changes; assert SimHash distance < threshold |
| Governance enforcement | Attempt edit that violates architectural invariant; assert PreToolUse hook returns exit code 2 (block) |
| Incremental reindex | Edit file; assert PostToolUse reindexes only changed file; assert index consistency maintained |
| Tempororal risk scoring | Simulate git history with known churn, bug density, ownership volatility; assert risk scores match expected ranges |
| Cross-reference consistency | Validate that all documented APIs, config keys, and CLI flags match their implementations (used to verify the 60-commit Assembly phase) |

---

## Cross-Component Integration Tests

These tests verify the end-to-end pipeline. They are gated behind M4 and M5 completion.

### Pipeline Integration (M6: Planned)

| Test Scenario | Components Involved | Expected Outcome |
|---------------|---------------------|------------------|
| **ETW event to enriched token** | LongHorizons Agent -> Elasticsearch -> WindOH API -> BullMQ -> Enrichment Worker -> LLM -> MongoDB | Event captured, tokenized, exported, polled, enriched, cached. End-to-end latency < 30 seconds. |
| **ART execution to coverage mapping** | LessAtomic -> LongHorizons Agent -> Elasticsearch -> WindOH ART Mapper | ART technique executed; corresponding stable_token observed in ES; coverage mapper records detection |
| **Cross-platform behavioral correlation** | LongHorizons (Windows) + LongHorizons (Linux) -> Elasticsearch -> WindOH API -> Token Link | Same behavioral pattern (process creation) on Windows and Linux produces different stable_tokens but same behavioral category; cross-origin comparison works |
| **Markov sequence prediction accuracy** | LongHorizons Agent -> Elasticsearch -> WindOH Markov Engine | Known attack sequence (Recon -> Initial Access -> Execution -> Persistence) predicted with >80% transition probability |
| **Full-coverage ART pass** | LessAtomic (752 tests) -> LongHorizons Agent (47 providers) -> Elasticsearch -> WindOH ART Mapper | Coverage percentage computed per technique; gaps documented; false negatives investigated |

### Failure-Mode Integration Tests

| Scenario | Expected Behavior | Validated |
|----------|-------------------|-----------|
| Agent -> ES network partition | SQLite outbox buffers; retries with backoff; no data loss | Yes |
| ES -> API polling interruption | API resumes from last processed offset; no duplicate enrichment | Planned (M6) |
| LLM unavailable during enrichment | BullMQ retries with backoff; job remains queued; no data loss | Yes |
| MongoDB connection lost during enrichment | API returns 503; health check fails; Mongoose auto-reconnect | Yes |
| Redis connection lost | BullMQ pauses processing; ioredis auto-reconnect with backoff | Yes |
| Worker process crash mid-enrichment | BullMQ marks job as failed; job re-queued automatically; max retry limit prevents infinite loops | Yes |

---

## Performance Benchmarks

### Measured (Completed)

| Component | Metric | Baseline | Measured | Reduction/Improvement |
|-----------|--------|----------|----------|----------------------|
| LessVolatile | Single dump processing time | 3-4 hours (manual) | ~5 minutes | 97% reduction |
| LessVolatile | Batch 100 dumps | 170 hours (manual) | ~45 minutes | 99.6% reduction |
| LessVolatile | Per-dump cost at $200/hr | $600-$800 | ~$16 | 97.5% reduction |
| LessAtomic | Full 752-test suite (8-core) | 6-12 hours (Invoke-Atomic) | 40-90 minutes | ~8x faster |
| LessToil | Languages indexed | 0 | 56 | N/A |
| LessToil | Assembly phase effort | 2-3 weeks (manual) | 3 days (with LessToil) | ~80% reduction |

### Under Validation (M4)

| Component | Metric | Target | Status |
|-----------|--------|--------|--------|
| LongHorizons Agent | Event-to-token throughput | >10,000 events/sec sustained | Validating |
| LongHorizons Agent | Stable token storage reduction | 90-99% vs raw event logging | Validating |
| LongHorizons Agent | SQLite outbox buffer memory | <50 MB under load | Validating |
| WindOH API | Token enrichment latency | <30 seconds end-to-end | Validating (M5) |

---

## Known Gaps and Planned Tests

### Gaps Identified

| Gap | Impact | Plan |
|-----|--------|------|
| **Full ART coverage matrix pass (M4)** | Cannot state with certainty which ATT&CK techniques are detectable via ETW | Priority: completing the 265-technique validation pass. Every technique with a detectable ETW footprint must produce a corresponding stable_token |
| **Linux eBPF kernel version matrix** | Probe behavior validated on kernel 5.4, 5.15, 6.1; not yet validated on 4.x, 3.x, or 2.6.x | Provision VMs per kernel version; validate tier fallback for each |
| **Cloud API mock endpoints** | Cloud service pollers validated with recorded responses, not live API calls | Provision sandbox accounts in each provider; run live polling validation |
| **MacOS ESF agent** | Architecture documented but agent not yet built | Gated behind M7; architecture is validated as analogous to ETW trace sessions |
| **Cross-platform behavioral correlation** | Same behavior on Windows and Linux should produce comparable enrichment | Planned for M6 integration testing |
| **Markov prediction accuracy at scale** | Model validated on small datasets; accuracy at fleet scale (>10,000 endpoints) unknown | Planned for M6 with production telemetry |
| **LLM enrichment quality at volume** | Quality validated on representative sample; degradation at high volume (>1M unique payload_tokens) unknown | Monitor enrichment rejection rate and ATT&CK validation confidence as token count grows |

### Planned Tests (M6: Platform Integration)

1. **End-to-end latency**: Measure time from ETW event on endpoint to enriched token in MongoDB. Target: <30 seconds.
2. **Throughput ceiling**: Determine maximum sustained events/sec the pipeline can ingest before backpressure. Target: >50,000 events/sec.
3. **Fleet scaling**: Simulate 1, 10, 100, 1,000, 10,000, 100,000 endpoints. Measure Elasticsearch storage growth, MongoDB enrichment cache hit rate, and Markov model rebuild time at each tier.
4. **False positive rate**: Run 1 million benign operations (software installs, updates, normal user activity). Count enrichment flags raised. Target: <0.1% false positive rate.
5. **Adversary emulation completeness**: Execute all 752 ART tests. Measure percentage that produce a detectable ETW event. Document gaps per technique.
6. **Recovery time objective (RTO)**: Measure time from component failure to full pipeline recovery for each failure mode in the failure handling matrix.

### Planned Tests (M7: Cross-Platform)

1. **Linux agent parity**: Execute equivalent adversary behavior on Windows and Linux. Verify comparable detection coverage.
2. **Kubernetes agent integration**: Deploy agent as DaemonSet. Verify audit log capture, pod security context validation, admission review tracking, and network policy event logging.
3. **Cloud agent live validation**: Deploy agents in sandbox AWS/Azure/GCP/Oracle accounts. Verify live API polling against production endpoints.

---

## Test Infrastructure

### Hardware

| Resource | Specification | Role |
|----------|---------------|------|
| HotStuff workstation | HP Z8 G4, 2x Xeon Platinum 8260 (96 logical processors), 1.5 TB ECC DDR4, 2x RTX 5090 (64 GB VRAM), NVMe/SSD/HDD | Local LLM inference, parallel builds, multi-VM test orchestration |
| Test VMs | Windows 10/11, Windows Server 2019/2022 | Agent validation, LessAtomic execution, forensic tool testing |
| WSL2 environment | Linux kernel, Docker, vLLM | LessToil development, LLM serving, cross-platform build testing |

### Software

| Tool | Purpose |
|------|---------|
| Atomic Red Team (Red Canary, MIT-licensed) | Adversary emulation test library: 265 techniques, 752 Windows atomic tests |
| Volatility 3 (Volatility Foundation) | Memory forensics framework: 68 Windows plugins, 29 Linux, 26 macOS |
| Elasticsearch 8.x | Telemetry indexing and querying |
| MongoDB 7 | Enrichment caching and token link persistence |
| Redis 7 | BullMQ job queue backing store |
| vLLM / llama.cpp / Ollama | Local LLM inference for enrichment pipeline |
| MaxMind GeoLite2 | GeoIP/ASN enrichment validation |

---

## References

- [ENGINEERING_PRINCIPLES.md](../ENGINEERING_PRINCIPLES.md): Seven non-negotiable architectural principles with decision rationales
- [docs/operations/FAILURE_HANDLING.md](operations/FAILURE_HANDLING.md): Per-component failure mode catalog with recovery procedures
- [docs/operations/RUNBOOKS.md](operations/RUNBOOKS.md): Operational runbooks for common incident response scenarios
- [docs/security/THREAT_MODEL.md](security/THREAT_MODEL.md): Threat model with trust boundaries and data flow assumptions
- [docs/security/SECURITY_MODEL.md](security/SECURITY_MODEL.md): Security architecture: encryption, authentication, authorization
- [LessAtomic/QUICKSTART.md](../LessAtomic/QUICKSTART.md): 10-second startup; dry-run; performance benchmarks
- [LongHorizons/ES-INDEX-TEMPLATES.md](../LongHorizons/ES-INDEX-TEMPLATES.md): Index mappings, ILM policy, query patterns
- [Project/PROJECT.md](../Project/PROJECT.md): Full PMBOK-aligned project plan with milestone schedule, risk register, and quality metrics
