output "key_vault_id" {
  value       = azurerm_key_vault.keycloak.id
  description = "Key Vault resource ID"
}

output "key_vault_uri" {
  value       = azurerm_key_vault.keycloak.vault_uri
  description = "Key Vault URI for secret access"
}

output "key_vault_name" {
  value       = azurerm_key_vault.keycloak.name
  description = "Key Vault name"
}

output "secret_references" {
  value = {
    postgres_admin_user_id        = azurerm_key_vault_secret.postgres_admin_user.versionless_id
    postgres_admin_password_id    = azurerm_key_vault_secret.postgres_admin_password.versionless_id
    keycloak_admin_user_id        = azurerm_key_vault_secret.keycloak_admin_user.versionless_id
    keycloak_admin_password_id    = azurerm_key_vault_secret.keycloak_admin_password.versionless_id
  }
  description = "Versionless secret IDs for use by Keycloak configuration"
  sensitive   = true
}

output "terraform_backend_config" {
  value = "Terraform state stored in: terraform.tfstate (local) or configure remote backend"
  description = "Information about Terraform state location"
}

