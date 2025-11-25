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

# === Ensure 'jq' is installed for JSON handling ===
echo "🔧 Checking for 'jq' (required for DB credential handling)..."
if ! command -v jq >/dev/null 2>&1; then
  echo "📦 Installing jq..."
  apt-get install -y -qq jq
else
  echo "✅ 'jq' is already installed."
fi

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
SERVER_TAG_SAFE=$(echo "${SERVER_IP:-$(hostname -I | awk '{print $1}')}" | tr '.:/ ' '____' | tr -c '[:alnum:]_' '_')

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
    TMP="/tmp/${APP}_${MODE}_backup_$(date +%s)"
    rm -rf "$TMP"
    mkdir -p "$TMP"

    # --- DB Backup ---
    if [ -f "$CONFIG" ]; then
      DB_NAME=$(grep -E "define\s*\(\s*'DB_NAME'" "$CONFIG" | sed -E "s/.*'DB_NAME'\s*,\s*'([^']+)'.*/\1/")
      DB_USER=$(grep -E "define\s*\(\s*'DB_USER'" "$CONFIG" | sed -E "s/.*'DB_USER'\s*,\s*'([^']+)'.*/\1/")
      DB_PASS=$(grep -E "define\s*\(\s*'DB_PASSWORD'" "$CONFIG" | sed -E "s/.*'DB_PASSWORD'\s*,\s*'([^']+)'.*/\1/")

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
     weekly)  OUT="${APP}_${SERVER_TAG_SAFE}_week-${WEEK}.tar.gz" ;;
      monthly) OUT="${APP}_${SERVER_TAG_SAFE}_month-${MONTH}.tar.gz" ;;
      yearly)  OUT="${APP}_${SERVER_TAG_SAFE}_year-${YEAR}.tar.gz" ;;
      *)       OUT="${APP}_${SERVER_TAG_SAFE}_${DATE}.tar.gz" ;;
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
#!/usr/bin/env -S bash -Eeuo pipefail
# Restore a WP app from Vultr backups, recreating DB/user/grants exactly as in wp-config.php

set -Eeuo pipefail

# === Config ===
WEBAPPS_DIR="/home/runcloud/webapps"
BACKUP_DIR="/home/runcloud/backups"
VULTR_BUCKET="runcloud-app-backups"

need_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing $1"; exit 1; }; }
need_bin rclone
need_bin tar
need_bin mysql
need_bin jq || { echo "Installing jq..."; apt-get update -qq && apt-get install -y -qq jq; }

# --- Select app & mode ---
read -rp "Enter the App Name to restore (folder under $WEBAPPS_DIR): " APP
[[ -z "$APP" ]] && { echo "App Name cannot be empty."; exit 1; }

PS3="Select the backup type: "
select MODE in daily weekly monthly yearly; do
  [[ -n "${MODE:-}" ]] && break || echo "Invalid choice."
done

# List available archives (new naming includes SERVER_TAG in filename)
echo "Fetching available '$MODE' backups for '$APP'..."
mapfile -t BACKUPS < <(rclone lsf "vultr:${VULTR_BUCKET}/${APP}/${MODE}/" | grep -E '\.tar\.gz$' || true)
if (( ${#BACKUPS[@]} == 0 )); then
  echo "❌ No backups found for '${APP}/${MODE}'."; exit 1;
fi

echo "Available archives:"
select ARCHIVE in "${BACKUPS[@]}"; do
  [[ -n "${ARCHIVE:-}" ]] && break || echo "Invalid choice."
done

# Paths
APP_PATH="${WEBAPPS_DIR}/${APP}"
LOCAL_DIR="${BACKUP_DIR}/${MODE}"
LOCAL_ARCHIVE="${LOCAL_DIR}/${ARCHIVE}"
TMP="/tmp/restore_${APP}_$(date +%s)"
SAFETY_DIR="/root/pre_restore_backups"
SAFETY_TARBALL="${SAFETY_DIR}/${APP}_pre-restore_$(date +%Y%m%d_%H%M%S).tar.gz"
CREDS_JSON="/root/db_credentials_${APP}.json"  # snapshot for reuse/visibility

mkdir -p "$LOCAL_DIR" "$SAFETY_DIR"

# --- Ensure local copy of archive ---
if [[ ! -f "$LOCAL_ARCHIVE" ]]; then
  echo "📡 Downloading ${ARCHIVE} from Vultr..."
  rclone copy "vultr:${VULTR_BUCKET}/${APP}/${MODE}/${ARCHIVE}" "$LOCAL_DIR/" --progress
fi

# --- Extract to TMP ---
rm -rf "$TMP"; mkdir -p "$TMP"
echo "📦 Extracting ${ARCHIVE}..."
tar -xzf "$LOCAL_ARCHIVE" -C "$TMP"

# --- Determine DB credentials (prefer the ones INSIDE the archive) ---
WP_CONF_ARCHIVE="$TMP/files/wp-config.php"
WP_CONF_LIVE="$APP_PATH/wp-config.php"

extract_creds_from_wpconfig() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  local name user pass host
  name=$(grep -E "define\(\s*'DB_NAME'\s*,\s*'[^']*'\s*\)" "$f" | sed -E "s/.*'DB_NAME'\s*,\s*'([^']*)'.*/\1/")
  user=$(grep -E "define\(\s*'DB_USER'\s*,\s*'[^']*'\s*\)" "$f" | sed -E "s/.*'DB_USER'\s*,\s*'([^']*)'.*/\1/")
  pass=$(grep -E "define\(\s*'DB_PASSWORD'\s*,\s*'[^']*'\s*\)" "$f" | sed -E "s/.*'DB_PASSWORD'\s*,\s*'([^']*)'.*/\1/")
  host=$(grep -E "define\(\s*'DB_HOST'\s*,\s*'[^']*'\s*\)" "$f" | sed -E "s/.*'DB_HOST'\s*,\s*'([^']*)'.*/\1/")
  [[ -n "$name" && -n "$user" && -n "$pass" ]] || return 1
  printf '%s\n' "$name" "$user" "$pass" "${host:-localhost}"
}

DB_NAME=""; DB_USER=""; DB_PASS=""; DB_HOST="localhost"

if CREDS=($(extract_creds_from_wpconfig "$WP_CONF_ARCHIVE")); then
  DB_NAME="${CREDS[0]}"; DB_USER="${CREDS[1]}"; DB_PASS="${CREDS[2]}"; DB_HOST="${CREDS[3]}"
  echo "🔑 Using credentials from archived wp-config.php"
elif CREDS=($(extract_creds_from_wpconfig "$WP_CONF_LIVE")); then
  DB_NAME="${CREDS[0]}"; DB_USER="${CREDS[1]}"; DB_PASS="${CREDS[2]}"; DB_HOST="${CREDS[3]}"
  echo "🔑 Using credentials from LIVE wp-config.php (archive lacked one)"
else
  echo "❌ Could not extract DB credentials from wp-config.php"; exit 1
fi

# Persist creds snapshot
cat > "$CREDS_JSON" <<JSON
{"db_name":"$DB_NAME","db_user":"$DB_USER","db_pass":"$DB_PASS","db_host":"$DB_HOST"}
JSON
chmod 600 "$CREDS_JSON"

echo "DB_NAME=$DB_NAME"
echo "DB_USER=$DB_USER"
echo "DB_PASS_LEN=${#DB_PASS} (masked)"
echo "DB_HOST=$DB_HOST"

# --- Safety backup of current state (files + DB) ---
echo "🛡️ Creating safety backup of current state..."
if [[ -d "$APP_PATH" ]]; then
  SAFETY_DB_DUMP=""
  if [[ -f "$WP_CONF_LIVE" ]]; then
    # Try to dump existing DB (best-effort)
    if mysqldump -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" --single-transaction --quick --skip-lock-tables "$DB_NAME" > "/tmp/${DB_NAME}_pre-restore.sql" 2>/dev/null; then
      SAFETY_DB_DUMP="/tmp/${DB_NAME}_pre-restore.sql"
    fi
  fi
  tar -czf "$SAFETY_TARBALL" -C "$APP_PATH" . ${SAFETY_DB_DUMP:+-C /tmp $(basename "$SAFETY_DB_DUMP")}
  [[ -n "$SAFETY_DB_DUMP" ]] && rm -f "$SAFETY_DB_DUMP"
  echo "✅ Safety archive: $SAFETY_TARBALL"
else
  echo "ℹ️ No existing app directory; skipping safety backup."
fi

# --- Restore files ---
echo "📁 Restoring files to ${APP_PATH}..."
mkdir -p "$APP_PATH"
rm -rf "${APP_PATH:?}/"*
cp -a "$TMP/files/." "$APP_PATH/"

# Permissions
echo "🔒 Fixing permissions..."
chown -R runcloud:runcloud "$APP_PATH"
find "$APP_PATH" -type d -exec chmod 755 {} \;
find "$APP_PATH" -type f -exec chmod 644 {} \;

# --- Recreate DB, user, and grants exactly as in creds ---
# Handle both MySQL and MariaDB, and avoid unix_socket plugin issues
sql_escape() { printf "%s" "$1" | sed "s/'/''/g"; }

DB_NAME_SQL=$(sql_escape "$DB_NAME")
DB_USER_SQL=$(sql_escape "$DB_USER")
DB_PASS_SQL=$(sql_escape "$DB_PASS")

echo "⚙️ Ensuring database exists: \`$DB_NAME\`"
mysql -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME_SQL\`;"

# Detect unix_socket plugin and user presence
PLUGIN=$(mysql -N -e "SELECT plugin FROM mysql.user WHERE User='$DB_USER_SQL' AND Host='localhost' LIMIT 1;" 2>/dev/null || true)
USER_EXISTS=$(mysql -N -e "SELECT COUNT(*) FROM mysql.user WHERE User='$DB_USER_SQL' AND Host='localhost';" 2>/dev/null || echo 0)

if [[ "${USER_EXISTS:-0}" -gt 0 ]]; then
  echo "👤 User exists — enforcing password auth and updating password."
  if [[ "${PLUGIN:-}" == "unix_socket" ]]; then
    mysql -e "ALTER USER '$DB_USER_SQL'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_PASS_SQL';"
  else
    mysql -e "ALTER USER '$DB_USER_SQL'@'localhost' IDENTIFIED BY '$DB_PASS_SQL';"
  fi
else
  echo "👤 Creating user '$DB_USER'@'localhost'."
  mysql -e "CREATE USER '$DB_USER_SQL'@'localhost' IDENTIFIED BY '$DB_PASS_SQL';"
fi

# Grant privileges idempotently
echo "🔑 Granting privileges on \`$DB_NAME\`.* to '$DB_USER'@'localhost'"
mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME_SQL\`.* TO '$DB_USER_SQL'@'localhost'; FLUSH PRIVILEGES;"

# --- Restore DB from archive if present ---
if [[ -f "$TMP/db.sql" ]]; then
  echo "🗃️ Importing database dump..."
  mysql -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" < "$TMP/db.sql"
  echo "✅ Database restored."
else
  echo "⚠️ No db.sql in archive; files restored only."
fi

# --- Cleanup ---
rm -rf "$TMP"
# Keep the downloaded archive; remove this if you want auto-delete:
# rm -f "$LOCAL_ARCHIVE"

echo "✅ Restore complete for ${APP} (${ARCHIVE})."
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