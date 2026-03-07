# ============================================================================
# LOCALS — derive helper values
# ============================================================================

locals {
  # JDBC URL used both by Keycloak AND by JGroups JDBC_PING
  jdbc_url = "jdbc:postgresql://${azurerm_postgresql_flexible_server.keycloak.fqdn}:5432/${var.postgres_db_name}?ssl=true&sslmode=require"

  # When keycloak_hostname is not set we allow strict-hostname=false so
  # Keycloak accepts requests from the ACA-assigned FQDN on first boot.
  # IMPORTANT: Do NOT set KC_HOSTNAME to "localhost" on Phase 1 — Keycloak
  # would use it as the issuer base URL and admin console redirects would
  # break in the browser.  Instead omit KC_HOSTNAME entirely (empty string
  # is ignored below) so Keycloak derives the hostname dynamically from the
  # incoming request (safe because KC_HOSTNAME_STRICT=false).
  hostname_strict = var.keycloak_hostname != "" ? "true" : "false"
  hostname_value  = var.keycloak_hostname  # empty string → env var omitted (see container block)

  # JGroups JDBC_PING JAVA_OPTS - enables TCP cluster discovery via shared DB table
  # Keycloak 26.x ships cache-ispn-jdbc-ping.xml; activated via KC_CACHE_STACK=jdbc-ping
  jgroups_java_opts = join(" ", [
    "-Djgroups.jdbc.connection_url=${local.jdbc_url}",
    "-Djgroups.jdbc.connection_username=${var.postgres_admin_user}",
    "-Djgroups.jdbc.connection_password=${var.postgres_admin_password}",
    "-Djgroups.jdbc.driver_name=postgresql",
    # Bind to the container's private IP for intra-cluster TCP communication
    #"-Djgroups.bind.address=SITE_LOCAL",
    # Use GLOBAL so JGroups binds to the VNet-routable IP (10.0.2.x), not
    # the 169.254.x.x link-local ACA sidecar address that SITE_LOCAL resolves to.
    "-Djgroups.bind.address=GLOBAL",
    # Disable multicast (not available in ACA/Azure)
    "-Djgroups.use.mcast_addr=false",
  ])
}

# ============================================================================
# RESOURCE GROUP
# ============================================================================

resource "azurerm_resource_group" "keycloak" {
  name     = var.resource_group_name
  location = var.location
}

# ============================================================================
# NETWORKING — VNet, Subnets, NSG
# ============================================================================

resource "azurerm_virtual_network" "keycloak" {
  name                = "keycloak-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.keycloak.location
  resource_group_name = azurerm_resource_group.keycloak.name
}

# Subnet for PostgreSQL Flexible Server (delegated, /24 is sufficient for DB)
resource "azurerm_subnet" "postgres" {
  name                 = "postgres-subnet"
  resource_group_name  = azurerm_resource_group.keycloak.name
  virtual_network_name = azurerm_virtual_network.keycloak.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }

  lifecycle {
    ignore_changes = [service_endpoints]
  }
}

# Subnet for Container Apps — ACA VNet integration requires at least /23
resource "azurerm_subnet" "container_apps" {
  name                 = "container-apps-subnet"
  resource_group_name  = azurerm_resource_group.keycloak.name
  virtual_network_name = azurerm_virtual_network.keycloak.name
  address_prefixes     = ["10.0.2.0/23"]

  delegation {
    name = "app-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# NSG — allow PostgreSQL port only from Container Apps subnet; deny everything else
resource "azurerm_network_security_group" "postgres" {
  name                = "postgres-nsg"
  location            = azurerm_resource_group.keycloak.location
  resource_group_name = azurerm_resource_group.keycloak.name

  security_rule {
    name                       = "AllowFromContainerApps"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "10.0.2.0/23"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAll"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "postgres" {
  subnet_id                 = azurerm_subnet.postgres.id
  network_security_group_id = azurerm_network_security_group.postgres.id
}

# ============================================================================
# DATABASE — Azure PostgreSQL Flexible Server
# ============================================================================

# Private DNS Zone — PostgreSQL resolves only within the VNet
resource "azurerm_private_dns_zone" "postgres" {
  name                = "keycloak.private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.keycloak.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "keycloak-link"
  resource_group_name   = azurerm_resource_group.keycloak.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.keycloak.id
}

resource "azurerm_postgresql_flexible_server" "keycloak" {
  name                          = var.postgres_server_name
  location                      = azurerm_resource_group.keycloak.location
  resource_group_name           = azurerm_resource_group.keycloak.name
  delegated_subnet_id           = azurerm_subnet.postgres.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  administrator_login           = var.postgres_admin_user
  administrator_password        = var.postgres_admin_password
  public_network_access_enabled = false
  backup_retention_days         = 7
  storage_mb                    = 32768
  storage_tier                  = "P4"
  sku_name                      = var.postgres_sku
  version                       = var.postgres_version

  lifecycle {
    ignore_changes = [
      zone,
      high_availability,
    ]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "keycloak" {
  name      = var.postgres_db_name
  server_id = azurerm_postgresql_flexible_server.keycloak.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ============================================================================
# CONTAINER APPS ENVIRONMENT
# ============================================================================

resource "azurerm_container_app_environment" "keycloak" {
  name                           = var.container_app_environment_name
  location                       = azurerm_resource_group.keycloak.location
  resource_group_name            = azurerm_resource_group.keycloak.name
  infrastructure_subnet_id       = azurerm_subnet.container_apps.id
  internal_load_balancer_enabled = false

  lifecycle {
    ignore_changes = [
      infrastructure_resource_group_name,
      workload_profile,
    ]
  }
}

# ============================================================================
# KEYCLOAK — HA Container App (2–5 replicas, JDBC_PING clustering)
#
# Clustering design:
#   - JGroups uses JDBC_PING for member discovery (shared PostgreSQL table
#     JGROUPSPING).  This is the only reliable discovery mechanism in ACA
#     because UDP multicast is not available and DNS_PING requires a headless
#     Kubernetes-style service that ACA does not expose.
#   - KC_CACHE_STACK=jdbc-ping activates the built-in cache-ispn-jdbc-ping.xml
#     Infinispan stack shipped with Keycloak 26.x.
#   - All replicas share the same database, so sessions and caches are
#     distributed correctly across nodes.
#   - Keycloak runs in HTTP mode (KC_HTTP_ENABLED=true) because ACA terminates
#     TLS and forwards requests via the load-balanced ingress.  The proxy
#     header mode (KC_PROXY_HEADERS=xforwarded) tells Keycloak to trust the
#     X-Forwarded-* headers injected by ACA.
# ============================================================================

resource "azurerm_container_app" "keycloak" {
  name                         = "keycloak"
  container_app_environment_id = azurerm_container_app_environment.keycloak.id
  resource_group_name          = azurerm_resource_group.keycloak.name
  revision_mode                = "Single"

  lifecycle {
    ignore_changes = [
      tags,
      workload_profile_name,
    ]
  }

  template {
    container {
      name   = "keycloak"
      image  = var.keycloak_image
      cpu    = 1.0
      memory = "2Gi"

      # Keycloak 26.x start command.
      # NOTE: "start --optimized" requires a custom pre-built image (kc.sh build).
      # The standard quay.io/keycloak/keycloak image uses plain "start" which
      # performs auto-build at first launch (slower but works out of the box).
      args = ["start"]

      # ── Database ──────────────────────────────────────────────────────────
      env {
        name  = "KC_DB"
        value = "postgres"
      }
      env {
        name  = "KC_DB_URL"
        value = local.jdbc_url
      }
      env {
        name  = "KC_DB_USERNAME"
        value = var.postgres_admin_user
      }
      env {
        name  = "KC_DB_PASSWORD"
        value = var.postgres_admin_password
      }
      env {
        name  = "KC_DB_SCHEMA"
        value = "public"
      }

      # ── Hostname / proxy ──────────────────────────────────────────────────
      # ACA terminates TLS; Keycloak listens on HTTP internally
      env {
        name  = "KC_HTTP_ENABLED"
        value = "true"
      }
      env {
        name  = "KC_HTTP_PORT"
        value = "8080"
      }
      env {
        name  = "KC_HTTPS_PORT"
        value = "8443"
      }
      env {
        name  = "KC_PROXY_HEADERS"
        value = "xforwarded"
      }
      # hostname-strict controls whether Keycloak rejects requests not matching
      # KC_HOSTNAME.  Set to false on first boot (when hostname is unknown).
      env {
        name  = "KC_HOSTNAME_STRICT"
        value = local.hostname_strict
      }
      # KC_HOSTNAME: only set when keycloak_hostname is known (Phase 2).
      # On Phase 1 (empty string) we intentionally omit this so Keycloak
      # derives the public hostname from the incoming X-Forwarded-Host header.
      # Terraform does not support conditional env blocks natively, so we pass
      # an empty string and Keycloak ignores KC_HOSTNAME="" when strict=false.
      env {
        name  = "KC_HOSTNAME"
        value = local.hostname_value
      }

      # ── Clustering — Infinispan + JGroups JDBC_PING ───────────────────────
      # Enables distributed Infinispan caches (sessions, tokens, etc.)
      env {
        name  = "KC_CACHE"
        value = "ispn"
      }
      # Activates the JDBC_PING JGroups discovery stack built into Keycloak 26.x
      env {
        name  = "KC_CACHE_STACK"
        value = "jdbc-ping"
      }
      # JGroups JDBC_PING connection details + TCP bind address
      env {
        name  = "JAVA_OPTS_APPEND"
        value = local.jgroups_java_opts
      }

      # ── Bootstrap admin (only used when no admin exists in DB) ────────────
      # Keycloak 26.x uses KC_BOOTSTRAP_ADMIN_* (the old KEYCLOAK_ADMIN_*
      # env vars still work as aliases but the new names are canonical).
      env {
        name  = "KC_BOOTSTRAP_ADMIN_USERNAME"
        value = var.keycloak_admin_user
      }
      env {
        name  = "KC_BOOTSTRAP_ADMIN_PASSWORD"
        value = var.keycloak_admin_password
      }
      # Keep legacy names as fallback for compatibility
      env {
        name  = "KEYCLOAK_ADMIN"
        value = var.keycloak_admin_user
      }
      env {
        name  = "KEYCLOAK_ADMIN_PASSWORD"
        value = var.keycloak_admin_password
      }

      # ── Observability ─────────────────────────────────────────────────────
      env {
        name  = "KC_HEALTH_ENABLED"
        value = "true"
      }
      env {
        name  = "KC_METRICS_ENABLED"
        value = "true"
      }
      env {
        name  = "KC_LOG_LEVEL"
        value = "INFO"
      }

      # ── Liveness probe — management port 9000 ─────────────────────────────
      liveness_probe {
        transport = "HTTP"
        port      = 9000
        path      = "/health/live"

        initial_delay           = 60  # provider max is 60; startup probe covers the rest
        interval_seconds        = 15
        timeout                 = 5
        failure_count_threshold = 5
      }

      # ── Readiness probe ───────────────────────────────────────────────────
      readiness_probe {
        transport = "HTTP"
        port      = 9000
        path      = "/health/ready"

        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 3
        success_count_threshold = 1
      }

      # ── Startup probe — generous timeout for DB schema migration ──────────
      startup_probe {
        transport = "HTTP"
        port      = 9000
        path      = "/health/live"

        initial_delay           = 60  # provider max is 60
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 30  # 30 × 10s = 300s total startup window
      }
    }

    # Minimum 2 replicas to form an actual HA cluster
    min_replicas = 2
    max_replicas = 5
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }


  }

  depends_on = [
    azurerm_postgresql_flexible_server.keycloak,
    azurerm_postgresql_flexible_server_database.keycloak,
  ]
}
