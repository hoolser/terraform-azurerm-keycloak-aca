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
