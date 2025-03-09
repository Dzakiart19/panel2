#!/bin/bash

# Konfigurasi
LOG_FILE="/tmp/pterodactyl_install.log"
DOMAIN="localhost"
DB_NAME="pterodactyl"
DB_USER="pterodactyl"
DB_PASS=$(openssl rand -hex 12)
ADMIN_EMAIL="admin@example.com"
ADMIN_USER="admin"
ADMIN_PASSWORD=$(openssl rand -hex 12)
MYSQL_ROOT_PASSWORD="root_$(openssl rand -hex 6)"

# Fungsi untuk logging
log() {
  echo -e "[$(date +'%Y-%m-%d %T')] $1" | tee -a $LOG_FILE
}

# Fungsi penanganan error
error_handler() {
  log "\n❌ Error terjadi di line $1"
  log "Cek log detail di: $LOG_FILE"
  exit 1
}

trap 'error_handler $LINENO' ERR
set -eo pipefail

# Mulai instalasi
clear
log "🚀 Memulai instalasi Pterodactyl Panel..."
log "Versi Script: 2.1 - GitHub Codespaces Optimized"

# Update sistem
log "🔄 Memperbarui paket sistem..."
apt-get update -y >> $LOG_FILE 2>&1
DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq >> $LOG_FILE 2>&1

# Instal dependensi
log "📦 Menginstal dependensi sistem..."
apt-get install -y \
    curl \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    nginx \
    mariadb-server \
    php8.1 \
    php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} \
    redis-server \
    >> $LOG_FILE 2>&1

# Setup MySQL (Revisi)
log "🔧 Mengkonfigurasi database..."
systemctl start mariadb >> $LOG_FILE 2>&1
systemctl enable mariadb >> $LOG_FILE 2>&1

# Secure MySQL installation
mysql -uroot <<MYSQL_SCRIPT
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('$MYSQL_ROOT_PASSWORD');
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Instal Composer
log "📦 Menginstal Composer..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >> $LOG_FILE 2>&1

# Setup Pterodactyl
log "🦖 Menginstal Pterodactyl Panel..."
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl

curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz >> $LOG_FILE 2>&1
tar -xzvf panel.tar.gz >> $LOG_FILE 2>&1
chmod -R 755 storage/* bootstrap/cache/

cp .env.example .env
composer install --no-dev --optimize-autoloader >> $LOG_FILE 2>&1

php artisan key:generate --force >> $LOG_FILE 2>&1
php artisan p:environment:setup \
  --author="$ADMIN_EMAIL" \
  --url="https://$DOMAIN" \
  --timezone="Asia/Jakarta" \
  --cache="redis" \
  --session="database" \
  --queue="redis" \
  --redis-host="localhost" \
  --redis-pass="null" \
  --redis-port="6379" \
  --settings-ui="yes" >> $LOG_FILE 2>&1

php artisan p:environment:database \
  --host="127.0.0.1" \
  --port="3306" \
  --database="$DB_NAME" \
  --username="$DB_USER" \
  --password="$DB_PASS" >> $LOG_FILE 2>&1

php artisan migrate --seed --force >> $LOG_FILE 2>&1
php artisan p:user:make \
  --email="$ADMIN_EMAIL" \
  --username="$ADMIN_USER" \
  --name="Administrator" \
  --password="$ADMIN_PASSWORD" \
  --admin=1 >> $LOG_FILE 2>&1

# Setup Nginx
log "🔧 Mengkonfigurasi Nginx..."
cat > /etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    root /var/www/pterodactyl/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx >> $LOG_FILE 2>&1

# Setup SSL
log "🔐 Membuat SSL self-signed..."
mkdir -p /etc/ssl/private
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt \
  -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Development/CN=$DOMAIN" >> $LOG_FILE 2>&1

# Konfigurasi Firewall
log "🔥 Mengatur firewall..."
ufw allow 80/tcp >> $LOG_FILE 2>&1
ufw allow 443/tcp >> $LOG_FILE 2>&1
ufw allow 22/tcp >> $LOG_FILE 2>&1
yes | ufw enable >> $LOG_FILE 2>&1

log "✅ Instalasi berhasil diselesaikan!"

# Tampilkan informasi kredensial
cat <<CREDENTIALS

=============================================
          INSTALASI BERHASIL 
=============================================
URL Panel: https://$DOMAIN
👉 Akses Panel: Buka tab 'Ports' di Codespaces
   Klik kanan port 80 → Open in Browser

🔑 Kredensial Login:
- Username: $ADMIN_USER
- Password: $ADMIN_PASSWORD
- Email: $ADMIN_EMAIL

🔒 Kredensial Database:
- Database: $DB_NAME
- User: $DB_USER
- Password: $DB_PASS
- Root Password: $MYSQL_ROOT_PASSWORD

📌 Langkah Verifikasi:
1. Buka URL panel di browser
2. Login dengan kredensial di atas
3. Periksa status layanan:
   systemctl status {nginx,mariadb,php8.1-fpm}

❗ Catatan Penting:
- Password di-generate secara acak
- SSL self-signed aman untuk development
- Port 80/443 sudah di-expose otomatis
=============================================
CREDENTIALS
