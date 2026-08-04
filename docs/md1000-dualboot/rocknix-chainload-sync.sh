#!/bin/sh
# 把 U 盘 ROCKNIX 的 KERNEL + dtb 同步到 eMMC 的链载 payload。
#
# 板子中立：这里没有任何东西绑特定 RK 机型。dtb 在 eMMC 上一律存成固定档名 "dtb"，
# 正是为了让 u-boot 链载块永远不必知道这块板子的 dtb 叫什么。
#
# 为什么需要这支：
#   链载读的是 eMMC 上的副本，而刷 ROCKNIX 固件只会更新 U 盘上的
#   /flash/{KERNEL,device_trees/*.dtb} —— 两者之间没有任何东西会自动配对。
#   原厂 u-boot 扫不到 USB，所以内核与 dtb 非放 eMMC 不可。
#   ★2026-07-23 实机就是这样被坑★：AV 的 dts 是对的、新固件里的 dtb 也确实含修正，
#   但 /proc/device-tree 是旧的（12 组 pinctrl、无 rk809-sound），白白怀疑了好几轮。
#   诊断法：md5sum 两边的 dtb，不一致就是中招。
#
# 落点：
#   <emmc-boot>/rocknix/KERNEL   内核映像（initramfs 就包在里面）
#   <emmc-boot>/rocknix/dtb      设备树，固定用这个档名
#
# 环境变数：
#   EMMC_BOOT_DEV    eMMC boot 分区（预设 /dev/mmcblk0p1；/boot 已经是它时用不到）
#   DTB_NAME         U 盘上的来源 dtb 档名；只有当映像带了不只一个 dtb 时才需要指定
#   USB_WAIT_TRIES   等 USB 列举的重试次数（预设 1；开机时由 service 设成较大值）
#
# 退出码：0 = payload 是最新的（或刚更新完）
#         1 = 做不出可用的 payload
#   ★呼叫端注意★：1 不一定代表「必须中止」—— eMMC 上已经有 payload 时照样能链载，
#   只是跑的是现有那份。switch-to-rocknix.sh 就是这样处理的。

set -e

EMMC_BOOT_DEV="${EMMC_BOOT_DEV:-/dev/mmcblk0p1}"
DEST_DTB="dtb"
MNT_EMMC=""
MNT_USB=""
BOOTDIR=""

log() { echo "rocknix-chainload-sync: $*"; }

cleanup() {
  [ -n "${MNT_USB}" ]  && { umount "${MNT_USB}"  2>/dev/null || true; rmdir "${MNT_USB}"  2>/dev/null || true; }
  [ -n "${MNT_EMMC}" ] && { umount "${MNT_EMMC}" 2>/dev/null || true; rmdir "${MNT_EMMC}" 2>/dev/null || true; }
  return 0
}
trap cleanup EXIT

[ "$(id -u)" = "0" ] || { log "请用 root 运行"; exit 1; }

# ---------------------------------------------------------------------------
# 找 eMMC boot 目录。
# Armbian 上 /boot 通常【就是】那颗 boot 分区，有 boot.cmd 就直接用，不多此一举去 mount。
# ---------------------------------------------------------------------------
if [ -f /boot/boot.cmd ]; then
  BOOTDIR=/boot
else
  MNT_EMMC="$(mktemp -d)"
  if ! mount "${EMMC_BOOT_DEV}" "${MNT_EMMC}" 2>/dev/null; then
    log "ERROR 挂不上 ${EMMC_BOOT_DEV}，也找不到 /boot/boot.cmd"
    exit 1
  fi
  BOOTDIR="${MNT_EMMC}"
fi
DEST="${BOOTDIR}/rocknix"

# ---------------------------------------------------------------------------
# 找 U 盘上的 ROCKNIX boot 分区。
# 先认标签，认不到再扫「带 KERNEL 档的分区」—— 标签可能被改过，机器上也可能不只一颗
# 可移除磁碟。开机时由 systemd 拉起来的那次 USB 可能还没列举完，所以要重试。
# ---------------------------------------------------------------------------
find_usb() {
  _tries="${1:-1}"
  while [ "${_tries}" -gt 0 ]; do
    _p="$(blkid -L ROCKNIX 2>/dev/null || true)"
    if [ -n "${_p}" ]; then
      _m="$(mktemp -d)"
      if mount -o ro "${_p}" "${_m}" 2>/dev/null && [ -f "${_m}/KERNEL" ]; then
        MNT_USB="${_m}"; USB_DEV="${_p}"; return 0
      fi
      umount "${_m}" 2>/dev/null || true; rmdir "${_m}" 2>/dev/null || true
    fi

    for _p in $(ls /dev/sd?1 2>/dev/null); do
      _m="$(mktemp -d)"
      if mount -o ro "${_p}" "${_m}" 2>/dev/null && [ -f "${_m}/KERNEL" ]; then
        MNT_USB="${_m}"; USB_DEV="${_p}"; return 0
      fi
      umount "${_m}" 2>/dev/null || true; rmdir "${_m}" 2>/dev/null || true
    done

    _tries=$((_tries - 1))
    [ "${_tries}" -gt 0 ] && sleep 2
  done
  return 1
}

if ! find_usb "${USB_WAIT_TRIES:-1}"; then
  # 没插 U 盘。已经铺过 payload 的话这不算致命 —— 板子照样链载得起来，
  # 只是跑的是现有那份。
  if [ -f "${DEST}/KERNEL" ] && [ -f "${DEST}/${DEST_DTB}" ]; then
    log "找不到 U 盘 ROCKNIX 分区，沿用 eMMC 上现有的 payload"
    log "若刚刷过新映像，插好 U 盘再跑一次"
    exit 0
  fi
  log "ERROR 没有带 KERNEL 的 U 盘 ROCKNIX 分区，eMMC 上也没有 payload"
  exit 1
fi
log "U 盘 ROCKNIX 分区 = ${USB_DEV}"

# ---------------------------------------------------------------------------
# 挑来源 dtb。
#
# ★ROCKNIX 的 dtb 在 boot 分区的 device_trees/ 子目录底下★
#  （EmuELEC 是放在根目录，别把那边的假设搬过来）。
#
# 只有一个是常态，直接采用。有好几个代表这份映像带了不只一块板子 —— 猜错 dtb
# 正是那种会让机器开不了机的静默错误，所以宁可停下来问，不猜。
# ---------------------------------------------------------------------------
DTBDIR="${MNT_USB}/device_trees"
if [ -n "${DTB_NAME}" ]; then
  SRC_DTB="${DTBDIR}/${DTB_NAME}"
  [ -f "${SRC_DTB}" ] || { log "ERROR U 盘 device_trees/ 里找不到 DTB_NAME=${DTB_NAME}"; exit 1; }
else
  _count="$(ls "${DTBDIR}"/*.dtb 2>/dev/null | wc -l)"
  if [ "${_count}" -eq 0 ]; then
    log "ERROR U 盘 device_trees/ 里没有 *.dtb"
    exit 1
  elif [ "${_count}" -eq 1 ]; then
    SRC_DTB="$(ls "${DTBDIR}"/*.dtb)"
  else
    log "ERROR 这份映像带了 ${_count} 个 dtb，请用 DTB_NAME 指定其中一个："
    for _d in "${DTBDIR}"/*.dtb; do log "  $(basename "${_d}")"; done
    exit 1
  fi
fi
log "来源 dtb = $(basename "${SRC_DTB}")"

mkdir -p "${DEST}"
changed=0

copy_if_different() {
  _src="$1"; _dst="$2"
  if [ ! -f "${_dst}" ] || \
     [ "$(md5sum < "${_src}" | cut -d' ' -f1)" != "$(md5sum < "${_dst}" | cut -d' ' -f1)" ]; then
    cp -f "${_src}" "${_dst}"
    log "已更新 $(basename "${_dst}")"
    changed=1
  fi
}

copy_if_different "${MNT_USB}/KERNEL" "${DEST}/KERNEL"
copy_if_different "${SRC_DTB}" "${DEST}/${DEST_DTB}"

sync
if [ "${changed}" = "1" ]; then
  log "payload 已更新 —— 【下次开机】才生效"
else
  log "payload 与 U 盘一致，无需更新"
fi
exit 0
