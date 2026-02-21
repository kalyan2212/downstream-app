# downstream-app
Downstream data management web app – Flask + PostgreSQL, deployed to Azure VM via Terraform + GitHub Actions.

## Architecture (low-cost, no HA)
- **1× App VM** (`Standard_B1s`) – nginx → gunicorn → Flask, direct public IP
- **1× DB VM**  (`Standard_B1s`) – standalone PostgreSQL 15 (private subnet)
- No load balancer, no replicas — ~$15–20/month total

## Deployment (Two-Step Process)

### Step 1 – Bootstrap (one time only)

> **Required for Microsoft personal accounts (kbdazure@gmail.com).**
> Username/password login is blocked by Microsoft for MSA accounts.
> The Bootstrap workflow uses **Device Code** login instead.

1. Go to **Actions → Bootstrap - First-Time Azure Setup → Run workflow**
2. Enter a GitHub PAT with **Secrets: Read and write** permission
3. Click **Run workflow**
4. **Watch the logs** — you will see:
   ```
   To sign in, use a web browser to open https://microsoft.com/devicelogin
   and enter the code XXXXXXXX
   ```
5. Open that URL in your browser, enter the code, and sign in
6. The workflow will automatically:
   - Select your Azure subscription
   - Create a tfstate storage account
   - Create a Service Principal with Contributor role
   - Generate an SSH key pair
   - Store all credentials as GitHub secrets

### Step 2 – Deploy

1. Go to **Actions → Deploy All-in-One → Run workflow**
2. Select branch: `copilot/deploy-app-to-azure`
3. Click **Run workflow** (no inputs needed — uses secrets from Step 1)

The workflow will:
- `terraform apply` — creates App VM + DB VM
- Cloud-init sets up PostgreSQL, Flask, nginx automatically
- Health check confirms `GET /health → {"status":"ok"}`

## Health Endpoint
`GET /health` → `{"status": "ok", "db": "reachable"}` (HTTP 200)

## Local Development
```bash
pip install -r requirements.txt
DB_HOST=localhost DB_PASSWORD=yourpass python web_app.py
```
