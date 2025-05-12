#!/bin/bash

set -e

# === Parameter parsen ===
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --domain) DOMAIN="$2"; shift ;;
        --email) EMAIL="$2"; shift ;;
        --netbird-key) NETBIRD="$2"; shift ;;
        --webdav-user) WEBDAV_USER="$2"; shift ;;
        --webdav-password) WEBDAV_PASSWORD="$2"; shift ;;
        *) echo "Unbekannter Parameter: $1" >&2; exit 1 ;;
    esac
    shift
done

# === Falls Parameter fehlen: abfragen ===
if [ -z "$DOMAIN" ]; then
    read -p "Bitte die Domain angeben (z.B. paperless.example.com): " DOMAIN
fi

if [ -z "$EMAIL" ]; then
    read -p "Bitte die E-Mail für Let's Encrypt angeben: " EMAIL
fi

if [ -z "$NETBIRD" ]; then
    read -p "Bitte den Setup-Key für Netbird eingeben: " NETBIRD
fi

if [ -z "$WEBDAV_USER" ]; then
    read -p "Bitte den WebDAV-Benutzernamen angeben: " WEBDAV_USER
fi

if [ -z "$WEBDAV_PASSWORD" ]; then
    read -p "Bitte das WebDAV-Passwort angeben: " WEBDAV_PASSWORD
fi

echo "==> Domain: $DOMAIN"
echo "==> E-Mail: $EMAIL"
echo "==> Netbird Setup-Key: $NETBIRD"

REPO_URL="https://raw.githubusercontent.com/fr0schler/paperless-seamless-setup/main"

sed -i 's|https://download.docker.com/linux/ubuntu|https://download.docker.com/linux/debian|' /etc/apt/sources.list.d/docker.list

echo "==> Docker installieren..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common fail2ban nginx-extras apache2-utils


curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> iptables auf Legacy umstellen..."
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

systemctl enable docker
systemctl start docker

echo "==> iptables auf Legacy umstellen (IPv4 & IPv6)..."
if update-alternatives --list iptables | grep -q "iptables-legacy"; then
    update-alternatives --set iptables /usr/sbin/iptables-legacy
else
    echo "WARNUNG: iptables-legacy nicht verfügbar für IPv4!"
fi

if update-alternatives --list ip6tables | grep -q "ip6tables-legacy"; then
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
else
    echo "WARNUNG: ip6tables-legacy nicht verfügbar für IPv6!"
fi

echo "==> Docker neu starten..."
systemctl restart docker

# Fail2ban Konfiguration
echo "==> Fail2Ban für WebDAV einrichten..."

cat <<EOF > /etc/fail2ban/filter.d/nginx-webdav.conf
[Definition]
failregex = ^<HOST> -.*"(GET|PROPFIND|OPTIONS|PUT|DELETE|MOVE|COPY|MKCOL) .* HTTP.*" 401
EOF

cat <<EOF >> /etc/fail2ban/jail.local

[nginx-webdav]
enabled  = true
port     = 443
filter   = nginx-webdav
logpath  = /var/log/nginx/error.log
maxretry = 5
bantime  = 3600
findtime = 600
EOF

sed -i 's/enabled = true/enabled = false/' /etc/fail2ban/jail.d/defaults-debian.conf

# Fail2ban neu starten
systemctl restart fail2ban

echo "==> NGINX und Certbot installieren..."
apt-get install -y nginx python3-certbot-nginx

echo "==> Paperless-ngx Setup vorbereiten..."
mkdir -p /opt/paperless-ngx
cd /opt/paperless-ngx

# Konfigurationsdateien aus eigenem GitHub-Repo laden
curl -L "$REPO_URL/docker-compose.yml" -o docker-compose.yml
curl -L "$REPO_URL/.env.sample" -o docker-compose.env


# Admin-Zugang sicherstellen
sed -i 's/PAPERLESS_ADMIN_USER=.*/PAPERLESS_ADMIN_USER=admin/' docker-compose.env
sed -i 's/PAPERLESS_ADMIN_PASSWORD=.*/PAPERLESS_ADMIN_PASSWORD=paperless123/' docker-compose.env

# Domain für CSRF und Allowed Hosts setzen
sed -i "s|^PAPERLESS_ALLOWED_HOSTS=.*|PAPERLESS_ALLOWED_HOSTS=$DOMAIN|" docker-compose.env
sed -i "s|^PAPERLESS_CSRF_TRUSTED_ORIGINS=.*|PAPERLESS_CSRF_TRUSTED_ORIGINS=https://$DOMAIN|" docker-compose.env

echo "==> Docker Compose starten..."
docker compose -f docker-compose.yml up -d

echo "==> NGINX konfigurieren..."
cat <<EOF > /etc/nginx/sites-available/$DOMAIN.conf
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        client_max_body_size 5G;
    }

    # WebDAV für Consume-Ordner
    location /consume/ {
        root /opt/paperless-ngx/;
        dav_methods PUT DELETE MKCOL COPY MOVE;
        dav_ext_methods PROPFIND OPTIONS;
        create_full_put_path on;
        client_max_body_size 5G;

        # Authentifizierung
        auth_basic "Paperless WebDAV";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/$DOMAIN.conf
nginx -t && systemctl restart nginx

echo "==> Zertifikat von Let's Encrypt anfordern..."
sleep 30
certbot --nginx --non-interactive --agree-tos --redirect --email "$EMAIL" -d "$DOMAIN"

sleep 10
echo "==> WebDAV-user und Passwort setzen..."
htpasswd -b /etc/nginx/.htpasswd $WEBDAV_USER $WEBDAV_PASSWORD

echo "==> NGINX neu starten..."
nginx -t && systemctl reload nginx

echo "==> Netbird: Wird heruntergeladen und installiert."
curl -fsSL https://pkgs.netbird.io/install.sh | sh
echo "==> Netbird: Installation beendet, versuche mit Setup-Key zu Connecten."
netbird up --setup-key $NETBIRD
echo "==> Netbird ist installiert: mit Netbird up --setup-key <DEIN_SETUP_KEY>"
echo "==> Fertig! Paperless-ngx ist erreichbar unter: https://$DOMAIN"
