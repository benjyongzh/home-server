#!/bin/bash
set -euo pipefail

BACKUP_DIR="/var/backups/nextcloud-db"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="$BACKUP_DIR/nextcloud-$TIMESTAMP.dump"

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

# Remove backups older than 30 days
find "$BACKUP_DIR" \
  -maxdepth 1 \
  -type f \
  -name 'nextcloud-*.dump' \
  -mtime +29 \
  -delete

echo "Old backups cleaned up."
