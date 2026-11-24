#!/bin/bash
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
echo "Installation de Mariadb"
apt install mariadb-server mariadb-client -y
echo "Configuration de l'utilisateur"


BASE="Inscription"
read -p "Nom de la base de données ($BASE): " BASE
BASE=${BASE:-Inscription}
read -p "Nom de l'utilisateur pour la base de données : " USER_DB
read -p "IP dont l'utilisateur $USER_DB est autorisé à se connecter : " IP
read -s -p "Mot de passe pour $USER_DB : " PASS

echo

mariadb <<EOF
CREATE DATABASE IF NOT EXISTS \`$BASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$USER_DB'@'$IP' IDENTIFIED BY '$PASS';
GRANT ALL PRIVILEGES ON \`$BASE\`.* TO '$USER_DB'@'$IP';
FLUSH PRIVILEGES;
EOF
IPVM=$(hostname -I | awk '{print $1}')

echo "Utilisateur $USER_DB créé avec accès à la base $BASE."
echo "L'adresse IP de cette machine est : $IPVM"
echo "Terminé !"