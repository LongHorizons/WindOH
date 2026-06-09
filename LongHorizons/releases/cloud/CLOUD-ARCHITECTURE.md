# WindOH Cloud Architecture

## Multi-Cloud Telemetry — One Schema, Five Providers, 24 Services

The LongHorizons cloud agent runs as a lightweight binary inside your cloud environment, polling provider APIs directly. Every event — a CloudTrail management call, a GuardDuty finding, a VPC Flow Log ACCEPT/REJECT, an Azure Sentinel alert, a GCP Security Command Center threat, an OCI Cloud Guard problem — is normalized into the **CloudEvent schema** and fed through the same deterministic tokenization pipeline as Windows ETW and Linux eBPF events.

The agent uses each provider's native credential chain. No long-lived access keys required. No cross-cloud data egress. Your cloud telemetry stays inside the environment that produced it.

---

## Mermaid Diagrams — Per-Provider Architecture

### AWS (9 Services)

```mermaid
graph TB
    classDef aws fill:#FF9900,stroke:#232F3E,color:#232F3E,font-weight:bold
    classDef agent fill:#1168bd,stroke:#0b4884,color:#fff
    classDef pipeline fill:#43a047,stroke:#2e7d32,color:#fff
    classDef infra fill:#666,stroke:#444,color:#fff

    subgraph AWS["<b>AWS Account — 9 Services Polled</b>"]
        CT["<b>CloudTrail</b><br/>Management + Data Events<br/>iam:PassRole, s3:GetObject<br/>sts:AssumeRole, ec2:RunInstances<br/>kms:Decrypt, lambda:Invoke<br/>bedrock:InvokeModel"]

        VPC["<b>VPC Flow Logs</b><br/>vpc-* ENI 5-tuple<br/>ACCEPT/REJECT per SG<br/>srcaddr→dstaddr:port<br/>pkt-srcaddr in S3 / CloudWatch"]

        GD["<b>GuardDuty</b><br/>CryptoCurrency:EC2/BitcoinTool.B!DNS<br/>Backdoor:EC2/C&CActivity.B!TCP<br/>Recon:EC2/PortProbeUnprotected<br/>CredentialCompromise:IAMUser/AnomalousBehavior<br/>Stealth:S3/MaliciousIPCaller.Custom<br/>Impact:EC2/AbusedDomain—high-severity findings"]

        SH["<b>Security Hub</b><br/>AWS Foundational Security Best Practices<br/>CIS AWS Foundations Benchmark v1.4.0 / v3.0.0<br/>PCI DSS v3.2.1 / v4.0<br/>NIST SP 800-53 Rev. 5<br/>Findings aggregated across all member accounts"]

        S3["<b>S3 Access Logs</b><br/>bucket/object GET PUT DELETE HEAD<br/>requester, request-URI, HTTP status<br/>error code, bytes sent, total time<br/>SSE-KMS/SSE-S3 object encryption<br/>cross-account access denial events"]

        WAF["<b>WAF Logs</b><br/>WebACL rule matches<br/>rate-based-rule 2000/5min threshold<br/>XSS/SQLi/geo-match blocking<br/>IP reputation groups — AWSManagedRulesAmazonIpReputationList<br/>BotControl signal labels: VERDICT/SEARCH_ENGINE/VERIFIED_BOT"]

        R53["<b>Route53 Resolver</b><br/>DNS query logs → CloudWatch<br/>VPC .2 resolver queries<br/>qtype: A AAAA CNAME MX TXT<br/>qname: example.com → srcids.instance<br/>NXDOMAIN / REFUSED / SERVFAIL counts"]

        ELB["<b>ELB Access Logs</b><br/>ALB/NLB/CLB → S3 every 5 min<br/>client:port → target:port<br/>backend_processing_time / response_processing_time<br/>elb_status_code vs target_status_code<br/>ssl_cipher + ssl_protocol TLS version<br/>user-agent / chosen-cert ARN / SNI domain"]

        CFG["<b>Config Rules</b><br/>s3-bucket-server-side-encryption-enabled<br/>restricted-ssh, restricted-common-ports<br/>iam-password-policy, mfa-enabled-for-iam-console-access<br/>cloudtrail-enabled, guardduty-enabled-centralized<br/>NonCompliant → ComplianceChangeNotification"]
    end

    subgraph Agent["<b>WindOH Cloud Agent (EC2 / ECS Fargate / EKS)</b>"]
        CREW["AWS SDK Credential Chain<br/>1. env AWS_ACCESS_KEY_ID<br/>2. EC2 instance profile (IMDSv2)<br/>3. ECS task role → IAM role<br/>4. ~/.aws/credentials → STS"]
        POLL["Concurrent Service Pollers<br/>tokio::spawn per service<br/>9 futures → join_all → batch"]
        TOK["Tokenization → SHA-256<br/>stable_token = behavioral skeleton<br/>payload_token = instance detail<br/>CloudEvent schema normalization"]
    end

    subgraph Pipe["<b>Shared Pipeline</b>"]
        CMS["Count-Min Sketch<br/>Rare ≤2 · Uncommon 3–20 · Common >20"]
        RES["Exemplar Reservoir<br/>fixed-size per base token"]
        OUT["SQLite Outbox<br/>3 priority tiers · WAL mode"]
    end

    subgraph Sink["<b>Export Targets</b>"]
        ES["Elasticsearch 8.x<br/>cloud-events-aws index<br/>bulk API · gzip · retry"]
        S3OUT["S3 Archive Parquet<br/>cloudtrail-archive/year=/month=/day=/<br/>Apache Parquet + Snappy<br/>Athena/Redshift Spectrum queryable"]
    end

    CT -->|"cloudtrail:LookupEvents paginated"| POLL
    VPC -->|"ec2:DescribeFlowLogs → S3 GetObject"| POLL
    GD -->|"guardduty:ListFindings → GetFindings"| POLL
    SH -->|"securityhub:GetFindings ASFF 1.0"| POLL
    S3 -->|"s3:GetBucketLogging → log objects"| POLL
    WAF -->|"wafv2:GetLogConfiguration → Kinesis Firehose → S3"| POLL
    R53 -->|"route53resolver:ListResolverQueryLogConfigs"| POLL
    ELB -->|"elbv2:DescribeLoadBalancers → S3 access logs"| POLL
    CFG -->|"config:GetComplianceDetailsByConfigRule"| POLL

    POLL --> TOK --> CMS --> RES --> OUT
    OUT --> ES
    OUT --> S3OUT

    class CT,VPC,GD,SH,S3,WAF,R53,ELB,CFG aws
    class CREW,POLL,TOK agent
    class CMS,RES,OUT pipeline
    class ES,S3OUT infra
```

### Azure (6 Services)

```mermaid
graph TB
    classDef azure fill:#0078D4,stroke:#005a9e,color:#fff,font-weight:bold
    classDef agent fill:#1168bd,stroke:#0b4884,color:#fff
    classDef pipeline fill:#43a047,stroke:#2e7d32,color:#fff

    subgraph Azure["<b>Azure Tenant — 6 Services Polled</b>"]
        AL["<b>Activity Log</b><br/>Microsoft.Insights/diagnosticSettings<br/>Administrative: VM create/delete, NSG rule change<br/>ServiceHealth: platform incident RCA<br/>ResourceHealth: degraded, unavailable<br/>Alert: metric threshold fires<br/>Autoscale: scale-out / scale-in trigger<br/>Security: Microsoft Defender for Cloud alerts"]

        NSG["<b>NSG Flow Logs</b><br/>Network Watcher per-NIC flow tuples<br/>Version 2 — 5-tuple + traffic decision<br/>src,dst IP:port → protocol → bytes/packets<br/>FlowState: B (begin) / C (continue) / E (end)<br/>TrafficDecision: Allowed / Denied<br/>FlowDirection: I (inbound) / O (outbound)<br/>Storage: Azure Blob / Data Lake Gen2"]

        SEN["<b>Sentinel Alerts</b><br/>Analytics rules: Scheduled / ML Behavior / Fusion<br/>Scheduled: SigninLogs | where RiskLevel == 'high'<br/>ML: AnomalousRDPGeography — impossible-travel<br/>Fusion: multi-stage attack correlation<br/>NRT: Near-Real-Time → 1 min latency<br/>UEBA: BehaviorAnalytics — user/entity insights<br/>Incidents: multiple-alert grouping + triage"]

        AD["<b>AD Sign-in Logs</b><br/>SigninLogs table — non-interactive, interactive<br/>UserPrincipalName, AppDisplayName, ClientAppUsed<br/>ConditionalAccessStatus, MfaResult, RiskLevel<br/>DeviceDetail: isCompliant, isManaged, trustType<br/>Location: city/state/country, geoCoordinates<br/>Error codes: 50053 (account locked), 50057 (disabled), 50126 (invalid credentials), 53003 (blocked by CA)"]

        KV["<b>Key Vault Logs</b><br/>AzureDiagnostics / AuditEvent category<br/>SecretGet, SecretList, SecretSet, SecretDelete<br/>KeySign, KeyVerify, KeyUnwrap, KeyWrap<br/>CertificateImport, CertificateExport<br/>CallerIPAddress, resultType (Success / Failure)<br/>requestUri: vault.azure.net → operation tracking"]

        AP["<b>Azure Policy</b><br/>PolicyAssignments at MG/Sub/RG scope<br/>audit, deny, deployIfNotExists, modify effects<br/>Built-in initiatives: CIS, PCI-DSS, HIPAA, NIST 800-53<br/>ComplianceState: Compliant / NonCompliant / Unknown<br/>resourceId + timestamp + reason<br/>remediation task creation + deployment tracking"]
    end

    subgraph Agent["<b>WindOH Cloud Agent (Azure VM / ACI / AKS)</b>"]
        CRED["DefaultAzureCredential Chain<br/>1. EnvironmentCredential<br/>2. WorkloadIdentityCredential<br/>3. ManagedIdentityCredential (IMDS)<br/>4. SharedTokenCacheCredential<br/>5. AzureCliCredential<br/>6. VisualStudioCredential"]
        POLL["Concurrent Service Pollers<br/>tokio::spawn per subscription<br/>6 services × N subscriptions"]
        TOK["Tokenization → CloudEvent Schema<br/>stable_token / payload_token<br/>AES-256-GCM at rest"]
    end

    subgraph Pipe["<b>Shared Pipeline</b>"]
        CMS2["Count-Min Sketch"]
        RES2["Exemplar Reservoir"]
        OUT2["SQLite Outbox"]
    end

    subgraph Sink["<b>Export Targets</b>"]
        ES["Elasticsearch 8.x<br/>cloud-events-azure index"]
        LA["Log Analytics Workspace<br/>Custom Logs table<br/>windoh_cloud_events_CL"]
    end

    AL -->|"Azure Monitor REST API → activity log"| POLL
    NSG -->|"Network Watcher REST → flow logs from Blob"| POLL
    SEN -->|"Sentinel REST API → /incidents + /alerts"| POLL
    AD -->|"Microsoft Graph API → auditLogs/signIns"| POLL
    KV -->|"Key Vault REST → diagnostic logs from EventHub/Blob"| POLL
    AP -->|"Azure Policy Insights REST → policyStates"| POLL

    POLL --> TOK --> CMS2 --> RES2 --> OUT2
    OUT2 --> ES
    OUT2 --> LA

    class AL,NSG,SEN,AD,KV,AP azure
    class CRED,POLL,TOK agent
    class CMS2,RES2,OUT2 pipeline
    class ES,LA infra
```

### GCP (5 Services)

```mermaid
graph TB
    classDef gcp fill:#4285F4,stroke:#3367D6,color:#fff,font-weight:bold
    classDef agent fill:#1168bd,stroke:#0b4884,color:#fff
    classDef pipeline fill:#43a047,stroke:#2e7d32,color:#fff

    subgraph GCP["<b>GCP Project — 5 Services Polled</b>"]
        CAL["<b>Cloud Audit Logs</b><br/>Admin Activity: gcloud compute instances delete, gsutil rm, bq rm<br/>Data Access: storage.objects.get, datastore.entities.query<br/>System Event: compute.instances.migrateOnHostMaintenance<br/>Policy Denied: IAM permissions check FAILED<br/>authenticationInfo: principalEmail, serviceAccountKeyName<br/>authorizationInfo: granted=true/false, permission, resource<br/>requestMetadata: callerIp, callerSuppliedUserAgent"]

        VPC["<b>VPC Flow Logs</b><br/>Per-subnet sampling: 100% / 50% / 10%<br/>metadata: src/dst instance, zone, project, region<br/>connection: 5-tuple + protocol + start/end RTT<br/>bytes_sent, packets_sent<br/>src_vpc / dst_vpc — cross-VPC traffic<br/>src_location / dst_location: US, EU, ASIA<br/>Base aggregation interval: 5 sec default"]

        SCC["<b>Security Command Center</b><br/>Findings per org/folder/project<br/>Category: XSS_SCRIPTING, MALWARE_BAD_DOMAIN<br/>SECRET_LEAK, OPEN_FIREWALL_PORT<br/>PUBLIC_SQL_INSTANCE, PUBLIC_BUCKET_ACL<br/>KUBERNETES_OVERPRIVILEGED_SERVICE_ACCOUNT<br/>Severity: CRITICAL / HIGH / MEDIUM / LOW<br/>sourceProperties: scannerName, scanId, findingClass"]

        CL["<b>Cloud Logging</b><br/>gcloud logging read — log filter syntax<br/>resource.type: gce_instance, gcs_bucket, gke_cluster<br/>severity: EMERGENCY ALERT CRITICAL ERROR WARNING NOTICE INFO DEBUG<br/>textPayload / jsonPayload / protoPayload<br/>trace: projects/PROJECT/traces/TRACE_ID<br/>logName: projects/PROJECT/logs/LOG_ID"]

        AT["<b>Access Transparency</b><br/>Google Cloud support/admin access logs<br/>accessReason: CUSTOMER_INITIATED_SUPPORT<br/>GOVERNMENT_REQUEST, GOOGLE_INITIATED_SERVICE<br/>product_performed_asserter: Customer / Google<br/>affected_resource: org/folder/project/service/resource<br/>When a Googler accesses your data — you see it"]
    end

    subgraph Agent["<b>WindOH Cloud Agent (GCE / GKE)</b>"]
        CRED["Application Default Credentials<br/>1. GOOGLE_APPLICATION_CREDENTIALS env<br/>2. GCE attached service account<br/>3. gcloud auth ADC → ~/.config/gcloud<br/>Service account key JSON → JWT → OAuth2 token"]
        POLL["Concurrent Service Pollers<br/>tokio::spawn per project_id<br/>5 services • paginated List/Get"]
        TOK["Tokenization → CloudEvent Schema<br/>stable_token / payload_token<br/>GCP resource hierarchy: org→folder→project"]
    end

    subgraph Pipe["<b>Shared Pipeline</b>"]
        CMS3["Count-Min Sketch"]
        RES3["Exemplar Reservoir"]
        OUT3["SQLite Outbox"]
    end

    subgraph Sink["<b>Export Targets</b>"]
        ES["Elasticsearch 8.x<br/>cloud-events-gcp index"]
        BQ["BigQuery Dataset<br/>windoh_cloud_events<br/>partitioned by _PARTITIONTIME<br/>SQL / Looker Studio queryable"]
    end

    CAL -->|"logging.googleapis.com → entries.list"| POLL
    VPC -->|"compute.googleapis.com → subnet flow logs"| POLL
    SCC -->|"securitycenter.googleapis.com → findings.list"| POLL
    CL -->|"logging.googleapis.com → entries.list (filtered)"| POLL
    AT -->|"logging.googleapis.com → accessTransparency logs"| POLL

    POLL --> TOK --> CMS3 --> RES3 --> OUT3
    OUT3 --> ES
    OUT3 --> BQ

    class CAL,VPC,SCC,CL,AT gcp
    class CRED,POLL,TOK agent
    class CMS3,RES3,OUT3 pipeline
    class ES,BQ infra
```

### Oracle OCI (4 Services)

```mermaid
graph TB
    classDef oracle fill:#F80000,stroke:#C74640,color:#fff,font-weight:bold
    classDef agent fill:#1168bd,stroke:#0b4884,color:#fff
    classDef pipeline fill:#43a047,stroke:#2e7d32,color:#fff

    subgraph OCI["<b>Oracle Cloud — 4 Services Polled</b>"]
        AUD["<b>OCI Audit Logs</b><br/>com.oraclecloud.objectstorage.getobject<br/>com.oraclecloud.computeapi.launchinstance<br/>com.oraclecloud.identity.user.create<br/>com.oraclecloud.database.dbnode.delete<br/>identity.principal.id, identity.principal.type<br/>request.operation, request.resourceId<br/>request.action (CREATE, READ, UPDATE, DELETE, INSPECT)<br/>response.status, clientIp, userAgent<br/>Tenancy → Compartment → Resource hierarchy"]

        VCN["<b>VCN Flow Logs</b><br/>Per-subnet, per-NIC capture<br/>src_ip, dst_ip, src_port, dst_port, protocol<br/>tcp_flags: SYN ACK FIN RST<br/>packet_size, action (ACCEPT/REJECT)<br/>Oracle-authored: oci-azure/oci-aws backbone interconnect<br/>Cross-region: remote VCN peered traffic<br/>Service gateway: OCI services → Object Storage, Autonomous DB"]

        CG["<b>Cloud Guard</b><br/>Detector recipes (Oracle-managed + custom)<br/>Problem types: InstancePubliclyAccessible<br/>ObjectStorageBucketPubliclyAccessible<br/>SecurityListHasStatelessRules<br/>BootVolumeWithoutBackup<br/>IAMUserHasApiKeyAndNoMfa<br/>Risk: Critical / High / Medium / Low<br/>Responder recipes: auto-remediate via Events"]

        EVT["<b>Events Service</b><br/>com.oraclecloud.computeapi.launchinstance.end<br/>com.oraclecloud.objectstorage.createbucket.end<br/>com.oraclecloud.database.autonomousdb.stop.end<br/>Event rules → Notifications → Streaming<br/>Dead-letter queue for failed deliveries<br/>Actions: Notifications → email, PagerDuty, Slack<br/>Actions: Functions → serverless remediation<br/>Actions: Streaming → Kafka-compatible analysis"]
    end

    subgraph Agent["<b>WindOH Cloud Agent (OCI Compute / OKE)</b>"]
        CRED["OCI API Signing Key<br/>~/.oci/config — tenancy_ocid, user_ocid<br/>key_fingerprint, key_file (.pem)<br/>region: us-ashburn-1 / us-phoenix-1 / etc.<br/>Instance Principals (IMDS v2 token)<br/>RSA-SHA256 signing per request"]
        POLL["Concurrent Service Pollers<br/>tokio::spawn per region<br/>4 services • list/get paginated"]
        TOK["Tokenization → CloudEvent Schema<br/>stable_token / payload_token<br/>OCI compartment hierarchy preserved"]
    end

    subgraph Pipe["<b>Shared Pipeline</b>"]
        CMS4["Count-Min Sketch"]
        RES4["Exemplar Reservoir"]
        OUT4["SQLite Outbox"]
    end

    subgraph Sink["<b>Export Targets</b>"]
        ES["Elasticsearch 8.x<br/>cloud-events-oci index"]
        STRM["OCI Streaming<br/>windoh-events stream<br/>Kafka-compatible<br/>50 GB free tier"]
    end

    AUD -->|"audit.REGION.oraclecloud.com → ListEvents"| POLL
    VCN -->|"Object Storage → flow log parquet files"| POLL
    CG -->|"cloudguard.REGION.oraclecloud.com → ListProblems"| POLL
    EVT -->|"events.REGION.oraclecloud.com → ListRules"| POLL
    POLL --> TOK --> CMS4 --> RES4 --> OUT4
    OUT4 --> ES
    OUT4 --> STRM

    class AUD,VCN,CG,EVT oracle
    class CRED,POLL,TOK agent
    class CMS4,RES4,OUT4 pipeline
    class ES,STRM infra
```

### Kubernetes (4 Services)

```mermaid
graph TB
    classDef k8s fill:#326CE5,stroke:#1d4bb8,color:#fff,font-weight:bold
    classDef agent fill:#1168bd,stroke:#0b4884,color:#fff
    classDef pipeline fill:#43a047,stroke:#2e7d32,color:#fff

    subgraph K8S["<b>Kubernetes Cluster — 4 Services Polled</b>"]
        KAL["<b>API Server Audit Logs</b><br/>audit.k8s.io/v1 — audit policy file<br/>Stages: RequestReceived, ResponseStarted, ResponseComplete, Panic<br/>Levels: None, Metadata, Request, RequestResponse<br/>user: system:serviceaccount:default:my-sa<br/>sourceIPs, userAgent: kubectl/v1.29, kubelet/v1.29<br/>objectRef: pods, deployments, secrets, configmaps, serviceaccounts<br/>responseStatus.code: 200, 201, 403, 404<br/>requestObject / responseObject (RequestResponse level)<br/>annotations: authorization.k8s.io/decision=allow<br/>pod-security.kubernetes.io/enforce-policy=baseline:v1.29"]

        PS["<b>Pod Security Contexts</b><br/>Pod Security Admission (PSA) — built-in since 1.25<br/>Enforce: privileged / baseline / restricted<br/>Audit: violations logged but not denied<br/>Warn: user-facing warning on violation<br/>spec.containers[*].securityContext:<br/>— privileged: true/false<br/>— runAsNonRoot: true/false<br/>— runAsUser: 0 (root) or >0<br/>— allowPrivilegeEscalation: true/false<br/>— capabilities.add: NET_ADMIN, SYS_ADMIN, SYS_PTRACE<br/>— seccompProfile.type: RuntimeDefault / Unconfined<br/>hostNetwork, hostPID, hostIPC booleans"]

        ADM["<b>Admission Reviews</b><br/>ValidatingWebhookConfiguration<br/>— OPA/Gatekeeper Constraint violations<br/>— Kyverno policy enforcement<br/>— Trivy-Operator vulnerability reports<br/>MutatingWebhookConfiguration<br/>— Istio sidecar injection (sidecar.istio.io/inject)<br/>— Vault agent sidecar injection<br/>— Pod label mutations<br/>admission.k8s.io/v1 AdmissionReview<br/>request.uid, request.userInfo, request.object<br/>response.allowed: true/false, response.status.message"]

        NP["<b>Network Policy Events</b><br/>networking.k8s.io/v1 NetworkPolicy<br/>— podSelector, namespaceSelector, ipBlock (CIDR)<br/>— policyTypes: Ingress, Egress<br/>— from/to: pod/namespace/ipBlock rules<br/>— ports: protocol (TCP/UDP/SCTP), port number/name<br/>Calico / Cilium network policy logs<br/>— Felix: iptables-save → rule hit counter increment<br/>— Hubble: eBPF per-packet verdict log<br/>— Cilium network policy verdict log: action (allow/deny/audit)<br/>— cilium-dbg policy trace --src-pod X --dst-pod Y"]
    end

    subgraph Agent["<b>WindOH Cloud Agent (in-cluster DaemonSet / sidecar)</b>"]
        CRED["Kubernetes Auth<br/>1. In-Cluster: ServiceAccount token<br/> mounted at /var/run/secrets/kubernetes.io<br/>2. Kubeconfig: ~/.kube/config<br/>RBAC: ClusterRole + ClusterRoleBinding<br/>— get/list/watch on audit.k8s.io<br/>— get/list/watch on * (events)<br/>— get/list/watch on networking.k8s.io"]
        POLL["Concurrent API Pollers<br/>tokio::spawn per API group<br/>4 services • watch-based streaming"]
        TOK["Tokenization → CloudEvent Schema<br/>stable_token / payload_token<br/>cluster→namespace→pod hierarchy"]
    end

    subgraph Pipe["<b>Shared Pipeline</b>"]
        CMS5["Count-Min Sketch"]
        RES5["Exemplar Reservoir"]
        OUT5["SQLite Outbox"]
    end

    subgraph Sink["<b>Export Targets</b>"]
        ES["Elasticsearch 8.x<br/>cloud-events-k8s index"]
        LOKI["Grafana Loki<br/>windoh-k8s stream<br/>namespace/pod/container labels"]
    end

    KAL -->|"audit.k8s.io → events API"| POLL
    PS -->|"core/v1 → pods / namespaces status"| POLL
    ADM -->|"admissionregistration.k8s.io → webhooks"| POLL
    NP -->|"networking.k8s.io → networkpolicies"| POLL
    POLL --> TOK --> CMS5 --> RES5 --> OUT5
    OUT5 --> ES
    OUT5 --> LOKI

    class KAL,PS,ADM,NP k8s
    class CRED,POLL,TOK agent
    class CMS5,RES5,OUT5 pipeline
    class ES,LOKI infra
```

---

## CloudEvent Schema — Unified Across All Providers

Every event from every provider converges on this schema before tokenization:

| Category | Fields | AWS Source | Azure Source | GCP Source | Oracle Source |
|----------|--------|-----------|-------------|-----------|---------------|
| **Actor** | principal ARN/ObjectID/email, type, access key ID, MFA, source IP, user agent, invoked-by chain | `userIdentity.arn`, `userIdentity.type` (IAMUser/AssumedRole/AWSAccount/AWSService) | `claims.oid`, `identity` (user/servicePrincipal/managedIdentity) | `authenticationInfo.principalEmail`, `serviceAccountKeyName` | `identity.principal.id`, `identity.principal.type` (User/Instance/Service) |
| **Resource** | ARN/URI, type, name, region, account/sub/project, zone, tags | `resources[0].ARN`, `awsRegion` | `resourceId`, `subscriptionId`, `tenantId` | `resource.name`, `resource.labels.project_id` | `request.resourceId`, `compartmentId` |
| **Network** | 5-tuple (src/dst IP:port, protocol), VPC/subnet/VCN, SG, direction, ACCEPT/REJECT, bytes, packets | `sourceIPAddress`, VPC Flow Log `srcaddr→dstaddr` | `claims.ipaddr`, NSG `src_ip→dst_ip` | `callerIp`, VPC Flow Log `src/dst_instance` | `clientIp`, VCN Flow Log `src_ip→dst_ip` |
| **API** | Service, action, category (Read/Write/Management/Data), status, error code, request ID | `eventSource`, `eventName`, `errorCode` | `operationName`, `status` (Succeeded/Failed) | `serviceName`, `methodName`, `status.code` | `request.operation`, `response.status` |
| **Authorization** | Allow/Deny, policy name/ID, permissions used/missing, condition keys | `errorCode: AccessDenied`, IAM `conditionKeys` | `authorization.action`, `authorization.decision` | `authorizationInfo.granted`, `authorizationInfo.permission` | N/A (IAM in audit log via `request.action`) |
| **Threat** | Finding ID, type, severity 0–10, title, MITRE ATT&CK tactic/technique, indicator type/value, compromised resource | GuardDuty `finding.type` + `finding.severity`, Security Hub `Severity.Normalized` | Sentinel `alert.severity`, Defender for Cloud `properties.severity` | SCC `finding.category`, `finding.severity` | Cloud Guard `problem_type`, `problem.risk` |
| **Compliance** | Framework (CIS/PCI/HIPAA/SOC2/NIST), control ID, status, remediation | Config Rules `complianceType`, Security Hub `Compliance.Status` | Azure Policy `complianceState`, `policyDefinitionId` | SCC `finding.sourceProperties.Recommendation` | Cloud Guard `detector_rule.description` |
| **IP Context** | is_aws_service, is_azure_service, is_gcp_service, TOR exit node, anonymous proxy, GeoIP country/city/ASN | AWS IP ranges JSON + GeoLite2 | Azure IP ranges JSON + GeoLite2 | GCP IP ranges + GeoLite2 | GeoLite2 |

---

## Deployment Patterns

| Pattern | Description | Best For |
|---------|-------------|----------|
| **Sidecar** | Agent runs in same VPC/subnet as monitored resources — polls cloud API endpoints over private link (AWS PrivateLink / Azure Private Link / GCP Private Google Access / OCI Service Gateway) | Single-account, latency-sensitive |
| **Hub-spoke** | One agent per spoke account/project, exports to a centralized Elasticsearch in the hub | Multi-account, least-privilege |
| **DaemonSet (K8s)** | Agent runs on every node or as a cluster-wide singleton | In-cluster observability |
| **Serverless** | AWS: ECS Fargate scheduled task → Lambda poller. Azure: Container Instance → Logic App trigger. GCP: Cloud Run job → Cloud Scheduler | Cost-optimized, intermittent polling |

---

## Token Flow: Multi-Cloud → Single Pane

```mermaid
flowchart LR
    subgraph AWSAccount["AWS: 012345678901"]
        aws_agent["wizard-aws"]
    end
    subgraph AzureTenant["Azure: tenant.onmicrosoft.com"]
        azure_agent["wizard-azure"]
    end
    subgraph GCPProject["GCP: my-project-id"]
        gcp_agent["wizard-gcp"]
    end
    subgraph OCITenancy["OCI: ocid1.tenancy..."]
        oracle_agent["wizard-oracle"]
    end
    subgraph K8sCluster["Kubernetes: prod-cluster"]
        k8s_agent["wizard-k8s"]
    end

    subgraph Pipeline["WindOH Platform"]
        ES["Elasticsearch<br/>cloud-events-* indices"]
        API["WindOH API<br/>origin-agnostic normalization"]
        LLM["LLM Enrichment<br/>once per payload_token"]
        Mongo["MongoDB<br/>permanent enrichment cache"]
    end

    aws_agent -->|"gzip JSON bulk"| ES
    azure_agent -->|"gzip JSON bulk"| ES
    gcp_agent -->|"gzip JSON bulk"| ES
    oracle_agent -->|"gzip JSON bulk"| ES
    k8s_agent -->|"gzip JSON bulk"| ES
    ES --> API --> LLM --> Mongo

    style AWSAccount fill:#FF9900,stroke:#232F3E,color:#232F3E
    style AzureTenant fill:#0078D4,stroke:#005a9e,color:#fff
    style GCPProject fill:#4285F4,stroke:#3367D6,color:#fff
    style OCITenancy fill:#F80000,stroke:#C74640,color:#fff
    style K8sCluster fill:#326CE5,stroke:#1d4bb8,color:#fff
```
