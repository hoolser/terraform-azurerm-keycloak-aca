# ============================================================================
# AZURE KEY VAULT — Independent Terraform Configuration
# ============================================================================
# This configuration creates and manages Azure Key Vault secrets independently.
# It has its own state file and can be deployed/destroyed separately from Keycloak.
#
# Deploy first:
#   cd terraform-keyvault
#   terraform init
#   terraform apply -var-file="dev.tfvars"
#
# Output: Key Vault URI and secret names for use by Keycloak configuration
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    key_vault {
      # Environment-specific soft-delete behavior
      # dev:  purge_soft_delete_on_destroy=true, recover_soft_deleted_key_vaults=true
      # prod: purge_soft_delete_on_destroy=false, recover_soft_deleted_key_vaults=true
      purge_soft_delete_on_destroy    = var.purge_kv_on_destroy
      recover_soft_deleted_key_vaults = var.recover_kv_on_apply
    }
  }
}

# ──────────────────────────────────────────────────────────────────────────
# Data source: Current Azure client context
# ──────────────────────────────────────────────────────────────────────────
data "azurerm_client_config" "current" {}

# ──────────────────────────────────────────────────────────────────────────
# Resource Group for Key Vault
# ──────────────────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "keycloak_vault" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    environment = var.environment
    purpose     = "keycloak-secrets"
  }
}

# ──────────────────────────────────────────────────────────────────────────
# Azure Key Vault
# ──────────────────────────────────────────────────────────────────────────
resource "azurerm_key_vault" "keycloak" {
  name                            = var.key_vault_name
  location                        = azurerm_resource_group.keycloak_vault.location
  resource_group_name             = azurerm_resource_group.keycloak_vault.name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = "standard"
  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = true
  rbac_authorization_enabled      = true
  purge_protection_enabled        = true
  soft_delete_retention_days      = 7
  public_network_access_enabled   = true

  tags = {
    environment = var.environment
    purpose     = "secrets-management"
  }
}

# ──────────────────────────────────────────────────────────────────────────
# Key Vault Secrets: PostgreSQL credentials
# ──────────────────────────────────────────────────────────────────────────
resource "azurerm_key_vault_secret" "postgres_admin_user" {
  name         = "postgres-admin-user"
  value        = var.postgres_admin_user
  key_vault_id = azurerm_key_vault.keycloak.id

  tags = {
    purpose = "database-authentication"
  }
}

resource "azurerm_key_vault_secret" "postgres_admin_password" {
  name        = "postgres-admin-password"
  value       = var.postgres_admin_password
  key_vault_id = azurerm_key_vault.keycloak.id

  lifecycle {
    ignore_changes = [value]  # Allow manual rotation via Azure CLI
  }

  tags = {
    purpose = "database-authentication"
  }
}

# ──────────────────────────────────────────────────────────────────────────
# Key Vault Secrets: Keycloak bootstrap admin credentials
# ──────────────────────────────────────────────────────────────────────────
resource "azurerm_key_vault_secret" "keycloak_admin_user" {
  name         = "keycloak-admin-user"
  value        = var.keycloak_admin_user
  key_vault_id = azurerm_key_vault.keycloak.id

  tags = {
    purpose = "keycloak-authentication"
  }
}

resource "azurerm_key_vault_secret" "keycloak_admin_password" {
  name        = "keycloak-admin-password"
  value       = var.keycloak_admin_password
  key_vault_id = azurerm_key_vault.keycloak.id

  lifecycle {
    ignore_changes = [value]  # Allow manual rotation via Azure CLI
  }

  tags = {
    purpose = "keycloak-authentication"
  }
}

# ──────────────────────────────────────────────────────────────────────────
# RBAC: Grant current user admin access to manage secrets
# ──────────────────────────────────────────────────────────────────────────
resource "azurerm_role_assignment" "current_user_kv_admin" {
  scope              = azurerm_key_vault.keycloak.id
  role_definition_name = "Key Vault Administrator"
  principal_id       = data.azurerm_client_config.current.object_id
}

