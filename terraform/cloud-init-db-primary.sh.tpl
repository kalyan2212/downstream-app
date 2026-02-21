#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# DB Primary VM cloud-init  –  PostgreSQL 15 primary + streaming replication
# Template variables:
#   db_name, db_user, db_password, replication_password, replica_ip, app_subnet
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
exec > /var/log/cloud-init-db-primary.log 2>&1

echo "[$(date)] Starting DB primary setup..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y postgresql-15 postgresql-client-15

PG_CONF=/etc/postgresql/15/main/postgresql.conf
PG_HBA=/etc/postgresql/15/main/pg_hba.conf

# ── postgresql.conf tuning ────────────────────────────────────────────────────
# Listen on all interfaces
sed -i "s|^#listen_addresses = 'localhost'|listen_addresses = '*'|" "$PG_CONF"
# Replication settings
sed -i "s|^#wal_level = replica|wal_level = replica|"            "$PG_CONF"
sed -i "s|^#max_wal_senders = 10|max_wal_senders = 5|"          "$PG_CONF"
sed -i "s|^#wal_keep_size = 0|wal_keep_size = 512|"             "$PG_CONF"
sed -i "s|^#hot_standby = on|hot_standby = on|"                 "$PG_CONF"

# ── pg_hba.conf  ──────────────────────────────────────────────────────────────
# Allow app-subnet → downstream DB
cat >> "$PG_HBA" << HBAEOF

# Downstream app VMs
host    ${db_name}      ${db_user}          ${app_subnet}           scram-sha-256

# Streaming replication from replica
host    replication     replication_user    ${replica_ip}/32        scram-sha-256
HBAEOF

# ── Restart PostgreSQL to pick up config ──────────────────────────────────────
systemctl restart postgresql

# ── Create DB, users, roles ───────────────────────────────────────────────────
sudo -u postgres psql -v ON_ERROR_STOP=1 << SQLEOF
-- Application database
CREATE DATABASE ${db_name};

-- Application user
CREATE USER ${db_user} WITH ENCRYPTED PASSWORD '${db_password}';
GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};
\c ${db_name}
GRANT ALL ON SCHEMA public TO ${db_user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON TABLES TO ${db_user};

-- Replication user
CREATE ROLE replication_user WITH REPLICATION LOGIN
    ENCRYPTED PASSWORD '${replication_password}';
SQLEOF

echo "[$(date)] DB primary setup complete."
