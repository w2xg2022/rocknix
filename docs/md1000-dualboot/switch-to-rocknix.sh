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

# ① 每次都把 U 盘上的 KERNEL + dtb 同步到 eMMC
#
# ★这一步以前只在「eMMC 上还没有副本」时才做，是个大坑★：链载读的是 eMMC 的
# /boot/rocknix/{Image,rk3566-md1000.dtb}，而刷 ROCKNIX 固件只会更新 U 盘上的
# /flash/{KERNEL,device_trees/*.dtb}。没有任何东西会去同步这两者，于是铺过一次
# 之后 eMMC 副本就永远停在旧版 —— 刷了新固件、装置却还在跑旧内核/旧 dtb。
# 2026-07-23 实机就是这样被坑：AV 的 dts 明明是对的、新固件里的 dtb 也确实含修正，
# 但 /proc/device-tree 是旧的(12 组 pinctrl、无 rk809-sound)，白白怀疑了好几轮。
# 诊断法：md5sum 两边的 dtb，不一致就是中招。
#
# 所以改成每次运行都比对并同步。找不到 U 盘时：已有副本就只警告不中断(不比旧行为差)，
# 没副本才是真的没法继续。
sync_payload() {
  USB=""; UMNT=""
  for p in $(ls /dev/sd?1 2>/dev/null); do
    m=$(mktemp -d)
    if mount -o ro "$p" "$m" 2>/dev/null && [ -f "$m/KERNEL" ]; then USB="$p"; UMNT="$m"; break; fi
    umount "$m" 2>/dev/null || true; rmdir "$m" 2>/dev/null || true
  done
  if [ -z "$USB" ]; then
    if [ -f /boot/rocknix/Image ] && [ -f /boot/rocknix/rk3566-md1000.dtb ]; then
      echo "!! 找不到 U 盘 ROCKNIX 分区，沿用 eMMC 上现有的 Image/dtb"
      echo "!! 若刚刷过新固件，这次链载跑的会是旧内核/旧 dtb —— 插好 U 盘再跑一次本脚本"
      return 0
    fi
    echo "找不到带 KERNEL 的 U 盘 ROCKNIX 分区（插好 U 盘再跑）"; exit 1
  fi
  echo "U 盘 ROCKNIX 分区 = $USB"

  DTB="$UMNT/device_trees/rk3566-md1000.dtb"
  [ -f "$DTB" ] || DTB="$(ls "$UMNT"/device_trees/*.dtb 2>/dev/null | head -1)"
  [ -f "$DTB" ] || { echo "U 盘里缺 device_trees/*.dtb"; umount "$UMNT"; rmdir "$UMNT" 2>/dev/null || true; exit 1; }

  mkdir -p /boot/rocknix
  changed=0
  for pair in "$UMNT/KERNEL:/boot/rocknix/Image" "$DTB:/boot/rocknix/rk3566-md1000.dtb"; do
    src=${pair%:*}; dst=${pair#*:}
    if [ ! -f "$dst" ] || [ "$(md5sum <"$src" | cut -d' ' -f1)" != "$(md5sum <"$dst" | cut -d' ' -f1)" ]; then
      cp -f "$src" "$dst"; changed=1
      echo "  已更新 $(basename "$dst")"
    fi
  done
  sync; umount "$UMNT"; rmdir "$UMNT" 2>/dev/null || true
  [ "$changed" = "1" ] || echo "  Image/dtb 与 U 盘一致，无需更新"
}

echo "== 同步链载用的 Image/dtb =="
sync_payload

# 判断是否还需要装 boot.cmd 链载块（这一步才是真的只做一次）
if ! grep -q 'rocknix/TRIGGER' /boot/boot.cmd 2>/dev/null; then
  echo "== 首次：安装 boot.cmd 链载块 =="
  command -v mkimage >/dev/null 2>&1 || { echo "缺 mkimage —— 先装：apt-get update && apt-get install -y u-boot-tools"; exit 1; }

  # ② 装 boot.cmd 链载块 + 重编 boot.scr（带备份）
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

# 切换：放 TRIGGER，下次开机 -> ROCKNIX
touch /boot/rocknix/TRIGGER
sync
echo "已放 TRIGGER，下次开机 -> ROCKNIX (USB)。3 秒后重启..."
sleep 3
reboot
