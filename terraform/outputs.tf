output "postgres_server_fqdn" {
  description = "PostgreSQL server FQDN (publicly reachable in PoC mode)"
  value       = azurerm_postgresql_flexible_server.keycloak.fqdn
}

output "postgres_pgadmin_connection" {
  description = "pgAdmin / psql connection details (PoC — public access enabled)"
  value = {
    host     = azurerm_postgresql_flexible_server.keycloak.fqdn
    port     = 5432
    database = var.postgres_db_name
    username = var.postgres_admin_user
    sslmode  = "require"
  }
  sensitive = true
}

output "keycloak_fqdn" {
  description = "Keycloak public FQDN assigned by Azure Container Apps"
  value       = try(azurerm_container_app.keycloak.ingress[0].fqdn, "Pending")
}

output "keycloak_url" {
  description = "Keycloak root URL"
  value       = "https://${try(azurerm_container_app.keycloak.ingress[0].fqdn, "pending")}"
}

output "keycloak_admin_console_url" {
  description = "Keycloak Admin Console URL"
  value       = "https://${try(azurerm_container_app.keycloak.ingress[0].fqdn, "pending")}/admin/"
}

output "resource_group" {
  description = "Resource Group name"
  value       = azurerm_resource_group.keycloak.name
}

output "vnet" {
  description = "Virtual Network details"
  value = {
    name = azurerm_virtual_network.keycloak.name
    id   = azurerm_virtual_network.keycloak.id
  }
}

output "container_app_environment" {
  description = "Container App Environment details"
  value = {
    name = azurerm_container_app_environment.keycloak.name
    id   = azurerm_container_app_environment.keycloak.id
  }
}

output "keycloak_container_app" {
  description = "Keycloak Container App details"
  value = {
    name = azurerm_container_app.keycloak.name
    id   = azurerm_container_app.keycloak.id
  }
}

output "database_credentials" {
  description = "Database connection details"
  value = {
    host     = azurerm_postgresql_flexible_server.keycloak.fqdn
    port     = 5432
    admin    = var.postgres_admin_user
    database = var.postgres_db_name
  }
  sensitive = true
}
