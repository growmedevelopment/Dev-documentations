#!/bin/bash
set -euo pipefail

echo "🚀 Starting remote deployment on $(hostname)"

# --- Configure needrestart for non-interactive restarts to prevent hangs ---
echo "🔧 Configuring automatic service restarts for unattended upgrades..."
sed -i 's/#$nrconf{restart} = .*/$nrconf{restart} = '"'a'"';/' /etc/needrestart/needrestart.conf

# === 1. Install Dependencies (mail, etc.) ===
echo "📦 Ensuring dependencies are installed..."

# Wait for existing apt processes to release locks
echo "⏳ Waiting for apt lock to be released..."
MAX_RETRIES=12
RETRY_COUNT=0

while fuser /var/lib/apt/lists/lock >/dev/null 2>&1 \
   || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  if (( RETRY_COUNT >= MAX_RETRIES )); then
    echo "❌ Timeout: APT lock not released after $((RETRY_COUNT * 5)) seconds."
    exit 1
  fi
  echo "   → Another apt process is running. Retrying in 5s..."
  sleep 5
  ((RETRY_COUNT++))
done

# Check and disable any broken or missing Release-file repositories
echo "🔍 Checking for invalid APT sources..."
if grep -R "^deb .*mirror.rackspace.com/mariadb" /etc/apt/sources.list /etc/apt/sources.list.d/*.list &>/dev/null; then
  echo "   → Found outdated MariaDB repo; disabling it."
  sed -i.bak '/mirror\.rackspace\.com\/mariadb/s/^/# /' /etc/apt/sources.list.d/*.list || true
fi
# Use DEBIAN_FRONTEND=noninteractive to suppress interactive prompts from apt
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unzip mailutils libsasl2-modules


# === 2. Install and Configure rclone for Vultr Object Storage ===
echo "⚙️ Installing and configuring rclone for Vultr..."

if ! command -v rclone >/dev/null 2>&1; then
  curl https://rclone.org/install.sh | bash
fi

mkdir -p /root/.config/rclone
cat > /root/.config/rclone/rclone.conf <<EOF
[vultr]
type = s3
provider = Other
env_auth = false
access_key_id = ${AWS_ACCESS_KEY_ID}
secret_access_key = ${AWS_SECRET_ACCESS_KEY}
endpoint = https://sjc1.vultrobjects.com
acl = private
EOF

echo "✅ rclone configured for Vultr Object Storage."


# === 3. Configure Postfix SMTP Relay ===
echo "📧 Configuring Postfix relay..."
RELAY_SMTP="[smtp.gmail.com]:587"
RELAY_USER="$SMTP_RELAY_USER"
RELAY_PASS="$SMTP_RELAY_PASS"
postconf -e "relayhost = $RELAY_SMTP"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_use_tls = yes"
postconf -e "smtp_tls_security_level = encrypt"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

cat > /etc/postfix/sasl_passwd <<EOF
$RELAY_SMTP $RELAY_USER:$RELAY_PASS
EOF
chmod 600 /etc/postfix/sasl_passwd


# Safely remove any existing database file
rm -f /etc/postfix/sasl_passwd.db

postmap /etc/postfix/sasl_passwd
systemctl restart postfix
echo "✅ Postfix relay configured."

# === 4. Deploy Automated Backup Script ===
echo "📜 Deploying automated backup script to /root/full_vultr_backup.sh..."
# Use a quoted 'EOS' to prevent the shell from expanding variables like "$@" or "$1" inside the heredoc.
cat <<'EOS' > /root/full_vultr_backup.sh
#!/bin/bash
set -euo pipefail

# This will be replaced by a sed command later.
ADMIN_EMAIL="BACKUP_ADMIN_EMAIL_PLACEHOLDER"
SERVER_IP="SERVER_IP_PLACEHOLDER"

MIN_FREE_SPACE_MB=2048
DISK_PATH="/"
LOG_FILE="/root/backup_failure.log"

# --- Error handler ---
error_notify() {
  local MSG="$1"
  echo "❌ $MSG" | tee -a "$LOG_FILE"
  echo -e "🚨 Backup failed on $(hostname) at $(date)\n\n$MSG" | mail -s "🚨 FULL BACKUP FAILURE - $(hostname)" "$ADMIN_EMAIL"
}
trap 'error_notify "Unexpected script error at line $LINENO"' ERR

# --- Ensure 'mail' is installed ---
if ! command -v mail >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y mailutils || {
    echo "❌ Cannot install mailutils, aborting."; exit 1;
  }
fi

# --- Check disk space ---
AVAILABLE_MB=$(df -m "$DISK_PATH" | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_MB" -lt "$MIN_FREE_SPACE_MB" ]; then
  error_notify "Low disk space on $SERVER_IP: ${AVAILABLE_MB}MB available (required: ${MIN_FREE_SPACE_MB}MB)."
  exit 1
fi

main() {
  MODE="${1:-daily}"

  WEBAPPS_DIR="/home/runcloud/webapps"
  BACKUP_DIR="/home/runcloud/backups/$MODE"
  VULTR_BUCKET="runcloud-app-backups"
  VULTR_ENDPOINT="https://sjc1.vultrobjects.com"

  DATE=$(date +'%Y-%m-%d')
  WEEK=$(date +'%Y-%V')
  MONTH=$(date +'%Y-%m')
  YEAR=$(date +'%Y')

  mkdir -p "$BACKUP_DIR"

  case "$MODE" in
    daily)   RETENTION_DAYS=7 ;;
    weekly)  RETENTION_DAYS=30 ;;
    monthly) RETENTION_DAYS=365 ;;
    yearly)  RETENTION_DAYS=1825 ;;
    *)       RETENTION_DAYS=0 ;;
  esac
  CUTOFF_DATE=$(date -d "-$RETENTION_DAYS days" +%s)

  for APP_PATH in "$WEBAPPS_DIR"/*; do
    [ -d "$APP_PATH" ] || continue
    APP=$(basename "$APP_PATH")
    CONFIG="$APP_PATH/wp-config.php"
    TMP="/tmp/${APP}_${MODE}_backup"
    mkdir -p "$TMP"

    # --- DB Backup ---
    if [ -f "$CONFIG" ]; then
      DB_NAME=$(grep DB_NAME "$CONFIG" | sed -E "s/.*['\"](.*)['\"].*/\1/")
      DB_USER=$(grep DB_USER "$CONFIG" | sed -E "s/.*['\"](.*)['\"].*/\1/")
      DB_PASS=$(grep DB_PASSWORD "$CONFIG" | sed -E "s/.*['\"](.*)['\"].*/\1/")

      if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
        error_notify "Failed to extract DB credentials from $CONFIG for $APP"
        continue
      fi

      echo "🔐 Dumping database for $APP..."
      if ! mysqldump -u"$DB_USER" --password="$DB_PASS" --skip-comments "$DB_NAME" > "$TMP/db.sql" 2>> "$LOG_FILE"; then
        error_notify "❌ Database backup failed for $APP (mysqldump error)"
        continue
      fi
    fi

    # --- File backup ---
    mkdir -p "$TMP/files"
    cp -a "$APP_PATH/." "$TMP/files/"

    case "$MODE" in
      weekly) OUT="${APP}_week-${WEEK}.tar.gz" ;;
      monthly) OUT="${APP}_month-${MONTH}.tar.gz" ;;
      yearly) OUT="${APP}_year-${YEAR}.tar.gz" ;;
      *) OUT="${APP}_${DATE}.tar.gz" ;;
    esac

    TAR_PATH="$BACKUP_DIR/$OUT"
    tar -czf "$TAR_PATH" -C "$TMP" . || {
      error_notify "Failed to create archive $OUT"
      continue
    }

   # --- Upload to Vultr using rclone ---
   if [ -f "$TAR_PATH" ]; then
     echo "📤 Uploading $TAR_PATH to Vultr with rclone..."
     if rclone copy "$TAR_PATH" "vultr:$VULTR_BUCKET/$APP/$MODE/" -P; then
       echo "$(date '+%Y-%m-%d %H:%M:%S') ✅ Backup and upload successful for $APP" >> /root/backup_success.log
       rm -rf "$TMP" "$TAR_PATH"
     else
       error_notify "❌ $(date '+%Y-%m-%d %H:%M:%S') Upload failed for $APP using rclone"
     fi
   else
     error_notify "❌ $(date '+%Y-%m-%d %H:%M:%S') Backup file not found for $APP (expected at $TAR_PATH)"
   fi

    # --- Cleanup old backups for this app (Consider S3 Lifecycle Policies as an alternative) ---
    echo "🔍 Cleaning $APP backups for $MODE"
    rclone lsf --format "t" "vultr:$VULTR_BUCKET/$APP/$MODE/" --absolute | while read -r FILE; do
      FILE_NAME=$(basename "$FILE")
      FILE_TIMESTAMP=$(date -d "$(rclone lsl "vultr:$VULTR_BUCKET/$APP/$MODE/$FILE_NAME" | awk '{print $2, $3}')" +%s)
      if [ "$FILE_TIMESTAMP" -lt "$CUTOFF_DATE" ]; then
        echo "🗑️ Deleting old backup: $FILE_NAME"
        rclone delete "vultr:$VULTR_BUCKET/$APP/$MODE/$FILE_NAME"
      fi
    done
  done

  echo "🧹 Cleaning local backups older than $RETENTION_DAYS days"
  find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -exec rm {} \;

  echo "✅ Backup script finished for mode: $MODE"
}

# The "$@" is now safe because the heredoc is quoted and the shell won't expand it here.
# The script itself will handle it correctly when it runs.
[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
EOS

# Safely inject the email address using sed after the file is created.
sed -i "s|SERVER_IP_PLACEHOLDER|${TARGET_IP}|" /root/full_vultr_backup.sh
sed -i "s|BACKUP_ADMIN_EMAIL_PLACEHOLDER|${BACKUP_ADMIN_EMAIL:-development@growme.ca}|" /root/full_vultr_backup.sh
chmod +x /root/full_vultr_backup.sh

# === 5. Schedule Automated Backups (Cron) ===
echo "🗓️  Scheduling automated backups via cron..."
cat <<EOF > /etc/cron.d/vultr_backups
# Cron jobs for Vultr backups, managed by deployment script.
# Do not edit this file manually. Changes will be overwritten.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# --- Standard Backups (All Servers) ---
30 2 * * * root /root/full_vultr_backup.sh daily >> /root/backup_daily.log 2>&1
0  3 * * 0 root /root/full_vultr_backup.sh weekly >> /root/backup_weekly.log 2>&1
EOF


# This conditional block uses the TARGET_IP variable passed from the dispatcher.
if [[ "${TARGET_IP}" == "216.128.183.67" ]]; then
  echo "✨ IP matched. Adding monthly and yearly cron jobs for this server."
  cat <<EOF >> /etc/cron.d/vultr_backups

# --- Long-Term Archival Backups (This Server Only) ---
0 3 1 * * root /root/full_vultr_backup.sh monthly >> /root/backup_monthly.log 2>&1
0 3 1 1 * root /root/full_vultr_backup.sh yearly >> /root/backup_yearly.log 2>&1
EOF
else
  echo "ℹ️ IP did not match. Skipping long-term archival cron jobs."
fi

chmod 0644 /etc/cron.d/vultr_backups

# === 6. Deploy Interactive Restore Tool ===
echo "🔧 Deploying interactive restore tool as 'restore-backup' command..."
# Use a quoted 'EOS' here too for consistency and safety.
cat <<'EOS' > /root/restore-backup.sh
#!/bin/bash
set -euo pipefail

# === Configuration ===
WEBAPPS_DIR="/home/runcloud/webapps"
BACKUP_DIR="/home/runcloud/backups"
VULTR_BUCKET="runcloud-app-backups"
VULTR_ENDPOINT="https://sjc1.vultrobjects.com"

# --- Function to list available backups from Vultr ---
list_backups() {
  local app="$1"
  local mode="$2"
  rclone lsf "vultr:${VULTR_BUCKET}/${app}/${mode}/"
}

# === User Inputs (Improved) ===
read -p "Enter the App Name to restore: " APP
if [[ -z "$APP" ]]; then echo "App Name cannot be empty."; exit 1; fi

PS3="Select the backup type: "
select MODE in "daily" "weekly" "monthly" "yearly"; do
  if [[ -n "$MODE" ]]; then break; else echo "Invalid choice."; fi
done

echo "Fetching available '$MODE' backups for '$APP'..."
mapfile -t backups < <(list_backups "$APP" "$MODE")

if [ ${#backups[@]} -eq 0 ]; then
  echo "❌ No backups found for '$APP' of type '$MODE'. Aborting."
  exit 1
fi

PS3="Select the backup to restore (or type 'q' to quit): "
select ARCHIVE in "${backups[@]}"; do
  if [[ "$REPLY" == "q" ]]; then echo "Aborting."; exit 0; fi
  if [[ -n "$ARCHIVE" ]]; then break; else echo "Invalid choice."; fi
done

# === Setup Paths ===
APP_PATH="${WEBAPPS_DIR}/${APP}"
LOCAL_ARCHIVE_PATH="${BACKUP_DIR}/${MODE}/${ARCHIVE}"
TMP="/tmp/restore_${APP}_$(date +%s)"
SAFETY_BACKUP_DIR="/root/pre_restore_backups"
SAFETY_BACKUP_FILE="${SAFETY_BACKUP_DIR}/${APP}_pre-restore_$(date +%Y%m%d_%H%M%S).tar.gz"

# === CRITICAL: Pre-Restore Safety Backup ===
echo "🛡️  Creating a safety backup of the current state before restoring..."
mkdir -p "$SAFETY_BACKUP_DIR"
if [ -d "$APP_PATH" ]; then
  # Safety backup for database if it exists
  CONFIG="$APP_PATH/wp-config.php"
  if [ -f "$CONFIG" ]; then
    DB_NAME=$(grep "DB_NAME" "$CONFIG" | sed -E "s/.*['\"](.*)['\"].*/\1/")
    DB_USER=$(grep "DB_USER" "$CONFIG" | sed -E "s/.*['\"](.*)['\"].*/\1/")
    DB_PASS=$(grep "DB_PASSWORD" "$CONFIG" | sed -E "s/.*['\"](.*)['\"].*/\1/")
    SAFETY_DB_BACKUP="/tmp/${DB_NAME}_pre-restore.sql"
    echo "  -> Backing up current database '$DB_NAME'..."
    mysqldump -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$SAFETY_DB_BACKUP"
  fi
  # Create a single archive of the current files and the DB dump
  echo "  -> Archiving current files for '$APP'..."
  tar -czf "$SAFETY_BACKUP_FILE" -C "$APP_PATH" . ${SAFETY_DB_BACKUP:+-C /tmp/ $(basename $SAFETY_DB_BACKUP)}
  rm -f "$SAFETY_DB_BACKUP"
  echo "✅ Safety backup created at: $SAFETY_BACKUP_FILE"
else
  echo "⚠️  No existing application found at $APP_PATH. Skipping safety backup."
fi

# === Download From Vultr if Needed ===
if [ ! -f "$LOCAL_ARCHIVE_PATH" ]; then
  echo "📡 Downloading $ARCHIVE from Vultr..."
  mkdir -p "${BACKUP_DIR}/${MODE}"
  rclone copy "vultr:${VULTR_BUCKET}/${APP}/${MODE}/${ARCHIVE}" "$BACKUP_DIR/${MODE}/" --progress || {
    echo "❌ Failed to download backup from Vultr."
    exit 1
  }
fi

# === Extract Backup Archive ===
echo "📦 Extracting archive..."
rm -rf "$TMP"
mkdir -p "$TMP"
tar -xzf "$LOCAL_ARCHIVE_PATH" -C "$TMP"

# === Restore Files ===
echo "📁 Restoring files to $APP_PATH..."
mkdir -p "$APP_PATH"
rm -rf "${APP_PATH:?}"/*
cp -a "$TMP/files/." "$APP_PATH/"
echo "🔒 Setting permissions..."
chown -R runcloud:runcloud "$APP_PATH"
find "$APP_PATH" -type d -exec chmod 755 {} \;
find "$APP_PATH" -type f -exec chmod 644 {} \;

# === Restore Database ===
CONFIG="$APP_PATH/wp-config.php"
if [ -f "$CONFIG" ]; then
  DB_NAME=$(grep "DB_NAME" "$CONFIG" | sed -E "s/.*['\"](.*)['\"].*/\1/")
  DB_USER=$(grep "DB_USER" "$CONFIG" | sed -E "s/.*['\"](.*)['\"].*/\1/")
  DB_PASS=$(grep "DB_PASSWORD" "$CONFIG" | sed -E "s/.*['\"](.*)['\"].*/\1/")

  if [ -f "$TMP/db.sql" ]; then
    echo "🗃️  Importing database '$DB_NAME'..."
    mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$TMP/db.sql" && echo "✅ Database restored."
  else
    echo "⚠️  No db.sql found. Files restored only."
  fi
else
  echo "⚠️  wp-config.php not found. Skipping database restore."
fi

# === Final Cleanup ===
rm -rf "$TMP"
rm -f "$LOCAL_ARCHIVE_PATH"
echo "🧹 Deleted temporary files and local archive."
echo "✅ Restore complete for $APP from $ARCHIVE."
EOS

chmod +x /root/restore-backup.sh
echo "✅ Interactive restore tool 'restore-backup' is now available."

echo "🎉 All configuration complete on $(hostname)"