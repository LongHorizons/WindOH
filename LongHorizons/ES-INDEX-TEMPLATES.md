# Elasticsearch Index Setup

The agent exports to 4 index families. Create these templates before starting the agent to ensure correct type mappings and prevent the type conflicts that caused the 0.15% export success rate (4.9M errors) in early testing.

## Critical: Provider Properties Type Safety

The agent now **stringifies all `provider_properties` leaf values** before export. This prevents ES from rejecting documents where the same field appears as a `string` in one document and a `long` in another. The templates below enforce `keyword` type for all provider property sub-fields.

---

## Index Templates

### telemetry-events-*

Primary event feed — individual telemetry events with full enrichment.

```json
PUT _index_template/telemetry-events
{
  "index_patterns": ["telemetry-events-*"],
  "template": {
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 1,
      "refresh_interval": "5s",
      "codec": "best_compression"
    },
    "mappings": {
      "dynamic": true,
      "dynamic_templates": [
        {
          "provider_properties_as_keywords": {
            "path_match": "provider_properties.*",
            "mapping": {
              "type": "keyword",
              "ignore_above": 512
            }
          }
        }
      ],
      "properties": {
        "@timestamp": { "type": "date" },
        "doc_type": { "type": "keyword" },

        "event_type": { "type": "keyword" },
        "event_name": { "type": "text", "fields": { "keyword": { "type": "keyword" } } },
        "severity": { "type": "keyword" },
        "category": { "type": "keyword" },
        "description_raw": { "type": "text" },
        "rarity_band": { "type": "keyword" },
        "field_completeness": { "type": "float" },

        "etw": {
          "properties": {
            "provider": { "type": "keyword" },
            "provider_guid": { "type": "keyword" },
            "event_id": { "type": "integer" },
            "opcode": { "type": "integer" },
            "level": { "type": "integer" },
            "thread_id": { "type": "long" },
            "keywords": { "type": "keyword" }
          }
        },

        "host": {
          "properties": {
            "name": { "type": "keyword" },
            "id": { "type": "keyword" },
            "os_version": { "type": "keyword" }
          }
        },

        "user": {
          "properties": {
            "sid": { "type": "keyword" },
            "name": { "type": "keyword" }
          }
        },

        "process": {
          "properties": {
            "pid": { "type": "integer" },
            "ppid": { "type": "integer" },
            "image_name": { "type": "keyword" },
            "image_path": { "type": "keyword" },
            "image_dir": { "type": "keyword" },
            "command_line_original": { "type": "text" },
            "command_line_normalized": { "type": "text" },
            "command_line_analysis": {
              "properties": {
                "length": { "type": "integer" },
                "entropy": { "type": "float" },
                "obfuscation_score": { "type": "integer" },
                "has_base64_encoded": { "type": "boolean" },
                "has_download_cmdlet": { "type": "boolean" },
                "has_invoke_expression": { "type": "boolean" },
                "has_hidden_window": { "type": "boolean" },
                "has_pipe_to_shell": { "type": "boolean" }
              }
            },
            "integrity": { "type": "keyword" },
            "integrity_level": { "type": "keyword" },
            "integrity_value": { "type": "integer" },
            "signature_bucket": { "type": "keyword" },
            "signature_publisher": { "type": "keyword" },
            "signature_status": { "type": "keyword" },
            "directory_class": { "type": "keyword" },
            "session_id": { "type": "integer" },
            "user": { "type": "keyword" },
            "user_domain": { "type": "keyword" },
            "hashes": { "type": "keyword" },
            "process_guid": { "type": "keyword" },
            "logon_id": { "type": "keyword" },
            "start_time": { "type": "long" },
            "end_time": { "type": "long" },
            "exit_code": { "type": "integer" },
            "loaded_modules": { "type": "keyword" }
          }
        },

        "parent": {
          "properties": {
            "image_name": { "type": "keyword" },
            "image_path": { "type": "keyword" },
            "image_dir": { "type": "keyword" },
            "directory_class": { "type": "keyword" },
            "signature_bucket": { "type": "keyword" },
            "grandparent_image_name": { "type": "keyword" },
            "grandparent_image_path": { "type": "keyword" }
          }
        },

        "network": {
          "properties": {
            "src_ip": { "type": "keyword" },
            "src_port": { "type": "integer" },
            "dst_ip": { "type": "keyword" },
            "dst_port": { "type": "integer" },
            "protocol": { "type": "keyword" },
            "dst_ip_class": { "type": "keyword" },
            "source_ip_class": { "type": "keyword" },
            "source_port_name": { "type": "keyword" },
            "destination_port_name": { "type": "keyword" },
            "state": { "type": "keyword" },
            "interface_index": { "type": "integer" },
            "ip_id": { "type": "integer" },
            "src_ip_class_name": { "type": "keyword" },
            "dst_ip_class_name": { "type": "keyword" },
            "tcb_index": { "type": "keyword" },
            "direction": { "type": "keyword" }
          }
        },

        "dns": {
          "properties": {
            "query_name": { "type": "keyword" },
            "query_type": { "type": "keyword" },
            "response_code": { "type": "keyword" },
            "query_status": { "type": "keyword" },
            "query_results": { "type": "text" },
            "answers": { "type": "keyword" },
            "server_list": { "type": "keyword" },
            "interface_index": { "type": "integer" },
            "cache_hit": { "type": "boolean" },
            "query_id": { "type": "integer" },
            "query_time_ms": { "type": "integer" }
          }
        },

        "registry": {
          "properties": {
            "operation": { "type": "keyword" },
            "key_path": { "type": "keyword" },
            "value_name": { "type": "keyword" },
            "value_type": { "type": "keyword" },
            "value_type_name": { "type": "keyword" },
            "value_data_preview": { "type": "text" },
            "hive": { "type": "keyword" },
            "details": { "type": "text" },
            "details_raw": { "type": "text" },
            "process_guid": { "type": "keyword" },
            "disposition": { "type": "keyword" },
            "ntstatus": { "type": "keyword" }
          }
        },

        "file": {
          "properties": {
            "operation": { "type": "keyword" },
            "path": { "type": "keyword" },
            "name": { "type": "keyword" },
            "directory": { "type": "keyword" },
            "extension": { "type": "keyword" },
            "size": { "type": "long" },
            "attributes": { "type": "keyword" },
            "file_attributes_decoded": { "type": "text" },
            "file_id": { "type": "keyword" },
            "creation_time": { "type": "long" },
            "last_access_time": { "type": "long" },
            "last_write_time": { "type": "long" },
            "end_of_file": { "type": "long" },
            "allocation_size": { "type": "long" },
            "irp_function": { "type": "keyword" },
            "path_analysis": {
              "properties": {
                "in_temp_dir": { "type": "boolean" },
                "in_downloads": { "type": "boolean" },
                "in_appdata": { "type": "boolean" },
                "suspicious_path_score": { "type": "integer" }
              }
            }
          }
        },

        "image_load": {
          "properties": {
            "module_path": { "type": "keyword" },
            "module_name": { "type": "keyword" },
            "module_dir": { "type": "keyword" },
            "module_directory_class": { "type": "keyword" },
            "signature_bucket": { "type": "keyword" },
            "signature_publisher": { "type": "keyword" },
            "image_checksum": { "type": "long" },
            "time_date_stamp": { "type": "long" },
            "compile_timestamp": { "type": "long" },
            "section_count": { "type": "integer" },
            "import_table_entropy": { "type": "float" },
            "debug_path": { "type": "keyword" }
          }
        },

        "wmi": {
          "properties": {
            "operation": { "type": "keyword" },
            "namespace": { "type": "keyword" },
            "query": { "type": "text" },
            "consumer": { "type": "keyword" },
            "filter": { "type": "keyword" },
            "status": { "type": "keyword" },
            "provider_name": { "type": "keyword" },
            "result": { "type": "keyword" },
            "activity_id": { "type": "keyword" },
            "start_time": { "type": "long" },
            "end_time": { "type": "long" }
          }
        },

        "tokens": {
          "properties": {
            "base": { "type": "keyword" },
            "payload": { "type": "keyword" },
            "schema_version": { "type": "integer" },
            "base_canonical": { "type": "text" },
            "payload_canonical": { "type": "text" }
          }
        },

        "process_classification": {
          "properties": {
            "classification": { "type": "keyword" },
            "is_system_path": { "type": "boolean" },
            "is_microsoft_signed": { "type": "boolean" },
            "is_temp_location": { "type": "boolean" }
          }
        },

        "process_lineage": {
          "properties": {
            "pid": { "type": "integer" },
            "ppid": { "type": "integer" },
            "image_name": { "type": "keyword" },
            "image_path": { "type": "keyword" },
            "parent_image_name": { "type": "keyword" },
            "parent_image_path": { "type": "keyword" },
            "session_id": { "type": "integer" },
            "user": { "type": "keyword" },
            "integrity": { "type": "keyword" }
          }
        },

        "enrichment": {
          "properties": {
            "local_ips": { "type": "keyword" },
            "primary_ip": { "type": "keyword" },
            "vt_hash_match": { "type": "keyword" },
            "abuseipdb_category": { "type": "keyword" },
            "domain_registration_days": { "type": "long" },
            "cert_valid": { "type": "boolean" }
          }
        },

        "burst_context": {
          "properties": {
            "events_5s": { "type": "integer" },
            "events_60s": { "type": "integer" },
            "total_events_for_pid": { "type": "integer" }
          }
        },

        "behavior_tags": { "type": "keyword" },
        "parsed_terms": { "type": "keyword" },
        "tree_depth": { "type": "integer" },
        "process_age_seconds": { "type": "long" },
        "timestamp_unix_ms": { "type": "long" },
        "timestamp_utc": { "type": "long" }
      }
    }
  }
}
```

---

### telemetry-exemplars-*

Representative event samples per base token.

```json
PUT _index_template/telemetry-exemplars
{
  "index_patterns": ["telemetry-exemplars-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "refresh_interval": "30s",
      "codec": "best_compression"
    },
    "mappings": {
      "dynamic": true,
      "dynamic_templates": [
        {
          "provider_properties_as_keywords": {
            "path_match": "provider_properties.*",
            "mapping": {
              "type": "keyword",
              "ignore_above": 512
            }
          }
        }
      ],
      "properties": {
        "@timestamp": { "type": "date" },
        "doc_type": { "type": "keyword" },
        "exemplar_reason": { "type": "keyword" },
        "classification": {
          "properties": {
            "rarity_band": { "type": "keyword" },
            "rarity_score": { "type": "float" }
          }
        },
        "event_type": { "type": "keyword" },
        "tokens.base": { "type": "keyword" },
        "tokens.payload": { "type": "keyword" }
      }
    }
  }
}
```

---

### telemetry-patterns

Aggregated pattern statistics documents.

```json
PUT _index_template/telemetry-patterns
{
  "index_patterns": ["telemetry-patterns"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "refresh_interval": "60s",
      "codec": "best_compression"
    },
    "mappings": {
      "dynamic": true,
      "dynamic_templates": [
        {
          "provider_properties_as_keywords": {
            "path_match": "provider_properties.*",
            "mapping": {
              "type": "keyword",
              "ignore_above": 512
            }
          }
        }
      ],
      "properties": {
        "@timestamp": { "type": "date" },
        "doc_type": { "type": "keyword" },
        "pattern_id": { "type": "keyword" },
        "global_pattern_id": { "type": "keyword" },
        "event_type": { "type": "keyword" },
        "schema_version": { "type": "integer" },
        "first_seen_utc": { "type": "date" },
        "last_seen_utc": { "type": "date" },
        "counts": {
          "properties": {
            "total": { "type": "long" },
            "decay_30d_score": { "type": "float" },
            "rarity_band": { "type": "keyword" }
          }
        },
        "variant_summary": {
          "properties": {
            "distinct_payloads_est_30d": { "type": "long" }
          }
        },
        "host_context": {
          "properties": {
            "os_version": { "type": "keyword" },
            "agent_version": { "type": "keyword" }
          }
        },
        "tokens.base": { "type": "keyword" }
      }
    }
  }
}
```

---

### telemetry-diagnostics

Agent health and self-monitoring.

```json
PUT _index_template/telemetry-diagnostics
{
  "index_patterns": ["telemetry-diagnostics"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "refresh_interval": "30s"
    },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "doc_type": { "type": "keyword" },
        "level": { "type": "keyword" },
        "component": { "type": "keyword" },
        "message": { "type": "text" },
        "details": { "type": "text" },
        "host": {
          "properties": {
            "id": { "type": "keyword" },
            "name": { "type": "keyword" }
          }
        }
      }
    }
  }
}
```

---

## The `dynamic_templates` Fix

The critical addition is the `dynamic_templates` block in every index:

```json
"dynamic_templates": [
  {
    "provider_properties_as_keywords": {
      "path_match": "provider_properties.*",
      "mapping": {
        "type": "keyword",
        "ignore_above": 512
      }
    }
  }
]
```

This ensures that **every field under `provider_properties` is indexed as a `keyword`**, regardless of whether the agent sends it as a string, number, or object. This prevents the ES mapping conflict errors (`mapper_parsing_exception`, `object mapping for [field] tried to parse as...`) that caused the 4.9M export failures in early testing.

Combined with the agent-side fix (all provider_properties values stringified in [pipeline.rs:1010-1024](../agent-core/src/pipeline.rs#L1010-L1024)), this establishes a defense-in-depth guarantee against type conflicts.

---

## Event Types (38 recognized)

`process_start` | `process_end` | `process_operation` | `network_connect` | `dns_query` | `registry` | `image_load` | `image_unload` | `thread_start` | `thread_end` | `thread_operation` | `wmi` | `file` | `antimalware` | `appmodel` | `shell_core` | `system_trace` | `memory_operation` | `power_state` | `boot_event` | `com_classic` | `rpcss` | `capi2` | `dotnet_runtime` | `ntfs` | `win32k` | `schannel` | `bits_client` | `filter_manager` | `wininet` | `winhttp` | `service` | `smb_client` | `vbscript` | `task_scheduler` | `applocker` | `applocker_block` | `defender` | `defender_threat` | `defender_action` | `defender_scan` | `defender_update` | `defender_config` | `threat_intelligence` | `process_forensic` | `browser_history` | `browser_download` | `registry_snapshot_diff` | `generic`

---

*Document updated 2026-05-29 — Reflects data quality overhaul with stringified provider_properties and type-safe index templates*
