#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# App VM cloud-init  –  installs nginx + gunicorn + flask app
# Template variables (filled by Terraform templatefile()):
#   db_host, db_name, db_user, db_password, flask_secret,
#   upstream_url, api_key, github_repo, admin_username
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
exec > /var/log/cloud-init-app.log 2>&1

echo "[$(date)] Starting app VM setup..."

# ── System packages ──────────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-pip python3-venv nginx git curl

# ── Clone repo ───────────────────────────────────────────────────────────────
APP_DIR=/opt/downstream-app
mkdir -p "$APP_DIR"

# Retry git clone up to 5 times (might need a moment after VM comes up)
for attempt in 1 2 3 4 5; do
  git clone ${github_repo} "$APP_DIR" && break || true
  echo "Git clone attempt $attempt failed, retrying in 15s..."
  sleep 15
done

cd "$APP_DIR"

# ── Python virtual environment ───────────────────────────────────────────────
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt

# ── Environment file ─────────────────────────────────────────────────────────
cat > "$APP_DIR/.env" << ENVEOF
DB_HOST=${db_host}
DB_PORT=5432
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
FLASK_SECRET=${flask_secret}
UPSTREAM_URL=${upstream_url}
API_KEY=${api_key}
ENVEOF
chmod 600 "$APP_DIR/.env"

# ── Systemd service for gunicorn ─────────────────────────────────────────────
cat > /etc/systemd/system/downstream.service << 'SVCEOF'
[Unit]
Description=Downstream Flask App
After=network-online.target
Wants=network-online.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/opt/downstream-app
EnvironmentFile=/opt/downstream-app/.env
ExecStart=/opt/downstream-app/venv/bin/gunicorn \
    --workers 4 \
    --bind 127.0.0.1:5001 \
    --access-logfile /var/log/downstream-access.log \
    --error-logfile /var/log/downstream-error.log \
    web_app:app
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

# ── Nginx reverse proxy ───────────────────────────────────────────────────────
cat > /etc/nginx/sites-available/downstream << 'NGXEOF'
server {
    listen 80 default_server;

    location / {
        proxy_pass         http://127.0.0.1:5001;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_read_timeout 120;
    }
}
NGXEOF

ln -sf /etc/nginx/sites-available/downstream /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# ── Permissions ───────────────────────────────────────────────────────────────
chown -R www-data:www-data "$APP_DIR"

# ── Wait for PostgreSQL primary, then init DB schema ─────────────────────────
echo "[$(date)] Waiting for PostgreSQL at ${db_host}:5432..."
for i in $(seq 1 30); do
  if python3 -c "
import psycopg2, sys, os
try:
    conn = psycopg2.connect(host='${db_host}', port=5432,
           dbname='${db_name}', user='${db_user}', password='${db_password}')
    conn.close()
    sys.exit(0)
except Exception as e:
    print(e)
    sys.exit(1)
" 2>/dev/null; then
    echo "[$(date)] PostgreSQL is reachable."
    break
  fi
  echo "  attempt $i/30 – not ready yet, sleeping 15s..."
  sleep 15
done

# Run init_db only once (use a flag file)
if [ ! -f /opt/downstream-app/.db_initialized ]; then
  DB_HOST=${db_host} DB_NAME=${db_name} DB_USER=${db_user} \
  DB_PASSWORD=${db_password} \
    /opt/downstream-app/venv/bin/python - << 'PYEOF'
from web_app import init_db
init_db()
PYEOF
  touch /opt/downstream-app/.db_initialized
  echo "[$(date)] DB schema initialized."
fi

# ── Start services ────────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl enable downstream nginx
systemctl start downstream
systemctl restart nginx

echo "[$(date)] App VM setup complete."
