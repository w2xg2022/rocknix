#!/bin/sh
# ROCKNIX -> boot back into Armbian on eMMC.
#
# All this does is remove rocknix/TRIGGER from the eMMC boot partition. Without
# that file the u-boot script skips the chainload block and Armbian boots as
# usual.
#
# Why it has to run from Linux: u-boot can test for the file but cannot delete
# it (no ext4 write support in this build). ROCKNIX, being a full Linux, has no
# such problem.
#
# IMPORTANT: ROCKNIX's /usr is a read-only squashfs. Save this script to
# /storage (writable and persistent) before running it.
set -e

EMMC_BOOT_DEV="${EMMC_BOOT_DEV:-/dev/mmcblk0p1}"
M=/tmp/emmcboot
MOUNTED_BY_US=0

mkdir -p "$M"
if ! mountpoint -q "$M" 2>/dev/null && ! grep -q " $M " /proc/mounts; then
  mount "${EMMC_BOOT_DEV}" "$M"
  MOUNTED_BY_US=1
fi

if [ -e "$M/rocknix/TRIGGER" ]; then
  rm -f "$M/rocknix/TRIGGER"
  echo "TRIGGER removed. Next boot goes to Armbian (eMMC)."
else
  echo "TRIGGER was not present. Next boot goes to Armbian (eMMC)."
fi

sync

# A failed umount must NOT stop the reboot. By this point TRIGGER is already
# gone, so the switch has effectively happened; letting set -e abort here only
# makes it look like nothing happened. Unmount just what we mounted ourselves.
if [ "$MOUNTED_BY_US" = "1" ]; then
  umount "$M" 2>/dev/null || echo "Note: could not unmount $M (harmless, TRIGGER is already removed)."
fi

echo "Rebooting in 3 seconds..."
sleep 3
reboot
