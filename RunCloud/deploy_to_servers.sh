#!/bin/bash

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/utils.sh"

main() {
  load_env
  detect_timeout_cmd
  get_all_servers_from_file
  run_script "ssh_script"
}

main