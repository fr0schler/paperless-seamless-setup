#!/bin/bash

set -e  # Stoppt das Skript bei Fehlern

# --- Paketquellen und Docker installieren ---
echo "==> Docker installieren..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# iptables Legacy Workaround
echo "==> iptables auf Legacy umstellen..."
update-alternatives --set iptables /usr/sbin/iptables-legacy

systemctl enable docker
systemctl start docker

# --- NGINX und Certbot installieren ---
echo "==> NGINX und Certbot installieren..."
apt-get install -y nginx python3-certbot-nginx

# --- Paperless-ngx Setup ---
echo "==> Paperless-ngx einrichten..."
mkdir -p /opt/paperless-ngx
curl -L https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/main/docker/compose/docker-compose.yml -o /opt/paperless-ngx/docker-compose.yml
curl -L https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/main/docker/compose/.env.sample -o /opt/paperless-ngx/.env

# Admin Login setzen
sed -i 's/PAPERLESS_ADMIN_USER=admin/PAPERLESS_ADMIN_USER=admin/' /opt/paperless-ngx/.env
sed -i 's/PAPERLESS_ADMIN_PASSWORD=admin/PAPERLESS_ADMIN_PASSWORD=paperless123/' /opt/paperless-ngx/.env

docker compose -f /opt/paperless-ngx/docker-compose.yml up -d

# --- NGINX Reverse Proxy konfigurieren ---
echo "==> NGINX konfigurieren..."
cat <<EOF > /etc/nginx/sites-available/paperless
server {
    listen 80;
    server_name paperless.hkp-solutions.de;  # <--- ERSETZEN MIT DEINER DOMAIN!

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -s /etc/nginx/sites-available/paperless /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# --- Let's Encrypt Zertifikat einrichten ---
echo "==> Let's Encrypt Zertifikat beantragen..."
sleep 30  # Warten, bis Paperless-ngx bereit ist

certbot --nginx --non-interactive --agree-tos --redirect --email tim@hkp-solutions.de -d paperless.hkp-solutions.de

echo "==> Fertig! Paperless-ngx läuft unter https://yourdomain.com"
