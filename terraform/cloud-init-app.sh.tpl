#!/bin/bash
# App VM cloud-init  -  installs nginx + gunicorn + flask app
# Terraform template variables: db_host, db_name, db_user, db_password,
#   flask_secret, upstream_url, api_key, github_repo, admin_username
set -euo pipefail
exec > /var/log/cloud-init-app.log 2>&1

echo "[$(date)] Starting app VM setup..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-pip python3-venv nginx git curl

APP_DIR=/opt/downstream-app
mkdir -p "$APP_DIR"

for attempt in 1 2 3 4 5; do
  git clone ${github_repo} "$APP_DIR" && break || true
  echo "Git clone attempt $attempt failed, retrying in 15s..."
  sleep 15
done

cd "$APP_DIR"
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt

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
    --workers 2 \
    --bind 127.0.0.1:5001 \
    --access-logfile /var/log/downstream-access.log \
    --error-logfile /var/log/downstream-error.log \
    web_app:app
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

# Auto-update service: pulls latest code from GitHub and restarts
cat > /etc/systemd/system/downstream-update.service << 'UPDEOF'
[Unit]
Description=Downstream App Auto-Update
After=network-online.target

[Service]
Type=oneshot
User=www-data
WorkingDirectory=/opt/downstream-app
ExecStart=/bin/bash -c "git pull origin main && ./venv/bin/pip install -r requirements.txt -q && systemctl restart downstream"
UPDEOF

cat > /etc/systemd/system/downstream-update.timer << 'TIMEOF'
[Unit]
Description=Downstream App Auto-Update Timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Unit=downstream-update.service

[Install]
WantedBy=timers.target
TIMEOF

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
chown -R www-data:www-data "$APP_DIR"

echo "[$(date)] Waiting for PostgreSQL at ${db_host}:5432..."
for i in $(seq 1 30); do
  if python3 -c "
import psycopg2, sys
try:
    c = psycopg2.connect(host='${db_host}',port=5432,dbname='${db_name}',user='${db_user}',password='${db_password}')
    c.close(); sys.exit(0)
except: sys.exit(1)
" 2>/dev/null; then
    echo "[$(date)] PostgreSQL is reachable."
    break
  fi
  echo "  attempt $i/30 - not ready, sleeping 15s..."
  sleep 15
done

if [ ! -f /opt/downstream-app/.db_initialized ]; then
  DB_HOST=${db_host} DB_NAME=${db_name} DB_USER=${db_user} \
  DB_PASSWORD=${db_password} \
    /opt/downstream-app/venv/bin/python -c "
from web_app import init_db
init_db()
" && touch /opt/downstream-app/.db_initialized
  echo "[$(date)] DB schema initialized."
fi

systemctl daemon-reload
systemctl enable downstream nginx downstream-update.timer
systemctl start downstream downstream-update.timer
systemctl restart nginx

echo "[$(date)] App VM setup complete."
