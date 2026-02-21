terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }

  # Remote state in Azure Blob Storage.
  # Bootstrapped by the deploy-all.yml workflow on first run.
  backend "azurerm" {
    resource_group_name = "tfstate-rg"
    container_name      = "tfstate"
    key                 = "downstream.tfstate"
    # storage_account_name passed via -backend-config at init time
    # use_azuread_auth = true (uses az login credentials)
  }
}

provider "azurerm" {
  features {}
  # Authenticates using Azure CLI credentials (az login)
  # No ARM_CLIENT_ID / ARM_CLIENT_SECRET needed
  use_cli = true
}
