# ============================================================================
# AZURE KEY VAULT — Data Source (External Management)
# ============================================================================
# This file references an EXISTING Key Vault created and managed by a separate
# Terraform configuration (terraform-keyvault/).
#
# The Key Vault is NOT created or destroyed by this configuration.
# It only reads existing secrets and grants Container App access to them.
#
# Prerequisites:
#   1. Deploy Key Vault first:
#      cd ../terraform-keyvault
#      terraform apply -var-file="dev.tfvars"
#
#   2. Then deploy Keycloak (this configuration):
#      cd ../terraform
#      terraform apply -var-file="dev.tfvars"
#
# Key Vault lifecycle:
#   - Create: ../terraform-keyvault/terraform apply
#   - Destroy: ../terraform-keyvault/terraform destroy
#   - Secrets: Manage via Azure CLI (terraform ignores value changes)
# ============================================================================

# ──────────────────────────────────────────────────────────────────────────
# Data source: Reference existing Azure Key Vault
# ──────────────────────────────────────────────────────────────────────────
data "azurerm_key_vault" "keycloak" {
  count               = var.use_key_vault ? 1 : 0
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group
}

# ──────────────────────────────────────────────────────────────────────────
# Data source: Reference existing Key Vault secrets
# ──────────────────────────────────────────────────────────────────────────
data "azurerm_key_vault_secret" "postgres_admin_user" {
  count           = var.use_key_vault ? 1 : 0
  name            = "postgres-admin-user"
  key_vault_id    = data.azurerm_key_vault.keycloak[0].id
}

data "azurerm_key_vault_secret" "postgres_admin_password" {
  count           = var.use_key_vault ? 1 : 0
  name            = "postgres-admin-password"
  key_vault_id    = data.azurerm_key_vault.keycloak[0].id
}

data "azurerm_key_vault_secret" "keycloak_admin_user" {
  count           = var.use_key_vault ? 1 : 0
  name            = "keycloak-admin-user"
  key_vault_id    = data.azurerm_key_vault.keycloak[0].id
}

data "azurerm_key_vault_secret" "keycloak_admin_password" {
  count           = var.use_key_vault ? 1 : 0
  name            = "keycloak-admin-password"
  key_vault_id    = data.azurerm_key_vault.keycloak[0].id
}

# ──────────────────────────────────────────────────────────────────────────
# User-Assigned Managed Identity for the Container App
# ──────────────────────────────────────────────────────────────────────────
resource "azurerm_user_assigned_identity" "keycloak_app" {
  count               = var.use_key_vault ? 1 : 0
  name                = "keycloak-container-app-identity"
  location            = azurerm_resource_group.keycloak.location
  resource_group_name = azurerm_resource_group.keycloak.name

  tags = {
    purpose = "container-app-managed-identity"
  }
}

# ──────────────────────────────────────────────────────────────────────────
# RBAC: Assign "Key Vault Secrets User" role to the Container App identity
# This allows the Container App to read (but not modify) secrets from Key Vault
# ──────────────────────────────────────────────────────────────────────────
resource "azurerm_role_assignment" "keycloak_app_secrets_user" {
  count              = var.use_key_vault ? 1 : 0
  scope              = data.azurerm_key_vault.keycloak[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id       = azurerm_user_assigned_identity.keycloak_app[0].principal_id
}


