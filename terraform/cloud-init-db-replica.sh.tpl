#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# DB Replica VM cloud-init  –  PostgreSQL 15 hot standby
# Template variables:
#   primary_ip, replication_password
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
exec > /var/log/cloud-init-db-replica.log 2>&1

echo "[$(date)] Starting DB replica setup..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y postgresql-15 postgresql-client-15

DATA_DIR=/var/lib/postgresql/15/main

# ── Wait for primary to accept connections ────────────────────────────────────
echo "[$(date)] Waiting for DB primary at ${primary_ip}:5432..."
for attempt in $(seq 1 40); do
  if PGPASSWORD="${replication_password}" pg_isready \
       -h ${primary_ip} -p 5432 -U replication_user 2>/dev/null; then
    echo "[$(date)] Primary is ready."
    break
  fi
  echo "  attempt $attempt/40 – primary not ready, sleeping 15s..."
  sleep 15
done

# Extra wait to ensure pg_hba.conf / replication slot is active
sleep 10

# ── Stop local PostgreSQL, clear data dir ────────────────────────────────────
systemctl stop postgresql || true
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR"
chown postgres:postgres "$DATA_DIR"
chmod 700 "$DATA_DIR"

# ── pg_basebackup  ─────────────────────────────────────────────────────────────
# -R: auto-create standby.signal + primary_conninfo in postgresql.auto.conf
# -Xs: stream WAL during backup
# -P: show progress
echo "[$(date)] Running pg_basebackup from ${primary_ip}..."
sudo -u postgres PGPASSWORD="${replication_password}" pg_basebackup \
  -h ${primary_ip} \
  -p 5432 \
  -U replication_user \
  -D "$DATA_DIR" \
  -P -Xs -R

echo "[$(date)] pg_basebackup complete."

# ── Ensure hot_standby is enabled ─────────────────────────────────────────────
PG_CONF=/etc/postgresql/15/main/postgresql.conf
sed -i "s|^#hot_standby = on|hot_standby = on|" "$PG_CONF" || true
echo "hot_standby = on" >> "$DATA_DIR/postgresql.auto.conf"

# ── Start replica ─────────────────────────────────────────────────────────────
systemctl start postgresql

echo "[$(date)] DB replica setup complete. Streaming replication active."
