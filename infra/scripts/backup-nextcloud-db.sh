#!/bin/bash
set -euo pipefail

: "${NAS_HOST:?Set NAS_HOST in /opt/shared/.env}"
: "${NAS_BACKUP_ROOT:?Set NAS_BACKUP_ROOT in /opt/shared/.env}"
: "${NEXTCLOUD_DB_BACKUP_DIR:?Set NEXTCLOUD_DB_BACKUP_DIR in /opt/shared/.env}"

BACKUP_DIR="/var/backups/nextcloud-db"
NAS_BACKUP_DIR="$NEXTCLOUD_DB_BACKUP_DIR"
NAS_BACKUP_SOURCE="$NAS_HOST:/volume1/backups"

case "$NAS_BACKUP_DIR" in
  "$NAS_BACKUP_ROOT"/*) ;;
  *) echo "ERROR: Backup directory must be inside the NAS backup mount" >&2; exit 1 ;;
esac
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="$BACKUP_DIR/nextcloud-$TIMESTAMP.dump"
NAS_BACKUP_FILE="$NAS_BACKUP_DIR/nextcloud-$TIMESTAMP.dump"

# Create a private backup directory
install -d -m 700 "$BACKUP_DIR"
umask 077

# Use a temporary file to avoid incomplete backups
TMP_FILE=$(mktemp "$BACKUP_DIR/.nextcloud-XXXXXX")
trap 'rm -f "$TMP_FILE"' EXIT

echo "Starting Nextcloud database backup..."

# Dump PostgreSQL database
docker exec postgres \
  pg_dump -U nextcloud -d nextcloud -Fc \
  > "$TMP_FILE"

# Verify archive is readable
test -s "$TMP_FILE"
docker exec -i postgres \
  pg_restore --list < "$TMP_FILE" > /dev/null

# Read the full archive and decompress its contents
docker exec -i postgres \
  pg_restore --file=/dev/null < "$TMP_FILE"

# Publish only a verified backup
mv "$TMP_FILE" "$BACKUP_FILE"
trap - EXIT

echo "Backup completed: $BACKUP_FILE"

# Require the intended NAS export to be mounted before copying. This avoids
# writing a seemingly successful second copy into an unmounted local folder.
timeout 20 ls -A "$NAS_BACKUP_ROOT" > /dev/null
actual_nas_source=$(findmnt -rn -M "$NAS_BACKUP_ROOT" -t nfs,nfs4 -o SOURCE)
if [ "$actual_nas_source" != "$NAS_BACKUP_SOURCE" ]; then
  echo "ERROR: Unexpected NAS backup source: $actual_nas_source" >&2
  exit 1
fi

install -d -m 700 "$NAS_BACKUP_DIR"

NAS_TMP_FILE=$(mktemp "$NAS_BACKUP_DIR/.nextcloud-XXXXXX")
trap 'rm -f "$NAS_TMP_FILE"' EXIT
install -m 600 "$BACKUP_FILE" "$NAS_TMP_FILE"
cmp -s "$BACKUP_FILE" "$NAS_TMP_FILE"
mv "$NAS_TMP_FILE" "$NAS_BACKUP_FILE"
trap - EXIT

echo "Verified NAS copy completed: $NAS_BACKUP_FILE"

# Remove backups older than 30 days
find "$BACKUP_DIR" \
  -maxdepth 1 \
  -type f \
  -name 'nextcloud-*.dump' \
  -mtime +29 \
  -delete

find "$NAS_BACKUP_DIR" \
  -maxdepth 1 \
  -type f \
  -name 'nextcloud-*.dump' \
  -mtime +29 \
  -delete

echo "Old backups cleaned up."
