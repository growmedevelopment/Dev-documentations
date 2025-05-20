#!/bin/bash

    WEBAPPS_DIR="/home/runcloud/webapps"
    BACKUP_DIR="/home/runcloud/backups"
    VULTR_BUCKET="your-bucket-name"
    VULTR_ENDPOINT="https://your-region.vultrobjects.com"

    read -p "App Name: " APP
    read -p "Backup Type (daily/weekly): " MODE
    read -p "Backup Date (YYYY-MM-DD or week-YYYY-VV): " DATE

    if [[ "$MODE" == "weekly" ]]; then
      ARCHIVE="${APP}_week-${DATE}.tar.gz"
    else
      ARCHIVE="${APP}_${DATE}.tar.gz"
    fi

    LOCAL="${BACKUP_DIR}/${MODE}/${ARCHIVE}"
    TMP="/tmp/restore_${APP}"

    # Download from Vultr if not found locally
    if [ ! -f "$LOCAL" ]; then
        echo "📡 Downloading $ARCHIVE from Vultr..."
        mkdir -p "${BACKUP_DIR}/${MODE}"
        aws s3 cp "s3://${VULTR_BUCKET}/${MODE}/${ARCHIVE}" "$LOCAL" --endpoint-url "$VULTR_ENDPOINT" || {
            echo "❌ Failed to download backup from Vultr."
            exit 1
        }
    fi

    # Extract archive
    echo "📦 Extracting archive..."
    rm -rf "$TMP"
    mkdir -p "$TMP"
    tar -xzf "$LOCAL" -C "$TMP"

    # Restore files
    APP_PATH="${WEBAPPS_DIR}/${APP}"
    echo "📁 Restoring files to $APP_PATH..."
    mkdir -p "$APP_PATH"
    rm -rf "$APP_PATH"/*
    cp -r "$TMP/files/"* "$APP_PATH/"
    chown -R runcloud:runcloud "$APP_PATH"

    # Restore database
    CONFIG="$APP_PATH/wp-config.php"
    if [ -f "$CONFIG" ]; then
        DB_NAME=$(grep DB_NAME "$CONFIG" | cut -d \" -f2)
        DB_USER=$(grep DB_USER "$CONFIG" | cut -d \" -f2)
        DB_PASS=$(grep DB_PASSWORD "$CONFIG" | cut -d \" -f2)

        if [ -f "$TMP/db.sql" ]; then
            echo "🗃️ Importing database..."
            mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$TMP/db.sql" && \
            echo "✅ Database restored."
        else
            echo "⚠️ No database dump found. Files restored only."
        fi
    else
        echo "⚠️ wp-config.php not found. Skipping database restore."
    fi

    # Cleanup
    rm -rf "$TMP"
    echo "✅ Restore complete for $APP from $MODE backup dated $DATE."