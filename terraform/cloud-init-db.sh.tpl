#!/bin/bash
# DB VM cloud-init  -  PostgreSQL 15 (standalone, no replication)
# Template variables: db_name, db_user, db_password, app_subnet
set -euo pipefail
exec > /var/log/cloud-init-db.log 2>&1

echo "[$(date)] Starting DB VM setup..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y postgresql-15 postgresql-client-15

PG_CONF=/etc/postgresql/15/main/postgresql.conf
PG_HBA=/etc/postgresql/15/main/pg_hba.conf

# Allow remote connections from the app subnet
sed -i "s|^#listen_addresses = 'localhost'|listen_addresses = '*'|" "$PG_CONF"

cat >> "$PG_HBA" << HBAEOF

# Downstream app VM
host    ${db_name}      ${db_user}      ${app_subnet}       scram-sha-256
HBAEOF

systemctl restart postgresql

sudo -u postgres psql -v ON_ERROR_STOP=1 << SQLEOF
CREATE DATABASE ${db_name};
CREATE USER ${db_user} WITH ENCRYPTED PASSWORD '${db_password}';
GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};
\c ${db_name}
GRANT ALL ON SCHEMA public TO ${db_user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${db_user};
SQLEOF

echo "[$(date)] DB VM setup complete."
