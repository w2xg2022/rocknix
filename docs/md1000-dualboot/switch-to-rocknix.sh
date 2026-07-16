#!/bin/sh
# Armbian -> 下次开机进 USB ROCKNIX
# 原理：在 eMMC boot 分区(=Armbian 的 /boot)放 /boot/rocknix/TRIGGER，boot.scr 见它就 booti ROCKNIX
set -e
if [ ! -f /boot/rocknix/Image ] || [ ! -f /boot/rocknix/rk3566-md1000.dtb ]; then
  echo "错误：/boot/rocknix/ 里缺 Image 或 dtb，无法 booti ROCKNIX"
  exit 1
fi
touch /boot/rocknix/TRIGGER
sync
echo "已放 TRIGGER，下次开机 -> ROCKNIX (USB)"
echo "3 秒后重启..."
sleep 3
reboot
