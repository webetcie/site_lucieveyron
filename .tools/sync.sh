#!/bin/bash

################################################################################
# Sync automatique SPIP / WordPress (dump distant + import local + fichiers)
# À lancer depuis ton Mac : ./tools/sync.sh
################################################################################

set -e

########################################
# CONFIG
########################################

# SSH
REMOTE_SSH_USER="lucieveyron"
REMOTE_SSH_HOST="vps2.wec.ovh"
REMOTE_SSH_PORT="43921"

# Commandes SSH / SCP
SSH_CMD="ssh -p $REMOTE_SSH_PORT $REMOTE_SSH_USER@$REMOTE_SSH_HOST"
SCP_CMD="scp -P $REMOTE_SSH_PORT"

# Chemins serveur
REMOTE_PATH="/var/www/lucieveyron/site"      # Dossier du site (toujours /site)
REMOTE_USER_ROOT="$(dirname "$REMOTE_PATH")"  # /var/www/lucieveyron
REMOTE_MYCNF="$REMOTE_USER_ROOT/.my.cnf"      # /var/www/lucieveyron/.my.cnf

# Base de données
REMOTE_DB_NAME="lucieveyron"      # BDD distante
LOCAL_DB_NAME="wec_lucieveyron"       # BDD locale
SPIP_TABLE_PREFIX="lucieveyron"

# Chemin local
CHEMIN_LOCAL="wec/lucieveyron"

########################################
# DÉTECTION SPIP / WORDPRESS
########################################

SITE_TYPE=""

$SSH_CMD "[ -d '$REMOTE_PATH/IMG' ]" && SITE_TYPE="SPIP"
$SSH_CMD "[ -d '$REMOTE_PATH/wp-content' ]" && SITE_TYPE="WP"

if [ "$SITE_TYPE" = "" ]; then
  echo "Impossible de détecter SPIP ou WordPress."
  exit 1
fi

echo "== Type détecté : $SITE_TYPE =="

########################################
# DUMP DISTANT
########################################

echo "== Dump MySQL distant =="

$SSH_CMD "PATH=/usr/bin:/usr/local/bin:/bin:/usr/sbin \
  mysqldump --defaults-file='$REMOTE_MYCNF' '$REMOTE_DB_NAME' \
  > '$REMOTE_PATH/sync_dump.sql'"

########################################
# RÉCUPÉRATION DU DUMP
########################################

echo "== Récupération du dump =="
$SCP_CMD $REMOTE_SSH_USER@$REMOTE_SSH_HOST:$REMOTE_PATH/sync_dump.sql ./sync_dump.sql

########################################
# IMPORT LOCAL
########################################

echo "== Import dans la BDD locale =="
/usr/local/mysql/bin/mysql -u root -p419ycx7Y $LOCAL_DB_NAME < ./sync_dump.sql

########################################
# RÉGLAGES LOCAUX
########################################

echo "== Ajustements URL locale =="

if [ "$SITE_TYPE" = "SPIP" ]; then
  /usr/local/mysql/bin/mysql -u root -p419ycx7Y $LOCAL_DB_NAME -e \
  "UPDATE ${SPIP_TABLE_PREFIX}_meta SET valeur='http://localhost/$CHEMIN_LOCAL' WHERE nom='adresse_site';"
else
  /usr/local/mysql/bin/mysql -u root -p419ycx7Y $LOCAL_DB_NAME -e \
  "UPDATE wp_options SET option_value='http://localhost/$CHEMIN_LOCAL' WHERE option_name IN ('siteurl','home');"
fi

########################################
# SYNC FICHIERS
########################################

if [ "$SITE_TYPE" = "SPIP" ]; then
  # Dossier IMG local = 2 niveaux au-dessus du plugin
  LOCAL_IMG_PATH="$(cd "$(dirname "$0")/../../.." && pwd)/IMG"

  echo "== Sync du dossier IMG =="
  rsync -avz --no-perms --no-owner --no-group --omit-dir-times -e "ssh -p $REMOTE_SSH_PORT" \
  $REMOTE_SSH_USER@$REMOTE_SSH_HOST:$REMOTE_PATH/IMG/ "$LOCAL_IMG_PATH/"
else
  # Dossier uploads local = 3 niveaux au-dessus du script
  LOCAL_UPLOADS_PATH="$(cd "$(dirname "$0")/../../.." && pwd)/uploads"

  echo "== Sync du dossier uploads =="
  rsync -avz --no-perms --no-owner --no-group --omit-dir-times -e "ssh -p $REMOTE_SSH_PORT" \
  $REMOTE_SSH_USER@$REMOTE_SSH_HOST:$REMOTE_PATH/wp-content/uploads/ "$LOCAL_UPLOADS_PATH/"
fi

########################################
# NETTOYAGE DES DUMPS
########################################

echo "== Nettoyage des dumps =="

# Suppression du dump local
rm -f ./sync_dump.sql

# Suppression du dump distant
$SSH_CMD "rm -f '$REMOTE_PATH/sync_dump.sql'"

echo "== Sync terminé =="
