terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }

  # Remote state in Azure Blob Storage.
  # Storage account is pre-created by scripts/bootstrap_tfstate.sh
  # Value is passed via -backend-config in CI.
  backend "azurerm" {
    resource_group_name = "tfstate-rg"
    container_name      = "tfstate"
    key                 = "downstream.tfstate"
    # storage_account_name supplied at init time via -backend-config
  }
}

provider "azurerm" {
  features {}
}
