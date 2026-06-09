#!/bin/bash
# =============================================================================
# WindOH Cloud Agent — AWS EC2 UserData (Amazon Linux 2023)
# =============================================================================
# Installs the LongHorizons cloud agent as a systemd service. The agent polls
# 9 AWS services (CloudTrail, VPC Flow Logs, GuardDuty, Security Hub, S3
# Access Logs, WAF Logs, Route53 Resolver, ELB Access Logs, Config Rules) via
# the EC2 instance profile — no long-lived access keys required.
# =============================================================================
set -euo pipefail

AGENT_ID="${agent_id}"
ES_ENDPOINT="${elasticsearch_endpoint}"
ES_API_KEY="${elasticsearch_api_key}"
ES_INDEX="${elasticsearch_index_pattern}"
AWS_REGION="${aws_region}"
POLLED_REGIONS="${polled_regions}"
POLL_INTERVAL="${poll_interval_secs}"
BEDROCK_ENABLED="${enable_bedrock_llm}"

AGENT_DIR="/opt/windoh"
CONFIG_DIR="/etc/windoh"
DATA_DIR="/var/lib/windoh"

# ---------------------------------------------------------------------------
# Disk layout — /var/lib/windoh on its own XFS filesystem for SQLite WAL
# ---------------------------------------------------------------------------
mkdir -p "$AGENT_DIR" "$CONFIG_DIR" "$DATA_DIR"

# ---------------------------------------------------------------------------
# Download the pre-built cloud agent wizard from releases
# ---------------------------------------------------------------------------
curl -fsSL -o "$AGENT_DIR/wizard-aws" \
  "https://github.com/LongHorizons/WindOH/raw/master/LongHorizons/releases/cloud/wizard-aws"
chmod 755 "$AGENT_DIR/wizard-aws"

# ---------------------------------------------------------------------------
# Write config.toml — the same format as config-aws.example.toml
# ---------------------------------------------------------------------------
cat > "$CONFIG_DIR/config.toml" << CONFIG
[agent]
id = "$AGENT_ID"

[paths]
data_dir = "$DATA_DIR"

[aws]
regions = [$POLLED_REGIONS]
poll_interval_secs = $POLL_INTERVAL

[aws.services]
cloudtrail = true
vpc_flow_logs = true
guardduty = true
security_hub = true
s3_access_logs = true
waf_logs = true
route53_logs = true
elb_logs = true
config_rules = true

[export.events]
endpoint = "$ES_ENDPOINT"
api_key = "$ES_API_KEY"
index_pattern = "$ES_INDEX"

[export.health]
endpoint = "$ES_ENDPOINT"
api_key = "$ES_API_KEY"
index_pattern = "cloud-health"
CONFIG

# ---------------------------------------------------------------------------
# Bedrock LLM enrichment (optional) — Claude 4.x for structured analysis
# The WindOH API sends enrichment prompts to Bedrock instead of a local vLLM
# endpoint. Data stays in your VPC. Same prompt, same response format.
# ---------------------------------------------------------------------------
if [ "$BEDROCK_ENABLED" = "true" ]; then
  cat >> "$CONFIG_DIR/config.toml" << BEDROCK

[bedrock]
region = "$AWS_REGION"
model_id = "anthropic.claude-sonnet-4-6-20250514"
# Also available:
#   anthropic.claude-opus-4-8-20250514
#   anthropic.claude-haiku-4-5-20251001
inference_profile = "arn:aws:bedrock:${aws_region}::foundation-model/anthropic.claude-sonnet-4-6-20250514"
BEDROCK
fi

# ---------------------------------------------------------------------------
# Initialize the agent — IMDSv2 credential auto-detection
# ---------------------------------------------------------------------------
"$AGENT_DIR/wizard-aws" init --region "$AWS_REGION" --agent-id "$AGENT_ID"

# ---------------------------------------------------------------------------
# Install as systemd service
# ---------------------------------------------------------------------------
"$AGENT_DIR/wizard-aws" install "$CONFIG_DIR/config.toml"

# ---------------------------------------------------------------------------
# Verify the service is running
# ---------------------------------------------------------------------------
sleep 3
"$AGENT_DIR/wizard-aws" status
