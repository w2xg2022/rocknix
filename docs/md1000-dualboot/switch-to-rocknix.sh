#!/bin/sh
# Armbian -> 进 USB ROCKNIX（一键：需要时自动完成一次性安装，然后 booti 链载）
#
# 原理：eMMC /boot/boot.cmd 开机见到 /boot/rocknix/TRIGGER 就 booti eMMC 的
#       rocknix/KERNEL 链载 ROCKNIX（rootfs 从 U 盘 LABEL=ROCKNIX/STORAGE）。
#       内核与 dtb 非放 eMMC 不可，因为原厂 u-boot 根本扫不到 USB；链载之后内核已经是
#       Linux，USB 由完整驱动接管，U 盘上的 rootfs 就拿得到了。
#
# 首次运行会自动装好三样东西：
#   1. /usr/local/sbin/rocknix-chainload-sync.sh   payload 同步逻辑
#   2. rocknix-chainload-sync.service              开机与【关机】各跑一次它，
#                                                  这样刚刷好的 U 盘会被自动接上
#   3. /boot/boot.cmd 里的链载块 + 重编的 boot.scr（原档备份为 *.armbian-orig）
#
# ★TRIGGER 是常驻的，不是一次性的★
#   u-boot 只读它、不删它。所以放了之后【每次开机都进 ROCKNIX】，直到在 ROCKNIX 里
#   跑 switch-to-armbian.sh 把它删掉为止。这是刻意的：ROCKNIX 起不来时你还能靠
#   拔 U 盘以外的手段判断，而不是「重开一次就莫名其妙回到 Armbian」。
#
# 安全：没 TRIGGER 时 Armbian 照常开机 —— 那才是真正可靠的保底。
#       「链载失败会落回 Armbian」只涵盖 eMMC 上还没铺 KERNEL、load 失败那种情况；
#       一旦内核铺上去，load 与 booti 都会成功，u-boot 就此交棒，
#       ★拔 U 盘救不回来★（内核会起来，然后卡在 initramfs 找不到 rootfs）。
#       bring-up 阶段务必准备一张可开机的 Armbian SD 卡。
set -e

# ★任何一步失败都要说话★(2026-08-04 实机踩过)
#   本脚本是 set -e，而第 3 步呼叫的是【外部 helper】—— 它任何非零回传都会让整支
#   就地中止。当时的表现是：payload 同步了、boot.cmd 也打好补丁了，但 TRIGGER 没放、
#   机器也没重开，画面上一句错误都没有，使用者只觉得「跑完了却切不过去」。
#   有了这个 trap，至少永远知道它死在哪一步、退出码是多少。
STEP="启动"
trap 'rc=$?; [ "$rc" -ne 0 ] && echo "★中止于[${STEP}]，退出码 ${rc} —— TRIGGER 未设置，仍会开 Armbian★" >&2' EXIT

BASE=https://raw.githubusercontent.com/w2xg2022/rocknix/next/docs/md1000-dualboot
SYNC_BIN=/usr/local/sbin/rocknix-chainload-sync.sh
UNIT=/etc/systemd/system/rocknix-chainload-sync.service

[ "$(id -u)" = "0" ] || { echo "请用 root 运行"; exit 1; }

# 整个资料夹被 clone 下来时优先用旁边那份，否则从 GitHub 抓。
# ★用 [ -f "$0" ] 把关★：本脚本常以 `sh -` / 管线方式执行，那时 $0 不是路径，
# dirname 会得到 "."，於是「旁边那份」会误指到当前目录下的同名档。
fetch() {
  _name="$1"; _dest="$2"
  if [ -f "$0" ] && [ -f "$(dirname "$0")/${_name}" ]; then
    cp -f "$(dirname "$0")/${_name}" "${_dest}"
  else
    curl -fsSL "${BASE}/${_name}" -o "${_dest}"
  fi
}

install_boot_block() {
  command -v mkimage >/dev/null 2>&1 || {
    echo "缺 mkimage —— 先装：apt-get update && apt-get install -y u-boot-tools"
    exit 1
  }
  [ -f /boot/boot.cmd.armbian-orig ] || cp /boot/boot.cmd /boot/boot.cmd.armbian-orig
  [ -f /boot/boot.scr.armbian-orig ] || cp /boot/boot.scr /boot/boot.scr.armbian-orig
  fetch boot-rocknix-block.txt /tmp/rk-blk.txt
  # 在第一处 'setenv load_addr' 之前插入链载块
  awk 'FNR==NR{blk=blk $0 ORS; next} /setenv load_addr/ && !d{printf "%s", blk; d=1} {print}' \
      /tmp/rk-blk.txt /boot/boot.cmd > /boot/boot.cmd.new
  if ! grep -q 'rocknix/TRIGGER' /boot/boot.cmd.new; then
    echo "插入失败（找不到 'setenv load_addr' 锚点），boot.cmd 未改动，已中止"
    rm -f /boot/boot.cmd.new
    exit 1
  fi
  mv /boot/boot.cmd.new /boot/boot.cmd
  mkimage -C none -A arm -T script -n 'flatmax load script' -d /boot/boot.cmd /boot/boot.scr >/dev/null
  echo "  已装链载块并重编 boot.scr（备份：/boot/boot.{cmd,scr}.armbian-orig）"
}

# 已装的块过期了吗。两种情况必须重写，否则板子会一直用这支脚本已经不再维护的设定：
#   - 还写着机型专属的 dtb 档名（rocknix/rk3566-md1000.dtb）而不是板子中立的 rocknix/dtb；
#   - 还带着 console=tty0（fbcon 会占住 framebuffer，模拟器起停时主控台文字会闪到画面上）
#     或 systemd.debug_shell（除错用的残留）。
block_is_outdated() {
  grep -q 'rocknix/dtb' /boot/boot.cmd 2>/dev/null || return 0
  grep -q 'console=tty0\|systemd.debug_shell' /boot/boot.cmd 2>/dev/null && return 0
  return 1
}

# --- 1. 装/更新同步脚本与它的 service ----------------------------------------
#
# ★刷了新固件却还在跑旧内核★是这套设计必须防的坑：链载读的是 eMMC 的
# /boot/rocknix/{KERNEL,dtb}，而刷 ROCKNIX 固件只会更新 U 盘上的
# /flash/{KERNEL,device_trees/*.dtb}，两者没有任何东西会自动配对。
# 2026-07-23 实机就是这样被坑：AV 的 dts 明明是对的、新固件里的 dtb 也确实含修正，
# 但 /proc/device-tree 是旧的（12 组 pinctrl、无 rk809-sound），白白怀疑了好几轮。
# 诊断法：md5sum 两边的 dtb，不一致就是中招。
STEP="安装 payload 同步脚本"
echo "== ${STEP} =="
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

# --- 2. 装或升级 boot.cmd 链载块 --------------------------------------------
STEP="安装/升级 boot.cmd 链载块"
if ! grep -q 'rocknix/TRIGGER' /boot/boot.cmd 2>/dev/null; then
  echo "== 首次：安装链载块 =="
  install_boot_block
elif block_is_outdated; then
  echo "== 升级过期的链载块 =="
  # 先还原成原始 Armbian boot.cmd 再插入现行块，免得叠成两个链载块。
  if [ -f /boot/boot.cmd.armbian-orig ]; then
    cp -f /boot/boot.cmd.armbian-orig /boot/boot.cmd
    install_boot_block
    rm -f /boot/rocknix/*.dtb 2>/dev/null || true   # 旧的机型专属档名，已无人读
    rm -f /boot/rocknix/Image 2>/dev/null || true   # 旧档名，现在叫 KERNEL
  else
    echo "  无法安全升级：/boot/boot.cmd.armbian-orig 不见了。"
    echo "  请手工把 /boot/boot.cmd 改成载入 'rocknix/KERNEL' 与 'rocknix/dtb'，然后："
    echo "    mkimage -C none -A arm -T script -n 'flatmax load script' -d /boot/boot.cmd /boot/boot.scr"
    exit 1
  fi
fi

# --- 3. 同步 payload --------------------------------------------------------
#
# ★同步失败【不该】连切换一起否决★(2026-08-04 定案)
#   helper 有好几条合理的 exit 1（U 盘没插、映像带了多个 dtb 要人指定…）。
#   在 set -e 下直接呼叫它，等於「U 盘临时没插」就让整个切换静默失败。
#   正确的取舍：eMMC 上已经有 payload 就只警告并继续（那颗 payload 照样能开机，
#   顶多不是最新的）；连 payload 都没有才是真的没法继续。
#   ★< /dev/null★：本脚本常以 curl | sh 执行，helper 会继承那条管线当 stdin；
#   万一它（或它呼叫的东西）读了 stdin，就会把还没执行的脚本内容吃掉 ——
#   表现同样是「跑到一半安静结束」。
STEP="同步链载用的 KERNEL/dtb"
echo "== ${STEP} =="
if ! "${SYNC_BIN}" < /dev/null; then
  if [ -f /boot/rocknix/KERNEL ] && [ -f /boot/rocknix/dtb ]; then
    echo "!! 同步失败，但 eMMC 上已有 payload —— 继续切换，这次跑的是现有那份"
    echo "!! 若刚刷过新映像，插好 U 盘再跑一次本脚本"
  else
    echo "★同步失败且 eMMC 上没有 payload，无法链载★（插好 U 盘再试）"
    exit 1
  fi
fi

# --- 4. 放 TRIGGER，下次开机 -> ROCKNIX --------------------------------------
STEP="设置 TRIGGER"
mkdir -p /boot/rocknix
touch /boot/rocknix/TRIGGER
sync
[ -f /boot/rocknix/TRIGGER ] || { echo "★TRIGGER 建立失败★（/boot 是否唯读？）"; exit 1; }
STEP=""
trap - EXIT
echo "已放 TRIGGER，下次开机 -> ROCKNIX (USB)。3 秒后重启..."
echo "（要切回 Armbian：在 ROCKNIX 里跑 switch-to-armbian.sh）"
sleep 3
reboot
