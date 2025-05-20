#!/bin/bash
set -euo pipefail

# Backup mode: either "daily" or "weekly"
MODE=$1

# Paths
WEBAPPS_DIR="/home/runcloud/webapps"
BACKUP_DIR="/home/runcloud/backups/$MODE"
VULTR_BUCKET="runcloud-app-backups"
VULTR_ENDPOINT="https://sjc1.vultrobjects.com"

# Date identifiers for filenames
DATE=$(date +'%Y-%m-%d')
WEEK=$(date +'%Y-%V')  # Year-week number for weekly naming

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Loop through all web applications
for APP_PATH in "$WEBAPPS_DIR"/*; do
    APP=$(basename "$APP_PATH")
    CONFIG="$APP_PATH/wp-config.php"
    TMP="/tmp/${APP}_${MODE}_backup"
    mkdir -p "$TMP"

    # Extract DB credentials from wp-config.php
    if [ -f "$CONFIG" ]; then
        DB_NAME=$(grep "DB_NAME" "$CONFIG" | sed "s/.*'\\(.*\\)'.*/\\1/")
        DB_USER=$(grep "DB_USER" "$CONFIG" | sed "s/.*'\\(.*\\)'.*/\\1/")
        DB_PASS=$(grep "DB_PASSWORD" "$CONFIG" | sed "s/.*'\\(.*\\)'.*/\\1/")

        # Dump the database
        mysqldump -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$TMP/db.sql"
    fi

    # Copy all files from the app directory
    cp -r "$APP_PATH" "$TMP/files"

    # Determine the backup filename
    if [ "$MODE" = "weekly" ]; then
        OUT="${APP}_week-${WEEK}.tar.gz"
    else
        OUT="${APP}_${DATE}.tar.gz"
    fi

    # Archive the backup
    tar -czf "$BACKUP_DIR/$OUT" -C "$TMP" .


    # Upload to Vultr Object Storage
    if aws s3 cp "$BACKUP_DIR/$OUT" "s3://$VULTR_BUCKET/$MODE/$OUT" --endpoint-url "$VULTR_ENDPOINT"; then
        # Log successful upload
        echo "Uploaded $OUT to Vultr" >> ~/backup_upload.log

        # Clean up temporary and local files
        rm -rf "$TMP"
        rm -f "$BACKUP_DIR/$OUT"
    else
        echo "❌ Upload failed for $OUT" >> ~/backup_upload.log
    fi
done

# === CLEANUP OLD BACKUPS ===

# Delete daily backups older than 7 days
find /home/runcloud/backups/daily -type f -name "*.tar.gz" -mtime +7 -exec rm {} \;

# Delete weekly backups older than 30 days
find /home/runcloud/backups/weekly -type f -name "*.tar.gz" -mtime +30 -exec rm {} \;