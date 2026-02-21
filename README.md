# downstream-app
Downstream data management web app – Flask + PostgreSQL, deployed to Azure VM via Terraform + GitHub Actions.

## Architecture (low-cost, no HA)
- **1× App VM** (`Standard_B1s`) – nginx → gunicorn → Flask, direct public IP
- **1× DB VM**  (`Standard_B1s`) – standalone PostgreSQL 15 (private subnet)
- No load balancer, no replicas — ~$15–20/month total

---

## Deploy in One Command (Azure Cloud Shell)

> **Why Cloud Shell?** The Azure account (`kbdazure@gmail.com`) is a Microsoft personal account (MSA). Direct username/password login from CI is blocked by Microsoft. Azure Cloud Shell is already authenticated, so no extra login is needed.

### Step 1 — Create a GitHub PAT (classic token)

> ⚠️ Use a **classic** token — fine-grained tokens sometimes fail with `gh secret set`.

1. Go to: https://github.com/settings/tokens/new?type=classic  
   - Token name: `downstream-deploy`  
   - Expiration: 90 days  
   - Check the **`repo`** scope (the top-level checkbox — this includes secrets access)
2. Click **Generate token**, then copy it (starts with `ghp_...`)

### Step 2 — Open Azure Cloud Shell

Go to **[shell.azure.com](https://shell.azure.com)** (already logged in as `kbdazure@gmail.com`).

### Step 3 — Run the setup script

```bash
curl -sSL https://raw.githubusercontent.com/kalyan2212/downstream-app/copilot/deploy-app-to-azure/scripts/complete-setup.sh \
  | GITHUB_PAT=ghp_YOUR_TOKEN_HERE bash
```

Replace `ghp_YOUR_TOKEN_HERE` with the PAT from Step 1.

**The script (~5 min):**
- Validates your PAT against the GitHub API
- Uses the existing Cloud Shell Azure session (no re-login needed)
- Creates a Service Principal + Terraform state storage + SSH keys
- Sets 9 GitHub secrets, triggers the Deploy workflow

**Tip:** If you get a PAT error, check the token has the full `repo` scope selected.

---

## What the Deploy Workflow Does

After setup, the **Deploy All-in-One** workflow (~12 min):
1. `terraform apply` — creates App VM + DB VM
2. Cloud-init installs PostgreSQL, Flask, nginx on the VMs
3. Health check confirms `GET /health → {"status":"ok","db":"reachable"}`

Monitor at: https://github.com/kalyan2212/downstream-app/actions/workflows/deploy-all.yml

---

## Health Endpoint
```
GET http://<APP_IP>/health
→ {"status": "ok", "db": "reachable"}
```

## SSH into VMs
```bash
# Key is saved to ~/.ssh/downstream_deploy_ci by the setup script
ssh -i ~/.ssh/downstream_deploy_ci kalyan2212@<APP_IP>
```

## Local Development
```bash
pip install -r requirements.txt
DB_HOST=localhost DB_PASSWORD=yourpass python web_app.py
```

