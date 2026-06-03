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

## Requirements
- Cloud provider credentials (IAM role, service principal, service account, API key)
- Outbound HTTPS to cloud APIs + Elasticsearch
- Elasticsearch 7.x or 8.x
