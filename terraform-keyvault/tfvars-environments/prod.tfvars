#subscription_id = "your-subscription-id-here"   # TODO: replace with your real subscription ID

environment              = "prod"
resource_group_name      = "keycloak-keyvault-rg-prod"
location                 = "northeurope"
# NOTE: Key Vault names are GLOBALLY UNIQUE across all Azure subscriptions
# If you get "VaultAlreadyExists" error, add a unique suffix (timestamp, org ID, etc.)
key_vault_name           = "tasos-vault-prod-20260319"

postgres_admin_user      = "keycloakadmin"
postgres_admin_password  = "KeycloakP@ssw0rd123!"

keycloak_admin_user      = "admin"
keycloak_admin_password  = "KeyclsdffdsfdsfsdPRODminP@ss123!"

# Key Vault soft-delete behavior for PROD environment
# In prod: DO NOT purge on destroy (safety measure to prevent accidental data loss)
# but attempt recovery if vault was previously soft-deleted
purge_kv_on_destroy      = false
recover_kv_on_apply      = true

