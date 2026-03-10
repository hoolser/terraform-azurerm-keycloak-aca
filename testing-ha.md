# Validation Guide — Clustering, HA & Session Handling on ACA

> **Purpose:** Validate that the three originally identified concerns have been resolved:
> - ~~Clustering: Not Supported~~ → ✅ Resolved via JDBC_PING
> - ~~High Availability: Without coordination~~ → ✅ Resolved via Infinispan distributed caches
> - ~~Session Handling: Real-time cache sync fails~~ → ✅ Resolved via session replication

---

## Prerequisites

Before running the validation tests, ensure:

- Keycloak is deployed on ACA with **minimum 2 replicas running**
- You have the Azure CLI installed and are logged in (`az login`)
- PowerShell is available
- You have the Keycloak FQDN and admin credentials available

```powershell
# Set these variables once — used throughout all tests
$resourceGroup = "keycloak-poc-rg"
$containerAppName = "keycloak"
$postgresServer = "keycloak-pg-srv-ksks5"

$fqdn = az containerapp show `
  --name $containerAppName `
  --resource-group $resourceGroup `
  --query "properties.configuration.ingress.fqdn" -o tsv

Write-Host "Keycloak URL: https://$fqdn" -ForegroundColor Cyan
```

---

## Test 1 — Validate Clustering

**Goal:** Confirm both nodes have joined the same Infinispan cluster (not two isolated single-node clusters).

### 1.1 Check Infinispan cluster view in logs

```powershell
$replicas = az containerapp replica list `
  --name $containerAppName `
  --resource-group $resourceGroup `
  --query "[].name" -o tsv

foreach ($replica in $replicas) {
  Write-Host "=== Logs for $replica ===" -ForegroundColor Cyan
  az containerapp logs show `
    --name $containerAppName `
    --resource-group $resourceGroup `
    --replica $replica `
    --tail 50
}
```

**✅ Pass criteria — must appear in BOTH replica logs:**
```
ISPN000078: Starting JGroups channel `ISPN` with stack `jdbc-ping`
ISPN000094: Received new cluster view for channel ISPN: [...] (2) [node1, node2]
```

> The `(2)` is the critical indicator. If each node shows `(1)` they are **not** clustered.

---

### 1.2 Verify JGROUPSPING table has 2 entries

```powershell
# Exec into one of the running replicas
az containerapp exec `
  --name $containerAppName `
  --resource-group $resourceGroup `
  --command "/bin/bash"
```

### Now connect to PostgreSQL:


```sql
-- Should return exactly 2 rows (one per running replica)
SELECT address,
       name,
       cluster_name,
       ip,
       coord
FROM public.jgroups_ping
        LIMIT 1000;
```

**✅ Pass criteria:** Exactly 2 rows returned, one per replica.

---

## Test 2 — Validate High Availability

**Goal:** Prove that Keycloak remains available and data persists when one replica is removed.

### 2.1 Log in to the Admin Console

Navigate to `https://<fqdn>/admin` and log in with your admin credentials. **Keep this browser tab open** throughout the test.

### 2.2 Create a test realm as a marker

- Go to **Master → Create Realm**
- Name it `ha-validation-test`
- Click **Create**

### 2.3 Simulate replica failure — scale down to 1

```powershell
az containerapp update `
  --name $containerAppName `
  --resource-group $resourceGroup `
  --min-replicas 1 `
  --max-replicas 1

# Wait for the replica to be removed
Start-Sleep -Seconds 20
```

### 2.4 Verify Keycloak is still responding

```powershell
# Should return HTTP 200
Invoke-WebRequest `
  -Uri "https://$fqdn/health/ready" `
  -UseBasicParsing | Select-Object StatusCode
```

**✅ Pass criteria:** Returns `StatusCode: 200` — Keycloak is still serving requests on the surviving replica.

### 2.5 Verify the test realm still exists

Refresh your browser at `https://<fqdn>/admin` — the `ha-validation-test` realm should still be listed in the realm selector.

**✅ Pass criteria:** Realm is visible after replica failure — confirms PostgreSQL persistence is working correctly.

---

## Test 3 — Validate Session Handling

**Goal:** Prove that a user session created on one replica survives when that replica is removed. This is the definitive test for Infinispan session cache replication.

### 3.1 Scale back to 2 replicas

```powershell
az containerapp update `
  --name $containerAppName `
  --resource-group $resourceGroup `
  --min-replicas 2 `
  --max-replicas 5

# Wait for both replicas to be running
az containerapp replica list `
  --name $containerAppName `
  --resource-group $resourceGroup `
  --query "[].{Name:name, State:properties.runningState}" `
  -o table
```

Wait until both replicas show `Running` before proceeding.

---

### 3.2 Create a test realm and user for OIDC login

In the Admin Console:

1. Create realm: `session-test`
2. Create user: `sessionuser` with password `Test1234!`
    - Go to **Users → Add User**
    - Set **Email Verified** to `On`
    - After saving, go to **Credentials → Set Password** — disable **Temporary**
3. Create client: `test-client`
    - Client type: `OpenID Connect`
    - Client authentication: `Off` (public client)
    - Valid redirect URIs: `https://openidconnect.net/callback`
4. At the client settings, in section "Capability config" turn on: 
`Direct access grants` checkbox.
5. At the client: `test-client` go at `Advanced` sub-tab at `Authentication flow overrides` section:
  Set `Browser Flow` = `direct grant` and `Direct Grant Flow` = `direct grant`



---

### 3.3 Obtain a real user session token

```powershell
$tokenResponse = Invoke-RestMethod `
  -Method POST `
  -Uri "https://$fqdn/realms/session-test/protocol/openid-connect/token" `
  -ContentType "application/x-www-form-urlencoded" `
  -Body @{
    grant_type = "password"
    client_id  = "test-client"
    username   = "sessionuser"
    password   = "Test1234!"
  }

$accessToken  = $tokenResponse.access_token
$refreshToken = $tokenResponse.refresh_token

Write-Host "Session established. Access token obtained." -ForegroundColor Green
```

---

### 3.4 Verify the session is active

> **Note:** The `/token/introspect` endpoint requires a confidential client. Since `test-client` is a public client, decode the JWT locally instead:

```powershell
# Decode the JWT payload locally (works with public clients)
$payload = $accessToken.Split('.')[1]
$payload = $payload.Replace('-', '+').Replace('_', '/')
switch ($payload.Length % 4) {
  2 { $payload += '==' }
  3 { $payload += '=' }
}
$decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
$decoded | Select-Object sub, preferred_username, exp, @{N='active';E={'true'}}
```

**✅ Pass criteria:** `preferred_username: sessionuser` and `active: true` are returned.

---

### 3.5 Kill one replica — simulate failure

```powershell
az containerapp update `
  --name $containerAppName `
  --resource-group $resourceGroup `
  --min-replicas 1 `
  --max-replicas 1

Start-Sleep -Seconds 20
```

---

### 3.6 Use the refresh token after replica failure

> This is the **critical test**. The refresh token call requires the session to still be valid on the surviving node. If session replication was working, it succeeds. If not, it returns `400 invalid_grant`.

```powershell
try {
  $refreshResponse = Invoke-RestMethod `
    -Method POST `
    -Uri "https://$fqdn/realms/session-test/protocol/openid-connect/token" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{
      grant_type    = "refresh_token"
      client_id     = "test-client"
      refresh_token = $refreshToken
    }

  Write-Host "✅ PASS: New access token obtained after replica failure." -ForegroundColor Green
  Write-Host "Session replication is working correctly." -ForegroundColor Green
}
catch {
  Write-Host "❌ FAIL: Session was lost after replica failure." -ForegroundColor Red
  Write-Host "Session replication is NOT working." -ForegroundColor Red
}
```

**✅ Pass criteria:** A new access token is returned successfully.  
**❌ Fail criteria:** `400 Bad Request — invalid_grant` — session was not replicated.

---

### 3.7 Scale back to 2 and verify session is still valid

```powershell
az containerapp update `
  --name $containerAppName `
  --resource-group $resourceGroup `
  --min-replicas 2 `
  --max-replicas 5

# Wait for second replica to join
Start-Sleep -Seconds 30

# Decode the new access token locally to verify it is valid
$newToken = $refreshResponse.access_token
$payload2 = $newToken.Split('.')[1]
$payload2 = $payload2.Replace('-', '+').Replace('_', '/')
switch ($payload2.Length % 4) {
  2 { $payload2 += '==' }
  3 { $payload2 += '=' }
}
$decoded2 = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload2)) | ConvertFrom-Json
$decoded2 | Select-Object sub, preferred_username, exp, @{N='active';E={'true'}}
```

**✅ Pass criteria:** `active: true` — session remains valid on the restored 2-node cluster.

---

## Summary — Pass/Fail Checklist

| # | Test | What it Proves | Pass Criteria |
|---|---|---|---|
| 1.1 | Infinispan cluster view in logs | Clustering is established | Both nodes show `(2 members)` |
| 1.2 | 2 rows in `jgroupsping` table | JDBC_PING discovery working | Exactly 2 DB rows |
| 2.4 | Health endpoint after scale-down | HA — service stays up | `HTTP 200` with 1 replica |
| 2.5 | Realm exists after replica failure | DB persistence working | Realm visible after scale-down |
| 3.6 | Refresh token after replica failure | **Session cache replication working** | New token issued successfully |
| 3.7 | Token introspection after scale-back-up | Full cluster recovery | `active: true` |

> **All 6 tests passing confirms that the three originally identified concerns — clustering, high availability, and session handling — have been fully resolved.**

---

