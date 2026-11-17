#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Lance ce script avec sudo ou en root."
    exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="/var/www/inscription"
BASE="Inscription"
IP=$(hostname -I | awk '{print $1}')

read -p "Nom de l'utilisateur de la base de données : " USER_DB
read -p "IP dont l'utilisateur $USER_DB est autorisé à se connecter : " IP
read -p "Nom de la base de données : " BASE
read -p "Port de la base de données : " PORT
read -s -p "Mot de passe de $USER_DB : " PASS
echo

echo "==> Installation des paquets..."
apt update
apt install -y apache2 php libapache2-mod-php php-mysql php-xml php-mbstring \
    php-intl php-curl php-zip php-cli composer unzip rsync

echo "==> Copie du projet dans $APP_DIR..."
mkdir -p "$APP_DIR"
rsync -a --delete \
    --exclude='.git' --exclude='*.sh' --exclude='.env.local' \
    --exclude='var' --exclude='vendor' \
    "$DIR/" "$APP_DIR/"

echo "==> Configuration (.env.local)..."
PASS_ENC=$(php -r 'echo rawurlencode($argv[1]);' -- "$PASS")
SECRET=$(openssl rand -hex 16)
cat > "$APP_DIR/.env.local" <<EOF
APP_ENV=prod
APP_SECRET=$SECRET
DATABASE_URL='mysql://$USER_DB:$PASS_ENC@$IP:$PORT/$BASE?serverVersion=mariadb-10.11.0&charset=utf8mb4'
EOF

chown -R www-data:www-data "$APP_DIR"

echo "==> Installation des dépendances (Composer)..."
cd "$APP_DIR"
sudo -u www-data env COMPOSER_HOME=/tmp/composer \
    composer install --no-dev --optimize-autoloader --no-interaction

echo "==> Migrations de la base..."
sudo -u www-data php bin/console doctrine:migrations:migrate --no-interaction

echo "==> Cache de production..."
sudo -u www-data php bin/console cache:clear
chown -R www-data:www-data "$APP_DIR/var"

echo "==> Configuration d'Apache..."
cat > /etc/apache2/sites-available/inscription.conf <<EOF
<VirtualHost *:80>
    DocumentRoot $APP_DIR/public
    <Directory $APP_DIR/public>
        AllowOverride None
        Require all granted
        FallbackResource /index.php
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/inscription_error.log
    CustomLog \${APACHE_LOG_DIR}/inscription_access.log combined
</VirtualHost>
EOF

a2enmod rewrite
a2dissite 000-default || true
a2ensite inscription
systemctl enable --now apache2
systemctl reload apache2

echo
echo "Installation terminée !"
echo "Site accessible à : http://$IP"