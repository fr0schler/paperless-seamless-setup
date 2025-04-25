# Paperless-ngx Setup (Docker + NGINX + Let's Encrypt)

## Netbird Cloud-init

1. Unter Debian

```yaml
runcmd:
  - curl -fsSL https://pkgs.netbird.io/install.sh | sh
  - netbird up --setup-key <DEIN_SETUP_KEY>
```

2. Version von Debian (Hetzner)

```yaml
runcmd:
  - sed -i 's|https://download.docker.com/linux/ubuntu|https://download.docker.com/linux/debian|' /etc/apt/sources.list.d/docker.list
  - curl -fsSL https://pkgs.netbird.io/install.sh | sh
  - netbird up --setup-key <DEIN_SETUP_KEY>
```

## 📊 Projektüberblick

Dieses Repository stellt ein automatisiertes Setup für **Paperless-ngx** bereit, inklusive:
- **Docker Compose**-Konfiguration
- **NGINX Reverse Proxy**
- **Let's Encrypt SSL** via Certbot
- **Cloud-Init**-Skript für automatische Server-Provisionierung

---

## 🔧 Bestandteile

- `docker-compose.yml`: Docker-Setup für Paperless-ngx, Redis und Postgres
- `.env.sample`: Beispiel-Umgebungsdatei für Konfiguration
- `setup.sh`: Bash-Skript zum Einrichten von Docker, NGINX, Certbot und Paperless-ngx
- `cloud-init.yaml`: Automatisiertes Setup für neue Server

---

## 📘 Nutzung

### 1. Cloud-Init verwenden (z.B. bei Hetzner, Proxmox)

1.1 **`cloud-init.yaml` herunterladen und anpassen:**
- Domain und E-Mail-Adresse in `setup.sh` eintragen.

1.2 **Server provisionieren mit Cloud-Init:**

```bash
cloud-init apply /pfad/zu/cloud-init.yaml
```

---

### 2. Manuelles Setup (bestehender Server)

2.1 **Setup-Skript herunterladen und ausführen:**

```bash
curl -L https://raw.githubusercontent.com/fr0schler/paperless-seamless-setup/main/setup-paperless.sh -o setup.sh
chmod +x setup.sh
```

```bash

./setup.sh --domain yoursubdomain.domain.tld --email mailbox@yourdomain.de --netbird-key <SETUP-KEY>
```

---

## 🔐 Zugangsdaten (Standard)

- **Benutzername:** `admin`
- **Passwort:** `paperless123`

---

## 🔄 SSL-Zertifikat erneuern (manuell testen)

```bash
certbot renew --dry-run
```

---

## 📖 Weitere Infos

- **Paperless-ngx Doku:** https://docs.paperless-ngx.com
- **Docker Compose Referenz:** https://docs.docker.com/compose/

---

## 📃 Lizenz

MIT License

