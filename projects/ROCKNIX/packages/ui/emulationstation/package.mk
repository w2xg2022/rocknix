# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

# es4all: 源码改由统一仓库 es4all 提供（原 ROCKNIX/emulationstation-next）。
PKG_NAME="emulationstation"
PKG_VERSION="cb6c65b297b72f6fcd690343f9cc5e62cafb6933"
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

  mkdir -p ${INSTALL}/usr/bin
  #ln -sf /storage/.config/emulationstation/resources ${INSTALL}/usr/bin/resources
  cp -rf ${PKG_BUILD}/emulationstation ${INSTALL}/usr/bin

  mkdir -p ${INSTALL}/etc/emulationstation/
  ln -sf /storage/.config/emulationstation/themes ${INSTALL}/etc/emulationstation/

  cp -rf ${PKG_DIR}/config/common/*.cfg ${INSTALL}/usr/config/emulationstation

  # If we're not an emulation device, ES may still be installed so we need a default config.
  if [ "${EMULATION_DEVICE}" = "no" ] || \
     [ "${BASE_ONLY}" = "true" ]
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
