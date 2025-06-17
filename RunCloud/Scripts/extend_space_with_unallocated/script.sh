#!/bin/bash
set -euo pipefail

SERVER_IP="$1"

echo "🔍 Checking SSH access to $SERVER_IP..."

if timeout 5s ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no root@"$SERVER_IP" "echo ok" &>/dev/null; then
  echo "✅ SSH OK for $SERVER_IP"
  echo "🚀 Running disk extension script remotely on $SERVER_IP..."

  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$SERVER_IP" 'bash -s' "$SERVER_IP" <<'REMOTE_SCRIPT'
#!/bin/bash
set -euo pipefail

SERVER_IP="${1:-UNKNOWN}"
echo "🚀 Running disk extension check on: $(hostname)"
echo "🔍 Target Server IP (for log context): $SERVER_IP"
echo "🧪 Checking for unallocated space..."

for tool in lsblk awk grep df growpart; do
  if ! command -v "$tool" &>/dev/null; then
    echo "❌ Required command '$tool' not found. Install it before running this script."
    exit 1
  fi
done

ROOT_PART=$(df / | tail -1 | awk '{print $1}')
if [[ -z "$ROOT_PART" ]]; then
  echo "❌ Could not detect root partition. Aborting."
  exit 1
fi

DISK=$(lsblk -no pkname "$ROOT_PART" 2>/dev/null)
if [[ -z "$DISK" ]]; then
  echo "❌ Could not detect underlying disk for $ROOT_PART"
  exit 1
fi

DISK_DEV="/dev/$DISK"
PART_NUM=$(echo "$ROOT_PART" | grep -o '[0-9]*$')
if [[ -z "$PART_NUM" ]]; then
  echo "❌ Could not extract partition number from $ROOT_PART"
  exit 1
fi

UNALLOCATED=$(lsblk -b -o NAME,SIZE,TYPE | awk -v disk="$DISK" '$1 == disk {disk_size=$2} $1 ~ disk && $3 == "part" {used+=$2} END {print disk_size - used}')
echo "📦 Unallocated space: $UNALLOCATED bytes"

if [[ "$UNALLOCATED" -gt 10485760 ]]; then
  echo "🟡 Detected >10MB unallocated space."
  echo "🔧 Extending partition $DISK_DEV partition #$PART_NUM..."

  growpart "$DISK_DEV" "$PART_NUM"

  echo "🔄 Resizing filesystem..."
  if resize2fs "$ROOT_PART" 2>/dev/null; then
    echo "✅ ext4 resize successful."
  elif xfs_growfs / 2>/dev/null; then
    echo "✅ XFS resize successful."
  else
    echo "❌ Filesystem resize failed. Manual intervention may be required."
    exit 1
  fi

  echo "✅ Disk space successfully extended."
else
  echo "✅ No significant unallocated space found. Nothing to do."
fi
REMOTE_SCRIPT

  echo "✅ Finished running script on $SERVER_IP"

else
  echo "❌ SSH FAILED for $SERVER_IP"
  exit 1
fi