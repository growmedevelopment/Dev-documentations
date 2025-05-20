#!/bin/bash
    MODE=$1
    WEBAPPS_DIR="/home/runcloud/webapps"
    BACKUP_DIR="/home/runcloud/backups/$MODE"
    VULTR_BUCKET="runcloud-app-backups"
    VULTR_ENDPOINT="https://sjc1.vultrobjects.com"
    DATE=$(date +'%Y-%m-%d')
    WEEK=$(date +'%Y-%V')

    mkdir -p "$BACKUP_DIR"


    for APP_PATH in "$WEBAPPS_DIR"/*; do
        APP=$(basename "$APP_PATH")
        APP_PATH="$WEBAPPS_DIR/$APP"
        CONFIG="$APP_PATH/wp-config.php"
        TMP="/tmp/${APP}_${MODE}_backup"
        mkdir -p "$TMP"

        if [ -f "$CONFIG" ]; then
            DB_NAME=$(grep "DB_NAME" "$CONFIG" | sed "s/.*'\\(.*\\)'.*/\\1/")
            DB_USER=$(grep "DB_USER" "$CONFIG" | sed "s/.*'\\(.*\\)'.*/\\1/")
            DB_PASS=$(grep "DB_PASSWORD" "$CONFIG" | sed "s/.*'\\(.*\\)'.*/\\1/")
            mysqldump -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$TMP/db.sql"
        fi

        cp -r "$APP_PATH" "$TMP/files"

        if [ "$MODE" = "weekly" ]; then

            OUT="${APP}_week-${WEEK}.tar.gz"
        else
            OUT="${APP}_${DATE}.tar.gz"
        fi

        tar -czf "$BACKUP_DIR/$OUT" -C "$TMP" .
        aws s3 cp "$BACKUP_DIR/$OUT" s3://$VULTR_BUCKET/$MODE/$OUT --endpoint-url "$VULTR_ENDPOINT"

        echo "Uploaded $OUT to Vultr" >> ~/backup_upload.log

        rm -rf "$TMP"
        rm -f "$BACKUP_DIR/$OUT"
    done

    # === CLEANUP OLD BACKUPS ===

    # Delete daily backups older than 7 days
    find /home/runcloud/backups/daily -type f -name "*.tar.gz" -mtime +7 -exec rm {} \;

    # Delete weekly backups older than 30 days
    find /home/runcloud/backups/weekly -type f -name "*.tar.gz" -mtime +30 -exec rm {} \;
