#!/bin/bash
set -euo pipefail

SERVER="$1"
echo "🔍 Checking SSH access to $SERVER..."

if timeout 5s ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no root@"$SERVER" "echo ok" &>/dev/null; then
  echo "✅ SSH OK for $SERVER"
  exit 0
else
  echo "❌ SSH FAILED for $SERVER"
  exit 1
fi