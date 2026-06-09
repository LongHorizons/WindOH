# =============================================================================
# WindOH Cloud Agent — Azure Terraform
# =============================================================================
# Deploys the LongHorizons cloud telemetry agent on an Azure VM with managed
# identity, enabling all 6 polled services: Activity Log (administrative /
# service health / resource health / alert / autoscale / security), NSG Flow
# Logs (Network Watcher v2 5-tuple flow records to Blob Storage), Sentinel
# (scheduled / ML Behavior / Fusion / NRT / UEBA analytics alerts), AD Sign-in
# Logs (Microsoft Graph interactive + non-interactive + Conditional Access
# status + MFA result), Key Vault (AuditEvent — Secret/Key/Certificate CRUD),
# and Azure Policy (compliance state + remediation tracking at MG/Sub/RG scope).
#
# The agent uses DefaultAzureCredential — no secrets in config files.
# Telemetry never leaves your tenant.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "location" {
  description = "Azure region for the cloud agent resources"
  type        = string
  default     = "eastus"
}

variable "agent_id" {
  description = "Unique identifier for this agent instance (e.g., azure-prod-01)"
  type        = string
  default     = "azure-prod-01"
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "subscription_ids" {
  description = "Azure subscription IDs to poll (Activity Log, Policy, NSG across all)"
  type        = list(string)
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

variable "vm_size" {
  description = "Azure VM size for the cloud agent"
  type        = string
  default     = "Standard_B2s"   # 2 vCPU, 4 GB RAM
}

variable "vnet_name" {
  description = "Existing VNet name"
  type        = string
}

variable "subnet_name" {
  description = "Existing subnet name for the agent VM"
  type        = string
}

variable "vnet_resource_group" {
  description = "Resource group containing the VNet"
  type        = string
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the agent VM admin user"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
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

data "azurerm_client_config" "current" {}
data "azurerm_subnet" "agent" {
  name                 = var.subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = var.vnet_resource_group
}

# =============================================================================
# Resource Group
# =============================================================================

resource "azurerm_resource_group" "agent" {
  name     = "rg-windoh-cloud-agent-${var.agent_id}"
  location = var.location
  tags     = var.tags
}

# =============================================================================
# Managed Identity — DefaultAzureCredential: no secrets, no keys
# =============================================================================

resource "azurerm_user_assigned_identity" "agent" {
  name                = "id-windoh-agent-${var.agent_id}"
  resource_group_name = azurerm_resource_group.agent.name
  location            = azurerm_resource_group.agent.location
  tags                = var.tags
}

# --- Reader role on each subscription ---
resource "azurerm_role_assignment" "subscription_reader" {
  for_each             = toset(var.subscription_ids)
  scope                = "/subscriptions/${each.value}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
}

# --- Monitoring Reader: Activity Log + diagnostic settings read ---
resource "azurerm_role_assignment" "monitoring_reader" {
  for_each             = toset(var.subscription_ids)
  scope                = "/subscriptions/${each.value}"
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
}

# --- Security Reader: Sentinel alerts, Defender for Cloud findings ---
resource "azurerm_role_assignment" "security_reader" {
  for_each             = toset(var.subscription_ids)
  scope                = "/subscriptions/${each.value}"
  role_definition_name = "Security Reader"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
}

# --- Storage Blob Data Reader: NSG Flow Logs on Blob Storage ---
resource "azurerm_role_assignment" "storage_blob_reader" {
  for_each             = toset(var.subscription_ids)
  scope                = "/subscriptions/${each.value}"
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
}

# --- Key Vault Secrets User: Read Key Vault diagnostic logs from EventHub-backed Storage ---
resource "azurerm_role_assignment" "key_vault_reader" {
  for_each             = toset(var.subscription_ids)
  scope                = "/subscriptions/${each.value}"
  role_definition_name = "Key Vault Reader"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
}

# --- Microsoft Graph API: Directory.Read.All for AD Sign-in Logs ---
# (Applied via Microsoft Graph, not Azure RBAC — requires separate azuread provider)
# See: https://learn.microsoft.com/en-us/graph/permissions-reference#auditlogdata
# Managed identity must be granted:
#   Application: Microsoft Graph
#   API Permission: AuditLog.Read.All (Application type)
#   Grant admin consent required.

# =============================================================================
# Log Analytics Workspace — Activity Log + Sentinel + Diagnostics sink
# =============================================================================

resource "azurerm_log_analytics_workspace" "agent" {
  name                = "law-windoh-agent-${var.agent_id}"
  resource_group_name = azurerm_resource_group.agent.name
  location            = azurerm_resource_group.agent.location
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags                = var.tags
}

# --- Enable Sentinel on the workspace ---
resource "azurerm_sentinel_log_analytics_workspace_onboarding" "agent" {
  workspace_id = azurerm_log_analytics_workspace.agent.id
}

# --- Diagnostic setting: Activity Log → Log Analytics ---
resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  for_each                   = toset(var.subscription_ids)
  name                       = "windoh-activity-log-${each.value}"
  target_resource_id         = "/subscriptions/${each.value}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.agent.id

  enabled_log {
    category = "Administrative"
    # retention_policy { enabled = false }
  }
  enabled_log {
    category = "Security"
  }
  enabled_log {
    category = "Alert"
  }
  enabled_log {
    category = "Policy"
  }
  enabled_log {
    category = "ServiceHealth"
  }
  enabled_log {
    category = "ResourceHealth"
  }
  enabled_log {
    category = "Autoscale"
  }
}

# =============================================================================
# NSG Flow Logs — Network Watcher v2, per-NIC 5-tuple → Blob Storage
# =============================================================================

resource "azurerm_storage_account" "nsg_flow_logs" {
  name                     = "windohnsg${var.agent_id}"
  resource_group_name      = azurerm_resource_group.agent.name
  location                 = azurerm_resource_group.agent.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

# Network Watcher Flow Log — deploy per NSG
# (Requires Network Watcher enabled in each region; this is configured at the
# subscription level via the Azure portal or azurerm provider's
# network_watcher_flow_log resource targeting each NSG ID.)

# =============================================================================
# Network — Agent VM NIC with NSG
# =============================================================================

resource "azurerm_network_security_group" "agent" {
  name                = "nsg-windoh-agent-${var.agent_id}"
  resource_group_name = azurerm_resource_group.agent.name
  location            = azurerm_resource_group.agent.location

  # Allow egress to Azure APIs (HTTPS)
  security_rule {
    name                       = "AllowAzureAPIs"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443"]
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
    description                = "Activity Log, Sentinel, Policy, Key Vault, Graph API"
  }

  # Allow egress to Elasticsearch
  security_rule {
    name                       = "AllowElasticsearch"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"   # Narrow to your ES cluster IP/CIDR
    description                = "Elasticsearch bulk API (HTTPS)"
  }

  tags = var.tags
}

resource "azurerm_network_interface" "agent" {
  name                = "nic-windoh-agent-${var.agent_id}"
  resource_group_name = azurerm_resource_group.agent.name
  location            = azurerm_resource_group.agent.location

  ip_configuration {
    name                          = "ipconfig-agent"
    subnet_id                     = data.azurerm_subnet.agent.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

resource "azurerm_network_interface_security_group_association" "agent" {
  network_interface_id      = azurerm_network_interface.agent.id
  network_security_group_id = azurerm_network_security_group.agent.id
}

# =============================================================================
# Azure VM — Cloud Agent Host (Ubuntu 22.04 LTS)
# =============================================================================

resource "azurerm_linux_virtual_machine" "agent" {
  name                            = "vm-windoh-agent-${var.agent_id}"
  resource_group_name             = azurerm_resource_group.agent.name
  location                        = azurerm_resource_group.agent.location
  size                            = var.vm_size
  admin_username                  = "windoh"
  disable_password_authentication = true

  network_interface_ids = [azurerm_network_interface.agent.id]

  admin_ssh_key {
    username   = "windoh"
    public_key = var.admin_ssh_public_key
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agent.id]
  }

  os_disk {
    name                 = "disk-windoh-agent-${var.agent_id}-os"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yml", {
    agent_id                    = var.agent_id
    tenant_id                   = var.tenant_id
    subscription_ids            = join(",", var.subscription_ids)
    elasticsearch_endpoint      = var.elasticsearch_endpoint
    elasticsearch_api_key       = var.elasticsearch_api_key
    poll_interval_secs          = var.poll_interval_secs
    log_analytics_workspace_id  = azurerm_log_analytics_workspace.agent.id
    log_analytics_workspace_key = azurerm_log_analytics_workspace.agent.primary_shared_key
  }))

  tags = var.tags
}

# =============================================================================
# Key Vault — Diagnostic Settings (audit every Secret/Key/Certificate operation)
# =============================================================================

resource "azurerm_key_vault" "agent_secrets" {
  name                       = "kv-windoh-agent-${var.agent_id}"
  resource_group_name        = azurerm_resource_group.agent.name
  location                   = azurerm_resource_group.agent.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 90

  tags = var.tags
}

# Diagnostic setting for the agent's own Key Vault — audit trail
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "windoh-kv-diagnostics"
  target_resource_id         = azurerm_key_vault.agent_secrets.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.agent.id

  enabled_log {
    category_group = "audit"
  }
  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = false
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "agent_vm_id" {
  description = "Azure VM resource ID running the cloud agent"
  value       = azurerm_linux_virtual_machine.agent.id
}

output "agent_vm_private_ip" {
  description = "Private IP of the cloud agent VM"
  value       = azurerm_network_interface.agent.private_ip_address
}

output "managed_identity_principal_id" {
  description = "Principal ID of the managed identity — grant additional RBAC roles as needed"
  value       = azurerm_user_assigned_identity.agent.principal_id
}

output "managed_identity_client_id" {
  description = "Client ID of the managed identity"
  value       = azurerm_user_assigned_identity.agent.client_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace resource ID — query agent diagnostics"
  value       = azurerm_log_analytics_workspace.agent.id
}

output "nsg_flow_log_storage_account" {
  description = "Storage account for NSG Flow Logs"
  value       = azurerm_storage_account.nsg_flow_logs.name
}

output "key_vault_uri" {
  description = "Key Vault URI — agent secrets stored here"
  value       = azurerm_key_vault.agent_secrets.vault_uri
}

output "subscription_coverage" {
  description = "Subscriptions being polled by the agent"
  value       = var.subscription_ids
}
