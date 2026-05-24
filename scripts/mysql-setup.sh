#!/bin/bash
set -euo pipefail
exec > /var/log/mysql-setup.log 2>&1

echo "==> Waiting for apt lock to clear..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 2; done

echo "==> Installing MySQL server..."
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server

echo "==> Configuring MySQL to accept remote connections..."
MYSQLD_CNF="/etc/mysql/mysql.conf.d/mysqld.cnf"
sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" "$MYSQLD_CNF"
grep -q "^bind-address" "$MYSQLD_CNF" || sed -i "/^\[mysqld\]/a bind-address = 0.0.0.0" "$MYSQLD_CNF"

systemctl restart mysql

echo "==> Creating database and user..."
mysql <<'SQL'
CREATE DATABASE IF NOT EXISTS `${db_name}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'%' IDENTIFIED BY '${db_password}';
GRANT ALL PRIVILEGES ON `${db_name}`.* TO '${db_user}'@'%';
FLUSH PRIVILEGES;
SQL

echo "==> MySQL setup complete."
