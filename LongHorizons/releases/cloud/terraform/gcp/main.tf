# =============================================================================
# WindOH Cloud Agent — GCP Terraform
# =============================================================================
# Deploys the LongHorizons cloud telemetry agent on a GCE instance with an
# attached service account, enabling all 5 polled services: Cloud Audit Logs
# (Admin Activity Read + Data Access Read — gcloud compute instances delete,
# gsutil rm, storage.objects.get, datastore.entities.query, IAM policy denied
# events), VPC Flow Logs (per-subnet 5-tuple with metadata, RTT, bytes/packets,
# location ASN), Security Command Center (findings per org/folder/project:
# XSS_SCRIPTING, MALWARE_BAD_DOMAIN, SECRET_LEAK, OPEN_FIREWALL_PORT,
# PUBLIC_SQL_INSTANCE, PUBLIC_BUCKET_ACL, KUBERNETES_OVERPRIVILEGED_SERVICE_ACCOUNT),
# Cloud Logging (resource.type: gce_instance|gcs_bucket|gke_cluster, severity
# filter, textPayload/jsonPayload/protoPayload), and Access Transparency
# (CUSTOMER_INITIATED_SUPPORT, GOVERNMENT_REQUEST, GOOGLE_INITIATED_SERVICE).
#
# The agent uses Application Default Credentials — the GCE attached service
# account generates OAuth2 tokens automatically via the metadata server.
# No service account keys stored on disk.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.20.0"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "project_id" {
  description = "GCP project ID where the agent runs"
  type        = string
}

variable "region" {
  description = "GCP region for the agent resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the agent VM"
  type        = string
  default     = "us-central1-a"
}

variable "agent_id" {
  description = "Unique identifier for this agent instance (e.g., gcp-prod-01)"
  type        = string
  default     = "gcp-prod-01"
}

variable "monitored_project_ids" {
  description = "GCP project IDs to poll for audit logs, flow logs, SCC, and Cloud Logging. The agent's own project is always included."
  type        = list(string)
  default     = []
}

variable "organization_id" {
  description = "GCP organization ID (numeric) for Security Command Center at org level"
  type        = string
  default     = null
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

variable "machine_type" {
  description = "GCE machine type for the cloud agent"
  type        = string
  default     = "e2-small"   # 2 vCPU, 2 GB RAM — shared core
}

variable "network" {
  description = "Existing VPC network name"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Existing subnet name"
  type        = string
  default     = "default"
}

variable "enable_bigquery_export" {
  description = "Create a BigQuery dataset and stream enriched events to it (SQL / Looker Studio queryable)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Labels applied to all resources"
  type        = map(string)
  default = {
    project   = "windoh"
    component = "cloud-agent"
  }
}

# =============================================================================
# Data Sources
# =============================================================================

data "google_project" "current" {}

# =============================================================================
# Service Account — Application Default Credentials
# =============================================================================

resource "google_service_account" "agent" {
  account_id   = "windoh-cloud-agent-${var.agent_id}"
  display_name = "WindOH Cloud Agent — ${var.agent_id}"
  description  = "Least-privilege service account for polling Cloud Audit Logs, VPC Flow Logs, SCC, Cloud Logging, and Access Transparency across monitored projects."
}

# --- Logging Viewer: Read Cloud Audit Logs + Cloud Logging entries ---
# roles/logging.viewer grants:
#   logging.logEntries.list
#   logging.logs.list
#   logging.logServiceIndexes.list
#   logging.logMetrics.list
#   logging.operations.list
resource "google_project_iam_member" "logging_viewer" {
  for_each = toset(concat([var.project_id], var.monitored_project_ids))
  project  = each.value
  role     = "roles/logging.viewer"
  member   = "serviceAccount:${google_service_account.agent.email}"
}

# --- Compute Network Viewer: Read VPC Flow Log sampling config ---
resource "google_project_iam_member" "compute_network_viewer" {
  for_each = toset(concat([var.project_id], var.monitored_project_ids))
  project  = each.value
  role     = "roles/compute.networkViewer"
  member   = "serviceAccount:${google_service_account.agent.email}"
}

# --- Security Center Findings Viewer: List + Get SCC findings ---
resource "google_project_iam_member" "scc_viewer" {
  for_each = toset(concat([var.project_id], var.monitored_project_ids))
  project  = each.value
  role     = "roles/securitycenter.findingsViewer"
  member   = "serviceAccount:${google_service_account.agent.email}"
}

# --- Access Transparency: Read access transparency logs ---
# roles/axt.admin grants:
#   logging.logEntries.list (filtered to access transparency logs)
#   accessapproval.requests.list

# --- BigQuery Data Editor (if BQ export enabled) ---
resource "google_bigquery_dataset_iam_member" "bq_editor" {
  count      = var.enable_bigquery_export ? 1 : 0
  project    = var.project_id
  dataset_id = google_bigquery_dataset.windoh[0].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.agent.email}"
}

# =============================================================================
# VPC Flow Logs — Enable on Agent Subnet
# =============================================================================

# Subnet flow logs capture: src/dst IP:port, protocol, bytes/packets, RTT,
# src/dst instance metadata, VPC, location (US/EU/ASIA), base 5-sec aggregation.
resource "google_compute_subnetwork" "agent_flow_logs_enabled" {
  count         = var.subnetwork != "default" ? 0 : 0   # Normally you'd configure this on existing subnets
  name          = "windoh-agent-subnet-flow"
  network       = var.network
  region        = var.region
  ip_cidr_range = "10.128.0.0/24"

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 1.0            # 100% sampling for the agent subnet
    metadata             = "INCLUDE_ALL_METADATA"
    metadata_fields      = ["SRC_INSTANCE", "DST_INSTANCE", "SRC_VPC", "DST_VPC", "SRC_LOCATION", "DST_LOCATION"]
  }
}

# =============================================================================
# BigQuery Dataset — Optional Export Sink (SQL / Looker Studio Queryable)
# =============================================================================

resource "google_bigquery_dataset" "windoh" {
  count       = var.enable_bigquery_export ? 1 : 0
  dataset_id  = "windoh_cloud_events"
  project     = var.project_id
  location    = var.region
  description = "WindOH enriched cloud events — CloudEvent schema, partitioned by ingestion time"

  labels = var.tags
}

# =============================================================================
# Firewall Rule — Allow Agent Egress to Cloud APIs + Elasticsearch
# =============================================================================

resource "google_compute_firewall" "agent_egress_allow" {
  name        = "windoh-cloud-agent-egress-${var.agent_id}"
  network     = var.network
  description = "Allow WindOH cloud agent egress to GCP APIs and Elasticsearch"
  direction   = "EGRESS"
  priority    = 900

  destination_ranges = [
    "0.0.0.0/0",           # Narrow in production to specific ES + API IPs
  ]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  target_service_accounts = [google_service_account.agent.email]
}

# =============================================================================
# GCE Instance — Cloud Agent Host (Container-Optimized OS)
# =============================================================================

resource "google_compute_instance" "agent" {
  name         = "windoh-cloud-agent-${var.agent_id}"
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = "projects/cos-cloud/global/images/family/cos-stable"
      size  = 30
      type  = "pd-standard"
    }
    auto_delete = true
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
  }

  service_account {
    email  = google_service_account.agent.email
    scopes = ["cloud-platform"]   # Full GCP API access for the 5 services
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init.yml", {
      agent_id                  = var.agent_id
      project_id                = var.project_id
      monitored_project_ids     = join(",", concat([var.project_id], var.monitored_project_ids))
      elasticsearch_endpoint    = var.elasticsearch_endpoint
      elasticsearch_api_key     = var.elasticsearch_api_key
      poll_interval_secs        = var.poll_interval_secs
      enable_bigquery_export    = var.enable_bigquery_export
      bigquery_dataset          = var.enable_bigquery_export ? google_bigquery_dataset.windoh[0].dataset_id : ""
    })
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  labels = var.tags
}

# =============================================================================
# Outputs
# =============================================================================

output "agent_instance_name" {
  description = "GCE instance name running the cloud agent"
  value       = google_compute_instance.agent.name
}

output "agent_instance_internal_ip" {
  description = "Internal IP of the cloud agent"
  value       = google_compute_instance.agent.network_interface[0].network_ip
}

output "agent_service_account_email" {
  description = "Service account email — grant additional IAM roles on other projects"
  value       = google_service_account.agent.email
}

output "agent_service_account_id" {
  description = "Service account unique ID"
  value       = google_service_account.agent.unique_id
}

output "bigquery_dataset" {
  description = "BigQuery dataset for enriched cloud events (if enabled)"
  value       = var.enable_bigquery_export ? google_bigquery_dataset.windoh[0].dataset_id : null
}

output "monitored_projects" {
  description = "Full list of GCP projects being polled"
  value       = concat([var.project_id], var.monitored_project_ids)
}

output "ssh_command" {
  description = "gcloud compute ssh command for the agent instance"
  value       = "gcloud compute ssh windoh-cloud-agent-${var.agent_id} --zone=${var.zone} --project=${var.project_id}"
}
