#!/bin/bash

echo "🚀 Starting remote deployment on $(hostname)"
echo "🧪 Checking for unallocated space..."

# Show block devices and partitions
lsblk

# Get root partition and disk
ROOT_PART=$(df / | tail -1 | awk '{print $1}')
DISK=$(lsblk -no pkname "$ROOT_PART")
DISK_DEV="/dev/$DISK"

# Detect root partition number
PART_NUM=$(echo "$ROOT_PART" | grep -o '[0-9]*$')

# Check for unallocated space
UNALLOCATED=$(lsblk -b -o NAME,SIZE,TYPE | awk -v disk="$DISK" '$1 == disk {disk_size=$2} $1 ~ disk && $3 == "part" {used+=$2} END {print disk_size - used}')

if [ "$UNALLOCATED" -gt 10485760 ]; then  # >10MB unallocated
  echo "🟡 Detected unallocated space: $UNALLOCATED bytes"
  echo "🔧 Attempting to extend partition..."

  if command -v growpart >/dev/null; then
    growpart "$DISK_DEV" "$PART_NUM"
    resize2fs "$ROOT_PART" || xfs_growfs /
    echo "✅ Partition successfully extended."
  else
    echo "❌ 'growpart' not found. Please install 'cloud-guest-utils' or manually extend the partition."
    exit 1
  fi
else
  echo "✅ No significant unallocated space detected."
fi