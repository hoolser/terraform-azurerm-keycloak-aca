terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.26"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id            = var.subscription_id

  resource_provider_registrations = "none"

}

