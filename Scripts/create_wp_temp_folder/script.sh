#!/opt/homebrew/bin/bash
set -euo pipefail

parse_args() {
  if [[ $# -lt 1 ]]; then
    echo "❌ Usage: $0 <SERVER_IP>"
    exit 1
  fi
  SERVER_IP="$1"
}

detect_timeout_cmd() {
  if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout"
  elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout"
  else
    echo "❌ 'timeout' or 'gtimeout' is required but not installed."
    exit 1
  fi
}

run_fix() {
  echo "🔧 Connecting to $SERVER_IP and fixing WordPress apps..."
  $TIMEOUT_CMD 30s ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$SERVER_IP" "DRY_RUN=$DRY_RUN bash -s" <<'EOF'
WEBAPPS_DIR="/home/runcloud/webapps"

for APP in "$WEBAPPS_DIR"/*; do
  CONFIG="$APP/wp-config.php"
  TEMP_DIR="$APP/wp-content/temp"

  if [[ -f "$CONFIG" ]]; then
    if grep -q "define('WP_TEMP_DIR'" "$CONFIG"; then
      echo "✅ $APP: WP_TEMP_DIR already defined"
    else
      echo "📌 $APP: Adding WP_TEMP_DIR definition"
      if [[ "$DRY_RUN" == "true" ]]; then
        echo "🔍 Would append define('WP_TEMP_DIR', ...) to $CONFIG"
      else
        echo "define('WP_TEMP_DIR', dirname(__FILE__) . '/wp-content/temp/');" >> "$CONFIG"
      fi
    fi

    if [[ ! -d "$TEMP_DIR" ]]; then
      if [[ "$DRY_RUN" == "true" ]]; then
        echo "🔍 Would create $TEMP_DIR and set permissions"
      else
        mkdir -p "$TEMP_DIR"
        chown runcloud:runcloud "$TEMP_DIR"
        chmod 755 "$TEMP_DIR"
        echo "📁 $APP: Created temp directory"
      fi
    else
      echo "✅ $APP: Temp directory already exists"
    fi
  else
    echo "⚠️ $APP: wp-config.php not found"
  fi
done
EOF
}

main() {
  parse_args "$@"
  detect_timeout_cmd
  run_fix
}

main "$@"