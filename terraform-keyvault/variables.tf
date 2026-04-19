variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, sup, prod)"
  default     = "dev"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for Key Vault"
}

variable "location" {
  type        = string
  description = "Azure region"
  default     = "northeurope"
}

variable "key_vault_name" {
  type        = string
  description = "Key Vault name (globally unique, 3-24 chars, lowercase alphanumeric + hyphens)"

  validation {
    condition     = length(var.key_vault_name) >= 3 && length(var.key_vault_name) <= 24 && can(regex("^[a-z0-9-]+$", var.key_vault_name))
    error_message = "Must be 3-24 chars, lowercase alphanumeric and hyphens only."
  }
}

variable "postgres_admin_user" {
  type        = string
  description = "PostgreSQL admin username"
  sensitive   = true
}

variable "postgres_admin_password" {
  type        = string
  description = "PostgreSQL admin password"
  sensitive   = true
}

variable "keycloak_admin_user" {
  type        = string
  description = "Keycloak bootstrap admin username"
  sensitive   = true
}

variable "keycloak_admin_password" {
  type        = string
  description = "Keycloak bootstrap admin password"
  sensitive   = true
}

# ============================================================================
# KEY VAULT SOFT-DELETE BEHAVIOR — Configurable per environment
# ============================================================================

variable "purge_kv_on_destroy" {
  type        = bool
  description = "Purge Key Vault immediately on destroy (dev=true, prod=false for safety)"
  default     = false

  validation {
    condition     = can(coalesce(var.purge_kv_on_destroy))
    error_message = "Must be true or false."
  }
}

variable "recover_kv_on_apply" {
  type        = bool
  description = "Attempt to recover soft-deleted Key Vault on apply (useful for dev/test environments)"
  default     = true

  validation {
    condition     = can(coalesce(var.recover_kv_on_apply))
    error_message = "Must be true or false."
  }
}
