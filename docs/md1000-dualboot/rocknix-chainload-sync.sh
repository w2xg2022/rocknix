#!/bin/sh
# Sync the USB ROCKNIX KERNEL + dtb into the eMMC chainload payload.
#
# Board-agnostic: nothing here is tied to a particular RK model. The dtb is
# stored on eMMC under the fixed name "dtb" precisely so that the u-boot block
# never has to know the board's dtb filename.
#
# WHY THIS EXISTS
#   The chainload reads the copy on eMMC, while flashing ROCKNIX only updates
#   the stick's /flash/{KERNEL,device_trees/*.dtb} -- nothing pairs the two
#   automatically. The stock u-boot cannot see USB devices, so the kernel and
#   the dtb have to live on eMMC.
#   On 2026-07-23 this cost hours on real hardware: the AV dts was correct and
#   the new image's dtb did contain the fix, but /proc/device-tree was the old
#   one (12 pinctrl groups, no rk809-sound). Diagnosis: md5sum both dtbs; a
#   mismatch means you are hit.
#
# WHAT IT WRITES
#   <emmc-boot>/rocknix/KERNEL   the kernel image (the initramfs is inside it)
#   <emmc-boot>/rocknix/dtb      the device tree, always under this fixed name
#
# ENVIRONMENT
#   EMMC_BOOT_DEV    eMMC boot partition (default /dev/mmcblk0p1; unused when
#                    /boot already is that partition)
#   DTB_NAME         source dtb filename on the stick; only needed when the
#                    image ships more than one
#   USB_WAIT_TRIES   retries while waiting for USB enumeration (default 1; the
#                    service raises it because at boot the stack may not be up)
#
# Exit codes: 0 = payload is current (or was just updated)
#             1 = could not produce a usable payload
#   NOTE FOR CALLERS: 1 does not necessarily mean "give up". If eMMC already
#   holds a payload the board can still chainload, it just runs what is there.
#   switch-to-rocknix.sh treats it that way on purpose.

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

[ "$(id -u)" = "0" ] || { log "must run as root"; exit 1; }

# ---------------------------------------------------------------------------
# Locate the eMMC boot directory.
# On Armbian /boot usually IS that partition, so if boot.cmd is there just use
# it instead of mounting the device a second time.
# ---------------------------------------------------------------------------
if [ -f /boot/boot.cmd ]; then
  BOOTDIR=/boot
else
  MNT_EMMC="$(mktemp -d)"
  if ! mount "${EMMC_BOOT_DEV}" "${MNT_EMMC}" 2>/dev/null; then
    log "ERROR cannot mount ${EMMC_BOOT_DEV} and /boot/boot.cmd is not there either"
    exit 1
  fi
  BOOTDIR="${MNT_EMMC}"
fi
DEST="${BOOTDIR}/rocknix"

# ---------------------------------------------------------------------------
# Locate the USB ROCKNIX boot partition.
#
# Prefer the label, then fall back to scanning for a partition that actually
# carries a KERNEL file -- the label may have been changed, and more than one
# removable disk may be attached.
#
# When run from systemd at boot the USB stack may not have enumerated yet, so
# retry instead of failing on the first attempt.
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
  # No stick attached. If a payload is already installed this is not fatal --
  # the board can still chainload, it will just run whatever is already there.
  if [ -f "${DEST}/KERNEL" ] && [ -f "${DEST}/${DEST_DTB}" ]; then
    log "no USB ROCKNIX partition found; keeping the existing payload on eMMC"
    log "if you just flashed a new image, plug the stick back in and run this again"
    exit 0
  fi
  log "ERROR no USB ROCKNIX partition with a KERNEL file, and no payload on eMMC"
  exit 1
fi
log "USB ROCKNIX partition = ${USB_DEV}"

# ---------------------------------------------------------------------------
# Pick the source dtb.
#
# ROCKNIX keeps its dtbs in the device_trees/ subdirectory of the boot
# partition (EmuELEC puts them in the root -- do not carry that assumption
# over).
#
# One dtb is the normal case and is taken automatically. Several means the
# image ships more than one board: picking the wrong one is exactly the kind of
# silent mistake that leaves the board unbootable, so stop and ask instead.
# ---------------------------------------------------------------------------
DTBDIR="${MNT_USB}/device_trees"
if [ -n "${DTB_NAME}" ]; then
  SRC_DTB="${DTBDIR}/${DTB_NAME}"
  [ -f "${SRC_DTB}" ] || { log "ERROR DTB_NAME=${DTB_NAME} not found under device_trees/"; exit 1; }
else
  _count="$(ls "${DTBDIR}"/*.dtb 2>/dev/null | wc -l)"
  if [ "${_count}" -eq 0 ]; then
    log "ERROR no *.dtb under device_trees/ on the USB partition"
    exit 1
  elif [ "${_count}" -eq 1 ]; then
    SRC_DTB="$(ls "${DTBDIR}"/*.dtb)"
  else
    log "ERROR the image ships ${_count} dtb files; set DTB_NAME to choose one:"
    for _d in "${DTBDIR}"/*.dtb; do log "  $(basename "${_d}")"; done
    exit 1
  fi
fi
log "source dtb = $(basename "${SRC_DTB}")"

mkdir -p "${DEST}"
changed=0

copy_if_different() {
  _src="$1"; _dst="$2"
  if [ ! -f "${_dst}" ] || \
     [ "$(md5sum < "${_src}" | cut -d' ' -f1)" != "$(md5sum < "${_dst}" | cut -d' ' -f1)" ]; then
    cp -f "${_src}" "${_dst}"
    log "updated $(basename "${_dst}")"
    changed=1
  fi
}

copy_if_different "${MNT_USB}/KERNEL" "${DEST}/KERNEL"
copy_if_different "${SRC_DTB}" "${DEST}/${DEST_DTB}"

sync
if [ "${changed}" = "1" ]; then
  log "payload updated -- takes effect on the NEXT boot"
else
  log "payload already matches the stick, nothing to do"
fi
exit 0
