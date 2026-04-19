variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
  default     = "keycloak-poc-rg"
}

variable "location" {
  type        = string
  description = "Azure region"
  default     = "northeurope"
}

variable "container_app_environment_name" {
  type        = string
  description = "Name of the Container App Environment"
  default     = "keycloak-env"
}

# ============================================================================
# PostgreSQL Configuration (Azure Managed Service)
# ============================================================================

variable "postgres_server_name" {
  type        = string
  description = "PostgreSQL server name (must be globally unique across Azure)"
  default     = "keycloak-pg-server"
}

variable "postgres_sku" {
  type        = string
  description = "PostgreSQL SKU. NOTE: Burstable (B_*) does NOT support Zone-Redundant HA."
  default     = "B_Standard_B2s"
}

variable "postgres_version" {
  type        = string
  description = "PostgreSQL version"
  default     = "16"
}

variable "postgres_db_name" {
  type        = string
  description = "PostgreSQL database name"
  default     = "keycloak"
}

variable "postgres_admin_user" {
  type        = string
  description = "PostgreSQL admin user"
  default     = "keycloakadmin"
  sensitive   = true
}

variable "postgres_admin_password" {
  type        = string
  description = "PostgreSQL admin password (minimum 8 characters, must contain upper, lower, digit, special)"
  sensitive   = true
}

# ============================================================================
# Keycloak Configuration
# ============================================================================

variable "keycloak_image" {
  type        = string
  description = "Keycloak container image"
  default     = "quay.io/keycloak/keycloak:26.5.0"
}

variable "keycloak_admin_user" {
  type        = string
  description = "Keycloak bootstrap admin username"
  default     = "admin"
  sensitive   = true
}

variable "keycloak_admin_password" {
  type        = string
  description = "Keycloak bootstrap admin password"
  sensitive   = true
}

variable "keycloak_hostname" {
  type        = string
  description = <<-EOT
    The public FQDN Keycloak will use for token issuer, redirect URIs, etc.
    On first deploy, leave as empty string "" — Keycloak will start with hostname-strict=false.
    After the first apply, retrieve the FQDN with:
      terraform output keycloak_fqdn
    Then set this variable to that value and run terraform apply again.
  EOT
  default     = ""
}

# ============================================================================
# HA / Autoscaling Configuration
# ============================================================================

variable "min_replicas" {
  type        = number
  description = "Minimum number of replicas for the Container App (Must be >= 2 for HA)"
  default     = 2
}

variable "max_replicas" {
  type        = number
  description = "Maximum number of replicas for the Container App"
  default     = 5
}

# ============================================================================
# Azure Key Vault Configuration
# ============================================================================
# When use_key_vault = true, sensitive credentials are stored securely in
# Azure Key Vault and accessed via a User-Assigned Managed Identity.
# ============================================================================

variable "use_key_vault" {
  type        = bool
  description = "Enable Azure Key Vault for secrets management (must be created separately via terraform-keyvault/)"
  default     = false
}

variable "key_vault_name" {
  type        = string
  description = <<-EOT
    Azure Key Vault name (must be created separately via terraform-keyvault/).
    Only required if use_key_vault = true.
    Example: "tasos-vault-dev"
  EOT
  default     = ""

  validation {
    condition = (
      var.use_key_vault == false ||
      (length(var.key_vault_name) >= 3 && length(var.key_vault_name) <= 24 && can(regex("^[a-z0-9-]+$", var.key_vault_name)))
    )
    error_message = "When use_key_vault=true, key_vault_name must be 3-24 chars, lowercase alphanumeric and hyphens only."
  }
}

variable "key_vault_resource_group" {
  type        = string
  description = "Resource group where Key Vault is deployed (from terraform-keyvault/)"
  default     = ""

  validation {
    condition = (
      var.use_key_vault == false || length(var.key_vault_resource_group) > 0
    )
    error_message = "When use_key_vault=true, key_vault_resource_group must be specified."
  }
}

