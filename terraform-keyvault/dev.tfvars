#subscription_id = "your-subscription-id-here"   # TODO: replace with your real subscription ID

environment              = "dev"
resource_group_name      = "keycloak-keyvault-rg-dev"
location                 = "northeurope"
# NOTE: Key Vault names are GLOBALLY UNIQUE across all Azure subscriptions
# If you get "VaultAlreadyExists" error, add a unique suffix (timestamp, org ID, etc.)
key_vault_name           = "tasos-vault-dev-20260319"

postgres_admin_user      = "keycloakadmin"
postgres_admin_password  = "KeycloakP@ssw0rd123!"

keycloak_admin_user      = "admin"
keycloak_admin_password  = "KeycloakAdminP@s5774444777!" #Different from the one is configured at terraform/dev.tfvars file to prove that is used from here (From Vault).

# Key Vault soft-delete behavior for DEV environment
# In dev: Purge immediately on destroy to allow quick recreation with same name
# and attempt recovery if vault was previously soft-deleted
purge_kv_on_destroy      = true
recover_kv_on_apply      = true

