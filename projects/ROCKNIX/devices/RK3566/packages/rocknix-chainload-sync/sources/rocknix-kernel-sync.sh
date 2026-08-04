#!/bin/sh
# ★刷了新固件却还在跑旧内核 —— 这个坑必须自愈★
#
# MD1000 这类板子是链载启动:u-boot 从 【eMMC】 的 /boot 分区读 rocknix/Image 与
# rocknix/*.dtb,rootfs(SYSTEM)才在 U 盘上。而 initramfs 是【包在 Image 里面的】。
# 所以把新映像刷到 U 盘,只换掉了 userland ——
#   eMMC 上的 Image 还是旧的 => 内核层的修改、initramfs 的修改全都没生效,
#   但 /etc/os-release 却显示新版本,看起来一切正常,极容易误判。
#   2026-07-23 实机就是这样被坑:AV 的 dts 明明是对的、新固件里的 dtb 也含修正,
#   /proc/device-tree 却是旧的,白白怀疑了好几轮。
#
# 这是三道防线里的第三道(另外两道在 Armbian 侧:开机/关机的
# rocknix-chainload-sync.service,以及 switch-to-rocknix.sh 每次运行都同步)。
# 有了这一道,只要进过一次 ROCKNIX,之后刷映像就会自愈 —— 不必记得回 Armbian 跑脚本。
#
# 判定用 md5 而不是时间戳:时间戳会因为 FAT 分区、时区、复制方式而失真。
#
# 注意:同步完要【下次开机】才生效,本次跑的仍是旧内核。所以刷完新映像要重开两次。
#
# ★不是链载机型就直接退出★:RK3566 这个 DEVICE 底下还有一堆掌机(RGB20Pro 等),
# 它们没有 eMMC 上的 rocknix/ payload,判断不到就什么都不做。

LOG=/storage/.config/logs/kernel-sync.log
M=/tmp/rocknix-emmc-sync
EMMC_BOOT_DEV=${EMMC_BOOT_DEV:-/dev/mmcblk0p1}

mkdir -p "$(dirname "$LOG")" 2>/dev/null
log() { echo "$(date '+%F %T') $*" >> "$LOG" 2>/dev/null; }

# 来源:U 盘 boot 分区(链载起来之后就是 /flash)
[ -f /flash/KERNEL ] || exit 0

mkdir -p "$M" || exit 0
mount "$EMMC_BOOT_DEV" "$M" 2>/dev/null || { rmdir "$M" 2>/dev/null; exit 0; }

cleanup() { umount "$M" 2>/dev/null; rmdir "$M" 2>/dev/null; }

# 没有 payload 就代表这台不是链载机型(或还没装过),不要凭空造一份出来
if [ ! -f "$M/rocknix/Image" ]; then
  cleanup
  exit 0
fi

# /flash 本身就在 eMMC 上 = 已经 installtoemmc 成单系统,没有 U 盘要同步
if readlink -f /dev/disk/by-label/ROCKNIX 2>/dev/null | grep -q '^/dev/mmcblk0'; then
  cleanup
  exit 0
fi

NEW=$(md5sum /flash/KERNEL 2>/dev/null | cut -d' ' -f1)
OLD=$(md5sum "$M/rocknix/Image" 2>/dev/null | cut -d' ' -f1)
if [ -n "$NEW" ] && [ "$NEW" != "$OLD" ]; then
  log "Image differs (emmc=${OLD:-none} usb=$NEW) - syncing"
  cp /flash/KERNEL "$M/rocknix/Image" && log "Image synced (takes effect next boot)"
fi

# dtb 一并同步(同样只有 eMMC 那份会被 u-boot 读到)。
#
# ★目标档名必须与 boot.cmd 链载块里写的一致★,而链载块的档名是 Armbian 侧装的,
# 这边无从得知 —— 所以【以 eMMC 上现有的那个档名为准】,逐个拿 U 盘
# device_trees/ 里的同名档去更新。ROCKNIX 的 dtb 在 device_trees/ 子目录,
# 不在根目录(EmuELEC 才是根目录,别把那个假设搬过来)。
for D in "$M"/rocknix/*.dtb; do
  [ -f "$D" ] || continue
  B=$(basename "$D")
  S="/flash/device_trees/$B"
  if [ ! -f "$S" ]; then
    log "WARN /flash/device_trees/$B 不存在,跳过(eMMC 上这份 dtb 无从更新)"
    continue
  fi
  if [ "$(md5sum "$S" | cut -d' ' -f1)" != "$(md5sum "$D" | cut -d' ' -f1)" ]; then
    cp "$S" "$D" && log "$B synced"
  fi
done

sync
cleanup
exit 0
