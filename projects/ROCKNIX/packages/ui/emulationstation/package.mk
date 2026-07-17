# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

# es4all: 源码改由统一仓库 es4all 提供（原 ROCKNIX/emulationstation-next）。
PKG_NAME="emulationstation"
PKG_VERSION="11e8bc98e43f93427daf1c3d2e6490b0634719c7"
PKG_GIT_CLONE_BRANCH="main"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/w2xg2022/es4all"
PKG_URL="${PKG_SITE}.git"
PKG_DEPENDS_TARGET="boost toolchain SDL2 freetype curl freeimage bash rapidjson SDL2_mixer fping p7zip alsa vlc drm_tool pugixml"
PKG_NEED_UNPACK="busybox"
PKG_LONGDESC="Emulationstation emulator frontend"
PKG_BUILD_FLAGS="-gold"
GET_HANDLER_SUPPORT="git"
PKG_PATCH_DIRS+="${DEVICE}"

# es4all: the scraper credentials below are compiled in, but calculate_stamp
# only hashes a package's own files -- rotate a key and the stamp still matches,
# so a stale binary ships. That gap is why the image job cleaned this package on
# every build, spending ~19m recompiling what the userland job had already
# built. PKG_STAMP is the build system's own hook for exactly this: it folds the
# values into the deep hash so a changed key rebuilds by itself. Only the
# sha256 reaches the stamp file, never the secrets.
PKG_STAMP="${SCREENSCRAPER_DEV_LOGIN}${GAMESDB_APIKEY}${CHEEVOS_DEV_LOGIN}"

if [ ! "${OPENGL}" = "no" ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGL} glu"
  PKG_CMAKE_OPTS_TARGET+=" -DGL=1"
fi

if [ ! "${OPENGLES_SUPPORT}" = no ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGLES}"
  PKG_CMAKE_OPTS_TARGET+=" -DGLES2=1"
fi

PKG_CMAKE_OPTS_TARGET+=" -DES4ALL_TARGET=rocknix \
                         -DROCKNIX=1 \
                         -DDISABLE_KODI=1 \
                         -DENABLE_FILEMANAGER=0 \
                         -DCEC=0 \
                         -DENABLE_PULSE=1 \
                         -DUSE_SYSTEM_PUGIXML=1"

pre_configure_target() {
  for key in SCREENSCRAPER_DEV_LOGIN \
        GAMESDB_APIKEY \
        CHEEVOS_DEV_LOGIN
  do
    if [ -z "${!key}" ]
    then
      echo "WARNING: ${key} not declared, will not build support."
    else
      echo "USING: ${key} = ${!key}"
    fi
  done

  export DEVICE=$(echo ${DEVICE^^} | sed "s#-#_##g")
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/config/locale
  cp -rf ${PKG_BUILD}/locale/lang/* ${INSTALL}/usr/config/locale/

  # Pre-generate default (en_US.UTF-8) locale for lower-end devices to speed up first boot
  # This saves a minute or two on RK3326 in a cost of about 1 MB of SYSTEM size
  # Copy-paste of a locale generating part of es_settings script
  I18NPATH=$(get_install_dir glibc)/usr/share/i18n/locales/ \
    localedef --force --verbose --inputfile=en_US --charmap=UTF-8 \
    ${INSTALL}/usr/config/locale/en_US.UTF-8 || true

  # es4all: also pre-generate the Chinese glibc locales. The base image seeded a
  # BROKEN zh_CN.UTF-8 (has LC_NAME but no LC_CTYPE), which fools es_settings'
  # "already generated" guard (it tests LC_NAME), so setlocale(LC_MESSAGES,"")
  # fails, gettext disables all translation and the UI falls back to English even
  # though system.language=zh_CN. Shipping complete zh_CN/zh_TW locales makes both
  # Chinese variants work out of the box regardless of the guard.
  for L in zh_CN zh_TW; do
    I18NPATH=$(get_install_dir glibc)/usr/share/i18n/locales/ \
      localedef --force --verbose --inputfile=${L} --charmap=UTF-8 \
      ${INSTALL}/usr/config/locale/${L}.UTF-8 || true
  done

  mkdir -p ${INSTALL}/usr/config/emulationstation/resources
  cp -rf ${PKG_BUILD}/resources/* ${INSTALL}/usr/config/emulationstation/resources/
  rm -rf ${INSTALL}/usr/config/emulationstation/resources/logo.png

  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_BUILD}/es_settings ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/es_settings

  cp ${PKG_BUILD}/start_es.sh ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/start_es.sh

  cp ${PKG_BUILD}/serial_number_check ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/serial_number_check

  # es4all: bluetooth shim so ES (batocera lineage) `batocera-bluetooth <verb>`
  # drives ROCKNIX's own rocknix-bluetooth (else the BLUETOOTH menu is hidden
  # because ES probes for the batocera-bluetooth executable).
  cp ${PKG_BUILD}/dist/rocknix/sources/batocera-bluetooth ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/batocera-bluetooth

  # es4all: 参数化 eMMC 安装器(一支 + 内置 board 表,仿 EmuELEC installtoemmc.sh)。
  # 把 U 盘启动的 ROCKNIX 装进内部 eMMC:删 Armbian rootfs、ROCKNIX + STORAGE、
  # 只搬 OS 不搬游戏、保留 u-boot/BOOT 作 chainload 宿主与 MASKROM 救援基础。
  # 用法: installtoemmc list|auto|<board> [--yes]。加机型只加一条 board_config case。
  cp ${PKG_BUILD}/dist/rocknix/sources/installtoemmc ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/installtoemmc

  mkdir -p ${INSTALL}/usr/bin
  #ln -sf /storage/.config/emulationstation/resources ${INSTALL}/usr/bin/resources
  cp -rf ${PKG_BUILD}/emulationstation ${INSTALL}/usr/bin

  mkdir -p ${INSTALL}/etc/emulationstation/
  ln -sf /storage/.config/emulationstation/themes ${INSTALL}/etc/emulationstation/

  cp -rf ${PKG_DIR}/config/common/*.cfg ${INSTALL}/usr/config/emulationstation

  # If we're not an emulation device, ES may still be installed so we need a default config.
  #
  # es4all: ...but SPLIT_BUILD says EMULATION_DEVICE=no is not a statement about
  # the device. The userland job pins it purely to keep the emulators out of that
  # job; the box is still an emulation device and the real es_systems.cfg comes
  # from the emulators package. Writing the stub there would be actively unsafe:
  # the image is assembled by a multithreaded scheduler (scripts/image runs
  # start_multithread_build, which sets MTWITHLOCKS=yes and so skips the ordered
  # dependency install), so whether the emulators package's real file lands after
  # this stub is a race -- and losing that race ships a firmware whose ES lists
  # no systems at all.
  if [ "${SPLIT_BUILD}" != "yes" ] && \
     { [ "${EMULATION_DEVICE}" = "no" ] || \
       [ "${BASE_ONLY}" = "true" ]; }
  then
    cat <<EOF >${INSTALL}/usr/config/emulationstation/es_systems.cfg
<?xml version="1.0" encoding="UTF-8"?>
<systemList>
        <system>
                <name>tools</name>
                <fullname>Tools</fullname>
                <manufacturer>ROCKNIX</manufacturer>
                <release>2024</release>
                <hardware>system</hardware>
                <path>/storage/.config/modules</path>
                <extension>.sh</extension>
                <command>%ROM%</command>
                <platform>tools</platform>
                <theme>tools</theme>
        </system>
</systemList>
EOF
  fi

  ln -sf ${INSTALL}/usr/config/emulationstation/es_systems.cfg ${INSTALL}/etc/emulationstation/es_systems.cfg

  ln -sf /storage/.cache/system_timezone ${INSTALL}/etc/timezone

  #Delete all vulkan options from es_features when vulkan is not present
  if [ ! "${VULKAN_SUPPORT}" = "yes" ]
    then
      sed -i '/vulkan/d' ${INSTALL}/usr/config/emulationstation/es_features.cfg
  fi

  # === es4all ROCKNIX 胶水（烤进镜像，来源均在 ${PKG_BUILD}/dist/rocknix）=====
  # 开机 hook：SSH/Samba 默认开、常驻虚拟键盘、2键退出、PSP/DC 独立模拟器、
  # RA/system 默认、手柄 autoconfig、隐藏 pico-8/music、主题就位。装到 autostart
  # common（scripts/autostart 在 ES 启动前依序运行）。
  mkdir -p ${INSTALL}/usr/lib/autostart/common
  cp -f ${PKG_BUILD}/dist/rocknix/autostart/002-es4all-glue ${INSTALL}/usr/lib/autostart/common/002-es4all-glue
  chmod 0755 ${INSTALL}/usr/lib/autostart/common/002-es4all-glue

  # 胶水资产（虚拟键盘脚本、PSP controls、X360 autoconfig），hook 从 /usr/config/es4all 读
  mkdir -p ${INSTALL}/usr/config/es4all
  cp -f ${PKG_BUILD}/dist/rocknix/deploy/assets/es4all-vkbd.py ${INSTALL}/usr/config/es4all/
  cp -f ${PKG_BUILD}/dist/rocknix/deploy/assets/controls.ini ${INSTALL}/usr/config/es4all/
  cp -f "${PKG_BUILD}/dist/rocknix/deploy/assets/Microsoft X-Box 360 pad.cfg" ${INSTALL}/usr/config/es4all/

  # es4all: RetroArch 中文字体(含 CJK 字形)。RA 内建 xmb 字体无 CJK -> 中文显示方块(tofu);
  # 开机胶水把 xmb_font / video_font_path 指向这里。字体源自 es4all-1key。
  mkdir -p ${INSTALL}/usr/config/es4all/fonts
  cp -f ${PKG_BUILD}/dist/rocknix/deploy/assets/fonts/regular.ttf ${INSTALL}/usr/config/es4all/fonts/
  cp -f ${PKG_BUILD}/dist/rocknix/deploy/assets/fonts/bold.ttf ${INSTALL}/usr/config/es4all/fonts/

  # es4all 主题（es-theme-alekfull-EmueELEC），首次开机 seed 进 /storage themes
  if [ -d ${PKG_BUILD}/dist/rocknix/themes/es-theme-alekfull-EmueELEC ]; then
    mkdir -p ${INSTALL}/usr/config/emulationstation/themes
    cp -a ${PKG_BUILD}/dist/rocknix/themes/es-theme-alekfull-EmueELEC ${INSTALL}/usr/config/emulationstation/themes/
  fi
}


post_install() {
  mkdir -p ${INSTALL}/usr/share
  ln -sf /storage/.config/locale ${INSTALL}/usr/share/locale

  mkdir -p ${INSTALL}/usr/lib
  ln -sf /usr/share/locale ${INSTALL}/usr/lib/locale

  ln -sf /usr/share/locale  ${INSTALL}/usr/config/emulationstation/locale
}
