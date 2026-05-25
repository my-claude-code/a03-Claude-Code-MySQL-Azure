#!/bin/bash
set -euo pipefail
exec > /var/log/app-setup.log 2>&1

echo "==> Waiting for apt lock to clear..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 2; done

echo "==> Installing dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3-venv git nginx

echo "==> Cloning app from GitHub..."
cd /opt
git clone https://github.com/my-claude-code/a02-Claude-Code-MYSQL.git flask-app
cd flask-app

echo "==> Creating virtual environment and installing packages..."
python3 -m venv venv
source venv/bin/activate
pip install --quiet -r requirements.txt
pip install --quiet gunicorn

echo "==> Writing .env..."
mkdir -p flask_session
cat > .env <<'ENV_EOF'
ENTRA_CLIENT_ID=${entra_client_id}
ENTRA_CLIENT_SECRET=${entra_client_secret}
ENTRA_TENANT_ID=${entra_tenant_id}
REDIRECT_URI=http://${app_public_ip}/auth/callback
FLASK_SECRET_KEY=${flask_secret_key}
DATABASE_URL=mysql+pymysql://${db_user}:${db_password}@${mysql_private_ip}:3306/${db_name}
ENV_EOF

echo "==> Waiting for MySQL on ${mysql_private_ip} (up to 10 minutes)..."
READY=0
for i in $(seq 1 60); do
    if python3 -c "
import pymysql, sys
try:
    c = pymysql.connect(host='${mysql_private_ip}', user='${db_user}', password='${db_password}', database='${db_name}')
    c.close()
    sys.exit(0)
except:
    sys.exit(1)
" 2>/dev/null; then
        echo "MySQL is ready after $i attempt(s)."
        READY=1
        break
    fi
    echo "Attempt $i/60 — MySQL not ready yet, retrying in 10s..."
    sleep 10
done

if [ "$READY" -eq 0 ]; then
    echo "ERROR: MySQL did not become available in time." >&2
    exit 1
fi

echo "==> Initialising database schema..."
FLASK_APP=app.py venv/bin/flask init-db

echo "==> Creating systemd service for gunicorn..."
cat > /etc/systemd/system/flask-app.service <<'SVC_EOF'
[Unit]
Description=Flask Entra Notes (gunicorn)
After=network.target

[Service]
User=root
WorkingDirectory=/opt/flask-app
Environment=PATH=/opt/flask-app/venv/bin
ExecStart=/opt/flask-app/venv/bin/gunicorn -w 2 -b 127.0.0.1:5000 app:app
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC_EOF

systemctl daemon-reload
systemctl enable flask-app
systemctl start flask-app

echo "==> Configuring nginx reverse proxy on port 80..."
cat > /etc/nginx/sites-available/flask-app <<'NGINX_EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass         http://127.0.0.1:5000;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_read_timeout 60s;
    }
}
NGINX_EOF

ln -sf /etc/nginx/sites-available/flask-app /etc/nginx/sites-enabled/flask-app
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

echo "==> App setup complete. Visit http://${app_public_ip}"
