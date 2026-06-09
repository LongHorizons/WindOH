# Cloud Telemetry Agent

Multi-cloud API log collector. One agent, five providers, unified schema.

## Distribution

Each provider has its own wizard binary. Each wizard embeds the cloud agent inside it. Pick the wizard for your provider:

```
wizard-aws                  — AWS installer + embedded agent
wizard-azure                — Azure installer + embedded agent
wizard-gcp                  — GCP installer + embedded agent
wizard-oracle               — Oracle OCI installer + embedded agent
wizard-k8s                  — Kubernetes installer + embedded agent
config-aws.example.toml     — AWS configuration reference
config-azure.example.toml   — Azure configuration reference
config-gcp.example.toml     — GCP configuration reference
config-oracle.example.toml  — Oracle configuration reference
config-k8s.example.toml     — Kubernetes configuration reference
install.sh                  — Shell install helper
```

## Install

```bash
# AWS
./wizard-aws init --region us-east-1 --agent-id prod-01
sudo ./wizard-aws install config-aws.toml

# Azure
./wizard-azure init --tenant-id "..." --agent-id prod-01
sudo ./wizard-azure install config-azure.toml

# GCP
./wizard-gcp init --project-id "my-project" --agent-id prod-01
sudo ./wizard-gcp install config-gcp.toml

# Oracle
./wizard-oracle init --tenancy-ocid "ocid1..." --agent-id prod-01
sudo ./wizard-oracle install config-oracle.toml

# Kubernetes
./wizard-k8s init --agent-id prod-01
sudo ./wizard-k8s install config-k8s.toml
```

## Uninstall / Update / Status

```bash
sudo ./wizard-aws uninstall --remove-data
sudo ./wizard-aws update config-aws.toml
./wizard-aws status
```

Same pattern for all providers — swap `wizard-aws` for your provider.

## Coverage

| Provider | Services |
|----------|----------|
| AWS (9) | CloudTrail, VPC Flow Logs, GuardDuty, Security Hub, S3 Access, WAF, Route53, ELB, Config |
| Azure (6) | Activity Log, NSG Flow Logs, Sentinel, AD Sign-in, Key Vault, Policy |
| GCP (5) | Cloud Audit Logs, VPC Flow Logs, SCC, Cloud Logging, Access Transparency |
| Oracle (4) | OCI Audit, VCN Flow Logs, Cloud Guard, Events |
| K8s (4) | Audit Logs, Pod Security, Admission Reviews, Network Policies |

## Build from Source

```bash
cd cloud
cargo build --release --target x86_64-unknown-linux-musl -p agent-service-cloud
for wizard in wizard-aws wizard-azure wizard-gcp wizard-oracle wizard-k8s; do
    cargo build --release --target x86_64-unknown-linux-musl -p "$wizard"
done
```

## Architecture

Full per-provider architecture with Mermaid diagrams, CloudEvent schema mapping, data flow animations, and deployment patterns: **[CLOUD-ARCHITECTURE.md](CLOUD-ARCHITECTURE.md)**

## Terraform

Production-grade infrastructure-as-code for each provider in `terraform/`:

| Provider | Directory | What It Creates |
|----------|-----------|-----------------|
| **AWS** | [`terraform/aws/`](terraform/aws/) | IAM role (least-privilege, 9 service policies), CloudTrail (multi-region + S3 data events + Lambda data events), VPC Flow Logs (S3 + CloudWatch), GuardDuty (all features including S3/EKS/RDS/EBS malware), Security Hub (CIS 1.4 + Foundational), S3 bucket encryption (KMS CMK), Config rules, EC2 instance w/ IMDSv2, Bedrock InvokeModel (Claude 4.x), S3 Parquet archive w/ lifecycle tiering |
| **Azure** | [`terraform/azure/`](terraform/azure/) | Resource group, User-assigned managed identity (DefaultAzureCredential), Log Analytics workspace + Sentinel onboarding, Activity Log diagnostic settings (7 categories per subscription), NSG Flow Log storage account, Azure VM (Ubuntu 22.04), NSG with egress rules, Key Vault w/ audit diagnostics |
| **GCP** | [`terraform/gcp/`](terraform/gcp/) | Service account (ADC), IAM bindings (logging.viewer, compute.networkViewer, securitycenter.findingsViewer per project), VPC Flow Log sampling config (100%, all metadata), GCE instance (Container-Optimized OS, Shielded VM), firewall egress rule, optional BigQuery export dataset |
| **Oracle** | [`terraform/oracle/`](terraform/oracle/) | Dynamic group + IAM policy (instance principals — no keys), VCN Flow Log (service log), NSG egress rules, Compute instance (Oracle Linux 8, flex shape), Cloud Guard enablement, optional OCI Streaming (Kafka-compatible, 50 GB free tier) |

Each Terraform directory is self-contained with provider-specific least-privilege policies, native credential chain setup (no long-lived access keys on disk), and cloud-init templates that download and install the agent wizard binary on first boot.

## Requirements
- Cloud provider credentials (IAM role, service principal, service account, API key)
- Outbound HTTPS to cloud APIs + Elasticsearch
- Elasticsearch 7.x or 8.x
- Terraform >= 1.5.0
