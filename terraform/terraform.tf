terraform {
  required_version = ">= 1.0"

  # Uncomment below to use Azure Storage for remote state
  # backend "azurerm" {
  #   resource_group_name  = "rg-name"
  #   storage_account_name = "storage-account"
  #   container_name       = "tfstate"
  #   key                  = "authentik/terraform.tfstate"
  # }
}
