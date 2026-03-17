# Keycloak 26.5.0 on Azure ACA — HA IaC Solution
> VNet + PostgreSQL Flexible Server + Azure Container Apps (HA, JDBC_PING clustering)

---

## Overview

This Terraform configuration deploys **Keycloak 26.5.0** with production-grade HA infrastructure on Azure Container Apps:

- ✅ Azure PostgreSQL Flexible Server (managed database)
- ✅ Virtual Network (VNet) with proper subnet segmentation
- ✅ Private DNS Zone and NSGs for security (no public database access)
- ✅ Single Keycloak Container App with **2–5 replicas** (HA cluster)
- ✅ JGroups **JDBC_PING** clustering — the only reliable discovery in ACA (no UDP multicast)
- ✅ Infinispan distributed caches (sessions, tokens) shared across all nodes
- ✅ SSL/TLS encryption for all database connections
- ✅ Bootstrap admin account set on first startup

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Azure Subscription                                 │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │ Resource Group                                                            │  │
│  │                                                                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │ Virtual Network (VNet) — 10.0.0.0/16                                │  │  │
│  │  │                                                                     │  │  │
│  │  │  ┌──────────────────────────────┐   ┌──────────────────────────────┐│  │  │
│  │  │  │ PostgreSQL Subnet            │   │ Container Apps Subnet        ││  │  │
│  │  │  │ 10.0.1.0/24                  │   │ 10.0.2.0/23                  ││  │  │
│  │  │  │ (delegated)                  │   │ (ACA infrastructure)         ││  │  │
│  │  │  │                              │   │                              ││  │  │
│  │  │  │  ┌────────────────────────┐  │   │  ┌────────────────────────┐  ││  │  │
│  │  │  │  │ Azure PostgreSQL       │  │   │  │ Container Apps         │  ││  │  │
│  │  │  │  │ Flexible Server        │◄─┼───┼─►│ Environment            │  ││  │  │
│  │  │  │  │                        │  │   │  │                        │  ││  │  │
│  │  │  │  │ Port: 5432             │  │   │  │  ┌──────────────────┐  │  ││  │  │
│  │  │  │  │ SSL: Required          │  │   │  │  │ keycloak (ACA)   │  │  ││  │  │
│  │  │  │  │ Private VNet only      │  │   │  │  │(JGroups cluster) │  │  ││  │  │
│  │  │  │  │                        │  │   │  │  │ replica-1 ─┐     │  │  ││  │  │
│  │  │  │  │ JGROUPSPING table      │  │   │  │  │ replica-2  ├──TCP│  │  ││  │  │
│  │  │  │  │ (cluster discovery)    │  │   │  │  │ replica-N ─┘     │  │  ││  │  │
│  │  │  │  └────────────────────────┘  │   │  │  │                  │  │  ││  │  │
│  │  │  │                              │   │  │  │ JDBC_PING        │  │  ││  │  │
│  │  │  │ NSG                          │   │  │  │ cluster discovery│  │  ││  │  │
│  │  │  │ Allow: 5432 from             │   │  │  │ via DB table     │  │  ││  │  │
│  │  │  │        10.0.2.0/23           │   │  │  └──────────────────┘  │  ││  │  │
│  │  │  │ Deny:  all others            │   │  │          │             │  ││  │  │
│  │  │  └──────────────────────────────┘   │  │          │             │  ││  │  │
│  │  │                                     │  │   ACA Ingress          │  ││  │  │
│  │  │                                     │  │   (Envoy LB)           │  ││  │  │
│  │  │                                     │  │   TLS terminated here  │  ││  │  │
│  │  │                                     │  └──────────┬─────────────┘  ││  │  │
│  │  │                                     └─────────────┼────────────────┘│  │  │
│  │  │                                                   │                 │  │  │
│  │  │                          Private DNS Zone         │                 │  │  │
│  │  │        keycloak.private.postgres.database.azure.com                 │  │  │
│  │  │                                                   │                 │  │  │
│  │  └───────────────────────────────────────────────────┼─────────────────┘  │  │
│  │                                                      │                    │  │
│  │                                         Public HTTPS Endpoint             │  │
│  │                   keycloak.<env>.<region>.azurecontainerapps.io           │  │
│  │                                                      │                    │  │
│  └──────────────────────────────────────────────────────┼────────────────────┘  │
│                                                         │                       │
│                                               Internet Users                    │
│                                               Applications                      │
│                                               OAuth / OIDC                      │
└─────────────────────────────────────────────────────────────────────────────────┘
```


---

## HA Clustering Design

### Why JDBC_PING?

Azure Container Apps does **not** support UDP multicast, so JGroups' default `MPING` (multicast) discovery cannot be used. The options are:

| Discovery | Works in ACA? | Notes |
|---|---|---|
| MPING (UDP multicast) | ❌ No | ACA blocks multicast |
| DNS_PING | ⚠️ Unreliable | Requires headless K8s-style DNS — not exposed by ACA |
| JDBC_PING | ✅ Yes | Uses shared PostgreSQL table `JGROUPSPING` for member registry |
| AZURE_PING | ⚠️ Complex | Uses Azure Blob Storage; requires MSI + storage account; more moving parts |

**JDBC_PING** is chosen because:
- All replicas already share the same PostgreSQL database
- No extra Azure resources required
- No UDP/multicast dependencies
- Natively supported in Keycloak 26.x via `KC_CACHE_STACK=jdbc-ping`

### How it works

1. Keycloak 26.x ships `cache-ispn-jdbc-ping.xml` with JDBC_PING built in.
2. Setting `KC_CACHE_STACK=jdbc-ping` activates it automatically.
3. Each replica registers its TCP address in the `JGROUPSPING` table on startup.
4. Other replicas query the table to discover peers and form a JGroups TCP cluster.
5. Once clustered, Infinispan distributes session/token caches across all nodes.

### Key environment variables for clustering

| Variable | Value | Purpose |
|---|---|---|
| `KC_CACHE` | `ispn` | Use Infinispan distributed caches |
| `KC_CACHE_STACK` | `jdbc-ping` | Use JDBC_PING for JGroups discovery |
| `JAVA_OPTS_APPEND` | (see main.tf) | JGroups JDBC datasource + TCP bind settings |

---

## Deployment Guide

### 1. Prerequisites

```powershell
az login --use-device-code   
(**OR az login --tenant {your-Directory-ID} --use-device-code)
az account list --query "[].{Name:name, ID:id}" -o table
```
Copy your Subscription ID.

### 2. Configure `terraform/terraform.tfvars`

Edit the file and set:

| Variable | Description |
|---|---|
| `subscription_id` | Your Azure Subscription ID |
| `postgres_server_name` | **Globally unique** name (e.g. `keycloak-pg-yourname123`) |
| `postgres_admin_password` | Strong password (upper, lower, digit, special) |
| `keycloak_admin_password` | Strong Keycloak admin password |

### 3. Phase 1 — Initial Deploy (without fixed hostname)

Run the initial apply to create the networking, database, and container environment.

*Tip: In `terraform.tfvars`, set `min_replicas = 1` and `max_replicas = 1` for this phase.*


```powershell
cd terraform
terraform init
terraform plan
terraform apply                   
( or terraform apply -auto-approve )
```
Deployment takes approximately **15–20 minutes** (most time is PostgreSQL provisioning).

### 4. Get the Keycloak FQDN

```powershell
terraform output keycloak_fqdn
```

Copy the FQDN (e.g. `keycloak.redpebble-abc123.northeurope.azurecontainerapps.io`).

### 5. Phase 2 — Fix the Hostname

Open `terraform.tfvars` and set `keycloak_hostname` to the FQDN from above, then re-apply:

Enable HA: Set `min_replicas` = `2` and `max_replicas` = `5`.
Then apply the changes:
```powershell
terraform apply
( or terraform apply -auto-approve )
```

This enables `KC_HOSTNAME_STRICT=true` so Keycloak enforces the correct issuer URL in tokens.

### 6. Access Keycloak

```powershell
terraform output keycloak_admin_console_url
```

Default credentials:
- **Username**: value of `keycloak_admin_user` (default: `admin`)
- **Password**: value of `keycloak_admin_password`

### 7. Verify HA Cluster

Check that both replicas are running:

```powershell
az containerapp replica list `
  --name keycloak `
  --resource-group keycloak-poc-rg `
  --query "[].{Name:name, State:properties.runningState}" `
  -o table
```
Expected: 2+ rows, all `Running`.

Check that JGroups clustering is working in the logs:

```powershell
az containerapp logs show `
  --name keycloak `
  --resource-group keycloak-poc-rg `
  --follow --tail 200
```

Look for log entries like:
```
KC_CACHE_STACK=jdbc-ping
GMS: address=keycloak-xxx, cluster=ISPN
View: [keycloak-replica1|1] (2) [keycloak-replica1, keycloak-replica2]
```

The `View: [...] (2) [...]` line confirms two nodes have joined the Infinispan cluster.

### 8. Destroy Everything

```powershell
terraform destroy
( or terraform destroy -auto-approve )
```

---

## Operational Notes

### Stop / Start PostgreSQL (to save cost between sessions)

```powershell
# Stop
az postgres flexible-server stop `
  --resource-group keycloak-poc-rg `
  --name <postgres_server_name>

# Start
az postgres flexible-server start `
  --resource-group keycloak-poc-rg `
  --name <postgres_server_name>
```

### View Logs

```powershell
az containerapp logs show `
  --name keycloak `
  --resource-group keycloak-poc-rg `
  --follow --tail 100
```

### Scale Manually

```powershell
az containerapp update `
  --name keycloak `
  --resource-group keycloak-poc-rg `
  --min-replicas 3 `
  --max-replicas 5
```

---

## Production Readiness TODOs

| # | Item | Details |
|---|---|---|
| TODO-1 | **Secrets Management** | Store `postgres_admin_password` and `keycloak_admin_password` in **Azure Key Vault**. Reference via a User-Assigned Managed Identity instead of plaintext in tfvars. |
| TODO-2 | **PostgreSQL Zone-Redundant HA** | Enable `high_availability { mode = "ZoneRedundant" }` on the DB server. Requires a GeneralPurpose SKU (e.g. `GP_Standard_D2s_v3`) — Burstable (`B_*`) does **not** support HA. |
| TODO-3 | **Custom Domain + Managed TLS** | Set a custom domain on the Container App for a stable `keycloak_hostname` that doesn't change between deploys. |
| TODO-4 | **Azure Monitor / Log Analytics** | Wire the Container App Environment to a Log Analytics Workspace for structured log retention and alerting. |

---

## Useful References

- [Keycloak 26.x — Configuring distributed caches](https://www.keycloak.org/server/caching)
- [Keycloak — All configuration options](https://www.keycloak.org/server/all-config)
- [JGroups JDBC_PING (Forum thread)](https://forum.keycloak.org/t/keycloak-19-0-3-quarkus-ha-in-azure-jgroup-configuration-azure-ping/18200/8)
- [Azure Container Apps — Scaling & Replicas](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
- [Azure PostgreSQL Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview)

---

## HA Validation & Testing

Detailed testing for the High Availability of Keycloak while deployed on Azure Container Apps has been performed. Extensive tests validate clustering, replica failover, and session replication across all nodes. The complete step-by-step validation procedure — including pass/fail criteria for each test — is documented in the [**`testing-ha.md`**](../testing-ha.md) file.

The actual observed results from running these tests against a live deployment — including JGROUPSPING table snapshots, Infinispan log excerpts, and scale up/down evidence — are recorded in [**`testing-ha-results.md`**](../testing-ha-results.md).

---

## Design Decisions & ACA Constraints

To successfully deploy Keycloak 26.5.0 as a true HA cluster on Azure Container Apps, several non-obvious customizations were required to work around ACA's networking constraints:

| # | Decision | Reason |
|---|---|---|
| 1 | **JDBC_PING** over MPING/multicast | ACA blocks UDP multicast entirely. Setting `KC_CACHE_STACK=jdbc-ping` activates Keycloak's built-in `cache-ispn-jdbc-ping.xml` stack and uses the shared PostgreSQL table `JGROUPSPING` as a peer registry — no extra Azure resources (e.g. a Storage Account for AZURE_PING) needed. |
| 2 | `jgroups.bind.address=GLOBAL` | The default `SITE_LOCAL` caused JGroups to bind to the `169.254.x.x` link-local ACA sidecar interface instead of the VNet-routable IP (`10.0.2.x`), making inter-replica TCP communication impossible. `GLOBAL` forces the correct interface. |
| 3 | `KC_HTTP_ENABLED=true` + `KC_PROXY_HEADERS=xforwarded` | ACA terminates TLS externally via its Envoy ingress and forwards plain HTTP internally. Keycloak must trust the `X-Forwarded-*` headers to derive the correct public URL. |
| 4 | Two-phase hostname setup | The ACA-assigned FQDN is unknown before the first deploy. Phase 1 starts with `KC_HOSTNAME_STRICT=false` and no fixed hostname so Keycloak boots successfully. Phase 2 locks in the FQDN with `KC_HOSTNAME_STRICT=true` to enforce correct token issuer URLs. |
| 5 | `min_replicas = 2` | Enforces a real HA cluster so Infinispan distributed caches (sessions, authenticationSessions, clientSessions, etc.) are always replicated across nodes, preventing session loss on replica restarts. |



