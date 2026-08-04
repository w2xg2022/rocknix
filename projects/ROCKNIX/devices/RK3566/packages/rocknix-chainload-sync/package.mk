# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 w2xg2022

# 链载机型(MD1000)的内核/dtb 自愈同步。
#
# u-boot 从 eMMC 读 rocknix/Image(initramfs 包在里面)与 rocknix/*.dtb,rootfs 才在
# U 盘。刷 U 盘只换 userland,eMMC 那份还是旧的,但 /etc/os-release 显示新版本 ——
# 看起来一切正常,极易误判。这是三道防线里的第三道,让「进过一次 ROCKNIX 之后」
# 刷映像就会自愈,另外两道在 Armbian 侧(docs/md1000-dualboot/)。
#
# 做成独立 package 而不是塞进 autostart:autostart 是全 DEVICE 共用的,
# 动它会波及所有机型。这个 package 只挂在 RK3566 的 ADDITIONAL_PACKAGES 上,
# 而且脚本本身还会在执行期判断「eMMC 上有没有 rocknix/ payload」,
# 同 DEVICE 底下那些掌机(RGB20Pro 等)跑起来是纯 no-op。

PKG_NAME="rocknix-chainload-sync"
PKG_VERSION=""
PKG_SHA256=""
PKG_ARCH="any"
PKG_LICENSE="GPL"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain systemd"
PKG_LONGDESC="Self-healing sync of the chainload payload (Image + dtb) from /flash to eMMC"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/rocknix-kernel-sync.sh ${INSTALL}/usr/bin/
  chmod 755 ${INSTALL}/usr/bin/rocknix-kernel-sync.sh
}

post_install() {
  enable_service rocknix-kernel-sync.service
}
