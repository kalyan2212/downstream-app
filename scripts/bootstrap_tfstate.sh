#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# bootstrap_tfstate.sh
#
# Run this ONCE before the first GitHub Actions deployment.
# It creates an Azure Storage Account to hold Terraform remote state.
#
# Prerequisites:
#   - Azure CLI installed and logged in:  az login
#   - Correct subscription selected:      az account set --subscription <ID>
#
# Usage:
#   bash scripts/bootstrap_tfstate.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RESOURCE_GROUP="tfstate-rg"
LOCATION="eastus"
# Storage account names must be globally unique, 3-24 chars, lowercase+digits only
STORAGE_ACCOUNT="tfstate$(openssl rand -hex 4)"
CONTAINER="tfstate"

echo "Creating resource group: $RESOURCE_GROUP"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

echo "Creating storage account: $STORAGE_ACCOUNT"
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --encryption-services blob \
  --min-tls-version TLS1_2

echo "Creating blob container: $CONTAINER"
az storage container create \
  --name "$CONTAINER" \
  --account-name "$STORAGE_ACCOUNT"

echo ""
echo "============================================================"
echo "  Done!  Add this secret to your GitHub repository:"
echo ""
echo "  Secret name : TF_STORAGE_ACCOUNT"
echo "  Secret value: $STORAGE_ACCOUNT"
echo ""
echo "  GitHub → Settings → Secrets and variables → Actions → New"
echo "============================================================"
