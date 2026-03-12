# HA Validation Results — Scale Up / Down Test Evidence

## Verify HA Cluster

We checked that both replicas are running:

Run:
```powershell
az containerapp replica list `
  --name keycloak `
  --resource-group keycloak-poc-rg `
  --query "[].{Name:name, State:properties.runningState}" `
  -o table
```

Result:

| Name | State |
|---|---|
| `keycloak--0000001-79559f95c9-sfpff` | Running |
| `keycloak--0000001-79559f95c9-jszjt` | Running |

---

Keycloak nodes running simultaneously as a verified Infinispan cluster (2 members) confirmed in logs.

From 1st replica:
```
2026-03-09T07:55:15.1550532Z stdout F 2026-03-09 07:55:15,154 INFO  [org.infinispan.LIFECYCLE] () [Context=actionTokens] ISPN100002: Starting rebalance with members [keycloak--0000001-79559f95c9-sfpff-12314, keycloak--0000001-79559f95c9-jszjt-95], phase READ_OLD_WRITE_ALL, topology id 13
```

From 2nd replica:
```
2026-03-09T07:55:15.2896648Z stdout F 2026-03-09 07:55:15,288 INFO  [org.infinispan.CLUSTER] () [Context=actionTokens] ISPN100010: Finished rebalance with members [keycloak--0000001-79559f95c9-sfpff-12314, keycloak--0000001-79559f95c9-jszjt-95], topology id 16
```

---

We checked that JGroups clustering is working in the logs:

Run:
```powershell
az containerapp logs show `
  --name keycloak `
  --resource-group keycloak-poc-rg `
  --follow --tail 200
```

Result:
```
INFO  [org.infinispan.CLUSTER] () ISPN000094: Received new cluster view for channel ISPN: [keycloak--0000001-79559f95c9-sfpff-12314|3] (2) [keycloak--0000001-79559f95c9-sfpff-12314, keycloak--0000001-79559f95c9-jszjt-95]
```

---

At the `JGROUPSPING` table in DB, in trials we validate Session Handling and that clustering still happens even if we scale down/up the min/max replicas of Azure Container Apps.

For example, initially there were the following 2 rows at the DB:

**Before:**

| own_addr | node_name | cluster_name | physical_addr | is_coord |
|---|---|---|---|---|
| `uuid://…-0002` | `keycloak--0000001-7bdcbd5545-vjgh6-65089` | `ISPN` | `100.100.193.124:7800` | `True` |
| `uuid://…-0003` | `keycloak--0000001-7bdcbd5545-c7wsx-4885` | `ISPN` | `100.100.195.73:7800` | `False` |

After updating the replicas at ACA from 2–5 to 1–1, the new replica from the new revision joined the table initially:

**Initially (transitional state):**

| own_addr | node_name | cluster_name | physical_addr | is_coord |
|---|---|---|---|---|
| `uuid://…-0002` | `keycloak--0000001-7bdcbd5545-vjgh6-65089` | `ISPN` | `100.100.193.124:7800` | `True` |
| `uuid://…-0003` | `keycloak--0000001-7bdcbd5545-c7wsx-4885` | `ISPN` | `100.100.195.73:7800` | `False` |
| `uuid://…-0005` | `keycloak--0000002-85f7564cd9-fg6np-33053` | `ISPN` | `100.100.197.41:7800` | `False` |

After some time, the old replicas from the old revision get removed from the DB (with **no downtime**):

**After:**

| own_addr | node_name | cluster_name | physical_addr | is_coord |
|---|---|---|---|---|
| `uuid://…-0005` | `keycloak--0000002-85f7564cd9-fg6np-33053` | `ISPN` | `100.100.197.41:7800` | `True` |

Note that after this change the session persisted — no re-authentication was prompted in the browser, the session was still active.

So, during this rebalancing we confirm that the session and the data of Keycloak remain maintained.

We also performed changes to the replicas from 1–1 to 2–5 (scale up) with respectively successful results.
