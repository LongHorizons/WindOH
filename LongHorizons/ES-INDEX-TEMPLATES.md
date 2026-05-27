# Elasticsearch Index Setup

The agent exports to 4 indexes. Create index templates in Elasticsearch before starting the agent to ensure correct mappings.

## Index Templates

### longhorizons-events

Primary event feed — individual telemetry events with full enrichment.

```json
PUT _index_template/longhorizons-events
{
  "index_patterns": ["longhorizons-events*"],
  "template": {
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 1,
      "refresh_interval": "5s",
      "codec": "best_compression"
    },
    "mappings": {
      "dynamic": true,
      "properties": {
        "timestamp_utc": { "type": "date" },
        "timestamp_unix_ms": { "type": "long" },
        "event_type": { "type": "keyword" },
        "provider": { "type": "keyword" },
        "host.name": { "type": "keyword" },
        "host.id": { "type": "keyword" },
        "process.pid": { "type": "integer" },
        "process.image_name": { "type": "keyword" },
        "process.image_path": { "type": "keyword" },
        "tokens.stable_hex": { "type": "keyword" },
        "tokens.payload_hex": { "type": "keyword" },
        "rarity_band": { "type": "keyword" },
        "risk_score": { "type": "float" },
        "decay_score": { "type": "double" },
        "behavior_tags": { "type": "keyword" },
        "process_classification": { "type": "keyword" }
      }
    }
  }
}
```

### longhorizons-exemplars

Representative event samples per stable token.

```json
PUT _index_template/longhorizons-exemplars
{
  "index_patterns": ["longhorizons-exemplars*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "refresh_interval": "30s",
      "codec": "best_compression"
    },
    "mappings": {
      "dynamic": true,
      "properties": {
        "timestamp_utc": { "type": "date" },
        "stable_hex": { "type": "keyword" },
        "exemplar_reason": { "type": "keyword" },
        "rarity_band": { "type": "keyword" },
        "host.name": { "type": "keyword" }
      }
    }
  }
}
```

### longhorizons-patterns

Aggregated pattern statistics documents.

```json
PUT _index_template/longhorizons-patterns
{
  "index_patterns": ["longhorizons-patterns*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "refresh_interval": "60s",
      "codec": "best_compression"
    },
    "mappings": {
      "dynamic": true,
      "properties": {
        "timestamp_utc": { "type": "date" },
        "pattern_type": { "type": "keyword" },
        "stable_hex": { "type": "keyword" },
        "rarity_band": { "type": "keyword" },
        "host.name": { "type": "keyword" },
        "frequency_estimate": { "type": "long" },
        "dropped_count": { "type": "long" }
      }
    }
  }
}
```

### longhorizons-diagnostics

Agent health and self-monitoring.

```json
PUT _index_template/longhorizons-diagnostics
{
  "index_patterns": ["longhorizons-diagnostics*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "refresh_interval": "60s"
    },
    "mappings": {
      "dynamic": true,
      "properties": {
        "timestamp_utc": { "type": "date" },
        "component": { "type": "keyword" },
        "level": { "type": "keyword" },
        "message": { "type": "text" },
        "host.name": { "type": "keyword" },
        "etw_restart_count": { "type": "integer" },
        "dropped_events": { "type": "long" }
      }
    }
  }
}
```

## ES API Key (Required for Elasticsearch 8.x)

Create an API key with permissions:

```json
POST _security/api_key
{
  "name": "longhorizons-agent",
  "role_descriptors": {
    "longhorizons-writer": {
      "cluster": ["monitor"],
      "index": [
        {
          "names": ["longhorizons-*"],
          "privileges": ["create_index", "index", "write", "read"]
        }
      ]
    }
  }
}
```

Response contains the base64 `id:api_key` string to use in `config.toml`.

## Data Retention (ILM Policy)

Recommended ILM policy to manage disk usage:

```json
PUT _ilm/policy/longhorizons-retention
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "50gb",
            "max_age": "7d"
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": { "number_of_shards": 1 },
          "forcemerge": { "max_num_segments": 1 }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

Apply to index templates via `"lifecycle": { "name": "longhorizons-retention" }` in settings.
