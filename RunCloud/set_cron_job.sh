#	1.	Iterate through all your servers via RunCloud API
#	2.	SSH into each one (assumes passwordless SSH using injected key)
#	3.	Upload and create full_vultr_backup.sh and restore-backup.sh
#	4.	Set chmod +x on both
#	5.	Add a crontab entry for daily/weekly/monthly/yearly backups


#!/bin/bash

# Replace with your actual RunCloud API token
API_KEY="YOUR_RUNCLOUD_API_KEY"
PUBLIC_KEY_PATH="$HOME/.ssh/id_ed25519.pub"

# Paths to your backup and restore script templates
BACKUP_SCRIPT="/DataBase Backup & Restore Guide/full_vultr_backup.sh"
RESTORE_SCRIPT="/DataBase Backup & Restore Guide/restore-backup.sh"

# Ensure public key exists
if [ ! -f "$PUBLIC_KEY_PATH" ]; then
  echo "❌ Public key not found at $PUBLIC_KEY_PATH"
  exit 1
fi

# Load full content of your script templates
BACKUP_CONTENT=$(<"$BACKUP_SCRIPT")
RESTORE_CONTENT=$(<"$RESTORE_SCRIPT")

page=1
while :; do
  response=$(curl -s --location --request GET "https://manage.runcloud.io/api/v3/servers?page=$page" \
    --header "Authorization: Bearer $API_KEY" \
    --header "Accept: application/json" \
    --header "Content-Type: application/json")

  # Check if response is valid
  if ! echo "$response" | jq empty > /dev/null 2>&1; then
    echo "❌ Invalid response on page $page"
    echo "$response"
    exit 1
  fi

  echo "$response" | jq -c '.data[]' | while read -r row; do
    server_id=$(echo "$row" | jq -r '.id')
    name=$(echo "$row" | jq -r '.name')
    ip=$(echo "$row" | jq -r '.ipAddress')

    echo "🔗 Connecting to $name ($ip)..."

    ssh -o StrictHostKeyChecking=no root@"$ip" <<EOF
cat > ~/full_vultr_backup.sh <<'EOS'
$BACKUP_CONTENT
EOS
cat > ~/restore-backup.sh <<'EOS'
$RESTORE_CONTENT
EOS
chmod +x ~/full_vultr_backup.sh ~/restore-backup.sh

# Setup cron jobs
(crontab -l 2>/dev/null; echo "30 2 * * * /bin/bash ~/full_vultr_backup.sh daily >> ~/backup_daily.log 2>&1") | sort -u | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * 0 /bin/bash ~/full_vultr_backup.sh weekly >> ~/backup_weekly.log 2>&1") | sort -u | crontab -
(crontab -l 2>/dev/null; echo "0 3 1 * * /bin/bash ~/full_vultr_backup.sh monthly >> ~/backup_monthly.log 2>&1") | sort -u | crontab -
(crontab -l 2>/dev/null; echo "0 3 1 1 * /bin/bash ~/full_vultr_backup.sh yearly >> ~/backup_yearly.log 2>&1") | sort -u | crontab -

echo "✅ Backup + Restore scripts and cronjobs configured on $name"
EOF
  done

  next_url=$(echo "$response" | jq -r '.meta.pagination.links.next')
  if [[ "$next_url" == "null" || -z "$next_url" ]]; then
    break
  fi

  ((page++))
done