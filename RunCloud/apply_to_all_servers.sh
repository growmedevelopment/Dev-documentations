#!/bin/bash
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/utils.sh"

main() {
  load_env
  detect_timeout_cmd
  fetch_all_servers
  run_script "ssh_script"  # Run from Scripts/ssh_script/script.sh
}

main