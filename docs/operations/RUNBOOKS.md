# Operational Runbooks

Procedures for diagnosing and recovering from failure conditions.

---

## Runbook 1: Restart Failed Agent

**Symptom:** Health check shows agent status `critical` or agent process not running.

**Diagnosis:**
```powershell
# Check service status
Get-Service LongHorizonsAgent

# Check recent logs
Get-Content C:\ProgramData\LongHorizonsAgent\logs\agent.log -Tail 50

# Check health diagnostics
sqlite3 C:\ProgramData\LongHorizonsAgent\state\agent.db \
  "SELECT status, json_extract(diagnostics, '$.pipeline.events_processed') FROM health ORDER BY timestamp DESC LIMIT 1"
```

**Recovery:**
```powershell
# Restart the service
Restart-Service LongHorizonsAgent

# If service fails to start, check config integrity
Test-Path C:\ProgramData\LongHorizonsAgent\config.toml

# Run foreground for detailed error output
.\agent.exe run --config C:\ProgramData\LongHorizonsAgent\config.toml
```

**If DPAPI failure:** Reinstall the agent service. The master key is tied to the service account — an account change invalidates DPAPI protection.

---

## Runbook 2: Recover Corrupted Dead-Letter Queue

**Symptom:** `dead_letter_depth` increasing; events not reaching Elasticsearch.

**Diagnosis:**
```powershell
# Check dead-letter contents
sqlite3 C:\ProgramData\LongHorizonsAgent\state\agent.db \
  "SELECT id, error, attempts, datetime(created_at) FROM outbox_dead_letter ORDER BY created_at DESC LIMIT 20"
```

**Recovery:**
```powershell
# Inspect a dead-lettered event
sqlite3 C:\ProgramData\LongHorizonsAgent\state\agent.db \
  "SELECT payload FROM outbox_dead_letter WHERE id = <id>"

# If event is valid but ES was temporarily unavailable:
# Re-queue for retry (update attempts to 0 and move back to outbox)
sqlite3 C:\ProgramData\LongHorizonsAgent\state\agent.db \
  "INSERT INTO outbox SELECT payload, 0, NULL FROM outbox_dead_letter WHERE id = <id>"
sqlite3 C:\ProgramData\LongHorizonsAgent\state\agent.db \
  "DELETE FROM outbox_dead_letter WHERE id = <id>"
```

---

## Runbook 3: Scale Enrichment Workers

**Symptom:** Enrichment queue depth growing; `pending_enrichment` metric increasing steadily.

**Diagnosis:**
```bash
# Check queue depth
curl -s http://localhost:3000/api/health | jq '.queues.enrichment'

# Check LLM latency
curl -s http://localhost:3000/api/health | jq '.dependencies.llm'
```

**Recovery:**
```bash
# Scale workers horizontally (Docker Compose)
docker compose up -d --scale enrichment-worker=4

# Or increase concurrency in BullMQ config
# Edit bullmq.config.ts: concurrency: 4 → 8
```

**Note:** Workers share the LLM endpoint. Scaling beyond the LLM's concurrent request capacity increases timeouts, not throughput. Monitor LLM queue depth alongside enrichment queue depth.

---

## Runbook 4: Rotate Elasticsearch API Keys

**Symptom:** Scheduled key rotation; agent or WindOH reports ES authentication errors.

**Procedure:**
```bash
# 1. Create new API key in Elasticsearch
curl -X POST "https://es.internal:9200/_security/api_key" \
  -H "Content-Type: application/json" \
  -d '{"name":"longhorizons-agent-v2","role_descriptors":{"longhorizons":{"cluster":["monitor"],"indices":[{"names":["longhorizons-*"],"privileges":["create_index","index","read"]}]}}}'

# 2. Update agent config on each endpoint
# Edit C:\ProgramData\LongHorizonsAgent\config.toml
# [export.events]
# api_key = "<new_key>"

# 3. Restart agent service
Restart-Service LongHorizonsAgent

# 4. Update WindOH environment
# Edit .env: ES_API_KEY=<new_key>

# 5. Rolling restart WindOH containers
docker compose up -d --no-deps --force-recreate api

# 6. Verify connectivity
curl -s http://localhost:3000/api/health | jq '.dependencies.elasticsearch'

# 7. Revoke old key after verification
curl -X DELETE "https://es.internal:9200/_security/api_key" \
  -H "Content-Type: application/json" \
  -d '{"name":"longhorizons-agent-v1"}'
```

---

## Runbook 5: Diagnose Stuck Enrichment Jobs

**Symptom:** Enrichment queue shows `failed` count increasing; tokens remain `pending_enrichment`.

**Diagnosis:**
```bash
# Check failed jobs in BullMQ
# Use Bull Board UI at http://localhost:3000/admin/queues

# Or query MongoDB for un-enriched tokens
mongosh "mongodb://localhost:27017/windoh" --eval '
  db.tokens.countDocuments({"enrichment.description": {$exists: false}})
'

# Check LLM endpoint health
curl -s http://192.168.0.133:31337/health
# Or for Ollama:
curl -s http://192.168.0.133:11434/api/tags
```

**Common causes:**
1. LLM OOM — check `dmesg` or system logs on LLM host. Reduce context length or model size.
2. Malformed prompt — a specific `stable_hash` has event data exceeding the LLM's context window. Skip enrichment for that token.
3. LLM timeout — increase `LLM_TIMEOUT_MS` or decrease `LLM_MAX_TOKENS`.

**Recovery:**
```bash
# Inspect a failed job's token data
mongosh "mongodb://localhost:27017/windoh" --eval '
  db.tokens.findOne({"stable_hash": "<hash>"})
'

# Force re-enrichment (clear enrichment and re-queue)
mongosh "mongodb://localhost:27017/windoh" --eval '
  db.tokens.updateOne(
    {"stable_hash": "<hash>"},
    {$unset: {enrichment: ""}}
  )
'
```

---

## Runbook 6: Recover from Worker Process Crash Loop

**Symptom:** Worker container restarting repeatedly; enrichment not progressing.

**Diagnosis:**
```bash
# Check worker logs
docker compose logs enrichment-worker --tail 100

# Check for OOM
docker compose exec enrichment-worker free -m

# Check for uncaught exceptions
docker compose logs enrichment-worker | grep -i "error\|fatal\|uncaught"
```

**Recovery:**
```bash
# 1. Stop the crash-looping worker
docker compose stop enrichment-worker

# 2. Clear the stuck job if it's causing the crash
# Use Bull Board UI or Redis CLI:
docker compose exec redis redis-cli --scan --pattern "bull:enrichment:*" | head -20

# 3. Restart worker
docker compose up -d enrichment-worker

# If crash persists:
# 4. Isolate the problematic token by checking which job was active at crash time
# 5. Skip enrichment for that token (Runbook 5)
# 6. File issue with token data and worker log excerpt
```

---

## Runbook 7: Restore MongoDB from Backup

**Symptom:** MongoDB data corruption or accidental deletion.

**Recovery:**
```bash
# Restore from most recent backup
mongorestore \
  --host localhost:27017 \
  --db windoh \
  --drop \
  /backups/mongodb/windoh-$(date -I)/

# After restore, enrichment will re-queue for any ES events
# that arrived after the backup timestamp (idempotent upsert handles this)
```

**Prevention:** Schedule automated backups:
```bash
# Cron / systemd timer:
0 2 * * * mongodump --host localhost:27017 --db windoh --out /backups/mongodb/windoh-$(date -I)/
```

---

## Runbook 8: Agent SQLite Database Maintenance

**Symptom:** Agent performance degradation; large `.db` file size.

**Diagnosis:**
```powershell
# Check database size and integrity
sqlite3 C:\ProgramData\LongHorizonsAgent\state\agent.db "PRAGMA integrity_check;"
sqlite3 C:\ProgramData\LongHorizonsAgent\state\agent.db "SELECT COUNT(*) FROM outbox;"
sqlite3 C:\ProgramData\LongHorizonsAgent\state\agent.db "SELECT COUNT(*) FROM events;"
```

**Recovery:**
```powershell
# Stop agent service
Stop-Service LongHorizonsAgent

# Run maintenance (WAL checkpoint + vacuum)
sqlite3 C:\ProgramData\LongHorizonsAgent\state\agent.db "PRAGMA wal_checkpoint(TRUNCATE);"
sqlite3 C:\ProgramData\LongHorizonsAgent\state\agent.db "VACUUM;"

# Trim old event data (retention configurable in config.toml)
sqlite3 C:\ProgramData\LongHorizonsAgent\state\agent.db \
  "DELETE FROM events WHERE timestamp < datetime('now', '-90 days');"

# Restart agent
Start-Service LongHorizonsAgent
```
