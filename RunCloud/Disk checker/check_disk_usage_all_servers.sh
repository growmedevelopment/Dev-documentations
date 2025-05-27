#!/bin/bash

# --- Configuration ---
# Load API Key and Notification Email from environment
# Adjust path if your .env is elsewhere (e.g., "$(dirname "$0")/.env" if in the same dir)
ENV_FILE="$(dirname "$0")/../../.env"

# --- Script Setup ---
TMP_API_SERVER_LIST=$(mktemp)
TMP_SUMMARY_DATA_FILE=$(mktemp) # For structured data for the HTML table
TMP_WARNINGS_LOG_FILE=$(mktemp) # For all warnings and notices

# Cleanup function to remove temp files on exit
cleanup() {
  rm -f "$TMP_API_SERVER_LIST" "$TMP_SUMMARY_DATA_FILE" "$TMP_WARNINGS_LOG_FILE"
}
trap cleanup EXIT # Register cleanup function to run on script exit (normal or error)

# --- Main Script ---

# Load environment variables
if [ -f "$ENV_FILE" ]; then
  set -a # Automatically export all variables
  source "$ENV_FILE"
  set +a
else
  echo "❌ .env file not found at $ENV_FILE. Please create it with API_KEY."
  exit 1
fi

if [ -z "$API_KEY" ]; then
  echo "❌ API_KEY is not set in the .env file or environment."
  exit 1
fi

# Initialize summary data file header for HTML table
echo -e "SERVER\tIP\tTotal\tUsed\tAvailable\tUse%" > "$TMP_SUMMARY_DATA_FILE"

# Fetch all servers from RunCloud API
echo "INFO: Fetching server list from RunCloud API..."
page=1
total_servers_from_api=0
while :; do
  response=$(curl -s --location --request GET "https://manage.runcloud.io/api/v3/servers?page=$page" \
    --header "Authorization: Bearer $API_KEY" \
    --header "Accept: application/json")

  if ! echo "$response" | jq empty > /dev/null 2>&1; then
    echo "WARN: Invalid JSON response from RunCloud API (page $page). Skipping this page." >> "$TMP_WARNINGS_LOG_FILE"
    ((page++))
    sleep 2
    continue
  fi

  servers_on_page=$(echo "$response" | jq '.data | length')
  if [[ $servers_on_page -gt 0 ]]; then
    echo "$response" | jq -c '.data[]' >> "$TMP_API_SERVER_LIST"
    if [ $? -ne 0 ]; then
        echo "WARN: jq failed to process API response for page $page." >> "$TMP_WARNINGS_LOG_FILE"
    fi
    total_servers_from_api=$((total_servers_from_api + servers_on_page))
  else
    break # No more servers
  fi
  ((page++))
  sleep 0.2 # Brief pause
done
echo "INFO: Finished fetching from API. Total server objects retrieved: $total_servers_from_api."

# Process each server
echo "INFO: Starting processing of servers..."
SERVER_PROCESSED_COUNT=0
while IFS= read -r server_json_line; do
  ((SERVER_PROCESSED_COUNT++))

  name=$(echo "$server_json_line" | jq -r '.name // "UnnamedServer"')
  ip=$(echo "$server_json_line" | jq -r '.ipAddress // "NoIP"')

  echo "Processing server #$SERVER_PROCESSED_COUNT: $name ($ip)"

  if [[ "$ip" == "NoIP" || "$name" == "UnnamedServer" ]]; then
      echo "WARN: Server #$SERVER_PROCESSED_COUNT: Missing IP or Name from API. JSON: $server_json_line" >> "$TMP_WARNINGS_LOG_FILE"
      echo -e "${name}\t${ip}\tError\tExtracting\tAPI\tData" >> "$TMP_SUMMARY_DATA_FILE"
      continue
  fi

  total_disk="N/A"; used_disk="N/A"; available_disk="N/A"; use_percent="N/A"

  # Get Disk Usage (df -k /)
  # -o LogLevel=ERROR suppresses SSH's own connection messages unless it's an error.
  # -o ConnectTimeout=10 sets a 10-second timeout for establishing the SSH connection.
  # -o BatchMode=yes disables interactive prompts (e.g., password).
  # -o StrictHostKeyChecking=no automatically adds new host keys (use with caution, consider known_hosts if security is paramount).
  # timeout 30s sets an overall timeout for the SSH command and its execution.
  df_output=$(timeout 30s ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR "root@$ip" '
    if ! command -v df >/dev/null 2>&1; then
      echo "__MISSING_DF__"
      exit 0
    fi
    df -k / | awk "NR==2 {print \$2\" \"\$3\" \"\$4\" \"\$5}"
  ' 2>/dev/null) # Capture remote command errors to /dev/null for simplicity here
  ssh_df_exit_code=$?
  if [[ "$df_output" == "__MISSING_DF__" ]]; then
    echo "WARN: $name ($ip): 'df' command is not installed." >> "$TMP_WARNINGS_LOG_FILE"
    df_output=""
  fi

  if [[ $ssh_df_exit_code -eq 0 && -n "$df_output" ]]; then
    read -r total_kb used_kb available_kb use_p <<<"$df_output"
    total_disk=$(awk -v kb="$total_kb" 'BEGIN{printf "%.1fG", kb/1024/1024}')
    used_disk=$(awk -v kb="$used_kb" 'BEGIN{printf "%.1fG", kb/1024/1024}')
    available_disk=$(awk -v kb="$available_kb" 'BEGIN{printf "%.1fG", kb/1024/1024}')
    use_percent="$use_p"
  else
    err_msg="WARN: $name ($ip): df command failed. Exit: $ssh_df_exit_code"
    if [[ $ssh_df_exit_code -eq 124 ]]; then err_msg+=" (Timeout)"; fi
    echo "$err_msg" >> "$TMP_WARNINGS_LOG_FILE"
  fi
  echo -e "${name}\t${ip}\t${total_disk}\t${used_disk}\t${available_disk}\t${use_percent}" >> "$TMP_SUMMARY_DATA_FILE"

  # Check for unallocated disk space (lsblk)
  lsblk_warning_output=$(timeout 20s ssh -o ConnectTimeout=7 -o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR "root@$ip" '
    if ! command -v lsblk >/dev/null 2>&1; then
      echo "__MISSING_LSBLK__"
      exit 0
    fi
    export LC_ALL=C
    DISK=$(lsblk -ndo NAME,TYPE | awk '\''$2 == "disk" {print $1; exit}'\'')
    PART_MOUNTED_ROOT=$(lsblk -no NAME,MOUNTPOINT | awk '\''$2 == "/" {print $1}'\'')
    if [ -z "$DISK" ] || [ -z "$PART_MOUNTED_ROOT" ]; then exit 0; fi
    PART_DEV_PATH=$(echo "$PART_MOUNTED_ROOT" | sed "s|^/dev/||")
    if [ ! -b "/dev/$DISK" ] || [ ! -b "/dev/$PART_DEV_PATH" ]; then exit 0; fi
    DISK_SIZE_BYTES=$(lsblk -nbdo SIZE "/dev/$DISK" 2>/dev/null)
    PART_SIZE_BYTES=$(lsblk -nbdo SIZE "/dev/$PART_DEV_PATH" 2>/dev/null)
    if [ -z "$DISK_SIZE_BYTES" ] || [ -z "$PART_SIZE_BYTES" ] || ! [[ "$DISK_SIZE_BYTES" =~ ^[0-9]+$ ]] || ! [[ "$PART_SIZE_BYTES" =~ ^[0-9]+$ ]]; then exit 0; fi
    DISK_GB=$((DISK_SIZE_BYTES / 1024 / 1024 / 1024))
    PART_GB=$((PART_SIZE_BYTES / 1024 / 1024 / 1024))
    if [ "$PART_GB" -lt "$DISK_GB" ] && [ $((DISK_GB - PART_GB)) -gt 1 ]; then
      UNUSED_GB=$((DISK_GB - PART_GB))
      echo "Partition /dev/'"$PART_DEV_PATH"' (${PART_GB}GB) may be smaller than disk /dev/'"$DISK"' (${DISK_GB}GB). Unallocated: ${UNUSED_GB}GB."
    fi
  ' 2>/dev/null) # Capture remote command errors to /dev/null
  ssh_lsblk_exit_code=$?
  if [[ "$lsblk_warning_output" == "__MISSING_LSBLK__" ]]; then
    echo "WARN: $name ($ip): 'lsblk' command is not installed." >> "$TMP_WARNINGS_LOG_FILE"
    lsblk_warning_output=""
  fi

  if [[ $ssh_lsblk_exit_code -ne 0 && $ssh_lsblk_exit_code -ne 124 ]]; then # 124 is timeout, already handled by empty output
      echo "WARN: $name ($ip): lsblk check failed. Exit: $ssh_lsblk_exit_code" >> "$TMP_WARNINGS_LOG_FILE"
  elif [[ $ssh_lsblk_exit_code -eq 124 ]]; then
      echo "WARN: $name ($ip): lsblk check timed out." >> "$TMP_WARNINGS_LOG_FILE"
  fi

  if [[ -n "$lsblk_warning_output" ]]; then
    echo "INFO: $name ($ip): $lsblk_warning_output" >> "$TMP_WARNINGS_LOG_FILE"
  fi
done < "$TMP_API_SERVER_LIST"
echo "INFO: Finished processing all $SERVER_PROCESSED_COUNT servers."

# Generate HTML Report
HTML_REPORT_FILE="RunCloud_Disk_Report_$(date +%Y-%m-%d).html"
echo "INFO: Generating HTML report: $HTML_REPORT_FILE"
{
  echo "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>RunCloud Disk Usage Report</title><style>"
  echo "body { font-family: sans-serif; margin: 20px; background-color: #f9f9f9; color: #333; }"
  echo "h2, h3 { color: #0056b3; }"
  echo "table { border-collapse: collapse; width: 100%; margin-bottom: 20px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); background-color: #fff; }"
  echo "th, td { border: 1px solid #ddd; padding: 8px 10px; text-align: left; }"
  echo "th { background-color: #007bff; color: white; }"
  echo "tr:nth-child(even) { background-color: #f2f2f2; }"
  echo "pre { background-color: #fff; border: 1px solid #ddd; padding: 10px; overflow-x: auto; white-space: pre-wrap; word-wrap: break-word; }"
  echo ".total-summary { margin-bottom:15px; font-size: 1.1em; }"
  echo ".error-text { color: #c00; font-weight: bold; }"
  echo "</style></head><body>"
  echo "<h2>RunCloud Server Disk Usage Report</h2>"
  echo "<p class='total-summary'>Generated: $(date)</p>"
  echo "<p class='total-summary'>Total Servers Processed: $SERVER_PROCESSED_COUNT</p>"
  echo "<table><tr><th>Server Name</th><th>IP Address</th><th>Total Disk</th><th>Used Disk</th><th>Available Disk</th><th>Use %</th></tr>"

  tail -n +2 "$TMP_SUMMARY_DATA_FILE" | while IFS=$'\t' read -r s_name s_ip s_total s_used s_avail s_use; do
    echo "<tr>"
    echo "  <td>${s_name}</td><td>${s_ip}</td>"
    td_class() { [[ "$1" == "N/A" || "$1" == "Error" ]] && echo "class='error-text'" || echo ""; }
    echo "  <td $(td_class "$s_total")>${s_total}</td>"
    echo "  <td $(td_class "$s_used")>${s_used}</td>"
    echo "  <td $(td_class "$s_avail")>${s_avail}</td>"
    echo "  <td $(td_class "$s_use")>${s_use}</td>"
    echo "</tr>"
  done
  echo "</table>"

  if [ -s "$TMP_WARNINGS_LOG_FILE" ]; then
    echo "<h3>Warnings & Notices:</h3><pre>"
    sed -e 's/&/\&/g' -e 's/</\</g' -e 's/>/\>/g' "$TMP_WARNINGS_LOG_FILE"
    echo "</pre>"
  fi
  echo "</body></html>"
} > "$HTML_REPORT_FILE"
echo "INFO: HTML report generated: $HTML_REPORT_FILE"

# Send Email Notification (Optional)
if [[ -n "$NOTIFY_EMAIL" ]] && command -v msmtp >/dev/null 2>&1; then
  echo "INFO: Attempting to send email report to $NOTIFY_EMAIL..."
  {
    echo "To: $NOTIFY_EMAIL"
    echo "Subject: RunCloud Disk Usage Report - $(date +%Y-%m-%d)"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html; charset=UTF-8"
    echo ""
    cat "$HTML_REPORT_FILE"
  } | msmtp "$NOTIFY_EMAIL"
  if [ $? -eq 0 ]; then
    echo "INFO: Email report sent successfully to $NOTIFY_EMAIL."
  else
    echo "WARN: Failed to send email via msmtp. Check msmtp configuration and logs."
  fi
elif [[ -n "$NOTIFY_EMAIL" ]]; then
  echo "WARN: 'msmtp' command not found, but NOTIFY_EMAIL is set. Cannot send email report."
fi

echo "✅ Script finished. Report: $HTML_REPORT_FILE"
# Temp files are cleaned up by the 'trap cleanup EXIT'