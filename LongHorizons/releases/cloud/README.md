# Cloud Telemetry Agent

Multi-cloud telemetry collector — unified schema across AWS, Azure, GCP, Oracle, and Kubernetes.

## 5 Providers, One Agent

```
cloud-agent run --config config.toml   # Starts all configured providers
```

Each provider is isolated in its own subdirectory with its own wizard.

### AWS — 9 Services
| Source | What It Captures |
|--------|-----------------|
| CloudTrail | Every API call (RunInstances, AssumeRole, ConsoleLogin...) |
| VPC Flow Logs | Network traffic metadata (ACCEPT/REJECT, bytes, packets) |
| GuardDuty | Threat findings (recon, C2, crypto mining, anomaly) |
| Security Hub | Aggregated compliance + findings across AWS services |
| S3 Access Logs | Object-level GET/PUT/DELETE |
| WAF Logs | Web application firewall (OWASP rules, rate limiting) |
| Route53 Resolver | DNS query logs |
| ELB Access Logs | ALB/NLB/CLB request logs |
| AWS Config | Compliance rule evaluations (CIS, PCI, custom) |

### Azure — 6 Services
- Activity Log (management plane operations)
- NSG Flow Logs (network security group)
- Sentinel alerts (SIEM)
- Azure AD Sign-in logs (authentication)
- Key Vault logs (secret/key access)
- Azure Policy (compliance)

### GCP — 5 Services
- Cloud Audit Logs (Admin Activity + Data Access)
- VPC Flow Logs (network)
- Security Command Center (findings)
- Cloud Logging (application logs)
- Access Transparency (Google admin access)

### Oracle OCI — 4 Services
- Audit Logs (all API operations)
- VCN Flow Logs (network)
- Cloud Guard (threat detection)
- Events Service (resource lifecycle)

### Kubernetes
- API server audit logs
- Pod security context violations
- Admission controller reviews
- Network policy events
- In-cluster or kubeconfig authentication

## Unified Schema
All cloud events normalize into a single `CloudEvent`:
```
CloudEvent
├── Actor (principal ARN, type, MFA, source IP, user agent)
├── Resource (ARN, type, region, account, tags)
├── Network (5-tuple, VPC/subnet, ACCEPT/REJECT)
├── API Action (service, action, category, status, error)
├── Authorization (Allow/Deny, policy, permissions)
├── Threat (finding, severity 0-10, MITRE ATT&CK, indicator)
└── Compliance (CIS/PCI/HIPAA, control, PASSED/FAILED)
```

## Per-Provider Wizards
```bash
# AWS
./wizard-aws init --region us-east-1
./wizard-aws install config-aws.toml

# Azure
./wizard-azure init --tenant-id "CHANGEME"
./wizard-azure install config-azure.toml

# GCP
./wizard-gcp init --project-id "my-project"
./wizard-gcp install config-gcp.toml

# Oracle
./wizard-oracle init --tenancy-ocid "ocid1..."
./wizard-oracle install config-oracle.toml

# Kubernetes
./wizard-k8s init
./wizard-k8s install config-k8s.toml
```

## Source Layout
```
cloud/
├── agent-core-cloud/        # Shared models, config, pipeline
├── agent-exporter-cloud/    # Shared ES bulk export
├── agent-service-cloud/     # Shared CLI, run loop
├── aws/                     # AWS: agent, wizard, deploy
├── azure/                   # Azure: agent, wizard, deploy
├── gcp/                     # GCP: agent, wizard, deploy
├── oracle/                  # Oracle: agent, wizard, deploy
└── kubernetes/              # K8s: agent, wizard, deploy
```
