#!/opt/homebrew/bin/bash
set -euo pipefail

# === Global Config Load .env===
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/../../utils.sh"
load_env
AUTH_HEADER="Authorization: Bearer $RUNCLOUD_API_TOKEN"

# === Global Arrays ===
declare -a all_apps=()
declare -a folders=()


### === Clean old backups in daily/weekly folders ===
#cleanup_old_backups() {
#  local app_name=$1
#  local frequency=$2
#  local prefix="${app_name}/${frequency}/"
#  local objects=()
#  if ! aws s3 ls "s3://runcloud-app-backups/$prefix" --endpoint-url "https://sjc1.vultrobjects.com" | grep -q .; then
#    echo "  ⚠️  No $frequency backups found for: $app_name (skipping)"
#    return
#  fi
#  echo "🧹 Cleaning $frequency backups for: $app_name"
#  while IFS= read -r object; do
#    objects+=("$object")
#  done < <(aws s3 ls "s3://runcloud-app-backups/$prefix" --endpoint-url "https://sjc1.vultrobjects.com" | awk '{print $4}' | sort)
#  if [ ${#objects[@]} -le 1 ]; then
#    echo "  ℹ️  Only one or no backups found in $frequency for: $app_name (nothing to delete)"
#    return
#  fi
#  for ((i=0; i<${#objects[@]}-1; i++)); do
#    if [ "$DRY_RUN" = true ]; then
#      echo "  🟡 Would delete: $prefix${objects[$i]}"
#    else
#      aws s3 rm "s3://runcloud-app-backups/$prefix${objects[$i]}" --endpoint-url "https://sjc1.vultrobjects.com"
#      echo "  ❌ Deleted: $prefix${objects[$i]}"
#    fi
#  done
#  local last_index=$(( ${#objects[@]} - 1 ))
#  echo "  ✅ Kept latest: $prefix${objects[$last_index]}"
#}
#
#declare -a orphaned_folders=()
#declare -a missing_backups=()
#
#find_orphaned_folders() {
#  echo ""
#  echo "🗑️ Checking folders without corresponding RunCloud app..."
#
#  local app_names_lower=($(for app in "${all_apps[@]}"; do echo "$app" | tr '[:upper:]' '[:lower:]'; done))
#
#  for folder in "${folders[@]}"; do
#    local folder_lower
#    folder_lower=$(echo "$folder" | tr '[:upper:]' '[:lower:]')
#    local match=false
#    for app_name in "${app_names_lower[@]}"; do
#      [[ "$folder_lower" == "$app_name" ]] && match=true && break
#    done
#    if [ "$match" = false ]; then
#      echo "  🔥 Orphaned folder: $folder"
#      orphaned_folders+=("$folder")
#      cleanup_old_backups "$folder" "daily"
#      cleanup_old_backups "$folder" "weekly"
#    fi
#  done
#}

#find_apps_missing_backups() {
#  echo ""
#  echo "❗ Checking apps missing backup folders..."
#  local folders_lower=($(for folder in "${folders[@]}"; do echo "$folder" | tr '[:upper:]' '[:lower:]'; done))
#  for app in "${all_apps[@]}"; do
#    local app_lower=$(echo "$app" | tr '[:upper:]' '[:lower:]')
#    local found=false
#    for folder in "${folders_lower[@]}"; do
#      [[ "$folder" == "$app_lower" ]] && found=true && break
#    done
#    if [ "$found" = false ]; then
#      missing_backups+=("$app")
#    fi
#  done
#}

### === Detect orphaned folders ===
#find_orphaned_folders() {
#  echo ""
#  echo "🗑️ Checking folders without corresponding RunCloud app..."
#
#  # Convert all app names to lowercase once for easier comparison
#  local app_names_lower=($(for app in "${all_apps[@]}"; do echo "$app" | tr '[:upper:]' '[:lower:]'; done))
#
#  for folder in "${folders[@]}"; do
#    local folder_lower
#    folder_lower=$(echo "$folder" | tr '[:upper:]' '[:lower:]')
#    local match=false
#
#    # Compare folder to each app name
#    for app_name in "${app_names_lower[@]}"; do
#      if [[ "$folder_lower" == "$app_name" ]]; then
#        match=true
#        break
#      fi
#    done
#
#    if [ "$match" = false ]; then
#      echo "  🔥 Orphaned folder: $folder"
#
#      # Optionally cleanup backups in orphaned folders
#      cleanup_old_backups "$folder" "daily"
#      cleanup_old_backups "$folder" "weekly"
#    fi
#  done
#}

### === Detect apps missing backups ===
#find_apps_missing_backups() {
#  echo ""
#  echo "❗ Checking apps missing backup folders..."
#  local folders_lower=($(for folder in "${folders[@]}"; do echo "$folder" | tr '[:upper:]' '[:lower:]'; done))
#  local missing=()
#  for app in "${all_apps[@]}"; do
#    local app_lower=$(echo "$app" | tr '[:upper:]' '[:lower:]')
#    local found=false
#    for folder in "${folders_lower[@]}"; do
#      [[ "$folder" == "$app_lower" ]] && found=true && break
#    done
#    if [ "$found" = false ]; then
#      missing+=("$app")
#    fi
#  done
#  if [ ${#missing[@]} -eq 0 ]; then
#    echo "  ✅ All apps have backup folders."
#  else
#    for app in "${missing[@]}"; do
#      echo "  ❗ Missing backups for: $app"
#    done
#  fi
#}

#generate_html_report() {
#  local report_file="/tmp/backup_audit_report.html"
#  {
#    echo "<html><body>"
#    echo "<h2>RunCloud Backup Audit Summary</h2>"
#
#    echo "<h3>🗑️ Orphaned Folders</h3>"
#    if [ ${#orphaned_folders[@]} -eq 0 ]; then
#      echo "<p><strong>✅ No orphaned folders found.</strong></p>"
#    else
#      echo "<table border='1' cellpadding='5'><tr><th>Folder Name</th></tr>"
#      for folder in "${orphaned_folders[@]}"; do
#        echo "<tr><td>$folder</td></tr>"
#      done
#      echo "</table>"
#    fi
#
#    echo "<h3>❗ Apps Missing Backups</h3>"
#    if [ ${#missing_backups[@]} -eq 0 ]; then
#      echo "<p><strong>✅ All apps have backup folders.</strong></p>"
#    else
#      echo "<table border='1' cellpadding='5'><tr><th>App Name</th></tr>"
#      for app in "${missing_backups[@]}"; do
#        echo "<tr><td>$app</td></tr>"
#      done
#      echo "</table>"
#    fi
#
#    echo "</body></html>"
#  } > "$report_file"
#  echo "$report_file"
#}
#
#send_html_email() {
#  local html_file=$1
#  local subject="RunCloud Backup Audit Report"
#  local to="dmytro@growme.ca"
#
#  {
#    echo "To: $to"
#    echo "Subject: $subject"
#    echo "Content-Type: text/html"
#    echo ""
#    cat "$html_file"
#  } | msmtp "$to"
#}

# === MAIN EXECUTION ===
fetch_all_vultr_backups_folders
fetch_all_runcloud_apps "$AUTH_HEADER"

#
#find_orphaned_folders
#find_apps_missing_backups
#
#html_report=$(generate_html_report)
#send_html_email "$html_report"