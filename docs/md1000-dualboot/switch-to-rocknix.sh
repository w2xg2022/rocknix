#!/bin/sh
# Armbian -> 进 USB ROCKNIX（一键：需要时自动完成一次性安装，然后 booti 链载）
#
# 原理：eMMC /boot/boot.cmd 开机见到 /boot/rocknix/TRIGGER 就 booti eMMC 的 rocknix/Image
#       链载 ROCKNIX（rootfs 从 U 盘 LABEL=ROCKNIX/STORAGE）。
#       内核与 dtb 非放 eMMC 不可，因为原厂 u-boot 根本扫不到 USB；链载之后内核已经是
#       Linux，USB 由完整驱动接管，U 盘上的 rootfs 就拿得到了。
#
# 首次运行会自动装好三样东西：
#   1. /usr/local/sbin/rocknix-chainload-sync.sh   payload 同步逻辑
#   2. rocknix-chainload-sync.service              开机与【关机】各跑一次它，
#                                                  这样刚刷好的 U 盘会被自动接上，
#                                                  不必记得回来跑本脚本
#   3. /boot/boot.cmd 里的链载块 + 重编的 boot.scr（原档备份为 *.armbian-orig）
#
# 安全：没 TRIGGER 时 Armbian 照常开机 —— 那才是真正可靠的保底。
#       「链载失败会落回 Armbian」只涵盖 eMMC 上还没铺 KERNEL、load 失败那种情况；
#       一旦内核铺上去，load 与 booti 都会成功，u-boot 就此交棒，
#       ★拔 U 盘救不回来★（内核会起来，然后卡在 initramfs 找不到 rootfs）。
#       bring-up 阶段务必准备一张可开机的 Armbian SD 卡。
set -e
BASE=https://raw.githubusercontent.com/w2xg2022/rocknix/next/docs/md1000-dualboot
SYNC_BIN=/usr/local/sbin/rocknix-chainload-sync.sh
UNIT=/etc/systemd/system/rocknix-chainload-sync.service

[ "$(id -u)" = "0" ] || { echo "请用 root 运行"; exit 1; }

# 整个资料夹被 clone 下来时优先用旁边那份，否则从 GitHub 抓。
fetch() {
  _name="$1"; _dest="$2"
  _local="$(dirname "$0")/${_name}"
  if [ -f "${_local}" ]; then
    cp -f "${_local}" "${_dest}"
  else
    curl -fsSL "${BASE}/${_name}" -o "${_dest}"
  fi
}

# --- ① 装/更新同步脚本与它的 service ----------------------------------------
#
# ★刷了新固件却还在跑旧内核★是这套设计必须防的坑：链载读的是 eMMC 的
# /boot/rocknix/{Image,*.dtb}，而刷 ROCKNIX 固件只会更新 U 盘上的
# /flash/{KERNEL,device_trees/*.dtb}，两者没有任何东西会自动配对。
# 2026-07-23 实机就是这样被坑：AV 的 dts 明明是对的、新固件里的 dtb 也确实含修正，
# 但 /proc/device-tree 是旧的（12 组 pinctrl、无 rk809-sound），白白怀疑了好几轮。
# 诊断法：md5sum 两边的 dtb，不一致就是中招。
#
# 所以有三道防线：这个 service（开机+关机）、本脚本每次运行都同步（下面第 ③ 步）、
# 以及 ROCKNIX 系统内的 rocknix-kernel-sync.service 从另一边做同样的事。
echo "== 安装 payload 同步脚本 =="
mkdir -p "$(dirname "${SYNC_BIN}")"
fetch rocknix-chainload-sync.sh "${SYNC_BIN}"
chmod 755 "${SYNC_BIN}"

if command -v systemctl >/dev/null 2>&1; then
  fetch rocknix-chainload-sync.service "${UNIT}"
  systemctl daemon-reload
  systemctl enable rocknix-chainload-sync.service >/dev/null 2>&1 || true
  echo "  已启用 rocknix-chainload-sync.service（开机与关机各同步一次）"
else
  echo "  没有 systemd —— 脚本装好了，但不会自动跑"
fi

# --- ② 装 boot.cmd 链载块（这一步才是真的只做一次）--------------------------
if ! grep -q 'rocknix/TRIGGER' /boot/boot.cmd 2>/dev/null; then
  echo "== 首次：安装 boot.cmd 链载块 =="
  command -v mkimage >/dev/null 2>&1 || { echo "缺 mkimage —— 先装：apt-get update && apt-get install -y u-boot-tools"; exit 1; }

  [ -f /boot/boot.cmd.armbian-orig ] || cp /boot/boot.cmd /boot/boot.cmd.armbian-orig
  [ -f /boot/boot.scr.armbian-orig ] || cp /boot/boot.scr /boot/boot.scr.armbian-orig
  fetch boot-rocknix-block.txt /tmp/rk-blk.txt
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

# --- ③ 每次都同步 payload ---------------------------------------------------
echo "== 同步链载用的 Image/dtb =="
"${SYNC_BIN}"

# --- ④ 放 TRIGGER，下次开机 -> ROCKNIX --------------------------------------
mkdir -p /boot/rocknix
touch /boot/rocknix/TRIGGER
sync
echo "已放 TRIGGER，下次开机 -> ROCKNIX (USB)。3 秒后重启..."
sleep 3
reboot
