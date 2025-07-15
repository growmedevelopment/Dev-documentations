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


# === 1.1 Ensure 'at' command is installed and enabled ===
echo "⏳ Checking for 'at' command..."
if ! command -v at >/dev/null 2>&1; then
  echo "📦 Installing 'at' and enabling service..."
  apt-get install -y at && systemctl enable --now atd
else
  echo "✅ 'at' command already installed."
fi

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

# Ensure /var/log/mail.log is configured correctly (one-time setup)
MAIL_LOG="/var/log/mail.log"
MAIL_OWNER="syslog"
MAIL_GROUP="adm"
NEEDS_FIX=0

# Check if log file exists
if [ ! -f "$MAIL_LOG" ]; then
  touch "$MAIL_LOG"
  NEEDS_FIX=1
fi

# Check ownership
current_owner=$(stat -c '%U' "$MAIL_LOG")
current_group=$(stat -c '%G' "$MAIL_LOG")
if [ "$current_owner" != "$MAIL_OWNER" ] || [ "$current_group" != "$MAIL_GROUP" ]; then
  chown "$MAIL_OWNER:$MAIL_GROUP" "$MAIL_LOG"
  NEEDS_FIX=1
fi

# Check permissions
current_perm=$(stat -c '%a' "$MAIL_LOG")
if [ "$current_perm" != "640" ]; then
  chmod 640 "$MAIL_LOG"
  NEEDS_FIX=1
fi

# Restart services only if changes were made
if [ "$NEEDS_FIX" -eq 1 ]; then
  echo "Fixing mail log permissions/ownership, restarting rsyslog and postfix..."
  systemctl restart rsyslog
  systemctl restart postfix
else
  echo "Mail log permissions and ownership are already correct."
fi

# === 3.1. Deploy Automated Backup Script in 3 hours after server returned fail ===
cat <<'EOS' > /root/delayed_retry.sh
#!/bin/bash
set -euo pipefail

SERVER_IP="SERVER_IP_PLACEHOLDER"
MODE="${1:-daily}"
ADMIN_EMAIL="BACKUP_ADMIN_EMAIL_PLACEHOLDER"

if /root/full_vultr_backup.sh "$MODE"; then
  echo "✅ Delayed backup succeeded for mode: $MODE on server $SERVER_IP at $(date)" \
    | mail -s "✅ FULL BACKUP SUCCESS (Delayed) - $SERVER_IP" "$ADMIN_EMAIL"
else
  echo "❌ Delayed backup failed again for mode: $MODE on server $SERVER_IP at $(date)" \
    | mail -s "❌ FULL BACKUP FAILED AGAIN (Delayed) - $SERVER_IP" "$ADMIN_EMAIL"
fi
EOS

chmod +x /root/delayed_retry.sh

sed -i "s|SERVER_IP_PLACEHOLDER|${TARGET_IP}|" /root/delayed_retry.sh
sed -i "s|BACKUP_ADMIN_EMAIL_PLACEHOLDER|${BACKUP_ADMIN_EMAIL:-development@growme.ca}|" /root/delayed_retry.sh

# === 4. Deploy Automated Backup Script ===
echo "📜 Deploying automated backup script to /root/full_vultr_backup.sh..."
# Use a quoted 'EOS' to prevent the shell from expanding variables like "$@" or "$1" inside the heredoc.
cat <<'EOS' > /root/full_vultr_backup.sh
#!/bin/bash
set -euo pipefail

# This will be replaced by a sed command later.
ADMIN_EMAIL="BACKUP_ADMIN_EMAIL_PLACEHOLDER"
SERVER_IP="SERVER_IP_PLACEHOLDER"
CURRENT_APP=""

MIN_FREE_SPACE_MB=2048
DISK_PATH="/"
LOG_FILE="/root/backup_failure.log"

# --- Error handler ---
log_debug() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') 🐛 $1" >> /tmp/backup_debug.log
}

error_notify() {
  local MSG="$1"
  log_debug "📧 ADMIN_EMAIL is: $ADMIN_EMAIL"
  log_debug "🔔 error_notify() triggered with message: $MSG"
  echo "❌ $MSG" | tee -a "$LOG_FILE"
  if echo -e "🚨 Backup failed on $(hostname) at $(date)\n\n$MSG" \
    | mail -s "🚨 FULL BACKUP FAILURE - $(hostname)" "$ADMIN_EMAIL" 2>> /tmp/mail_error.log; then
    log_debug "📧 Email successfully sent to $ADMIN_EMAIL"
  else
    log_debug "❌ Failed to send email to $ADMIN_EMAIL (see /tmp/mail_error.log)"
  fi
}

trap 'error_notify "Unexpected script error at line $LINENO for $CURRENT_APP"' ERR

success_notify() {
  local MSG="$1"
  log_debug "📧 ADMIN_EMAIL is: $ADMIN_EMAIL"
  log_debug "✅ success_notify() triggered with message: $MSG"
  echo "$MSG" | mail -s "✅ FULL BACKUP SUCCESS - $(hostname)" "$ADMIN_EMAIL"
}

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
declare -A app_failed=()
declare -A app_recovered=()

main() {
  MODE="${1:-daily}"
  WEBAPPS_DIR="/home/runcloud/webapps"
  BACKUP_DIR="/home/runcloud/backups/$MODE"
  VULTR_BUCKET="runcloud-app-backups"

  DATE=$(date +'%Y-%m-%d')
  WEEK=$(date +'%Y-%V')
  MONTH=$(date +'%Y-%m')
  YEAR=$(date +'%Y')

  mkdir -p "$BACKUP_DIR"

  case "$MODE" in
    daily)   RETENTION_DAYS=5 ;;
    weekly)  RETENTION_DAYS=30 ;;
    monthly) RETENTION_DAYS=365 ;;
    yearly)  RETENTION_DAYS=1825 ;;
    *)       RETENTION_DAYS=0 ;;
  esac
  CUTOFF_DATE=$(date -d "-$RETENTION_DAYS days" +%s)

  for APP_PATH in "$WEBAPPS_DIR"/*; do
    [ -d "$APP_PATH" ] || continue
    APP=$(basename "$APP_PATH")
    CURRENT_APP="$APP"
    CONFIG="$APP_PATH/wp-config.php"
    TMP="/tmp/${APP}_${MODE}_backup"
    mkdir -p "$TMP"

    # --- DB Backup ---
    if [ -f "$CONFIG" ]; then
      DB_NAME=$(grep DB_NAME "$CONFIG" | sed -E "s/.*['\"](.*)['\"].*/\1/")
      DB_USER=$(grep DB_USER "$CONFIG" | sed -E "s/.*['\"](.*)['\"].*/\1/")
      DB_PASS=$(grep DB_PASSWORD "$CONFIG" | sed -E "s/.*['\"](.*)['\"].*/\1/")

      if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
        error_notify "❌ Failed to extract DB credentials from $CONFIG for $APP"
        app_failed["$APP"]=1
        continue
      fi

      echo "🔐 Dumping database for $APP..."
      if ! mysqldump -u"$DB_USER" --password="$DB_PASS" --skip-comments "$DB_NAME" > "$TMP/db.sql" 2>> "$LOG_FILE"; then
        error_notify "❌ Database backup failed for $APP (mysqldump error) on server $SERVER_IP"
        app_failed["$APP"]=1
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

    # --- Upload backup ---
    MAX_STREAM_ATTEMPTS=3
    uploaded=0
    for stream_attempt in $(seq 1 $MAX_STREAM_ATTEMPTS); do
      echo "📤 Attempt $stream_attempt/$MAX_STREAM_ATTEMPTS: Streaming tar directly to Vultr for $APP..."
      if tar -czf - -C "$TMP" . | timeout 1h rclone rcat "vultr:$VULTR_BUCKET/$APP/$MODE/$OUT" >> /tmp/backup_debug.log 2>&1; then
        log_debug "✅ Streaming backup and upload successful for $APP"
        echo "$(date '+%Y-%m-%d %H:%M:%S') ✅ Streaming backup successful for $APP" >> /root/backup_success.log
        rm -rf "$TMP"
        uploaded=1

        if [[ ${app_failed["$APP"]+exists} ]]; then
          success_notify "✅ Backup succeeded after retry for $APP on server $SERVER_IP at $(date)"
          app_recovered["$APP"]=1
          unset app_failed["$APP"]
        fi
        break
      else
        log_debug "❌ Attempt $stream_attempt failed for $APP"
        if [[ $stream_attempt -lt $MAX_STREAM_ATTEMPTS ]]; then
          echo "🔁 Retrying streaming backup in 30 seconds..."
          sleep 30
        fi
      fi
    done

    if [[ $uploaded -eq 0 ]]; then
      error_notify "❌ All $MAX_STREAM_ATTEMPTS streaming attempts failed for $APP on server $SERVER_IP"
      app_failed["$APP"]=1
    fi

    # --- Cleanup old backups based on upload date ---
    echo "🔍 Cleaning backups for $APP ($MODE) older than $RETENTION_DAYS days..."
    rclone lsl "vultr:$VULTR_BUCKET/$APP/$MODE/" | awk '{print $2, $3, substr($0, index($0,$4))}' | while read -r DATE TIME FILENAME; do
      FILE_TIMESTAMP=$(date -d "$DATE $TIME" +%s || echo 0)
      if [ "$FILE_TIMESTAMP" -lt "$CUTOFF_DATE" ]; then
        echo "🗑️ Deleting old backup: $FILENAME (uploaded: $DATE $TIME)"
        rclone delete "vultr:$VULTR_BUCKET/$APP/$MODE/$FILENAME"
      fi
    done
  done

  echo "🧹 Cleaning local backups older than $RETENTION_DAYS days"
  find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -exec rm {} \;

  echo "✅ Backup script finished for mode: $MODE"

  if [[ ${#app_failed[@]} -gt 0 ]]; then
    return 1
  else
    return 0
  fi
}

# === Retry Logic for Entire Backup Script ===
MAX_RETRIES=3
RETRY_DELAY=3600  # 1 hour in seconds

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  for attempt in $(seq 1 $MAX_RETRIES); do
    echo "🔁 Running backup attempt $attempt/$MAX_RETRIES at $(date)"
    if main "$@"; then
      if [[ $attempt -gt 1 ]]; then
          recovered_count=${#app_recovered[@]}
          if (( recovered_count > 1 )); then
            recovered_list=$(IFS=,; echo "${!app_recovered[@]}" | sed 's/ /, /g')
            success_notify "✅ Full backup succeeded on server $SERVER_IP at $(date) after retry. Recovered apps: $recovered_list"
          fi
        fi
      exit 0
    elif [[ $attempt -lt $MAX_RETRIES ]]; then
      echo "⚠️ Backup attempt $attempt failed. Retrying in $((RETRY_DELAY/60)) minutes..."
      sleep $RETRY_DELAY
    else
      echo "❌ Backup failed after $MAX_RETRIES attempts. Scheduling final retry in 3 hours..."
      error_notify "❌ Backup script failed after $MAX_RETRIES attempts on $SERVER_IP at $(date) for $CURRENT_APP. A final retry will be attempted in 3 hours."

      echo "echo '/root/delayed_retry.sh \"$1\"' | at now + 3 hours" | bash
      exit 1
    fi
  done
fi
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


# === 7. Configure Log Rotation for Backup Logs ===
echo "🔁 Configuring log rotation for backup logs..."

# Ensure logrotate is installed
apt-get install -y -qq logrotate

# Define the list of log files
log_files=(
  "/root/backup_daily.log"
  "/root/backup_failure.log"
  "/root/backup_success.log"
  "/root/backup_upload.log"
  "/root/backup_weekly.log"
  "/tmp/backup_debug.log"
  "/tmp/mail_error.log"
)

# Filter only existing log files
existing_logs=()
for file in "${log_files[@]}"; do
  if [[ -f "$file" ]]; then
    existing_logs+=("$file")
  fi
done

# Only create logrotate config if at least one file exists
if [[ ${#existing_logs[@]} -gt 0 ]]; then
  echo "   → Found ${#existing_logs[@]} log files. Writing logrotate config..."
  {
    for f in "${existing_logs[@]}"; do
      echo "$f"
    done
    cat <<'EOF'
{
    weekly
    rotate 1
    compress
    missingok
    notifempty
    su root root
}
EOF
  } > /etc/logrotate.d/vultr-backups

  chmod 0644 /etc/logrotate.d/vultr-backups
  logrotate -f /etc/logrotate.d/vultr-backups || echo "⚠️  Logrotate failed to run."
  echo "✅ Log rotation configured for backup logs."
else
  echo "ℹ️ No backup log files found. Skipping logrotate configuration."
fi


echo "🎉 All configuration complete on $(hostname)"