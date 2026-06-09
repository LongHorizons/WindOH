# =============================================================================
# WindOH Cloud Agent — Oracle OCI Terraform
# =============================================================================
# Deploys the LongHorizons cloud telemetry agent on an OCI Compute instance,
# enabling all 4 polled services: OCI Audit Logs (com.oraclecloud.objectstorage.*,
# com.oraclecloud.computeapi.*, com.oraclecloud.identity.*, com.oraclecloud.database.*
# across tenancy → compartment hierarchy), VCN Flow Logs (per-subnet/per-NIC
# capture: 5-tuple + tcp_flags SYN/ACK/FIN/RST, packet_size, ACCEPT/REJECT,
# cross-region peered traffic, service gateway Object Storage/Autonomous DB),
# Cloud Guard (detector recipes — InstancePubliclyAccessible,
# ObjectStorageBucketPubliclyAccessible, SecurityListHasStatelessRules,
# BootVolumeWithoutBackup, IAMUserHasApiKeyAndNoMfa — with risk levels
# Critical/High/Medium/Low and auto-remediation responder recipes), and
# Events Service (event rules → Notifications/Streaming/Functions pipeline
# for compute, storage, database, and IAM lifecycle events).
#
# The agent uses API signing key authentication (RSA-SHA256 per-request
# signature) with tenancy_ocid + user_ocid + key_fingerprint + private_key.
# Instance Principals (IMDS v2 token) are used when running on OCI Compute.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.40.0"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "tenancy_ocid" {
  description = "OCI tenancy OCID"
  type        = string
}

variable "compartment_id" {
  description = "OCI compartment OCID for agent resources (may be same as tenancy or a child compartment)"
  type        = string
}

variable "user_ocid" {
  description = "OCI user OCID for API signing key (if not using Instance Principals)"
  type        = string
  default     = null
}

variable "key_fingerprint" {
  description = "Fingerprint of the API signing public key uploaded to the OCI user"
  type        = string
  default     = null
}

variable "private_key_path" {
  description = "Path to the API signing private key PEM file on the agent instance"
  type        = string
  default     = "/etc/windoh/oci-key.pem"
}

variable "agent_id" {
  description = "Unique identifier for this agent instance (e.g., oracle-prod-01)"
  type        = string
  default     = "oracle-prod-01"
}

variable "region" {
  description = "OCI region for the agent resources"
  type        = string
  default     = "us-ashburn-1"
}

variable "elasticsearch_endpoint" {
  description = "Elasticsearch bulk API endpoint"
  type        = string
  sensitive   = true
}

variable "elasticsearch_api_key" {
  description = "Elasticsearch API key for indexing"
  type        = string
  sensitive   = true
}

variable "poll_interval_secs" {
  description = "Seconds between API poll cycles"
  type        = number
  default     = 60
}

variable "vm_shape" {
  description = "OCI Compute shape for the cloud agent"
  type        = string
  default     = "VM.Standard.E4.Flex"   # AMD flex shape
}

variable "vm_ocpus" {
  description = "OCPUs for the flex shape"
  type        = number
  default     = 1
}

variable "vm_memory_gb" {
  description = "Memory in GB for the flex shape"
  type        = number
  default     = 4
}

variable "vcn_id" {
  description = "Existing VCN OCID to deploy the agent into"
  type        = string
}

variable "subnet_id" {
  description = "Existing subnet OCID for the agent compute instance"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for the agent instance opc user"
  type        = string
}

variable "enable_oci_streaming" {
  description = "Create an OCI Streaming stream and export enriched events via Kafka-compatible API (50 GB free tier)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Freeform tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "WindOH"
    Component = "CloudAgent"
    ManagedBy = "Terraform"
  }
}

# =============================================================================
# Data Sources
# =============================================================================

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "oracle_linux_8" {
  compartment_id           = var.compartment_id
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = var.vm_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

data "oci_core_vcn" "agent" {
  vcn_id = var.vcn_id
}

data "oci_core_subnet" "agent" {
  subnet_id = var.subnet_id
}

# =============================================================================
# Dynamic Group + Policy — Instance Principals (no keys on disk)
# =============================================================================

# Dynamic Group: any compute instance with the defined tag
resource "oci_identity_dynamic_group" "agent" {
  name           = "WindOH-CloudAgent-${var.agent_id}"
  description    = "Dynamic group for WindOH cloud agent instances"
  compartment_id = var.tenancy_ocid
  matching_rule  = "ALL { instance.compartment.id = '${var.compartment_id}', tag.WindOH-CloudAgent.value = '${var.agent_id}' }"
}

# Policy: grant the dynamic group read access to all 4 services
resource "oci_identity_policy" "agent" {
  name           = "WindOH-CloudAgent-Policy-${var.agent_id}"
  description    = "Least-privilege policy for WindOH cloud agent — read audit, VCN flow logs, Cloud Guard, and Events"
  compartment_id = var.tenancy_ocid

  statements = [
    # Audit: read all audit events in the tenancy
    "Allow dynamic-group ${oci_identity_dynamic_group.agent.name} to read audit-events in tenancy",
    # VCN Flow Logs: read flow log configurations + access Object Storage for flow log parquet files
    "Allow dynamic-group ${oci_identity_dynamic_group.agent.name} to read subnets in tenancy",
    "Allow dynamic-group ${oci_identity_dynamic_group.agent.name} to read vcns in tenancy",
    "Allow dynamic-group ${oci_identity_dynamic_group.agent.name} to read log-groups in tenancy",
    "Allow dynamic-group ${oci_identity_dynamic_group.agent.name} to read log-sets in tenancy",
    # Cloud Guard: read problems, detector recipes, responder recipes
    "Allow dynamic-group ${oci_identity_dynamic_group.agent.name} to read cloud-guard-family in tenancy",
    # Events: read rules and event definitions
    "Allow dynamic-group ${oci_identity_dynamic_group.agent.name} to read cloudevents-rules in tenancy",
    "Allow dynamic-group ${oci_identity_dynamic_group.agent.name} to read events in tenancy",
    # Object Storage: read VCN Flow Log parquet files from standard Object Storage buckets
    "Allow dynamic-group ${oci_identity_dynamic_group.agent.name} to read object-family in tenancy",
  ]
}

# =============================================================================
# VCN Flow Logs — Enable on Agent Subnet
# =============================================================================

resource "oci_logging_log_group" "agent" {
  display_name   = "windoh-agent-${var.agent_id}-log-group"
  compartment_id = var.compartment_id
  description    = "Log group for WindOH cloud agent VCN Flow Logs + agent diagnostics"
  freeform_tags  = var.tags
}

resource "oci_logging_log" "vcn_flow_log" {
  display_name   = "windoh-agent-${var.agent_id}-vcn-flow-log"
  log_group_id   = oci_logging_log_group.agent.id
  log_type       = "SERVICE"
  compartment_id = var.compartment_id

  configuration {
    source {
      category    = "flowlogs"
      resource    = var.subnet_id
      service     = "flowlogs"
      source_type = "OCISERVICE"
    }
  }

  freeform_tags = var.tags
}

# =============================================================================
# OCI Streaming — Kafka-Compatible Event Export (Optional)
# =============================================================================

resource "oci_streaming_stream_pool" "agent" {
  count           = var.enable_oci_streaming ? 1 : 0
  name            = "windoh-agent-${var.agent_id}-pool"
  compartment_id  = var.compartment_id
  freeform_tags   = var.tags
}

resource "oci_streaming_stream" "agent" {
  count           = var.enable_oci_streaming ? 1 : 0
  name            = "windoh-events-${var.agent_id}"
  stream_pool_id  = oci_streaming_stream_pool.agent[0].id
  partitions      = 3
  freeform_tags   = var.tags
}

# =============================================================================
# Network Security Group — Minimal Egress for Cloud Agent
# =============================================================================

resource "oci_core_network_security_group" "agent" {
  display_name   = "windoh-agent-nsg-${var.agent_id}"
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  freeform_tags  = var.tags
}

# Egress: OCI API endpoints (HTTPS)
resource "oci_core_network_security_group_security_rule" "egress_oci_apis" {
  network_security_group_id = oci_core_network_security_group.agent.id
  direction                 = "EGRESS"
  protocol                  = "6"   # TCP
  description               = "OCI Audit, VCN Flow Logs, Cloud Guard, Events APIs"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

# Egress: Elasticsearch bulk API (HTTPS)
resource "oci_core_network_security_group_security_rule" "egress_elasticsearch" {
  network_security_group_id = oci_core_network_security_group.agent.id
  direction                 = "EGRESS"
  protocol                  = "6"
  description               = "Elasticsearch bulk API"
  destination               = "0.0.0.0/0"   # Narrow to your ES cluster IP/CIDR
  destination_type          = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

# =============================================================================
# OCI Compute Instance — Cloud Agent Host (Oracle Linux 8)
# =============================================================================

resource "oci_core_instance" "agent" {
  display_name        = "windoh-cloud-agent-${var.agent_id}"
  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  shape               = var.vm_shape

  create_vnic_details {
    subnet_id        = var.subnet_id
    nsg_ids          = [oci_core_network_security_group.agent.id]
    assign_public_ip = false   # Agent only needs egress; use NAT gateway or service gateway
  }

  shape_config {
    ocpus         = var.vm_ocpus
    memory_in_gbs = var.vm_memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.oracle_linux_8.images[0].id
    boot_volume_size_in_gbs = 50
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(templatefile("${path.module}/cloud-init.yml", {
      agent_id               = var.agent_id
      tenancy_ocid           = var.tenancy_ocid
      region                 = var.region
      use_instance_principals = true
      elasticsearch_endpoint  = var.elasticsearch_endpoint
      elasticsearch_api_key   = var.elasticsearch_api_key
      poll_interval_secs     = var.poll_interval_secs
      enable_streaming       = var.enable_oci_streaming
      stream_id              = var.enable_oci_streaming ? oci_streaming_stream.agent[0].id : ""
    }))
  }

  defined_tags  = {}
  freeform_tags = merge(var.tags, {
    "WindOH-CloudAgent" = var.agent_id   # Matches dynamic group matching_rule
  })
}

# =============================================================================
# Cloud Guard — Enable at Tenancy Level
# =============================================================================

resource "oci_cloud_guard_configuration" "agent" {
  compartment_id   = var.compartment_id
  reporting_region = var.region
  status           = "ENABLED"

  # Self-managed — the agent reads problems; responder recipes are
  # configured manually per target per your risk tolerance.
}

# =============================================================================
# Outputs
# =============================================================================

output "agent_instance_id" {
  description = "OCI compute instance OCID running the cloud agent"
  value       = oci_core_instance.agent.id
}

output "agent_instance_private_ip" {
  description = "Private IP of the cloud agent compute instance"
  value       = oci_core_instance.agent.private_ip
}

output "dynamic_group_name" {
  description = "Dynamic group name — add more matching rules for additional instances"
  value       = oci_identity_dynamic_group.agent.name
}

output "policy_name" {
  description = "IAM policy name — review statements for least-privilege"
  value       = oci_identity_policy.agent.name
}

output "vcn_flow_log_id" {
  description = "VCN Flow Log OCID for the agent subnet"
  value       = oci_logging_log.vcn_flow_log.id
}

output "stream_id" {
  description = "OCI Streaming stream OCID for Kafka-compatible event export (if enabled)"
  value       = var.enable_oci_streaming ? oci_streaming_stream.agent[0].id : null
}

output "stream_bootstrap_servers" {
  description = "Kafka bootstrap servers endpoint for OCI Streaming (if enabled)"
  value       = var.enable_oci_streaming ? "cell-1.streaming.${var.region}.oci.oraclecloud.com:9092" : null
}

output "monitored_tenancy" {
  description = "OCI tenancy OCID being monitored"
  value       = var.tenancy_ocid
}
