##############################################################
# 📘 RunCloud Server Disk Monitoring – Setup & Execution Guide
#
# Script Name: check_disk_usage_all_servers.sh
# Script Path: /Users/user/pathToProject/Dev-documentations/check_disk_usage_all_servers.sh
#
# ✅ Requirements:
# 1. macOS with Homebrew or Linux (Debian/Ubuntu)
# 2. Tools: jq, msmtp, coreutils (macOS)
#    macOS: brew install coreutils jq msmtp
#    Ubuntu: sudo apt install jq msmtp
#
# 3. .env file in script directory:
#    API_KEY=your_runcloud_api_key
#    NOTIFY_EMAIL=your.email@example.com
#
# 4. ~/.msmtprc configuration (Gmail example):
#    defaults
#    auth on
#    tls on
#    tls_trust_file /etc/ssl/certs/ca-certificates.crt
#    logfile ~/.msmtp.log
#
#    account gmail
#    host smtp.gmail.com
#    port 587
#    from your.email@gmail.com
#    user your.email@gmail.com
#    password your_app_password
#
#    account default : gmail
#
#    Then run: chmod 600 ~/.msmtprc
#
# 🧪 Manual Execution (required Bash on macOS):
#    /opt/homebrew/bin/bash /Users/dmytrokovalenko/Documents/Projects/Growme/Dev-documentations/check_disk_usage_all_servers.sh
#
# 🔁 Add to cron for daily checks (example: 9 AM):
#    0 9 * * * /opt/homebrew/bin/bash /Users/dmytrokovalenko/Documents/Projects/Growme/Dev-documentations/check_disk_usage_all_servers.sh > /dev/null 2>&1
#
# 📧 Output:
#    - HTML email with disk usage and unallocated space summary
#    - Highlighted rows for critical/unallocated space conditions
#    - Includes SSH/disk info failures below the main table
#
# 📂 Logs:
#    - Email delivery logs: ~/.msmtp.log
#
##############################################################
##############################################################
# 📘 RunCloud Server Disk Monitoring – Setup & Execution Guide
#
# Script Name: check_disk_usage_all_servers.sh
# Script Path: /Users/dmytrokovalenko/Documents/Projects/Growme/Dev-documentations/check_disk_usage_all_servers.sh
#
# ✅ Requirements:
# 1. macOS with Homebrew or Linux (Debian/Ubuntu)
# 2. Tools: jq, msmtp, coreutils (macOS)
#    macOS: brew install coreutils jq msmtp
#    Ubuntu: sudo apt install jq msmtp
#
# 3. .env file in script directory:
#    API_KEY=your_runcloud_api_key
#    NOTIFY_EMAIL=your.email@example.com
#
# 4. ~/.msmtprc configuration (Gmail example):
#    defaults
#    auth on
#    tls on
#    tls_trust_file /etc/ssl/certs/ca-certificates.crt
#    logfile ~/.msmtp.log
#
#    account gmail
#    host smtp.gmail.com
#    port 587
#    from your.email@gmail.com
#    user your.email@gmail.com
#    password your_app_password
#
#    account default : gmail
#
#    Then run: chmod 600 ~/.msmtprc
#
# 🧪 Manual Execution (required Bash on macOS):
#    /opt/homebrew/bin/bash /Users/dmytrokovalenko/Documents/Projects/Growme/Dev-documentations/check_disk_usage_all_servers.sh
#
# 🔁 Add to cron for daily checks (example: 9 AM):
#    0 9 * * * /opt/homebrew/bin/bash /Users/dmytrokovalenko/Documents/Projects/Growme/Dev-documentations/check_disk_usage_all_servers.sh > /dev/null 2>&1
#
# 📧 Output:
#    - HTML email with disk usage and unallocated space summary
#    - Highlighted rows for critical/unallocated space conditions
#    - Includes SSH/disk info failures below the main table
#
# 📂 Logs:
#    - Email delivery logs: ~/.msmtp.log
#
##############################################################