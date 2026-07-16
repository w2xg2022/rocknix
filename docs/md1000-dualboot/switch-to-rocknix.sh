#!/bin/sh
# Armbian -> 进 USB ROCKNIX（一键：需要时自动完成一次性安装，然后 booti 链载）
#
# 原理：eMMC /boot/boot.cmd 开机见到 /boot/rocknix/TRIGGER 就 booti eMMC 的 rocknix/Image
#       链载 ROCKNIX（rootfs 从 U 盘 LABEL=ROCKNIX/STORAGE）。首次运行本脚本会自动：
#       ① 把 U 盘 ROCKNIX 的 KERNEL + dtb 铺到 eMMC /boot/rocknix/
#       ② 往 /boot/boot.cmd 插入链载判断块、重编 boot.scr（自动备份 *.armbian-orig）
# 安全：没 TRIGGER 时 Armbian 照常开机；链载失败（如拔了 U 盘）也落回 Armbian，绝不变砖。
set -e
BASE=https://raw.githubusercontent.com/w2xg2022/rocknix/next/docs/md1000-dualboot
[ "$(id -u)" = "0" ] || { echo "请用 root 运行"; exit 1; }

# 判断是否需要先做一次性安装
need_setup=0
{ [ -f /boot/rocknix/Image ] && [ -f /boot/rocknix/rk3566-md1000.dtb ]; } || need_setup=1
grep -q 'rocknix/TRIGGER' /boot/boot.cmd 2>/dev/null || need_setup=1

if [ "$need_setup" = "1" ]; then
  echo "== 首次：自动完成一次性安装 =="
  command -v mkimage >/dev/null 2>&1 || { echo "缺 mkimage —— 先装：apt-get update && apt-get install -y u-boot-tools"; exit 1; }

  # ① 找带 KERNEL 的 U 盘 ROCKNIX 分区（FAT32），复制 KERNEL + dtb 到 eMMC
  USB=""; UMNT=""
  for p in $(ls /dev/sd?1 2>/dev/null); do
    m=$(mktemp -d)
    if mount -o ro "$p" "$m" 2>/dev/null && [ -f "$m/KERNEL" ]; then USB="$p"; UMNT="$m"; break; fi
    umount "$m" 2>/dev/null || true; rmdir "$m" 2>/dev/null || true
  done
  [ -n "$USB" ] || { echo "找不到带 KERNEL 的 U 盘 ROCKNIX 分区（插好 U 盘再跑）"; exit 1; }
  echo "U 盘 ROCKNIX 分区 = $USB"
  mkdir -p /boot/rocknix
  cp -f "$UMNT/KERNEL" /boot/rocknix/Image
  DTB="$UMNT/device_trees/rk3566-md1000.dtb"
  [ -f "$DTB" ] || DTB="$(ls "$UMNT"/device_trees/*.dtb 2>/dev/null | head -1)"
  [ -f "$DTB" ] || { echo "U 盘里缺 device_trees/*.dtb"; umount "$UMNT"; exit 1; }
  cp -f "$DTB" /boot/rocknix/rk3566-md1000.dtb
  sync; umount "$UMNT"; rmdir "$UMNT" 2>/dev/null || true
  echo "已铺 /boot/rocknix/{Image,rk3566-md1000.dtb}"

  # ② 装 boot.cmd 链载块（若无）+ 重编 boot.scr（带备份）
  if ! grep -q 'rocknix/TRIGGER' /boot/boot.cmd 2>/dev/null; then
    [ -f /boot/boot.cmd.armbian-orig ] || cp /boot/boot.cmd /boot/boot.cmd.armbian-orig
    [ -f /boot/boot.scr.armbian-orig ] || cp /boot/boot.scr /boot/boot.scr.armbian-orig
    curl -fsSL "$BASE/boot-rocknix-block.txt" -o /tmp/rk-blk.txt
    # 在第一处 'setenv load_addr' 之前插入链载块
    awk 'FNR==NR{blk=blk $0 ORS; next} /setenv load_addr/ && !d{printf "%s", blk; d=1} {print}' \
        /tmp/rk-blk.txt /boot/boot.cmd > /boot/boot.cmd.new
    if ! grep -q 'rocknix/TRIGGER' /boot/boot.cmd.new; then
      echo "插入失败（找不到 'setenv load_addr' 锚点），boot.cmd 未改动，已中止"; rm -f /boot/boot.cmd.new; exit 1
    fi
    mv /boot/boot.cmd.new /boot/boot.cmd
    mkimage -C none -A arm -T script -n 'flatmax load script' -d /boot/boot.cmd /boot/boot.scr >/dev/null
    echo "已装链载块并重编 boot.scr（备份：/boot/boot.{cmd,scr}.armbian-orig）"
  fi
fi

# 切换：放 TRIGGER，下次开机 -> ROCKNIX
touch /boot/rocknix/TRIGGER
sync
echo "已放 TRIGGER，下次开机 -> ROCKNIX (USB)。3 秒后重启..."
sleep 3
reboot
