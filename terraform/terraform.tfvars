#subscription_id = "your-subscription-id-here"   # TODO: replace with your real subscription ID

# Resource Group and Environment
resource_group_name            = "keycloak-poc-rg"
location                       = "northeurope"
container_app_environment_name = "keycloak-env"

# PostgreSQL Configuration
# postgres_server_name must be globally unique across Azure
postgres_server_name    = "keycloak-pg-srv-unique97"   # TODO: Change to something globally unique!
postgres_sku            = "B_Standard_B2s"
postgres_version        = "16"
postgres_db_name        = "keycloak"
postgres_admin_user     = "keycloakadmin"
postgres_admin_password = "KeycloakP@ssw0rd123!"      # TODO: Change to a secure password

# Keycloak Configuration
keycloak_image          = "quay.io/keycloak/keycloak:26.5.0"
keycloak_admin_user     = "admin"
keycloak_admin_password = "KeycloakAdminP@ss123!"     # TODO: Change to a secure password

# Two-phase hostname setup:
#   Phase 1 — leave empty so Keycloak starts with hostname-strict=false.
#              Run: terraform apply
#              Then: terraform output keycloak_fqdn
#   Phase 2 — paste the FQDN here and run: terraform apply again
keycloak_hostname = ""
#e.g.
#keycloak_hostname = "keycloak.jollywater-7f7e19ee.northeurope.azurecontainerapps.io"
