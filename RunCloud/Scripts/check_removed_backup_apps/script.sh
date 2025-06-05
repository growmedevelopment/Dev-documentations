#!/bin/bash
set -euo pipefail

# === Load .env if exists ===
load_env() {
  local env_file
  env_file="$(dirname "$0")/../../.env"
  if [ -f "$env_file" ]; then
    set -a
    source "$env_file"
    set +a
  fi
}

# === Get S3 folders from Vultr ===
fetch_s3_folders() {
  echo "☁️ Listing top-level folders in bucket: $BUCKET"
  folders=()
  while IFS= read -r line; do
    folders+=("$line")
  done < <(aws s3 ls "s3://$BUCKET/" --endpoint-url "$ENDPOINT" | awk '/PRE/ {print $2}' | sed 's#/##')

  echo "✅ Folders saved:"
  for folder in "${folders[@]}"; do
    echo "  -> $folder"
  done
}

# === Fetch all apps from RunCloud across all servers ===
fetch_all_apps_for_server() {
  local server_id=$1
  local page=1
  local more=true

  while $more; do
    echo "📡 Fetching apps from server: $server_id (page $page)"
    local response
    response=$(curl -s --location --request GET "$BASE_URL/servers/$server_id/webapps?sortColumn=name&sortDirection=asc&page=$page" \
      --header "$AUTH_HEADER" --header "Accept: application/json")

    if ! echo "$response" | jq -e '.data' >/dev/null 2>&1; then
      echo "  ⚠️ Failed to fetch apps for server $server_id. Skipping."
      break
    fi

    local page_apps=()  # Always declare this

    local names
    names=$(echo "$response" | jq -r '.data[]?.name')

    if [[ -n "$names" ]]; then
      while IFS= read -r name; do
        page_apps+=("$name")
      done <<< "$names"
    fi

    # Only loop if array is non-empty
    if [ ${#page_apps[@]} -gt 0 ]; then
      for app in "${page_apps[@]}"; do
        all_apps+=("$app (Server ID: $server_id)")
      done
    fi

    local total_pages
    total_pages=$(echo "$response" | jq '.meta.pagination.total_pages // 1')

    if (( page >= total_pages )); then
      more=false
    else
      ((page++))
    fi
  done
}

fetch_runcloud_apps() {
  echo "🌐 Fetching servers from RunCloud..."
  all_apps=()
  local page=1

  while :; do
    local response
    response=$(curl -s --location --request GET "$BASE_URL/servers?page=$page" \
      --header "$AUTH_HEADER" --header "Accept: application/json")

    local server_ids=($(echo "$response" | jq -r '.data[]?.id'))

    if [ ${#server_ids[@]} -eq 0 ]; then
      break
    fi

    for server_id in "${server_ids[@]}"; do
      fetch_all_apps_for_server "$server_id"
    done

    ((page++))
  done

  echo "✅ Total apps found: ${#all_apps[@]}"
  for app in "${all_apps[@]}"; do
    echo "  - $app"
  done
}

# === Compare apps and folders to find orphaned folders ===
find_deleted_apps() {
  echo ""
  echo "🗑️ Folders with no corresponding RunCloud app (likely deleted):"
  deleted_apps=()
  local app_names_lower=()

  for app in "${all_apps[@]}"; do
    app_names_lower+=("$(echo "${app%% *}" | tr '[:upper:]' '[:lower:]')")
  done

  for folder in "${folders[@]}"; do
    local folder_lower
    folder_lower=$(echo "$folder" | tr '[:upper:]' '[:lower:]')
    local match=false

    for app_name in "${app_names_lower[@]}"; do
      if [[ "$folder_lower" == "$app_name" ]]; then
        match=true
        break
      fi
    done

    if [ "$match" = false ]; then
      deleted_apps+=("$folder")
    fi
  done

  if [ ${#deleted_apps[@]} -eq 0 ]; then
    echo "  ✅ All folders have matching apps."
  else
    for folder in "${deleted_apps[@]}"; do
      echo "  - $folder"
    done
  fi
}

# === Compare folders and apps to find apps missing backups ===
find_missing_app_backups() {
  echo ""
  echo "❗ Apps without corresponding S3 backup folders:"
  missing_apps=()
  local folders_lower=()

  for folder in "${folders[@]}"; do
    folders_lower+=("$(echo "$folder" | tr '[:upper:]' '[:lower:]')")
  done

  for app in "${all_apps[@]}"; do
    local app_name
    app_name=$(echo "${app%% *}" | tr '[:upper:]' '[:lower:]')
    local found=false

    for folder in "${folders_lower[@]}"; do
      if [[ "$folder" == "$app_name" ]]; then
        found=true
        break
      fi
    done

    if [ "$found" = false ]; then
      missing_apps+=("$app")
    fi
  done

  if [ ${#missing_apps[@]} -eq 0 ]; then
    echo "  ✅ All apps have backup folders."
  else
    for app in "${missing_apps[@]}"; do
      echo "  - $app"
    done
  fi
}

# === MAIN EXECUTION ===
load_env

BUCKET="runcloud-app-backups"
ENDPOINT="https://sjc1.vultrobjects.com"
BASE_URL="https://manage.runcloud.io/api/v3"
AUTH_HEADER="Authorization: Bearer $API_KEY"

fetch_s3_folders
fetch_runcloud_apps
find_deleted_apps
find_missing_app_backups