#!/bin/sh
# Armbian -> boot into ROCKNIX on the USB stick.
#
# Run this from Armbian. The first run performs a one-off install; every run
# after that is just "sync the payload, set the flag, reboot".
#
# HOW IT WORKS
#   The stock u-boot on eMMC reads /boot/rocknix/TRIGGER at boot. If the file
#   exists it loads rocknix/KERNEL + rocknix/dtb from eMMC and booti's into
#   ROCKNIX, whose rootfs then comes off the USB stick (LABEL=ROCKNIX /
#   STORAGE). If the file is absent, Armbian boots as usual.
#
#   The kernel and dtb have to live on eMMC because the stock u-boot cannot see
#   USB devices at all. Once the kernel is up, Linux drives USB properly and the
#   rootfs on the stick is reachable.
#
#   Why booti and not kexec: kexec leaves the GPU/display in a dirty state and
#   ROCKNIX hard-freezes (black screen) when sway initialises DRM. booti hands
#   over from u-boot with the hardware freshly initialised; it is the only path
#   that has been verified to work on this board.
#
# WHAT THIS SCRIPT INSTALLS (first run only)
#   1. /usr/local/sbin/rocknix-chainload-sync.sh  -- the payload sync logic
#   2. rocknix-chainload-sync.service             -- runs that at every boot AND
#                                                    every shutdown, so a freshly
#                                                    flashed stick is picked up
#                                                    automatically without having
#                                                    to remember this script
#   3. the chainload block in /boot/boot.cmd, and a rebuilt boot.scr
#      (originals are backed up as *.armbian-orig)
#
# THE TRIGGER FILE IS PERSISTENT, NOT ONE-SHOT
#   u-boot only reads it, it never deletes it. Once set, EVERY boot goes to
#   ROCKNIX until switch-to-armbian.sh removes it from inside ROCKNIX. That is
#   deliberate: the board must not silently fall back to Armbian on the next
#   reboot, because the boot outcome is the only signal you get -- the stock
#   u-boot prints nothing to HDMI on this board.
#
# SAFETY BOUNDARY -- READ THIS
#   No TRIGGER means Armbian boots normally. That is the only reliable
#   fallback. The "chainload failure falls back to Armbian" behaviour only
#   covers the case where eMMC has no KERNEL yet and the `load` command fails.
#   Once a kernel is present on eMMC, `load` and `booti` both succeed and
#   u-boot is gone for good -- so PULLING THE USB STICK DOES NOT RESCUE YOU:
#   the kernel will start and then hang in the initramfs looking for a rootfs
#   that is not there (black screen, no network).
#   => During bring-up keep a bootable Armbian SD card around.
set -e

# Never fail silently. This script runs under `set -e` and step 3 calls an
# EXTERNAL helper -- any non-zero exit from it aborts the whole script on the
# spot. That is exactly what bit us on 2026-08-04: the payload was synced and
# boot.cmd was patched, but TRIGGER was never set and the board never rebooted,
# with not one word of explanation on screen. The user had to reboot by hand,
# landed back in Armbian, and concluded the chainload was broken -- when in
# fact the switch had never been armed.
STEP="startup"
trap 'rc=$?; [ "$rc" -ne 0 ] && echo "*** Aborted during [${STEP}], exit code ${rc} -- TRIGGER not set, the board still boots Armbian ***" >&2' EXIT

BASE=https://raw.githubusercontent.com/w2xg2022/rocknix/next/docs/md1000-dualboot
SYNC_BIN=/usr/local/sbin/rocknix-chainload-sync.sh
UNIT=/etc/systemd/system/rocknix-chainload-sync.service

[ "$(id -u)" = "0" ] || { echo "Please run as root."; exit 1; }

# Fetch a file from the directory this script came from if it is there (handy
# when the whole folder was cloned), otherwise from GitHub.
#
# Guard with [ -f "$0" ]: when the script is piped into a shell, "$0" is not a
# path, dirname yields "." and "the copy next to it" silently resolves to a
# same-named file in the current directory.
fetch() {
  _name="$1"; _dest="$2"
  _local="$(dirname "$0")/${_name}"
  if [ -f "$0" ] && [ -f "${_local}" ]; then
    cp -f "${_local}" "${_dest}"
  else
    curl -fsSL "${BASE}/${_name}" -o "${_dest}"
  fi
}

install_boot_block() {
  command -v mkimage >/dev/null 2>&1 || {
    echo "mkimage is missing -- install it first: apt-get update && apt-get install -y u-boot-tools"
    exit 1
  }
  [ -f /boot/boot.cmd.armbian-orig ] || cp /boot/boot.cmd /boot/boot.cmd.armbian-orig
  [ -f /boot/boot.scr.armbian-orig ] || cp /boot/boot.scr /boot/boot.scr.armbian-orig
  fetch boot-rocknix-block.txt /tmp/rk-blk.txt

  # Insert the block before the first 'setenv load_addr' line.
  awk 'FNR==NR{blk=blk $0 ORS; next} /setenv load_addr/ && !d{printf "%s", blk; d=1} {print}' \
      /tmp/rk-blk.txt /boot/boot.cmd > /boot/boot.cmd.new
  if ! grep -q 'rocknix/TRIGGER' /boot/boot.cmd.new; then
    echo "Insertion failed (anchor 'setenv load_addr' not found). boot.cmd left untouched; aborting."
    rm -f /boot/boot.cmd.new
    exit 1
  fi
  mv /boot/boot.cmd.new /boot/boot.cmd
  mkimage -C none -A arm -T script -n 'flatmax load script' -d /boot/boot.cmd /boot/boot.scr >/dev/null
  echo "  chainload block installed, boot.scr rebuilt (backups: /boot/boot.{cmd,scr}.armbian-orig)"
}

# Two things make an installed block outdated:
#   - it references a model-specific dtb filename (e.g. rocknix/rk3566-md1000.dtb)
#     instead of the board-agnostic rocknix/dtb;
#   - it still passes console=tty0, which binds fbcon to the framebuffer and makes
#     console text flash on screen whenever an emulator starts or exits, or
#     systemd.debug_shell, which is a debugging leftover.
# Either way the block has to be rewritten, or the board keeps booting with
# settings this script no longer maintains.
block_is_outdated() {
  grep -q 'rocknix/dtb' /boot/boot.cmd 2>/dev/null || return 0
  grep -qE 'console=tty0|systemd.debug_shell' /boot/boot.cmd 2>/dev/null && return 0
  return 1
}

# --- 1. install / refresh the sync helper and its service -------------------
#
# "Flashed a new image but still running the old kernel" is the trap this whole
# design has to guard against: the chainload reads eMMC's /boot/rocknix/{KERNEL,dtb},
# while flashing ROCKNIX only updates the stick's /flash/{KERNEL,device_trees/*.dtb}.
# Nothing pairs the two automatically. On 2026-07-23 this cost hours on real
# hardware: the AV dts was correct and the new image's dtb did contain the fix,
# but /proc/device-tree was the old one. Diagnosis: md5sum both dtbs; a mismatch
# means you are hit.
STEP="installing the payload sync helper"
echo "== Installing the payload sync helper =="
mkdir -p "$(dirname "${SYNC_BIN}")"
fetch rocknix-chainload-sync.sh "${SYNC_BIN}"
chmod 755 "${SYNC_BIN}"

if command -v systemctl >/dev/null 2>&1; then
  fetch rocknix-chainload-sync.service "${UNIT}"
  systemctl daemon-reload
  systemctl enable rocknix-chainload-sync.service >/dev/null 2>&1 || true
  echo "  rocknix-chainload-sync.service enabled (syncs at boot and at shutdown)"
else
  echo "  no systemd found -- the helper is installed but will not run automatically"
fi

# --- 2. install or upgrade the chainload block ------------------------------
STEP="installing/upgrading the chainload block"
if ! grep -q 'rocknix/TRIGGER' /boot/boot.cmd 2>/dev/null; then
  echo "== First run: installing the chainload block into /boot/boot.cmd =="
  install_boot_block
elif block_is_outdated; then
  echo "== Upgrading an outdated chainload block =="
  # Restore the pristine Armbian boot.cmd, then insert the current block, so we
  # never end up with two chainload blocks stacked on top of each other.
  if [ -f /boot/boot.cmd.armbian-orig ]; then
    cp -f /boot/boot.cmd.armbian-orig /boot/boot.cmd
    install_boot_block
    rm -f /boot/rocknix/*.dtb 2>/dev/null || true   # model-specific name, nothing reads it now
    rm -f /boot/rocknix/Image 2>/dev/null || true   # old kernel name, now KERNEL
  else
    echo "  cannot upgrade safely: /boot/boot.cmd.armbian-orig is missing."
    echo "  Edit /boot/boot.cmd by hand so it loads 'rocknix/KERNEL' and 'rocknix/dtb', then run:"
    echo "    mkimage -C none -A arm -T script -n 'flatmax load script' -d /boot/boot.cmd /boot/boot.scr"
    exit 1
  fi
fi

# --- 3. sync the payload ----------------------------------------------------
#
# A failed sync must NOT veto the switch. The helper has several legitimate
# non-zero exits (no stick attached, image ships several dtbs and needs
# DTB_NAME, ...); calling it bare under `set -e` turns every one of them into
# "the switch silently did nothing". If eMMC already holds a payload the board
# can still chainload -- it just runs whatever is there.
#
# `< /dev/null`: this script is often piped into a shell, and the helper would
# inherit that pipe as its stdin. If it (or anything it calls) read stdin, the
# not-yet-executed rest of this script would be swallowed -- which again looks
# like "it stopped halfway with no error".
STEP="syncing KERNEL + dtb"
echo "== Syncing KERNEL + dtb to eMMC =="
if ! "${SYNC_BIN}" < /dev/null; then
  if [ -f /boot/rocknix/KERNEL ] && [ -f /boot/rocknix/dtb ]; then
    echo "!! Sync failed, but eMMC already has a payload -- continuing with it."
    echo "!! If you just flashed a new image, plug the stick back in and re-run."
  else
    echo "*** Sync failed and eMMC has no payload -- cannot chainload. ***"
    exit 1
  fi
fi

# --- 4. flip the switch -----------------------------------------------------
STEP="setting TRIGGER"
mkdir -p /boot/rocknix
touch /boot/rocknix/TRIGGER
sync
[ -f /boot/rocknix/TRIGGER ] || { echo "*** Could not create TRIGGER (is /boot read-only?) ***"; exit 1; }
STEP=""
trap - EXIT
echo "TRIGGER set. Next boot goes to ROCKNIX (USB). Rebooting in 3 seconds..."
echo "(To come back: run switch-to-armbian.sh from inside ROCKNIX.)"
sleep 3
reboot
