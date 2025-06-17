#!/opt/homebrew/bin/bash

# === Load environment variables ===
ENV_FILE="$(dirname "$0")/../../.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "❌ .env file not found at $ENV_FILE"
  exit 1
fi

# === Required env vars check ===
for var in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY API_KEY; do
  if [[ -z "${!var}" ]]; then
    echo "❌ Missing required variable: $var"
    exit 1
  fi
done

REGION="sjc1"
BUCKET="runcloud-app-backups"

# === Fetch all existing application names from RunCloud ===
echo "📡 Fetching active application list..."
apps=()
# === Fetch all servers ===
server_ids=$(curl -s --location "https://manage.runcloud.io/api/v3/servers" \
  --header "Authorization: Bearer $API_KEY" \
  --header "Accept: application/json" \
  | jq -r '.data[].id')

# === Fetch apps for each server ===
for server_id in $server_ids; do
  page=1
  while :; do
    response=$(curl -s --location "https://manage.runcloud.io/api/v3/servers/$server_id/webapps?page=$page" \
      --header "Authorization: Bearer $API_KEY" \
      --header "Accept: application/json")

    if ! echo "$response" | jq -e '.data' > /dev/null; then
      echo "⚠️ Failed to fetch apps for server $server_id"
      break
    fi

    app_names=$(echo "$response" | jq -r '.data[].name')
    apps+=($app_names)

    has_more=$(echo "$response" | jq -r '.meta.pagination.links.next // empty')
    [[ -z "$has_more" ]] && break
    ((page++))
  done
done

# === Fetch all object keys ===
echo "📦 Getting all backups from Vultr bucket..."
all_keys=$(aws --endpoint-url https://$REGION.vultrobjects.com s3api list-objects-v2 \
  --bucket "$BUCKET" --query 'Contents[].Key' --output text | tr '\t' '\n')

# === Group backups by app ===
declare -A app_keys
for key in $all_keys; do
  app_name=$(echo "$key" | cut -d'/' -f3)
  [[ -z "$app_name" ]] && continue
  app_keys["$app_name"]+="$key"$'\n'
done

# === Delete all but latest backup for non-existent apps ===
for app in "${!app_keys[@]}"; do
  if printf '%s\n' "${apps[@]}" | grep -q -x "$app"; then
    continue  # App still exists — skip
  fi

  echo "🗂 Orphaned app: $app"
  mapfile -t keys <<< "$(printf '%s' "${app_keys[$app]}" | grep -v '^$')"

  declare -A key_dates=()
  for key in "${keys[@]}"; do
    mod_date=$(aws --endpoint-url https://$REGION.vultrobjects.com s3api head-object \
      --bucket "$BUCKET" --key "$key" --query 'LastModified' --output text)
    key_dates["$key"]="$mod_date"
  done

  sorted_keys=($(for k in "${!key_dates[@]}"; do
    printf "%s\t%s\n" "${key_dates[$k]}" "$k"
  done | sort -r | awk '{print $2}'))

  keep_key="${sorted_keys[0]}"
  echo "✅ Keeping most recent backup: $keep_key"

  for key in "${sorted_keys[@]:1}"; do
    echo "🟡 Would delete: $key (debug mode)"
  done
done