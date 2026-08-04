#!/bin/sh
# 把链载 payload(KERNEL + dtb)从 U 盘 ROCKNIX 分区同步到 eMMC。
#
# ★为什么需要这个东西★
#   MD1000 这类板子的原厂 u-boot 根本扫不到 USB,所以内核与 dtb 必须放在 eMMC,
#   rootfs(SYSTEM)才留在 U 盘。刷新固件只会换掉 U 盘上那份 ——
#   没有任何东西会去更新 eMMC 上的副本。于是 /etc/os-release 显示新版本,
#   实际跑的却是旧内核;而 initramfs 是【包在 KERNEL 里面的】,内核层与
#   initramfs 层的所有修改都会静默失效,看起来就像「你的修正没生效」。
#   2026-07-23 实机就是这样被坑(AV 的 dts 对、固件里的 dtb 也对,
#   /proc/device-tree 却是旧的),白白怀疑了好几轮。
#
# ★payload 就只有两个档★
#   <emmc-boot>/rocknix/Image          内核映像,initramfs 包在里面
#   <emmc-boot>/rocknix/<board>.dtb    设备树,档名与 boot.cmd 链载块里那个一致
#   其余一概不需要:SYSTEM、oemsplash、*.md5 都是 initramfs 起来之后从 /flash
#   (也就是 U 盘)读的,那时内核早就跑起来了。u-boot 只读上面两个,而且只读得到 eMMC。
#
# ★用 md5,绝不用时间戳★
#   来源在 FAT 分区上,时间戳会被时区处理与映像的写入方式弄失真。
#
# 注意:同步完要【下次开机】才生效 —— u-boot 早在本脚本跑之前就载入旧内核了。
#      所以刷完新映像要重开两次。
#
# 环境变数:
#   EMMC_BOOT_DEV    eMMC boot 分区(预设 /dev/mmcblk0p1);只在 /boot 不是
#                    boot 分区本身时才会用到
#   DTB_NAME         U 盘 device_trees/ 底下的来源 dtb 档名;只有在映像带了
#                    不只一个 dtb、无法推断时才需要设
#   USB_WAIT_TRIES   等 USB 列举的重试次数(预设 1;开机时由 service 设成 10)
#
# 结束码:0 = payload 已是最新(或刚更新完)   1 = 无法产生可用的 payload

set -e

MNT_EMMC=""
MNT_USB=""
BOOTDIR=""

log() { echo "rocknix-chainload-sync: $*"; }

cleanup() {
  [ -n "${MNT_USB}" ]  && { umount "${MNT_USB}"  2>/dev/null || true; rmdir "${MNT_USB}"  2>/dev/null || true; }
  [ -n "${MNT_EMMC}" ] && { umount "${MNT_EMMC}" 2>/dev/null || true; rmdir "${MNT_EMMC}" 2>/dev/null || true; }
}
trap cleanup EXIT

[ "$(id -u)" = "0" ] || { log "请用 root 运行"; exit 1; }

# ---------------------------------------------------------------------------
# 找 eMMC boot 目录。
#
# Armbian 上 /boot 通常【就是】那颗 boot 分区(switch-to-rocknix.sh 一路都直接
# 写 /boot/boot.cmd),所以有 boot.cmd 就直接用,不多此一举去 mount。
# 没有的话才退回挂 EMMC_BOOT_DEV。
# ---------------------------------------------------------------------------
if [ -f /boot/boot.cmd ]; then
  BOOTDIR=/boot
else
  MNT_EMMC="$(mktemp -d)"
  if ! mount "${EMMC_BOOT_DEV:-/dev/mmcblk0p1}" "${MNT_EMMC}" 2>/dev/null; then
    log "ERROR 挂不上 ${EMMC_BOOT_DEV:-/dev/mmcblk0p1},也找不到 /boot/boot.cmd"
    exit 1
  fi
  BOOTDIR="${MNT_EMMC}"
fi
DEST="${BOOTDIR}/rocknix"

# ---------------------------------------------------------------------------
# 找 U 盘上的 ROCKNIX boot 分区。
#
# 先认标签(DISTRO_BOOTLABEL="ROCKNIX"),认不到再扫「带 KERNEL 档的分区」——
# 标签可能被改过,而且机器上可能不只插一颗可移除磁碟。
# 开机时由 systemd 拉起来的那次,USB 可能还没列举完,所以要重试而不是第一次就失败。
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
  # 没插 U 盘。已经铺过 payload 的话这不算致命 —— 板子照样链载得起来,
  # 只是跑的是现有那份。
  if [ -f "${DEST}/Image" ]; then
    log "找不到 U 盘 ROCKNIX 分区,沿用 eMMC 上现有的 payload"
    log "若刚刷过新映像,插好 U 盘再跑一次本脚本"
    exit 0
  fi
  log "ERROR 没有带 KERNEL 的 U 盘 ROCKNIX 分区,eMMC 上也没有 payload"
  exit 1
fi
log "U 盘 ROCKNIX 分区 = ${USB_DEV}"

# ---------------------------------------------------------------------------
# 挑来源 dtb。
#
# ★ROCKNIX 的 dtb 在 boot 分区的 device_trees/ 子目录底下★
#  (EmuELEC 是放在根目录,别把那边的假设搬过来)。
#
# 只有一个是常态,直接采用。有好几个代表这份映像带了不只一块板子 —— 猜错 dtb
# 正是那种会让机器开不了机的静默错误,所以宁可停下来问,不猜。
# ---------------------------------------------------------------------------
DTBDIR="${MNT_USB}/device_trees"
if [ -n "${DTB_NAME}" ]; then
  SRC_DTB="${DTBDIR}/${DTB_NAME}"
  [ -f "${SRC_DTB}" ] || { log "ERROR U 盘 device_trees/ 里找不到 DTB_NAME=${DTB_NAME}"; exit 1; }
elif [ -f "${DEST}/rk3566-md1000.dtb" ] && [ -f "${DTBDIR}/rk3566-md1000.dtb" ]; then
  # eMMC 上已经铺过、U 盘也有同名的:直接沿用同一个档名,不必去数有几个。
  SRC_DTB="${DTBDIR}/rk3566-md1000.dtb"
else
  _count="$(ls "${DTBDIR}"/*.dtb 2>/dev/null | wc -l)"
  if [ "${_count}" -eq 0 ]; then
    log "ERROR U 盘 device_trees/ 里没有 *.dtb"
    exit 1
  elif [ "${_count}" -eq 1 ]; then
    SRC_DTB="$(ls "${DTBDIR}"/*.dtb)"
  else
    log "ERROR 这份映像带了 ${_count} 个 dtb,请用 DTB_NAME 指定其中一个:"
    for _d in "${DTBDIR}"/*.dtb; do log "  $(basename "${_d}")"; done
    exit 1
  fi
fi
log "来源 dtb = $(basename "${SRC_DTB}")"

# ★目标档名必须与 boot.cmd 链载块里写的一致★
# 链载块载入的是 rocknix/<board>.dtb,所以这里沿用来源的档名(同一块板子,
# 换映像也不会变)。要是有一天改成中性的 "dtb",这里跟链载块要一起改。
DEST_DTB="$(basename "${SRC_DTB}")"

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

copy_if_different "${MNT_USB}/KERNEL" "${DEST}/Image"
copy_if_different "${SRC_DTB}" "${DEST}/${DEST_DTB}"

sync
if [ "${changed}" = "1" ]; then
  log "payload 已更新 —— 【下次开机】才生效"
else
  log "payload 与 U 盘一致,无需更新"
fi
exit 0
