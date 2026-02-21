terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }

  # Remote state in Azure Blob Storage.
  # Bootstrapped by the bootstrap.yml workflow on first run.
  # ARM_* env vars supply authentication (set by bootstrap workflow).
  backend "azurerm" {
    resource_group_name = "tfstate-rg"
    container_name      = "tfstate"
    key                 = "downstream.tfstate"
    # storage_account_name passed via -backend-config at init time
  }
}

provider "azurerm" {
  features {}
  # Authenticates via ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID
  # environment variables set in GitHub Actions workflows.
}
