# Load environment variables from .env file two levels up
ENV_FILE="$(dirname "$0")/../../.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "❌ .env file not found at $ENV_FILE"
  exit 1
fi

#!/bin/bash

# === Configuration ===
PUBLIC_KEY_PATH="$HOME/.ssh/id_ed25519.pub"


if [ ! -f "$PUBLIC_KEY_PATH" ]; then
  echo "❌ SSH key not found at $PUBLIC_KEY_PATH"
  exit 1
fi

page=1
while :; do
  response=$(curl -s --location --request GET "https://manage.runcloud.io/api/v3/servers?page=$page" \
    --header "Authorization: Bearer $API_KEY" \
    --header "Accept: application/json" \
    --header "Content-Type: application/json")

  if ! echo "$response" | jq empty > /dev/null 2>&1; then
    echo "❌ Invalid response from RunCloud API (page $page)"
    exit 1
  fi

  echo "$response" | jq -c '.data[]' | while read -r server; do
    ip=$(echo "$server" | jq -r '.ipAddress')
    name=$(echo "$server" | jq -r '.name')

    echo "🔍 Checking availability of $name ($ip)..."
    if ! ping -c 2 -W 2 "$ip" > /dev/null; then
      echo "❌ $name ($ip) is offline."
      if command -v mail >/dev/null; then
        echo "$name ($ip) appears to be offline." | mail -s "🚨 Server Offline: $name" "$NOTIFY_EMAIL"
      fi
      continue
    fi

    echo "✅ $name is online. Deploying..."

    ssh -o StrictHostKeyChecking=no root@"$ip" bash <<'EOF'
# === Install AWS CLI ===
if ! command -v aws >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y awscli
fi

# === Configure AWS CLI for Vultr ===
aws configure set aws_access_key_id "---------access_key----------"
aws configure set aws_secret_access_key "---------secret_access---------"
aws configure set default.region us-east-1
aws configure set default.output json

mkdir -p ~/.aws
cat > ~/.aws/config <<EOF_AWS_CONFIG
[default]
region = us-east-1
output = json

s3 =
    endpoint_url = https://sjc1.vultrobjects.com
EOF_AWS_CONFIG

# === Write full_vultr_backup.sh ===
cat > /root/full_vultr_backup.sh <<'EOS'
#!/bin/bash
set -euo pipefail

main() {
  if [ -z "${1:-}" ]; then
    echo "❌ Usage: $0 [daily|weekly|monthly|yearly]"
    exit 1
  fi

  MODE=$1
  WEBAPPS_DIR="/home/runcloud/webapps"
  BACKUP_DIR="/home/runcloud/backups/$MODE"
  VULTR_BUCKET="runcloud-app-backups"
  VULTR_ENDPOINT="https://sjc1.vultrobjects.com"

  DATE=$(date +'%Y-%m-%d')
  WEEK=$(date +'%Y-%V')
  MONTH=$(date +'%Y-%m')
  YEAR=$(date +'%Y')

  mkdir -p "$BACKUP_DIR"

  for APP_PATH in "$WEBAPPS_DIR"/*; do
    [ -d "$APP_PATH" ] || continue
    APP=$(basename "$APP_PATH")
    CONFIG="$APP_PATH/wp-config.php"
    TMP="/tmp/${APP}_${MODE}_backup"
    mkdir -p "$TMP"

    if [ -f "$CONFIG" ]; then
      DB_NAME=$(grep "DB_NAME" "$CONFIG" | sed "s/.*'\\(.*\\)'.*/\\1/")
      DB_USER=$(grep "DB_USER" "$CONFIG" | sed "s/.*'\\(.*\\)'.*/\\1/")
      DB_PASS=$(grep "DB_PASSWORD" "$CONFIG" | sed "s/.*'\\(.*\\)'.*/\\1/")

      if ! mysqldump -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$TMP/db.sql"; then
        echo "❌ Failed DB backup for $APP on $(hostname)" | mail -s "🚨 DB Backup Failed: $APP" development@growme.ca
        continue
      fi
    fi

    cp -r "$APP_PATH" "$TMP/files"

    if [ "$MODE" = "weekly" ]; then
      OUT="${APP}_week-${WEEK}.tar.gz"
    elif [ "$MODE" = "monthly" ]; then
      OUT="${APP}_month-${MONTH}.tar.gz"
    elif [ "$MODE" = "yearly" ]; then
      OUT="${APP}_year-${YEAR}.tar.gz"
    else
      OUT="${APP}_${DATE}.tar.gz"
    fi

    tar -czf "$BACKUP_DIR/$OUT" -C "$TMP" .

    if aws s3 cp "$BACKUP_DIR/$OUT" "s3://$VULTR_BUCKET/$APP/$MODE/$OUT" --endpoint-url "$VULTR_ENDPOINT"; then
      echo "Uploaded $OUT to Vultr" >> ~/backup_upload.log
      rm -rf "$TMP"
      rm -f "$BACKUP_DIR/$OUT"
    else
      echo "❌ Upload failed for $OUT" >> ~/backup_upload.log
    fi
  done
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
EOS

chmod +x /root/full_vultr_backup.sh

# === Write check_alive.sh ===
cat > /root/check_alive.sh <<'EOC'
#!/bin/bash
set -e

PING_HOST="8.8.8.8"
EMAIL="development@growme.ca"

if ! ping -c 3 -W 3 "$PING_HOST" > /dev/null; then
  echo "⚠️ $(hostname) is unreachable (ping to $PING_HOST failed)" | mail -s "🚨 Server Health Alert: $(hostname)" "$EMAIL"
fi
EOC

chmod +x /root/check_alive.sh

# === Clear and set cron jobs ===
crontab -r

cat <<EOF_CRON | crontab -
30 2 * * * /bin/bash /root/full_vultr_backup.sh daily >> /root/backup_daily.log 2>&1
0 3 * * 0 /bin/bash /root/full_vultr_backup.sh weekly >> /root/backup_weekly.log 2>&1
*/5 * * * * /bin/bash /root/check_alive.sh
EOF_CRON

echo "✅ Script + cron jobs configured on $(hostname)"
EOF

  done

  next=$(echo "$response" | jq -r '.meta.pagination.links.next')
  if [[ "$next" == "null" || -z "$next" ]]; then
    break
  fi

  ((page++))
done