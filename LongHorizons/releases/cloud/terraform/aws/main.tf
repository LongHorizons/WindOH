# =============================================================================
# WindOH Cloud Agent — AWS Terraform
# =============================================================================
# Deploys the LongHorizons cloud telemetry agent on EC2 with least-privilege
# IAM, enabling all 9 polled AWS services. The agent polls: CloudTrail (mgmt
# + data events), VPC Flow Logs (S3/CloudWatch), GuardDuty (all finding
# types), Security Hub (ASFF 1.0 aggregated findings), S3 Access Logs
# (bucket/object-level), WAF Logs (WebACL rule matches + Bot Control), Route53
# Resolver DNS query logs, ELB Access Logs (ALB/NLB/CLB), and AWS Config Rules
# (compliance status + change notifications).
#
# Optional: Amazon Bedrock as a managed LLM enrichment endpoint (Claude 4.x
# via InvokeModel) instead of self-hosted llama.cpp/vLLM — still your VPC,
# still your data, no telemetry leaves your AWS account.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
  }

  # --- Remote state (uncomment and configure) ---
  # backend "s3" {
  #   bucket         = "windoh-terraform-state"
  #   key            = "aws/cloud-agent/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "windoh-terraform-locks"
  # }
}

# =============================================================================
# Variables
# =============================================================================

variable "aws_region" {
  description = "Primary AWS region for the cloud agent"
  type        = string
  default     = "us-east-1"
}

variable "agent_id" {
  description = "Unique identifier for this agent instance (e.g., aws-prod-01)"
  type        = string
  default     = "aws-prod-01"
}

variable "elasticsearch_endpoint" {
  description = "Elasticsearch bulk API endpoint (https://es.example.com:9200/_bulk)"
  type        = string
  sensitive   = true
}

variable "elasticsearch_api_key" {
  description = "Elasticsearch API key for indexing"
  type        = string
  sensitive   = true
  default     = null
}

variable "elasticsearch_index_pattern" {
  description = "ES index pattern for cloud events"
  type        = string
  default     = "cloud-events-aws"
}

variable "polled_regions" {
  description = "AWS regions to poll (CloudTrail, GuardDuty, Security Hub, Config are global-ish; VPC Flow Logs, WAF, ELB, S3 Access Logs are regional)"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "poll_interval_secs" {
  description = "Seconds between API poll cycles"
  type        = number
  default     = 60
}

variable "instance_type" {
  description = "EC2 instance type for the cloud agent"
  type        = string
  default     = "t3.small"   # 2 vCPU, 2 GB RAM — ample for cloud API polling
}

variable "vpc_id" {
  description = "VPC ID to deploy the agent into"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the agent EC2 instance"
  type        = string
}

variable "ssh_key_name" {
  description = "EC2 key pair name for SSH access (optional)"
  type        = string
  default     = null
}

variable "enable_bedrock_llm" {
  description = "Grant Bedrock InvokeModel permission so the WindOH API can use Claude 4.x for enrichment instead of a self-hosted llama.cpp/vLLM endpoint"
  type        = bool
  default     = false
}

variable "enable_s3_archive" {
  description = "Create an S3 bucket for archiving enriched events in Apache Parquet format (Athena / Redshift Spectrum queryable)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "WindOH"
    Component   = "CloudAgent"
    ManagedBy   = "Terraform"
  }
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# SSM Parameter for Amazon Linux 2023 AMI
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

# =============================================================================
# IAM — Least-Privilege Role for Cloud Agent
# =============================================================================

# Instance Profile role — the agent runs under this
resource "aws_iam_role" "agent" {
  name = "WindOH-CloudAgent-${var.agent_id}"
  path = "/windoh/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
      Condition = {
        Bool = { "aws:SecureTransport" = "true" }   # IMDSv2 required
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_instance_profile" "agent" {
  name = "WindOH-CloudAgent-${var.agent_id}"
  role = aws_iam_role.agent.name
}

# --- CloudTrail: Read management + data event history ---
# cloudtrail:LookupEvents is the primary polling API — paginated, 90-day retention
resource "aws_iam_policy" "cloudtrail" {
  name = "WindOH-CloudTrail-Read-${var.agent_id}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["cloudtrail:LookupEvents"]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["cloudtrail:DescribeTrails", "cloudtrail:GetTrailStatus"]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::*cloudtrail*",
          "arn:${data.aws_partition.current.partition}:s3:::*cloudtrail*/*"
        ]
      }
    ]
  })
}

# --- VPC Flow Logs: Read flow log records from S3 / CloudWatch Logs ---
resource "aws_iam_policy" "vpc_flow_logs" {
  name = "WindOH-VpcFlowLogs-Read-${var.agent_id}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeFlowLogs"]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = ["arn:${data.aws_partition.current.partition}:logs:*:*:log-group:*vpc-flow-logs*:*"]
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::*vpc-flow-logs*",
          "arn:${data.aws_partition.current.partition}:s3:::*vpc-flow-logs*/*"
        ]
      }
    ]
  })
}

# --- GuardDuty: List + Get findings across all detectors ---
resource "aws_iam_policy" "guardduty" {
  name = "WindOH-GuardDuty-Read-${var.agent_id}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "guardduty:ListDetectors",
        "guardduty:ListFindings",
        "guardduty:GetFindings",
        "guardduty:GetFindingsStatistics"
      ]
      Resource = ["*"]
    }]
  })
}

# --- Security Hub: GetFindings with ASFF 1.0 format ---
resource "aws_iam_policy" "security_hub" {
  name = "WindOH-SecurityHub-Read-${var.agent_id}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "securityhub:GetFindings",
        "securityhub:GetEnabledStandards",
        "securityhub:GetInsights"
      ]
      Resource = ["*"]
    }]
  })
}

# --- S3 Access Logs: List + Get bucket logging configuration + log objects ---
resource "aws_iam_policy" "s3_access_logs" {
  name = "WindOH-S3AccessLogs-Read-${var.agent_id}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetBucketLogging", "s3:GetBucketAcl"]
        Resource = ["arn:${data.aws_partition.current.partition}:s3:::*"]
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::*access-logs*",
          "arn:${data.aws_partition.current.partition}:s3:::*access-logs*/*",
          "arn:${data.aws_partition.current.partition}:s3:::*logging*",
          "arn:${data.aws_partition.current.partition}:s3:::*logging*/*"
        ]
      }
    ]
  })
}

# --- WAF: List WebACLs + get log configuration from Kinesis Firehose / S3 ---
resource "aws_iam_policy" "waf_logs" {
  name = "WindOH-WAFLogs-Read-${var.agent_id}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "wafv2:ListWebACLs",
          "wafv2:GetWebACL",
          "wafv2:GetLoggingConfiguration"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::*waf-logs*",
          "arn:${data.aws_partition.current.partition}:s3:::*waf-logs*/*",
          "arn:${data.aws_partition.current.partition}:s3:::*aws-waf-logs*",
          "arn:${data.aws_partition.current.partition}:s3:::*aws-waf-logs*/*"
        ]
      }
    ]
  })
}

# --- Route53 Resolver: List query log configs + read from CloudWatch Logs ---
resource "aws_iam_policy" "route53_resolver" {
  name = "WindOH-Route53Resolver-Read-${var.agent_id}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53resolver:ListResolverQueryLogConfigs",
          "route53resolver:GetResolverQueryLogConfig"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = ["logs:FilterLogEvents", "logs:GetLogEvents"]
        Resource = ["arn:${data.aws_partition.current.partition}:logs:*:*:log-group:*route53*:*"]
      }
    ]
  })
}

# --- ELB: Describe load balancers + read S3 access logs (ALB/NLB/CLB) ---
resource "aws_iam_policy" "elb" {
  name = "WindOH-ELBLogs-Read-${var.agent_id}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::*elb-logs*",
          "arn:${data.aws_partition.current.partition}:s3:::*elb-logs*/*",
          "arn:${data.aws_partition.current.partition}:s3:::*alb-logs*",
          "arn:${data.aws_partition.current.partition}:s3:::*alb-logs*/*"
        ]
      }
    ]
  })
}

# --- Config: Get compliance details per rule ---
resource "aws_iam_policy" "config_rules" {
  name = "WindOH-ConfigRules-Read-${var.agent_id}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "config:DescribeConfigRules",
        "config:GetComplianceDetailsByConfigRule",
        "config:DescribeComplianceByConfigRule"
      ]
      Resource = ["*"]
    }]
  })
}

# --- Bedrock: Optional managed LLM enrichment (Claude 4.x in your VPC) ---
resource "aws_iam_policy" "bedrock_llm" {
  count = var.enable_bedrock_llm ? 1 : 0
  name  = "WindOH-Bedrock-InvokeModel-${var.agent_id}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      Resource = [
        "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}::foundation-model/anthropic.claude-opus-4-8-20250514",
        "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}::foundation-model/anthropic.claude-sonnet-4-6-20250514",
        "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}::foundation-model/anthropic.claude-haiku-4-5-20251001"
      ]
      Condition = {
        StringEquals = { "aws:RequestedRegion" = var.aws_region }
      }
    }]
  })
}

# --- S3 Archive Parquet (optional) ---
resource "aws_iam_policy" "s3_archive" {
  count = var.enable_s3_archive ? 1 : 0
  name  = "WindOH-S3Archive-Write-${var.agent_id}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.archive[0].arn,
        "${aws_s3_bucket.archive[0].arn}/*"
      ]
    }]
  })
}

# Glue all policies onto the role
resource "aws_iam_role_policy_attachment" "policies" {
  for_each = toset(compact([
    aws_iam_policy.cloudtrail.arn,
    aws_iam_policy.vpc_flow_logs.arn,
    aws_iam_policy.guardduty.arn,
    aws_iam_policy.security_hub.arn,
    aws_iam_policy.s3_access_logs.arn,
    aws_iam_policy.waf_logs.arn,
    aws_iam_policy.route53_resolver.arn,
    aws_iam_policy.elb.arn,
    aws_iam_policy.config_rules.arn,
    try(aws_iam_policy.bedrock_llm[0].arn, null),
    try(aws_iam_policy.s3_archive[0].arn, null),
    # SSM managed policy for agent updates + Parameter Store secrets
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]))

  role       = aws_iam_role.agent.name
  policy_arn = each.value
}

# =============================================================================
# S3 Archive Bucket — Apache Parquet + Snappy, Athena Queryable
# =============================================================================

resource "aws_s3_bucket" "archive" {
  count  = var.enable_s3_archive ? 1 : 0
  bucket = "windoh-cloud-archive-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "archive" {
  count  = var.enable_s3_archive ? 1 : 0
  bucket = aws_s3_bucket.archive[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  count  = var.enable_s3_archive ? 1 : 0
  bucket = aws_s3_bucket.archive[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.archive[0].arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  count  = var.enable_s3_archive ? 1 : 0
  bucket = aws_s3_bucket.archive[0].id
  rule {
    id     = "parquet-tiering"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration { days = 2555 }   # 7-year retention
  }
}

resource "aws_s3_bucket_public_access_block" "archive" {
  count  = var.enable_s3_archive ? 1 : 0
  bucket = aws_s3_bucket.archive[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# KMS — Customer-Managed Key for S3 Archive + CloudTrail
# =============================================================================

resource "aws_kms_key" "archive" {
  count                   = var.enable_s3_archive ? 1 : 0
  description             = "WindOH Cloud Agent S3 archive + CloudTrail encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudTrail to encrypt"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = ["kms:GenerateDataKey*"]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/*" }
        }
      }
    ]
  })
  tags = var.tags
}

resource "aws_kms_alias" "archive" {
  count         = var.enable_s3_archive ? 1 : 0
  name          = "alias/windoh/cloud-agent/${var.agent_id}"
  target_key_id = aws_kms_key.archive[0].key_id
}

# =============================================================================
# CloudTrail — Enable Multi-Region Trail with Data Events for S3 + Lambda
# =============================================================================

resource "aws_cloudtrail" "main" {
  name                          = "windoh-cloud-agent-${var.agent_id}"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = var.enable_s3_archive ? aws_kms_key.archive[0].arn : null

  # Data events: capture S3 object-level and Lambda invocation activity
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:${data.aws_partition.current.partition}:s3:::"]   # All buckets
    }
    data_resource {
      type   = "AWS::Lambda::Function"
      values = ["arn:${data.aws_partition.current.partition}:lambda:::function:*"]  # All Lambda functions
    }
  }

  # Insight events: API call rate anomalies, unusual error rates
  insight_selector {
    insight_type = "ApiCallRateInsight"
  }
  insight_selector {
    insight_type = "ApiErrorRateInsight"
  }

  tags = var.tags
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "windoh-cloudtrail-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  force_destroy = false
  tags          = var.tags
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AWSCloudTrailAclCheck"
      Effect = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action   = "s3:GetBucketAcl"
      Resource = aws_s3_bucket.cloudtrail.arn
      Condition = {
        StringEquals = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/windoh-cloud-agent-${var.agent_id}" }
      }
    }, {
      Sid    = "AWSCloudTrailWrite"
      Effect = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      Condition = {
        StringEquals = {
          "s3:x-amz-acl"                = "bucket-owner-full-control"
          "aws:SourceArn"               = "arn:${data.aws_partition.current.partition}:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/windoh-cloud-agent-${var.agent_id}"
        }
      }
    }]
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    id     = "cloudtrail-lifecycle"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "ONEZONE_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration { days = 365 }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# VPC Flow Logs — Capture per-ENI 5-tuple flow records for the agent VPC
# =============================================================================

resource "aws_flow_log" "agent_vpc" {
  log_destination_type     = "s3"
  log_destination          = aws_s3_bucket.vpc_flow_logs.arn
  traffic_type             = "ALL"
  vpc_id                   = var.vpc_id
  max_aggregation_interval = 60   # 1-minute aggregation (or 600 for 10-min)
  log_format               = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${region} $${az-id} $${sublocation-type} $${sublocation-id} $${pkt-src-aws-service} $${pkt-dst-aws-service} $${flow-direction} $${traffic-path}"

  tags = var.tags
}

resource "aws_s3_bucket" "vpc_flow_logs" {
  bucket  = "windoh-vpc-flow-logs-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  tags    = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vpc_flow_logs" {
  bucket = aws_s3_bucket.vpc_flow_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vpc_flow_logs" {
  bucket                  = aws_s3_bucket.vpc_flow_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# GuardDuty — Enable Across All Polled Regions
# =============================================================================

resource "aws_guardduty_detector" "main" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  features {
    name = "S3_DATA_EVENTS"
    status = "ENABLED"
  }
  features {
    name = "EKS_AUDIT_LOGS"
    status = "ENABLED"
  }
  features {
    name = "RDS_LOGIN_EVENTS"
    status = "ENABLED"
  }
  features {
    name = "EBS_MALWARE_PROTECTION"
    status = "ENABLED"
  }
  features {
    name = "LAMBDA_NETWORK_LOGS"
    status = "ENABLED"
  }
  features {
    name = "RUNTIME_MONITORING"
    status = "ENABLED"
    additional_configuration {
      name        = "EKS_ADDON_MANAGEMENT"
      status      = "ENABLED"
    }
    additional_configuration {
      name        = "ECS_FARGATE_AGENT_MANAGEMENT"
      status      = "ENABLED"
    }
    additional_configuration {
      name        = "EC2_AGENT_MANAGEMENT"
      status      = "ENABLED"
    }
  }

  tags = var.tags
}

# =============================================================================
# Security Hub — Enable with CIS + AWS Foundational Best Practices
# =============================================================================

resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.4.0"
}

resource "aws_securityhub_standards_subscription" "foundational" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# =============================================================================
# Security Group — Minimal Egress for Cloud Agent
# =============================================================================

resource "aws_security_group" "agent" {
  name        = "windoh-cloud-agent-${var.agent_id}"
  description = "WindOH Cloud Agent — egress to cloud APIs + Elasticsearch"
  vpc_id      = var.vpc_id

  # --- Egress: AWS API endpoints ---
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    description = "AWS service APIs (CloudTrail, GuardDuty, Security Hub, Config, etc.)"
    cidr_blocks = ["0.0.0.0/0"]   # Narrow to VPC endpoints if using PrivateLink
  }

  # --- Egress: Elasticsearch ---
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    description = "Elasticsearch bulk API (HTTPS)"
    cidr_blocks = ["0.0.0.0/0"]   # Narrow to your ES cluster CIDR / security group
  }

  # --- Egress: Optional Bedrock via VPC Endpoint ---
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    description = "Amazon Bedrock runtime (HTTPS) — managed LLM enrichment"
    cidr_blocks = ["0.0.0.0/0"]   # Narrow to VPC endpoint if using Bedrock
  }

  # --- Egress: GeoLite2 / SearXNG (optional threat intel) ---
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    description = "Optional: SearXNG metasearch for threat intel enrichment"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --- Ingress: SSH (optional, from your admin CIDR) ---
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Catch-all egress — scoped to internet (narrow in production)"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# =============================================================================
# EC2 Instance — Cloud Agent Host
# =============================================================================

resource "aws_instance" "agent" {
  ami                     = data.aws_ssm_parameter.al2023.value
  instance_type           = var.instance_type
  subnet_id               = var.subnet_id
  iam_instance_profile    = aws_iam_instance_profile.agent.name
  vpc_security_group_ids  = [aws_security_group.agent.id]
  key_name                = var.ssh_key_name
  disable_api_termination = false

  root_block_device {
    volume_type = "gp3"
    volume_size = 30   # OS + agent binary (~8 MB) + SQLite outbox buffer
    encrypted   = true
    kms_key_id  = var.enable_s3_archive ? aws_kms_key.archive[0].arn : null
    tags        = merge(var.tags, { Name = "windoh-cloud-agent-${var.agent_id}-root" })
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"   # IMDSv2 required
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    agent_id                   = var.agent_id
    elasticsearch_endpoint     = var.elasticsearch_endpoint
    elasticsearch_api_key      = var.elasticsearch_api_key
    elasticsearch_index_pattern = var.elasticsearch_index_pattern
    aws_region                 = var.aws_region
    polled_regions             = join(",", var.polled_regions)
    poll_interval_secs         = var.poll_interval_secs
    enable_bedrock_llm         = var.enable_bedrock_llm
  }))

  tags = merge(var.tags, {
    Name = "windoh-cloud-agent-${var.agent_id}"
  })
}

# =============================================================================
# CloudWatch Agent Health Dashboard — Metrics + Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "agent_heartbeat" {
  alarm_name          = "windoh-agent-heartbeat-${var.agent_id}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "WindOH cloud agent instance health check failure"
  alarm_actions       = []   # Add SNS topic ARN for notifications

  dimensions = {
    InstanceId = aws_instance.agent.id
  }

  tags = var.tags
}

# =============================================================================
# Outputs
# =============================================================================

output "agent_instance_id" {
  description = "EC2 instance ID running the cloud agent"
  value       = aws_instance.agent.id
}

output "agent_instance_private_ip" {
  description = "Private IP of the cloud agent (agent.id → this IP in ES documents)"
  value       = aws_instance.agent.private_ip
}

output "agent_role_arn" {
  description = "IAM role ARN assumed by the cloud agent"
  value       = aws_iam_role.agent.arn
}

output "cloudtrail_bucket" {
  description = "S3 bucket receiving CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "vpc_flow_log_bucket" {
  description = "S3 bucket receiving VPC Flow Logs"
  value       = aws_s3_bucket.vpc_flow_logs.bucket
}

output "archive_bucket" {
  description = "S3 bucket for Parquet archive (if enabled)"
  value       = var.enable_s3_archive ? aws_s3_bucket.archive[0].bucket : null
}

output "security_group_id" {
  description = "Security group ID for the cloud agent"
  value       = aws_security_group.agent.id
}

output "cloudtrail_arn" {
  description = "CloudTrail trail ARN — reference in Config rules, GuardDuty trusted IP lists, etc."
  value       = aws_cloudtrail.main.arn
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = aws_guardduty_detector.main.id
}
