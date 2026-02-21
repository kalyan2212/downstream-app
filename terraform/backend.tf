terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state stored in Azure Blob Storage.
  # The storage account / container are pre-created by scripts/bootstrap_tfstate.sh
  # and the values are passed via -backend-config in CI or via a local backend.hcl.
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    container_name       = "tfstate"
    key                  = "downstream.tfstate"
    # storage_account_name is supplied at init time via -backend-config
  }
}

provider "azurerm" {
  features {}
}
