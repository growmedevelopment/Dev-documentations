#!/bin/bash

# --- Configuration ---
ENV_FILE="$(dirname "$0")/../../.env"

REMOTE_DF_PATH="$(command -v df || echo /bin/df)"
REMOTE_LSBLK_PATH="$(command -v lsblk || echo /bin/lsblk)"
REMOTE_AWK_PATH="$(command -v awk || echo /usr/bin/awk)"
REMOTE_SED_PATH="$(command -v sed || echo /bin/sed)" # Or /bin/sed

# --- Script Setup ---
TMP_API_SERVER_LIST=$(mktemp)
# This file will now specifically store servers with unallocated space for the email
TMP_UNALLOCATED_SPACE_SERVERS_LOG=$(mktemp)
# We can still generate a full HTML report for local review if desired
TMP_FULL_SUMMARY_DATA_FILE=$(mktemp) # For structured data for the full HTML table
TMP_ALL_WARNINGS_LOG_FILE=$(mktemp)  # For all warnings for the full HTML table

cleanup() {
  rm -f "$TMP_API_SERVER_LIST" "$TMP_UNALLOCATED_SPACE_SERVERS_LOG" \
        "$TMP_FULL_SUMMARY_DATA_FILE" "$TMP_ALL_WARNINGS_LOG_FILE"
}
trap cleanup EXIT

# --- Main Script ---

if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
else
  echo "❌ .env file not found at $ENV_FILE." >&2; exit 1
fi

if [ -z "$API_KEY" ]; then
  echo "❌ API_KEY is not set." >&2; exit 1
fi

# Header for the full local report
echo -e "SERVER\tIP\tTotal\tUsed\tAvailable\tUse%\tUnallocated_Space_Warning" > "$TMP_FULL_SUMMARY_DATA_FILE"

echo "INFO: Fetching server list from RunCloud API..."
page=1
while :; do
  response=$(curl -s --location --request GET "https://manage.runcloud.io/api/v3/servers?page=$page" \
    --header "Authorization: Bearer $API_KEY" --header "Accept: application/json")

  if ! echo "$response" | jq empty > /dev/null 2>&1; then
    echo "WARN: Invalid JSON (page $page). Skipping." >> "$TMP_ALL_WARNINGS_LOG_FILE"; ((page++)); sleep 2; continue
  fi
  servers_on_page=$(echo "$response" | jq '.data | length')
  if [[ $servers_on_page -gt 0 ]]; then
    echo "$response" | jq -c '.data[]' >> "$TMP_API_SERVER_LIST"
  else
    break
  fi
  ((page++)); sleep 0.2
done
echo "INFO: API fetch complete. Processing servers..."

SERVER_PROCESSED_COUNT=0
while IFS= read -r server_json_line; do
  ((SERVER_PROCESSED_COUNT++))
  name=$(echo "$server_json_line" | jq -r '.name // "Unnamed"')
  ip=$(echo "$server_json_line" | jq -r '.ipAddress // "NoIP"')
  echo "Processing #$SERVER_PROCESSED_COUNT: $name ($ip)"

  if [[ "$ip" == "NoIP" ]]; then
    echo "WARN: $name: Missing IP from API." >> "$TMP_ALL_WARNINGS_LOG_FILE"
    echo -e "${name}\t${ip}\tN/A\tN/A\tN/A\tN/A\tAPI_Error" >> "$TMP_FULL_SUMMARY_DATA_FILE"
    continue
  fi

  total_disk="N/A"; used_disk="N/A"; available_disk="N/A"; use_percent="N/A"; unallocated_space_warning=""

  # Get df (optional for email, but good for full report)
    df_output=$(timeout 20s ssh -o ConnectTimeout=7 -o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR "root@$ip" \
      "${REMOTE_DF_PATH} -k / | ${REMOTE_AWK_PATH} 'NR==2 {print \$2\" \"\$3\" \"\$4\" \"\$5}'" 2>/dev/null)
    ssh_df_exit_code=$?

    if [[ $ssh_df_exit_code -eq 0 && "$df_output" =~ ^[0-9]+\ [0-9]+\ [0-9]+\ [0-9]+%$ ]]; then
      read -r total_kb used_kb available_kb use_p <<<"$df_output"
      total_disk=$(awk -v kb="$total_kb" 'BEGIN{printf "%.1fG", kb/1024/1024}')
      used_disk=$(awk -v kb="$used_kb" 'BEGIN{printf "%.1fG", kb/1024/1024}')
      available_disk=$(awk -v kb="$available_kb" 'BEGIN{printf "%.1fG", kb/1024/1024}')
      use_percent="$use_p"
    else
      echo "WARN: $name ($ip): df command failed or output malformed. Exit=$ssh_df_exit_code, Output='$df_output'" >> "$TMP_ALL_WARNINGS_LOG_FILE"
      total_disk="N/A"; used_disk="N/A"; available_disk="N/A"; use_percent="N/A"
    fi

  # Check for unallocated disk space (lsblk) - THIS IS CRITICAL FOR THE EMAIL
  lsblk_remote_output=$(timeout 20s ssh -o ConnectTimeout=7 -o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR "root@$ip" "
    export PATH=/usr/sbin:/usr/bin:/bin:/sbin
    export LC_ALL=C
    DISK=\$(lsblk -ndo NAME,TYPE | awk '\$2 == \"disk\" {print \$1; exit}')
    PART_MOUNTED_ROOT=\$(lsblk -no NAME,MOUNTPOINT | awk '\$2 == \"/\" {print \$1}')
    if [ -z \"\$DISK\" ] || [ -z \"\$PART_MOUNTED_ROOT\" ]; then echo 'NO_INFO'; exit 0; fi
    PART_DEV_PATH=\$(echo \"\$PART_MOUNTED_ROOT\" | sed 's|^/dev/||')
    if [ ! -b \"/dev/\$DISK\" ] || [ ! -b \"/dev/\$PART_DEV_PATH\" ]; then echo 'NO_DEVICE_PATH'; exit 0; fi
    DISK_SIZE_BYTES=\$(lsblk -nbdo SIZE \"/dev/\$DISK\" 2>/dev/null)
    PART_SIZE_BYTES=\$(lsblk -nbdo SIZE \"/dev/\$PART_DEV_PATH\" 2>/dev/null)
    if [ -z \"\$DISK_SIZE_BYTES\" ] || [ -z \"\$PART_SIZE_BYTES\" ] || ! [[ \"\$DISK_SIZE_BYTES\" =~ ^[0-9]+\$ ]] || ! [[ \"\$PART_SIZE_BYTES\" =~ ^[0-9]+\$ ]]; then echo 'NO_SIZE_INFO'; exit 0; fi
    DISK_GB=\$((DISK_SIZE_BYTES / 1024 / 1024 / 1024))
    PART_GB=\$((PART_SIZE_BYTES / 1024 / 1024 / 1024))
    if [ \"\$PART_GB\" -lt \"\$DISK_GB\" ] && [ \$((DISK_GB - PART_GB)) -gt 1 ]; then
      UNUSED_GB=\$((DISK_GB - PART_GB))
      echo \"ALERT: Partition /dev/\$PART_DEV_PATH (\${PART_GB}GB) is smaller than disk /dev/\$DISK (\${DISK_GB}GB). Unallocated: \${UNUSED_GB}GB.\"
    else
      echo \"OK\"
    fi
  " 2>/dev/null)
  ssh_lsblk_exit_code=$?

  if [[ $ssh_lsblk_exit_code -ne 0 ]]; then
    err_msg_lsblk="WARN: $name ($ip): lsblk check cmd failed (Exit: $ssh_lsblk_exit_code)."
    if [[ $ssh_lsblk_exit_code -eq 127 ]]; then err_msg_lsblk+=" (Cmd not found - check paths)";
    elif [[ $ssh_lsblk_exit_code -eq 124 ]]; then err_msg_lsblk+=" (Timeout)"; fi
    echo "$err_msg_lsblk" >> "$TMP_ALL_WARNINGS_LOG_FILE"
    unallocated_space_warning="LSBLK_Cmd_Error"
  elif [[ "$lsblk_remote_output" == "ALERT:"* ]]; then
    # Extract the warning message part after "ALERT: "
    unallocated_space_warning="${lsblk_remote_output#ALERT: }"
    echo "$name ($ip): $unallocated_space_warning" >> "$TMP_UNALLOCATED_SPACE_SERVERS_LOG"
    echo "INFO: $name ($ip): ${unallocated_space_warning}" >> "$TMP_ALL_WARNINGS_LOG_FILE"
  elif [[ "$lsblk_remote_output" == "NO_"* ]]; then # NO_INFO, NO_DEVICE_PATH, NO_SIZE_INFO
    unallocated_space_warning="LSBLK_Check_Inconclusive ($lsblk_remote_output)"
     echo "INFO: $name ($ip): ${unallocated_space_warning}" >> "$TMP_ALL_WARNINGS_LOG_FILE"
  else # Should be "OK" or empty
    unallocated_space_warning="OK"
  fi

  # For the full local HTML report
  echo -e "${name}\t${ip}\t${total_disk}\t${used_disk}\t${available_disk}\t${use_percent}\t${unallocated_space_warning}" >> "$TMP_FULL_SUMMARY_DATA_FILE"

done < "$TMP_API_SERVER_LIST"
echo "INFO: Server processing complete."

# --- Generate Full HTML Report (Optional, for local review) ---
# You can decide if you always want this, or only if issues are found, or not at all.
GENERATE_FULL_HTML_REPORT="true" # Set to "false" to disable this full report
HTML_REPORT_FILE="RunCloud_Full_Disk_Report_$(date +%Y-%m-%d).html"

if [[ "$GENERATE_FULL_HTML_REPORT" == "true" ]]; then
  echo "INFO: Generating full HTML report: $HTML_REPORT_FILE"
  {
    echo "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>RunCloud Full Disk Report</title><style>"
    echo "body { font-family: sans-serif; margin: 20px; } table { border-collapse: collapse; width: 100%; } th, td { border: 1px solid #ddd; padding: 8px; text-align: left; } th { background-color: #f0f0f0; }"
    echo ".error-text { color: #c00; } .warn-text { color: #f80; }"
    echo "</style></head><body><h2>RunCloud Full Server Disk Report - $(date)</h2>"
    echo "<p>Total Servers Processed: $SERVER_PROCESSED_COUNT</p>"
    echo "<table><tr><th>Server</th><th>IP</th><th>Total</th><th>Used</th><th>Available</th><th>Use%</th><th>Unallocated Space Status</th></tr>"
    tail -n +2 "$TMP_FULL_SUMMARY_DATA_FILE" | while IFS=$'\t' read -r s_name s_ip s_total s_used s_avail s_use s_unalloc_warn; do
      unalloc_class=""
      if [[ "$s_unalloc_warn" == "ALERT:"* || "$s_unalloc_warn" == *"Error"* || "$s_unalloc_warn" == *"Inconclusive"* ]]; then
        unalloc_class="class='warn-text'"
      fi
      echo "<tr><td>$s_name</td><td>$s_ip</td><td>$s_total</td><td>$s_used</td><td>$s_avail</td><td>$s_use</td><td $unalloc_class>$s_unalloc_warn</td></tr>"
    done
    echo "</table>"
    if [ -s "$TMP_ALL_WARNINGS_LOG_FILE" ]; then
      echo "<h3>All Warnings & Notices (including SSH/df failures):</h3><pre>"
      sed -e 's/&/\&/g' -e 's/</\</g' -e 's/>/\>/g' "$TMP_ALL_WARNINGS_LOG_FILE"
      echo "</pre>"
    fi
    echo "</body></html>"
  } > "$HTML_REPORT_FILE"
  echo "INFO: Full HTML report generated: $HTML_REPORT_FILE"
fi

# --- Conditional Email for Unallocated Space ---
if [ -s "$TMP_UNALLOCATED_SPACE_SERVERS_LOG" ]; then # Check if the log file has any content
  if [[ -n "$NOTIFY_EMAIL" ]] && command -v msmtp >/dev/null 2>&1; then
    echo "INFO: Unallocated space detected on some servers. Sending email to $NOTIFY_EMAIL..."
    EMAIL_SUBJECT="ALERT: Servers with Potential Unallocated Disk Space - $(date +%Y-%m-%d)"
    {
      echo "To: $NOTIFY_EMAIL"
      echo "Subject: $EMAIL_SUBJECT"
      echo "Content-Type: text/html; charset=UTF-8"
      echo ""
      HTML_REPORT_FILE="RunCloud_Full_Disk_Report_$(date +%Y-%m-%d).html"
      if [[ ! -s "$HTML_REPORT_FILE" ]]; then
        echo "WARN: HTML report file is empty or missing." >> "$TMP_ALL_WARNINGS_LOG_FILE"
        echo "<html><body><p><strong>Disk report generation failed or is empty.</strong></p></body></html>" > "$HTML_REPORT_FILE"
      fi
      cat "$HTML_REPORT_FILE"
    } | msmtp "$NOTIFY_EMAIL"
    if [ $? -eq 0 ]; then
      echo "INFO: Unallocated space alert email sent successfully."
    else
      echo "WARN: Failed to send unallocated space alert email via msmtp." >> "$TMP_ALL_WARNINGS_LOG_FILE"
    fi
  elif [[ -n "$NOTIFY_EMAIL" ]]; then
    echo "WARN: Unallocated space detected, but 'msmtp' not found. Email not sent." >> "$TMP_ALL_WARNINGS_LOG_FILE"
    echo "ALERT: Unallocated space found on servers listed in $TMP_UNALLOCATED_SPACE_SERVERS_LOG"
  else
    echo "INFO: Unallocated space detected. NOTIFY_EMAIL not set. Servers listed in $TMP_UNALLOCATED_SPACE_SERVERS_LOG"
  fi
else
  echo "INFO: No servers found with significant unallocated disk space."
  if [[ -n "$NOTIFY_EMAIL" ]] && command -v msmtp >/dev/null 2>&1; then
    echo "INFO: Sending 'All Clear' email to $NOTIFY_EMAIL..."
    EMAIL_SUBJECT="OK: RunCloud Disk Usage Report - $(date +%Y-%m-%d)"
    {
      echo "To: $NOTIFY_EMAIL"
      echo "Subject: $EMAIL_SUBJECT"
      echo "Content-Type: text/html; charset=UTF-8"
      echo ""
      HTML_REPORT_FILE="RunCloud_Full_Disk_Report_$(date +%Y-%m-%d).html"
      if [[ ! -s "$HTML_REPORT_FILE" ]]; then
        echo "WARN: HTML report file is empty or missing." >> "$TMP_ALL_WARNINGS_LOG_FILE"
        echo "<html><body><p><strong>Disk report generation failed or is empty.</strong></p></body></html>" > "$HTML_REPORT_FILE"
      fi
      cat "$HTML_REPORT_FILE"
    } | msmtp "$NOTIFY_EMAIL"
    if [ $? -eq 0 ]; then
      echo "INFO: All clear email sent successfully."
    else
      echo "WARN: Failed to send all clear email via msmtp." >> "$TMP_ALL_WARNINGS_LOG_FILE"
    fi
  fi
fi

echo "✅ Script finished."