# Azure Key Vault — Independent Terraform Configuration

## Overview

This directory contains a **separate Terraform configuration** for managing Azure Key Vault and its secrets independently of the Keycloak Container App deployment.

**Key benefit:** Deploy, update, and destroy the Key Vault separately without affecting the Keycloak application.

---

## Directory Structure

```
terraform-keyvault/
├── main.tf           # Key Vault resources
├── variables.tf      # Input variables
├── outputs.tf        # Output secret references
├── dev.tfvars        # Dev environment values
├── prod.tfvars       # Prod environment values
└── README.md         # This file
```

---


### Step 1: Configure `terraform-keycloak/{env}.tfvars`

Edit the file and set:

| Variable | Description |
|---|---|
| `subscription_id` | Your Azure Subscription ID |
| `postgres_admin_password` | Strong password (upper, lower, digit, special) |
| `keycloak_admin_password` | Strong Keycloak admin password |
| `purge_kv_on_destroy` | `true` (dev) = immediate purge; `false` (prod) = soft-delete |
| `recover_kv_on_apply` | `true` = auto-recover if soft-deleted; `false` = fail if exists |

**Environment-Specific Settings:**

**Development (`dev.tfvars`):**
```hcl
purge_kv_on_destroy  = true   # Purge immediately for fast re-creation
recover_kv_on_apply  = true   # Recover from accidental deletion
```

**Production (`prod.tfvars`):**
```hcl
purge_kv_on_destroy  = false  # Keep vault for 7-day recovery window (safety)
recover_kv_on_apply  = true   # Recover if accidentally deleted
```

---

## Step 2: Deploy Key Vault (THIS directory)

```powershell
cd terraform-keyvault
terraform init
terraform plan -var-file="dev.tfvars"
terraform apply -var-file="dev.tfvars"
```

**IMPORTANT: Key Vault names are GLOBALLY UNIQUE**

Key Vault names must be unique across **all Azure subscriptions worldwide**. If you get an error like:

```
Error: VaultAlreadyExists - The vault name 'key-vault-dev' is already in use
```

**Solution:** Update the `key_vault_name` in your `.tfvars` file with a unique suffix:

```terraform
# e.g.: Use random suffix
key_vault_name = "vault-dev-abc123xyz"
```

Or manually purge the soft-deleted vault if you own it.

---

**What gets created:**
- Resource group for Key Vault
- Azure Key Vault (encrypted, purge-protected)
- 4 secrets:
  - `postgres-admin-user`
  - `postgres-admin-password`
  - `keycloak-admin-user`
  - `keycloak-admin-password`

**Output:**
- Key Vault URI (for use by Container App)
- Versionless secret IDs (for Container App to reference)

---

## Destroy Key Vault

```powershell
cd ../terraform-keyvault
terraform destroy -var-file="dev.tfvars"
```

**Behavior depends on `purge_kv_on_destroy` setting:**

| Setting | Dev Behavior | Prod Behavior |
|---------|------|---------|
| `purge_kv_on_destroy = true` | Vault **immediately purged** (can recreate with same name) | - |
| `purge_kv_on_destroy = false` | - | Vault **soft-deleted** (recoverable for 7 days) |


---

## Secrets Management

### View Secrets

```powershell
# List all secret names
az keyvault secret list --vault-name tasos-vault-dev --query "[].name"

# Get a secret value (requires Key Vault Administrator role)
az keyvault secret show --vault-name tasos-vault-dev --name postgres-admin-password --query "value"
```

### Rotate a Secret

```powershell
# Update a secret (no Terraform re-apply needed)
az keyvault secret set \
  --vault-name tasos-vault-dev \
  --name postgres-admin-password \
  --value "NewSecurePassword789!"

# Container App automatically picks up the new version
# (uses versionless secret ID: vault_uri/secrets/name/)
```

### Manual Secret Creation

If secrets don't exist or need to be created manually:

```powershell
az keyvault secret set \
  --vault-name tasos-vault-dev \
  --name postgres-admin-user \
  --value "keycloakadmin"

az keyvault secret set \
  --vault-name tasos-vault-dev \
  --name postgres-admin-password \
  --value "SecurePassword123!"

az keyvault secret set \
  --vault-name tasos-vault-dev \
  --name keycloak-admin-user \
  --value "admin"

az keyvault secret set \
  --vault-name tasos-vault-dev \
  --name keycloak-admin-password \
  --value "AdminPassword456!"
```

---

## RBAC Permissions

### Required for Terraform

Azure user needs one of:
- **Key Vault Administrator** (for this configuration)
- **Owner** (on subscription)

---

## Terraform Outputs

After deployment, view outputs:

```powershell
terraform output
```

**Output:**
- `key_vault_id`: Key Vault resource ID
- `key_vault_uri`: URI for secret access (`https://vault.azure.net/`)
- `key_vault_name`: Key Vault name
- `secret_references`: Versionless secret IDs for Container App

---

## Common Operations

### Plan Changes

```powershell
terraform plan -var-file="dev.tfvars"
```

### Apply Updates

```powershell
terraform apply -var-file="dev.tfvars"
```

### Switch Environment

```powershell
# View current state
terraform state list

# Deploy to production
terraform apply -var-file="prod.tfvars"

# Destroy dev
terraform destroy -var-file="dev.tfvars"
```

### Check Terraform State

```powershell
# Show Key Vault details from state
terraform state show azurerm_key_vault.keycloak

# Show secrets from state (secrets not in state, only URIs)
terraform state show azurerm_key_vault_secret.postgres_admin_password
```

---

## Related Documentation

- **Keycloak Configuration:** See `../terraform/README.md`
- **Azure Key Vault:** https://learn.microsoft.com/en-us/azure/key-vault/
- **Managed Identities:** https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/
- **RBAC:** https://learn.microsoft.com/en-us/azure/role-based-access-control/

---
