#!/bin/bash
set -euo pipefail

SERVER_IP="$1"
echo "🔍 Checking SSH access to $SERVER_IP..."

if timeout 5s ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no root@"$SERVER_IP" "echo ok" &>/dev/null; then
  echo "✅ SSH OK for $SERVER_IP"
  exit 0
else
  echo "❌ SSH FAILED for $SERVER_IP"
  exit 1
fi