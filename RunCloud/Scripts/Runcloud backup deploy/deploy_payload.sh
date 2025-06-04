#!/bin/bash
set -euo pipefail

echo "🚀 Starting remote deployment on $(hostname)"

# === 1. Install AWS CLI ===
if ! command -v aws >/dev/null 2>&1; then
  echo "📦 Installing AWS CLI..."
  apt-get update -qq && apt-get install -y awscli
fi

# === 2. Configure AWS CLI for Vultr Object Storage ===
echo "⚙️ Configuring AWS CLI for Vultr..."
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region us-east-1
aws configure set default.output json

mkdir -p ~/.aws
cat > ~/.aws/config <<EOF
[default]
region = us-east-1
output = json

s3 =
    endpoint_url = https://sjc1.vultrobjects.com
EOF

# === 2b. Verify AWS CLI configuration ===
if ! aws s3 ls --endpoint-url https://sjc1.vultrobjects.com > /dev/null 2>&1; then
  echo "❌ AWS CLI not properly configured or unable to connect to Vultr Object Storage."
  exit 1
fi
echo "✅ AWS CLI configured and authenticated."

# === 3. Install mail tools and configure Postfix ===
if ! dpkg -s mailutils > /dev/null 2>&1; then
  echo "📦 Installing mailutils..."
  apt-get update -qq && apt-get install -y mailutils
fi

if ! dpkg -s libsasl2-modules > /dev/null 2>&1; then
  echo "📦 Installing SASL modules..."
  apt-get install -y libsasl2-modules
fi

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
postmap /etc/postfix/sasl_passwd
systemctl restart postfix
echo "✅ Postfix relay configured."

# === 4. Write full_vultr_backup.sh ===
cat > /root/full_vultr_backup.sh <<'EOS'
#!/bin/bash
set -euo pipefail

ADMIN_EMAIL="${BACKUP_ADMIN_EMAIL:-development@growme.ca}"
MIN_FREE_SPACE_MB=2048
DISK_PATH="/"
LOG_FILE="/root/backup_failure.log"

error_notify() {
  local MSG="$1"
  echo "❌ $MSG" | tee -a "$LOG_FILE"
  echo -e "🚨 Backup failed on $(hostname) at $(date)\n\n$MSG" | mail -s "🚨 FULL BACKUP FAILURE - $(hostname)" "$ADMIN_EMAIL"
}
trap 'error_notify "Unexpected script error at line $LINENO"' ERR

if ! command -v mail >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y mailutils || {
    echo "❌ Cannot install mailutils, aborting."; exit 1;
  }
fi

AVAILABLE_MB=$(df -m "$DISK_PATH" | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_MB" -lt "$MIN_FREE_SPACE_MB" ]; then
  error_notify "Low disk space: ${AVAILABLE_MB}MB available (required: ${MIN_FREE_SPACE_MB}MB)."
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

    cp -r "$APP_PATH" "$TMP/files"

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

    if aws s3 cp "$TAR_PATH" "s3://$VULTR_BUCKET/$APP/$MODE/$OUT" --endpoint-url "$VULTR_ENDPOINT"; then
      echo "✅ Backup and upload successful for $APP" >> /root/backup_success.log
      rm -rf "$TMP" "$TAR_PATH"
    else
      error_notify "Upload failed for $APP"
    fi

    # === Cleanup old backups for this app
    echo "🔍 Cleaning $APP backups for $MODE"
    aws s3 ls "s3://$VULTR_BUCKET/$APP/$MODE/" --endpoint-url "$VULTR_ENDPOINT" | while read -r line; do
      FILE_DATE=$(echo "$line" | awk '{print $1}')
      FILE_NAME=$(echo "$line" | awk '{for (i=4; i<=NF; i++) printf $i" "; print ""}' | xargs)
      [ -z "$FILE_NAME" ] && continue
      FILE_TIMESTAMP=$(date -d "$FILE_DATE" +%s)
      if [ "$FILE_TIMESTAMP" -lt "$CUTOFF_DATE" ]; then
        echo "🗑️ Deleting old backup: $FILE_NAME"
        aws s3 rm "s3://$VULTR_BUCKET/$APP/$MODE/$FILE_NAME" --endpoint-url "$VULTR_ENDPOINT"
      fi
    done
  done

  echo "🧹 Cleaning local backups older than $RETENTION_DAYS days"
  find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -exec rm {} \;

  echo "✅ Backup script finished for mode: $MODE"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
EOS

chmod +x /root/full_vultr_backup.sh

# === 5. Write check_alive.sh ===
cat > /root/check_alive.sh <<'EOC'
#!/bin/bash
set -eo pipefail

PING_HOST="${PING_HOST:-8.8.8.8}"
EMAIL="${BACKUP_ADMIN_EMAIL:-development@growme.ca}"

if ! ping -c 3 -W 3 "$PING_HOST" > /dev/null; then
  echo "⚠️ $(hostname) is unreachable (ping to $PING_HOST failed)" | mail -s "🚨 Server Health Alert: $(hostname)" "$EMAIL"
fi
EOC

chmod +x /root/check_alive.sh

# === 6. Cron Job Setup ===
crontab -r
cat <<EOF_CRON | crontab -
30 2 * * * /bin/bash /root/full_vultr_backup.sh daily >> /root/backup_daily.log 2>&1
0 3 * * 0 /bin/bash /root/full_vultr_backup.sh weekly >> /root/backup_weekly.log 2>&1
*/5 * * * * /bin/bash /root/check_alive.sh
EOF_CRON

echo "✅ All configuration complete on $(hostname)"