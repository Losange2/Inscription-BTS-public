# Mise à jour du système Debian

set -e  # arrête le script à la première erreur

# Vérifier qu'on est root
if [ "$EUID" -ne 0 ]; then
    echo "Lance ce script avec sudo ou en root."
    exit 1
fi

echo "Mise à jour pour une bonne installation de Mariadb"
apt update
apt upgrade -y
apt autoremove -y

# Dossier du script (pour trouver les fichiers du projet)
DIR="$(cd "$(dirname "$0")" && pwd)"

WEBROOT="/var/www/html"
IP=$(hostname -I | awk '{print $1}')

echo "==> Installation des paquets..."
apt update
apt install -y apache2 php libapache2-mod-php php-mysql

echo "==> Démarrage d'Apache..."
systemctl enable --now apache2

echo "==> Copie du projet..."
rm -f "$WEBROOT/index.html"
cp -r "$DIR/projet/." "$WEBROOT/"
chown -R www-data:www-data "$WEBROOT"
chmod -R 755 "$WEBROOT"

systemctl restart apache2

echo
echo "Installation terminée !"
echo "Site accessible à : http://$IP"