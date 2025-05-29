#!/bin/bash
set -euo pipefail

# --- CONFIGURATION (edit these for your needs) ---
ADMIN_EMAIL="development@growme.ca, dmytro@growme.ca, aziz@growme.ca"
MIN_FREE_SPACE_MB=2048
DISK_PATH="/"  # Path to check disk space (usually root)

# --- Check if mail command exists; install if missing ---
if ! command -v mail >/dev/null 2>&1; then
  echo "mail command not found. Installing mailutils..."
  sudo apt update && sudo apt install mailutils -y
fi

# --- Check disk space before running backup ---
AVAILABLE_MB=$(df -m "$DISK_PATH" | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_MB" -lt "$MIN_FREE_SPACE_MB" ]; then
  echo "Not enough disk space. Only ${AVAILABLE_MB}MB available, required: ${MIN_FREE_SPACE_MB}MB."

  # Optional: email alert
  echo -e "🚨 Backup aborted on $(hostname) at $(date)\n\nOnly ${AVAILABLE_MB}MB available on ${DISK_PATH}, required: ${MIN_FREE_SPACE_MB}MB.\n\nCheck disk usage with:\n\n  df -h\n" \
    | mail -s "⚠️ Backup Failed - Low Disk Space on $(hostname)" "$ADMIN_EMAIL"

  exit 1
fi

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
MONTH=$(date +'%Y-%m')
YEAR=$(date +'%Y')

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
        mysqldump -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$TMP/db.sql" || {
            echo "❌ mysqldump failed for $APP" >> ~/backup_upload.log
            echo -e "🚨 mysqldump failed for $APP on $(hostname) at $(date)\n\nCheck disk space and database access.\n" \
              | mail -s "⚠️ Backup Failed - mysqldump error on $(hostname)" "$ADMIN_EMAIL"
            continue
        }
    fi

    # Copy all files from the app directory
    cp -r "$APP_PATH" "$TMP/files"

    # Determine the backup filename
    if [ "$MODE" = "weekly" ]; then
        OUT="${APP}_week-${WEEK}.tar.gz"
    elif [ "$MODE" = "monthly" ]; then
        OUT="${APP}_month-${MONTH}.tar.gz"
    elif [ "$MODE" = "yearly" ]; then
        OUT="${APP}_year-${YEAR}.tar.gz"
    else
        OUT="${APP}_${DATE}.tar.gz"
    fi

    # Archive the backup
    tar -czf "$BACKUP_DIR/$OUT" -C "$TMP" .


    # Upload to Vultr Object Storage
    if aws s3 cp "$BACKUP_DIR/$OUT" "s3://$VULTR_BUCKET/$APP/$MODE/$OUT" --endpoint-url "$VULTR_ENDPOINT"; then
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

# Delete monthly backups older than 12 months
find /home/runcloud/backups/monthly -type f -name "*.tar.gz" -mtime +365 -exec rm {} \;

# Delete yearly backups older than 5 years
find /home/runcloud/backups/yearly -type f -name "*.tar.gz" -mtime +1825 -exec rm {} \;