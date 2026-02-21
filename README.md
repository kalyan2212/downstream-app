# downstream-app
Downstream data management web app – Flask + PostgreSQL, deployed to Azure VM via Terraform + GitHub Actions.

## Architecture (low-cost, no HA)
- **1× App VM** (`Standard_B1s`) – nginx → gunicorn → Flask, with a direct public IP
- **1× DB VM**  (`Standard_B1s`) – standalone PostgreSQL 15 (private subnet)
- No load balancer, no replicas — minimises cost (~$15–20/month total)

## One-Time Setup (Bootstrap)

### Step 1 – Create a GitHub PAT
1. Go to **GitHub → Settings → Developer Settings → Personal Access Tokens → Fine-grained tokens**
2. Create a token with **Secrets: Read and write** permission on this repo
3. Copy the token

### Step 2 – Run the Bootstrap Workflow
1. Go to **Actions → Bootstrap - First-Time Azure Setup → Run workflow**
2. Fill in:
   | Input | Value |
   |-------|-------|
   | Azure login email | your Azure email |
   | Azure login password | your Azure password |
   | GitHub PAT | token from Step 1 |
   | DB password | choose a strong password |
   | Flask secret | choose a random string |
3. Click **Run workflow**

This automatically:
- Logs into Azure and selects the first available subscription
- Creates a Storage Account for Terraform remote state
- Creates an Azure Service Principal with Contributor role
- Generates an SSH key pair for VM access
- Sets all required GitHub Actions secrets

### Step 3 – Deploy
Once bootstrap completes, go to **Actions → Deploy to Azure → Run workflow** (or push to `main`).

The deploy workflow:
1. `terraform apply` – provisions the App VM and DB VM
2. SSH code push – deploys the latest app code
3. Health check – polls `/health` until the app responds `200 OK`

## Local Development
```bash
pip install -r requirements.txt
DB_HOST=localhost DB_PASSWORD=yourpass python web_app.py
# Open http://localhost:5001
```

## Health Endpoint
`GET /health` – returns `{"status": "ok", "db": "reachable"}` when healthy.
