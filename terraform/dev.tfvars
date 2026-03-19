#subscription_id = "your-subscription-id-here"   # TODO: replace with your real subscription ID

# Resource Group and Environment
resource_group_name            = "keycloak-poc-rg-dev"
location                       = "northeurope"
container_app_environment_name = "keycloak-env"

# PostgreSQL Configuration
# postgres_server_name must be globally unique across Azure
postgres_server_name    = "keycloak-pg-srv-5dev77772"   # TODO: Change to something globally unique!
postgres_sku            = "B_Standard_B2s"
postgres_version        = "16"
postgres_db_name        = "keycloak"
postgres_admin_user     = "keycloakadmin"
postgres_admin_password = "KeycloakP@ssw0rd123!"      # TODO: Change to a secure password

# Keycloak Configuration
keycloak_image          = "quay.io/keycloak/keycloak:26.5.0"
keycloak_admin_user     = "admin"
keycloak_admin_password = "KeycloakAdminP@ss123!"     # TODO: Change to a secure password

# ============================================================================
# AZURE KEY VAULT CONFIGURATION (dev env)
# ============================================================================
# Reference an EXISTING Key Vault created by ../terraform-keyvault/
#
# To deploy:
#   1. First deploy Key Vault:
#      cd ../terraform-keyvault
#      terraform apply -var-file="dev.tfvars"
#
#   2. Then deploy Keycloak:
#      cd ../terraform
#      terraform apply -var-file="dev.tfvars"
# ============================================================================

use_key_vault               = false  # Set to true if you want to use Key Vault for secrets management
key_vault_name              = "tasos-vault-dev-20260319"
key_vault_resource_group    = "keycloak-keyvault-rg-dev"

# Two-phase hostname setup:
#   Phase 1 — leave empty so Keycloak starts with hostname-strict=false.
#              Run: terraform apply
#              Then: terraform output keycloak_fqdn
#   Phase 2 — paste the FQDN here and run: terraform apply again
keycloak_hostname = ""
#e.g.
#keycloak_hostname = "keycloak.delightfulglacier-291b8d3c.northeurope.azurecontainerapps.io"

# Scaling Configuration
min_replicas = 1
max_replicas = 1
#After initial deployment, you can enable autoscaling by setting min_replicas to 1 and max_replicas to a higher number, then running terraform apply again.
#min_replicas = 2
#max_replicas = 2