#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/../../utils.sh"
load_env

DRY_RUN="${DRY_RUN:-true}"

API_DELAY_SECONDS="${API_DELAY_SECONDS:-1}"
API_BATCH_SIZE="${API_BATCH_SIZE:-20}"
API_BATCH_PAUSE="${API_BATCH_PAUSE:-5}"
api_call_count=0

fetch_all_runcloud_servers() {
  echo "🔄 Fetching all servers from RunCloud..." >&2
  page=1
  all_entries=()

  while true; do
    echo "➡️ Fetching page $page of servers..." >&2
    response=$(curl -sS -X GET \
      "https://manage.runcloud.io/api/v3/servers?page=$page&perPage=40" \
      -H "Authorization: Bearer $RUNCLOUD_API_TOKEN" \
      -H "Accept: application/json")

    # Extract entries
    entries=$(echo "$response" | jq -c '.data[] | {id, name, ipAddress}' 2>/dev/null || true)

    if [[ -z "$entries" ]]; then
      echo "✅ No more servers found on page $page. Ending pagination." >&2
      break
    fi

    # Append entries
    while IFS= read -r entry; do
      all_entries+=("$entry")
    done <<< "$entries"

    # Determine total pages
    total_pages=$(echo "$response" | jq '.meta.pagination.total_pages // 1')
    (( page >= total_pages )) && break || ((page++))
  done

  if [[ ${#all_entries[@]} -eq 0 ]]; then
    echo "❌ No servers found in RunCloud account." >&2
    return 1
  fi

  # Output collected servers as a JSON array
  jq -n --argjson arr "$(printf '%s\n' "${all_entries[@]}" | jq -s '.')" '$arr'
}

fetch_apps_for_given_servers() {
  local servers_json="$1"

  mapfile -t server_ids < <(echo "$servers_json" | jq -r '.[].id')
  mapfile -t server_names < <(echo "$servers_json" | jq -r '.[].name')

  declare -a all_apps_local=()

  for idx in "${!server_ids[@]}"; do
    server_id="${server_ids[$idx]}"
    server_name="${server_names[$idx]}"
    echo "📡 Fetching apps for server: $server_name (ID: $server_id)" >&2

    page=1
    more=true
    while $more; do
      ((api_call_count++))
      if (( api_call_count % API_BATCH_SIZE == 0 )); then
        echo "⏳ Batch limit reached, sleeping ${API_BATCH_PAUSE}s..." >&2
        sleep "$API_BATCH_PAUSE"
      else
        sleep "$API_DELAY_SECONDS"
      fi

      response=$(curl -sS --location --request GET \
        "https://manage.runcloud.io/api/v3/servers/$server_id/webapps?sortColumn=name&sortDirection=asc&page=$page" \
        --header "Authorization: Bearer $RUNCLOUD_API_TOKEN" --header "Accept: application/json")

      if ! echo "$response" | jq -e '.data' >/dev/null 2>&1; then
        echo "⚠️ Failed to fetch apps for server $server_id page $page. Skipping." >&2
        break
      fi

      page_apps=$(echo "$response" | jq -r '.data[]?.name')
      if [[ -n "$page_apps" ]]; then
        while IFS= read -r app_name; do
          all_apps_local+=("$app_name")
        done <<< "$page_apps"
      fi

      total_pages=$(echo "$response" | jq '.meta.pagination.total_pages // 1')
      (( page >= total_pages )) && more=false || ((page++))
    done
  done

  if [[ ${#all_apps_local[@]} -eq 0 ]]; then
    echo "❌ No apps found across the given servers."
    return 1
  fi

  jq -n --argjson arr "$(printf '%s\n' "${all_apps_local[@]}" | jq -R . | jq -s .)" '$arr'
}

AUTH_HEADER="Authorization: Bearer $RUNCLOUD_API_TOKEN"

echo "🌐 Fetching first 3 servers from RunCloud for testing..."
servers_json=$(fetch_all_runcloud_servers)

echo "🔍 Fetching apps for 3 selected servers..."
all_apps_json=$(fetch_apps_for_given_servers "$servers_json")
echo "✅ Resulting apps JSON:"
echo "$all_apps_json"

# 🔎 Validate the apps JSON before continuing
if ! echo "$all_apps_json" | jq empty >/dev/null 2>&1; then
  echo "❌ Fetched apps JSON is invalid. Exiting."
  exit 1
fi

echo "☁️ Listing Vultr backup folders..."
fetch_all_vultr_backups_folders
echo "✅ Vultr backup folders:"
printf '%s\n' "${folders[@]}"

# Convert fetched app JSON to bash array
mapfile -t current_apps < <(echo "$all_apps_json" | jq -r '.[]')

# 🟢 Identify orphaned folders
echo "🔎 Identifying orphaned folders..."
orphaned_folders=()

for folder in "${folders[@]}"; do
  folder_name="${folder%/}"  # Strip trailing slash
  folder_name_lower=$(echo "$folder_name" | tr '[:upper:]' '[:lower:]')

  found=false
  for app in "${current_apps[@]}"; do
    app_lower=$(echo "$app" | tr '[:upper:]' '[:lower:]')
    if [[ "$folder_name_lower" == "$app_lower" ]]; then
      found=true
      break
    fi
  done

  if ! $found; then
    orphaned_folders+=("$folder")
  fi
done

if [[ ${#orphaned_folders[@]} -eq 0 ]]; then
  echo "✅ No orphaned folders detected."
else
  echo "🧹 Found orphaned folders:"
  printf ' - %s\n' "${orphaned_folders[@]}"
fi

echo ""
echo "🚀 Cleaning backups for current apps..."
for orphan in "${orphaned_folders[@]}"; do
  folder_name="${orphan%/}"
  echo ""
  echo "🔨 Cleaning orphaned folder: ${folder_name}"

  weekly_path="vultr:runcloud-app-backups/${folder_name}/weekly"
  daily_path="vultr:runcloud-app-backups/${folder_name}/daily"

  ## WEEKLY BACKUPS
  echo "➡️ Checking weekly backups..."
  weekly_files=$(rclone lsf "$weekly_path" 2>/dev/null || true)
  if [[ -n "$weekly_files" ]]; then
    echo "🗑 Found weekly backups:"
    echo "$weekly_files"
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "⚠️ [DRY_RUN] Would delete all files in $weekly_path"
    else
      echo "🔥 Deleting all files in $weekly_path..."
      rclone purge "$weekly_path"
    fi
  else
    echo "✅ No weekly backups found."
  fi

  ## DAILY BACKUPS
  echo "➡️ Checking daily backups..."
  daily_files=$(rclone lsf "$daily_path" 2>/dev/null | sort || true)

  if [[ -z "$daily_files" ]]; then
    echo "✅ No daily backups found."
  else
    echo "📂 Found daily backups:"
    echo "$daily_files"

    # Get all but the last (most recent) file
    mapfile -t daily_array <<< "$daily_files"
    if (( ${#daily_array[@]} > 1 )); then
      files_to_delete=("${daily_array[@]:0:${#daily_array[@]}-1}")

      for file in "${files_to_delete[@]}"; do
        full_path="${daily_path}/${file}"
        echo "🔥 Deleting $full_path..."
        rclone delete "$full_path"
      done
    else
      echo "🛡 Only one daily backup exists, skipping deletion."
    fi
  fi
done