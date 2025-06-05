#!/bin/bash
set -euo pipefail

# === Load .env if exists ===
ENV_FILE="$(dirname "$0")/../../.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

# === Config ===
BUCKET="runcloud-app-backups"
ENDPOINT="https://sjc1.vultrobjects.com"

if [[ -z "${API_KEY:-}" ]]; then
  echo "❌ API_KEY is not set. Check your .env file."
  exit 1
fi

# === Get app names from RunCloud ===
echo "📡 Fetching applications from RunCloud..."
declare -a app_names
page=1

while :; do
  response=$(curl -s --location --request GET "https://manage.runcloud.io/api/v3/servers?page=$page" \
    --header "Authorization: Bearer $API_KEY" \
    --header "Accept: application/json")

  if ! echo "$response" | jq -e '.data' >/dev/null 2>&1; then
    echo "⚠️ Invalid response from RunCloud API (page $page):"
    echo "$response"
    exit 1
  fi

  servers=$(echo "$response" | jq -c '.data[]')
  [[ -z "$servers" ]] && break

  while IFS= read -r server; do
    server_id=$(echo "$server" | jq -r '.id')
    server_name=$(echo "$server" | jq -r '.name')
    echo "🔍 Fetching apps from $server_name (ID: $server_id)"

    apps_response=$(curl -s --location --request GET "https://manage.runcloud.io/api/v3/servers/$server_id/webapps" \
      --header "Authorization: Bearer $API_KEY" \
      --header "Accept: application/json")

    if ! echo "$apps_response" | jq -e '.data' >/dev/null 2>&1; then
      echo "⚠️ Failed to get apps for server $server_name ($server_id). Response:"
      echo "$apps_response"
      continue
    fi

    apps=$(echo "$apps_response" | jq -r '.data[].name')
    while IFS= read -r app_name; do
      [[ -n "$app_name" ]] && app_names+=("$app_name")
    done <<< "$apps"
  done <<< "$servers"

  next=$(echo "$response" | jq -r '.meta?.pagination?.links?.next // empty')
  [[ -z "$next" ]] && break
  ((page++))
done

echo "✅ Found ${#app_names[@]} apps on RunCloud"

# === Get folders from Vultr bucket ===
echo "☁️ Scanning folders in Vultr bucket: $BUCKET"
backup_folders=($(aws s3 ls s3://$BUCKET/ --endpoint-url "$ENDPOINT" | awk '/PRE/ {print $2}' | sed 's#/##'))

normalize() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

# === Compare normalized names ===
unmatched=0
for folder in "${backup_folders[@]}"; do
  normalized_folder=$(normalize "$folder")
  matched=false
  for app in "${app_names[@]}"; do
    normalized_app=$(normalize "$app")
    if [[ "$normalized_folder" == "$normalized_app" ]]; then
      matched=true
      break
    fi
  done

  if ! $matched; then
    echo "❌ Unmatched backup folder: $folder"
    ((unmatched++))
  fi
done

echo "📊 Total backup folders: ${#backup_folders[@]}, Unmatched: $unmatched"