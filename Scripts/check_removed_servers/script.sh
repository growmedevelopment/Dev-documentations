#!/usr/bin/env bash
set -euo pipefail

REPORT_FILE="/tmp/servers_removed_report.html"
ERROR_SUMMARY=()
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/../../utils.sh"
load_env

# Determine removed servers
get_removed_servers() {
  local vultr_json="$1"
  local runcloud_json="$2"

  # Validate Vultr JSON
  if ! echo "$vultr_json" | jq empty >/dev/null 2>&1; then
    echo "❌ ERROR: Provided Vultr JSON is invalid. Aborting." >&2
    exit 1
  fi

  # Validate RunCloud JSON
  if ! echo "$runcloud_json" | jq empty >/dev/null 2>&1; then
    echo "❌ ERROR: Provided RunCloud JSON is invalid. Aborting." >&2
    exit 1
  fi

  # Extract IPs from each set
  vultr_ips=$(echo "$vultr_json" | jq -r '.[] | .ipAddress' | sort)
  runcloud_ips=$(echo "$runcloud_json" | jq -r '.[] | .ipAddress' | sort)

  # IPs in Vultr but not in RunCloud (servers removed from RunCloud)
  removed=$(comm -23 <(echo "$vultr_ips") <(echo "$runcloud_ips"))
  echo "$removed"
}

# Generate HTML report
generate_report() {
  local removed_list="$1"

  echo "<html><body>" > "$REPORT_FILE"
  echo "<h2>🚨 Removed Servers Report - $(date)</h2>" >> "$REPORT_FILE"

  if [[ -z "$removed_list" ]]; then
    echo "<p>✅ No servers were removed. All servers are accounted for.</p>" >> "$REPORT_FILE"
  else
    echo "<p>⚠️ The following servers appear to have been removed (these IPs still exist in Vultr, but RunCloud no longer sees them):</p>" >> "$REPORT_FILE"
    echo "<ul>" >> "$REPORT_FILE"
    while IFS= read -r ip; do
      echo "<li>$ip</li>" >> "$REPORT_FILE"
    done <<< "$removed_list"
    echo "</ul>" >> "$REPORT_FILE"
  fi
}



# 🏁 Main workflow
echo "🚦 Starting removed servers check..."

vultr_data=$(fetch_all_vultr_servers)
runcloud_data=$(fetch_all_runcloud_servers)


removed_servers=$(get_removed_servers "$vultr_data" "$runcloud_data")
generate_report "$removed_servers"
send_html_report
echo "✅ Finished."