#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Lance ce script avec sudo ou en root."
    exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="/var/www/inscription"
PHP_REQ="8.4"
MARIA_V="10.11.0"   # Debian 12 : 10.11.0 | Debian 13 : 11.8.0
IP=$(hostname -I | awk '{print $1}')   # IP de cette machine (affichée à la fin)

# ---------- Questions ----------
read -p "Nom de l'utilisateur de la base de données : " USER_DB
read -p "IP du serveur de base de données : " DB_HOST
read -p "Nom de la base de données : " BASE
BASE=${BASE:-Inscription}
read -p "Port de la base de données [3306] : " PORT
PORT=${PORT:-3306}
read -s -p "Mot de passe de $USER_DB : " PASS
echo

export DEBIAN_FRONTEND=noninteractive

echo "==> Paquets de base..."
apt update
apt install -y apache2 lsb-release ca-certificates curl apt-transport-https gnupg unzip rsync openssl

# ---------- Vérification / mise à jour de PHP ----------
php_ok() {
    command -v php >/dev/null 2>&1 || return 1
    php -r 'exit(version_compare(PHP_VERSION, "'"$PHP_REQ"'", ">=") ? 0 : 1);'
}

if php_ok; then
    echo "==> PHP $(php -r 'echo PHP_VERSION;') détecté, version suffisante."
else
    echo "==> PHP $PHP_REQ requis : installation / mise à jour..."

    # PHP 8.4 est-il disponible dans les dépôts actuels ?
    if ! apt-cache policy php$PHP_REQ 2>/dev/null | grep -q 'Candidate: [0-9]'; then
        echo "==> Ajout du dépôt Sury..."
        curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
        dpkg -i /tmp/debsuryorg-archive-keyring.deb
        echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
        apt update
    fi

    apt install -y php$PHP_REQ php$PHP_REQ-cli libapache2-mod-php$PHP_REQ php$PHP_REQ-mysql php$PHP_REQ-xml php$PHP_REQ-mbstring php$PHP_REQ-intl php$PHP_REQ-curl php$PHP_REQ-zip

    # Désactiver les anciens modules PHP d'Apache et activer le bon
    for mod in /etc/apache2/mods-enabled/php*.load; do
        [ -e "$mod" ] || continue
        name=$(basename "$mod" .load)
        [ "$name" != "php$PHP_REQ" ] && a2dismod "$name" || true
    done
    a2enmod php$PHP_REQ
    update-alternatives --set php /usr/bin/php$PHP_REQ

    if ! php_ok; then
        echo "ERREUR : impossible d'obtenir PHP $PHP_REQ."
        exit 1
    fi
fi

# Extensions nécessaires (au cas où PHP était déjà en 8.4 mais incomplet)
PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
apt install -y php$PHPV-mysql php$PHPV-xml php$PHPV-mbstring php$PHPV-intl php$PHPV-curl php$PHPV-zip libapache2-mod-php$PHPV

# ---------- Composer ----------
if ! command -v composer >/dev/null 2>&1; then
    echo "==> Installation de Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
fi

# ---------- Copie du projet ----------
echo "==> Copie du projet dans $APP_DIR..."
mkdir -p "$APP_DIR"
rsync -a --delete --exclude='/.git' --exclude='*.sh' --exclude='/.env.local' --exclude='/var' --exclude='/vendor' "$DIR/" "$APP_DIR/"
# ---------- Configuration ----------
echo "==> Configuration (.env.local)..."
PASS_ENC=$(php -r 'echo rawurlencode($argv[1]);' -- "$PASS")
SECRET=$(openssl rand -hex 16)

cat > "$APP_DIR/.env.local" <<EOF
APP_ENV=prod
APP_SECRET=$SECRET
DATABASE_URL='mysql://$USER_DB:$PASS_ENC@$DB_HOST:$PORT/$BASE?serverVersion=mariadb-$MARIA_V&charset=utf8mb4'
EOF

chown -R www-data:www-data "$APP_DIR"

# ---------- Dépendances et base ----------
echo "==> Installation des dépendances (Composer)..."
cd "$APP_DIR"
runuser -u www-data -- env COMPOSER_HOME=/tmp/composer composer install --no-dev --optimize-autoloader --no-interaction

echo "==> Assets (CSS/JS)..."
runuser -u www-data -- php bin/console importmap:install
runuser -u www-data -- php bin/console asset-map:compile

echo "==> Migrations de la base..."
runuser -u www-data -- php bin/console doctrine:migrations:migrate --no-interaction

echo "==> Cache de production..."
runuser -u www-data -- php bin/console cache:clear
chown -R www-data:www-data "$APP_DIR/var"

# ---------- Apache ----------
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
systemctl enable apache2
systemctl restart apache2

echo
echo "Installation terminée !"
echo "Site accessible à : http://$IP"