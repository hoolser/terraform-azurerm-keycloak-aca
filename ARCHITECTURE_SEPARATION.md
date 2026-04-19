# Architecture: Separated Key Vault & Keycloak Deployments

## Overview

The infrastructure has been **refactored into two independent Terraform configurations** with separate state management:

```
┌─────────────────────────────────────────────────────────────────────┐
│ Repository                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────────┐      ┌──────────────────────────┐    │
│  │ terraform-keyvault/      │      │ terraform/               │    │
│  │ (Key Vault Config)       │      │ (Keycloak Config)        │    │
│  │                          │      │                          │    │
│  │ - Creates Key Vault      │      │ - Creates ACA            │    │
│  │ - Creates 4 secrets      │      │ - Creates PostgreSQL     │    │
│  │ - Independent state      │      │ - References Key Vault   │    │
│  │ - Deploy FIRST ───────┐  │      │ - Deploy SECOND          │    │
│  │                       └──┼──────┤ (depends on Key Vault)   │    │
│  │                          │      │                          │    │
│  └──────────────────────────┘      └──────────────────────────┘    │
│                                                                      │
│  terraform-keyvault/               terraform/                      │
│  ├── main.tf                        ├── main.tf                     │
│  ├── variables.tf                   ├── keyvault.tf (DATA SOURCE)  │
│  ├── outputs.tf                     ├── variables.tf                │
│  ├── dev.tfvars                     ├── outputs.tf                  │
│  ├── prod.tfvars                    ├── dev.tfvars                  │
│  ├── terraform.tfstate              ├── prod.tfvars                 │
│  └── README.md                      └── terraform.tfstate           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---
