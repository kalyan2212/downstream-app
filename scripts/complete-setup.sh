#!/bin/bash
# complete-setup.sh
# ============================================================
# Run this ONCE from Azure Cloud Shell (or any machine that
# can reach Azure and GitHub).
#
# What it does in one shot:
#   1. Logs you into Azure interactively (device code in Cloud Shell)
#   2. Creates an Azure Service Principal for CI
#   3. Creates Terraform remote-state storage
#   4. Generates an SSH key pair for VM access
#   5. Creates / updates ALL required GitHub Actions secrets
#   6. Triggers the Deploy All-in-One workflow
#
# Prerequisites:
#   - Azure CLI  (pre-installed in Azure Cloud Shell)
#   - GitHub CLI  (pre-installed in Azure Cloud Shell)
#   - A GitHub PAT with "Secrets: Read and write" on this repo
#
# Usage (in Azure Cloud Shell):
#   curl -sSL https://raw.githubusercontent.com/kalyan2212/downstream-app/copilot/deploy-app-to-azure/scripts/complete-setup.sh | bash
#
#   OR clone the repo and run:
#   bash scripts/complete-setup.sh
# ============================================================

set -euo pipefail

REPO="kalyan2212/downstream-app"
BRANCH="copilot/deploy-app-to-azure"
TF_RG="tfstate-rg"
TF_LOCATION="eastus"
TF_CONTAINER="tfstate"
APP_RG="downstream-rg"
DB_PASSWORD="DownstreamDB@2024!"
FLASK_SECRET="flask-downstream-secret-$(openssl rand -hex 8)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo ""
echo "============================================================"
echo "  downstream-app  •  Complete Azure Setup"
echo "  Repo: $REPO  |  Branch: $BRANCH"
echo "============================================================"
echo ""

# ── 0. Check tools ───────────────────────────────────────────
command -v az  >/dev/null || die "Azure CLI not found. Run in Azure Cloud Shell."
command -v gh  >/dev/null || die "GitHub CLI not found. Run in Azure Cloud Shell."
command -v ssh-keygen >/dev/null || die "ssh-keygen not found."

# ── 1. Get GitHub PAT ────────────────────────────────────────
if [ -z "${GITHUB_PAT:-}" ]; then
    echo ""
    warn "Need a GitHub Personal Access Token with 'Secrets: Read and write' permission."
    warn "Create one at: https://github.com/settings/tokens"
    echo -n "  Enter GitHub PAT: "
    read -rs GITHUB_PAT
    echo ""
fi
[ -z "$GITHUB_PAT" ] && die "GitHub PAT is required."

# Authenticate GitHub CLI
echo "$GITHUB_PAT" | gh auth login --with-token 2>/dev/null || die "GitHub PAT authentication failed."
success "GitHub CLI authenticated"

# ── 2. Azure login ───────────────────────────────────────────
info "Logging into Azure..."
echo ""
echo "  If running interactively (Cloud Shell), a browser/device code will appear."
echo "  In Cloud Shell, this opens automatically."
echo ""
# In Cloud Shell, az login opens a browser automatically
# On a plain terminal, it shows the device code
az login --tenant common --allow-no-subscriptions 2>&1 | grep -E "code|https|browser|Logged|subscription" || true

SUB_ID=$(az account list --query "[?state=='Enabled'] | [0].id" -o tsv)
SUB_NAME=$(az account list --query "[?state=='Enabled'] | [0].name" -o tsv)
TENANT_ID=$(az account list --query "[?state=='Enabled'] | [0].tenantId" -o tsv)
az account set --subscription "$SUB_ID"
success "Azure: subscription '$SUB_NAME' ($SUB_ID)"

# ── 3. Terraform state storage ───────────────────────────────
info "Setting up Terraform state storage..."

EXISTING_SA=$(az storage account list \
    --resource-group "$TF_RG" \
    --query "[?starts_with(name,'tfstate')].name | [0]" \
    -o tsv 2>/dev/null || true)

if [ -n "$EXISTING_SA" ] && [ "$EXISTING_SA" != "None" ]; then
    TF_STORAGE="$EXISTING_SA"
    success "Reusing existing storage account: $TF_STORAGE"
else
    SUFFIX=$(openssl rand -hex 4)
    TF_STORAGE="tfstate${SUFFIX}"
    az group create --name "$TF_RG" --location "$TF_LOCATION" --output none 2>/dev/null || true
    az storage account create \
        --name "$TF_STORAGE" \
        --resource-group "$TF_RG" \
        --location "$TF_LOCATION" \
        --sku Standard_LRS \
        --min-tls-version TLS1_2 \
        --output none
    az storage container create \
        --name "$TF_CONTAINER" \
        --account-name "$TF_STORAGE" \
        --output none
    success "Created storage account: $TF_STORAGE"
fi

# ── 4. Service Principal ─────────────────────────────────────
info "Creating Azure Service Principal..."
SP_NAME="downstream-app-ci-$(date +%s)"

SP_JSON=$(az ad sp create-for-rbac \
    --name "$SP_NAME" \
    --role Contributor \
    --scopes "/subscriptions/$SUB_ID" \
    --output json)

ARM_CLIENT_ID=$(echo "$SP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['appId'])")
ARM_CLIENT_SECRET=$(echo "$SP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
success "Service principal '$SP_NAME' created (appId: $ARM_CLIENT_ID)"

# ── 5. SSH key pair ──────────────────────────────────────────
info "Generating SSH key pair..."
ssh-keygen -t ed25519 -f /tmp/downstream_deploy_ci -N "" -C "downstream-ci-$(date +%Y%m%d)" -q
SSH_PUBLIC_KEY=$(cat /tmp/downstream_deploy_ci.pub)
success "SSH key pair generated"

# ── 6. Set GitHub secrets ────────────────────────────────────
info "Setting GitHub Actions secrets..."

set_secret() {
    gh secret set "$1" --repo "$REPO" --body "$2"
    echo "    ✓ $1"
}

set_secret "ARM_CLIENT_ID"       "$ARM_CLIENT_ID"
set_secret "ARM_CLIENT_SECRET"   "$ARM_CLIENT_SECRET"
set_secret "ARM_TENANT_ID"       "$TENANT_ID"
set_secret "ARM_SUBSCRIPTION_ID" "$SUB_ID"
set_secret "TF_STORAGE_ACCOUNT"  "$TF_STORAGE"
set_secret "DB_PASSWORD"         "$DB_PASSWORD"
set_secret "FLASK_SECRET"        "$FLASK_SECRET"
set_secret "SSH_PUBLIC_KEY"      "$SSH_PUBLIC_KEY"
# Private key stored as base64 to preserve newlines
set_secret "SSH_PRIVATE_KEY_B64" "$(base64 -w0 /tmp/downstream_deploy_ci)"

success "All GitHub secrets configured"

# ── 7. Save private key locally ──────────────────────────────
mkdir -p ~/.ssh
cp /tmp/downstream_deploy_ci ~/.ssh/downstream_deploy_ci
chmod 600 ~/.ssh/downstream_deploy_ci
echo ""
warn "SSH private key saved to: ~/.ssh/downstream_deploy_ci"
warn "Use this to SSH into VMs after deployment:"
warn "  ssh -i ~/.ssh/downstream_deploy_ci kalyan2212@<APP_IP>"
echo ""

# ── 8. Trigger deploy workflow ───────────────────────────────
info "Triggering Deploy All-in-One workflow..."

# Wait briefly for secrets to propagate
sleep 3

DISPATCH_RESULT=$(gh workflow run "Deploy All-in-One" \
    --repo "$REPO" \
    --ref "$BRANCH" \
    --field tf_action=apply 2>&1)

if echo "$DISPATCH_RESULT" | grep -q "error\|Error"; then
    warn "Could not auto-trigger workflow: $DISPATCH_RESULT"
    echo ""
    echo "  Trigger manually:"
    echo "  https://github.com/$REPO/actions/workflows/deploy-all.yml"
else
    success "Deploy workflow triggered!"
    echo ""
    echo "  Monitor progress at:"
    echo "  https://github.com/$REPO/actions/workflows/deploy-all.yml"
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "============================================================"
echo -e "  ${GREEN}Setup complete!${NC}"
echo ""
echo "  GitHub secrets set:    9"
echo "  Subscription:          $SUB_NAME"
echo "  Service Principal:     $SP_NAME"
echo "  Terraform state:       $TF_STORAGE (eastus)"
echo ""
echo "  The Deploy All-in-One workflow is running."
echo "  It will create 2 Azure VMs and confirm health in ~12 min."
echo ""
echo "  Once deployed, check:"
echo "  - App URL:   Look for 'App URL' in the workflow log"
echo "  - Health:    GET http://<APP_IP>/health"
echo "  - SSH:       ssh -i ~/.ssh/downstream_deploy_ci kalyan2212@<APP_IP>"
echo "============================================================"
echo ""
