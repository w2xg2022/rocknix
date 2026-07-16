#!/bin/sh
# ROCKNIX -> 下次开机回 eMMC Armbian
# 原理：移除 eMMC boot 分区上的 /boot/rocknix/TRIGGER，boot.scr 找不到它就走 Armbian
set -e
M=/tmp/emmcboot
mkdir -p "$M"
if ! mountpoint -q "$M"; then
  mount /dev/mmcblk0p1 "$M"
fi
if [ -e "$M/rocknix/TRIGGER" ]; then
  rm -f "$M/rocknix/TRIGGER"
  echo "已移除 TRIGGER，下次开机 -> Armbian (eMMC)"
else
  echo "TRIGGER 本就不存在，下次开机 -> Armbian (eMMC)"
fi
sync
umount "$M"
echo "3 秒后重启..."
sleep 3
reboot
