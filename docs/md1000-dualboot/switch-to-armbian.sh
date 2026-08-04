#!/bin/sh
# ROCKNIX -> 下次开机回 eMMC Armbian
# 原理：移除 eMMC boot 分区上的 rocknix/TRIGGER，boot.scr 找不到它就走 Armbian
set -e

M=/tmp/emmcboot
MOUNTED_BY_US=0

mkdir -p "$M"
if ! mountpoint -q "$M" 2>/dev/null && ! grep -q " $M " /proc/mounts; then
  mount /dev/mmcblk0p1 "$M"
  MOUNTED_BY_US=1
fi

if [ -e "$M/rocknix/TRIGGER" ]; then
  rm -f "$M/rocknix/TRIGGER"
  echo "已移除 TRIGGER，下次开机 -> Armbian (eMMC)"
else
  echo "TRIGGER 本就不存在，下次开机 -> Armbian (eMMC)"
fi
sync

# ★umount 失败不能挡住 reboot★
#   TRIGGER 此时【已经删掉】，切换其实已经成立；若因为目录被别人占用而 umount 失败，
#   set -e 会让脚本停在这里，使用者看到的是「按了没反应」，还以为切换没生效。
#   只卸载我们自己挂的那次，别去动别人已经挂好的。
if [ "$MOUNTED_BY_US" = "1" ]; then
  umount "$M" 2>/dev/null || echo "注意：$M 卸载失败（不影响切换，TRIGGER 已移除）"
fi

echo "3 秒后重启..."
sleep 3
reboot
