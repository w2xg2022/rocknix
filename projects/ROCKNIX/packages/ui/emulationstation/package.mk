# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

# es4all: 源码改由统一仓库 es4all 提供（原 ROCKNIX/emulationstation-next）。
PKG_NAME="emulationstation"
# pin 锚在 tag v1.1(已发布正式版)，不是分支 HEAD。交接单规则：编已发布版 pin
# 对应 tag `v1.X`(现场 git fetch --force --tags && git rev-parse v1.1)。
# ⚠️ tag v1.1 会被【重裁】：本次(2026-07-25)从 c1d6fdd 重裁到 49b5729，新增了手柄
# 「插上即用 + A 在南」的两处共用改动 A(剥 SDL 2.26+ 的 CRC-16 GUID，es-core
# InputManager rebuildAllJoysticks，删掉那段 #if WIN32 让 Linux 也剥)、B(_sdlToEsMapping
# 改一对一直通 = fallback 产出 A 在南)。所以每次接手都要现场重取 v1.1、别信旧 SHA。
# (更早的坑：c28dbaa 因简体化 rewrite history 成孤儿远端取不到；一度误 pin 分支 HEAD。)
PKG_VERSION="7fccfe7718b8ddca844444e7bd3a9e3d21df2dcb"   # = tag v1.2(2026-08-04 定版; 内外盘聚合选单接上 R 版)
# es4all 发 1.1 正式版后把 v1.1-dev 改名成了 v1.1-stable，远端已无 v1.1-dev。
# 这一栏写着不存在的分支就直接打断本包的 clone —— 每次 es4all 改名都要同步这里。
PKG_GIT_CLONE_BRANCH="v1.2-stable"
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

# NOTE(w2xg2022 2026-08-04): ★-DENABLE_EMUELEC=1 必须在【这里】—— 这份才是权威★
#   少了它不会警告, 而是【换掉整个前端】: 主选单、键位精灵用的表、网路/蓝牙选单、
#   外部挂载入口, 全都在 _ENABLEEMUELEC 底下。
#   ⚠️ 它长期只存在於三份【非权威】的地方 —— es4all 的 dist/rocknix/package.mk(参考副本)、
#      es4all-cross/cross-build.sh、以及 es4all 的 CI —— 唯独本档(云编译真正用的)没有。
#      於是本机与 CI 编出来的 ES 跟【固件里烤的那份不是同一个前端】, 而且完全静默:
#      不报错、不警告, 只是少了半个介面。
#   2026-08-04 v1.2 才因为编不过而暴露(openExternalMounts 声明在 _ENABLEEMUELEC 里):
#      GuiMenu.cpp:5297: error: 'openExternalMounts' was not declared in this scope
#   —— 是新功能替我们把一个既存的分岔照了出来, 不是新功能引进的问题。
PKG_CMAKE_OPTS_TARGET+=" -DES4ALL_TARGET=rocknix \
                         -DENABLE_EMUELEC=1 \
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
  # es4all: 上游这三行原本取 ${PKG_BUILD}/<文件>,因为上游 PKG_SITE 指向
  # ROCKNIX/emulationstation-next(根目录有这三支)。换成 w2xg2022/es4all 后根目录
  # 没有了,必须改路径,否则 makeinstall 直接失败。
  # es_settings / serial_number_check 是 ROCKNIX 自己的机制 -> 用 package 自带副本。
  cp ${PKG_DIR}/sources/es_settings ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/es_settings

  cp ${PKG_DIR}/sources/serial_number_check ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/serial_number_check

  # start_es.sh 由 es4all 维护(已移除 --no-splash:该参数在 main.cpp 直接
  # setBool("SplashScreen", false),且执行在载入 es_settings.cfg 之后,每次开机
  # 覆写用户设定,导致「启动画面设置」永远记不住)。故取 es4all 那份,不用
  # ${PKG_DIR}/sources 的旧版。
  cp ${PKG_BUILD}/dist/rocknix/sources/start_es.sh ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/start_es.sh

  # es4all: bluetooth shim so ES (batocera lineage) `batocera-bluetooth <verb>`
  # drives ROCKNIX's own rocknix-bluetooth (else the BLUETOOTH menu is hidden
  # because ES probes for the batocera-bluetooth executable).
  cp ${PKG_BUILD}/dist/rocknix/sources/batocera-bluetooth ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/batocera-bluetooth

  # es4all: AUDIO OUTPUT 后端脚本,ES 平台设置会调用 /usr/bin/es4all-setauddev。
  # 不装的话该选单点了没反应。
  cp ${PKG_BUILD}/dist/rocknix/sources/es4all-setauddev ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/es4all-setauddev

  # es4all: 视频模式后端(wlr-randr, Wayland)。1.1 已移除 VIDEO MODE 选单，但
  # 【后端与开机还原保留】—— autostart 002-es4all-glue 仍会无参调用它，把
  # system.videomode 还原回去(wlr-randr 只改执行期状态、重开机就没了)。所以
  # 选单没了不等于这支不用装,漏装就是每次开机分辨率回到 EDID 预设。
  # ⚠️ / 是唯读 squashfs、/usr/bin 写不进新档,漏装事后补不上,只能重编。
  cp ${PKG_BUILD}/dist/rocknix/sources/es4all-setvideomode ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/es4all-setvideomode

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
  # NOTE(w2xg2022 2026-08-04): ★手柄资料档不再从这里装 —— 已交给 es4all-profiles★
  #   es4all 的 0d0abd7「手柄资料档移出 dist 交给 profiles」把 controls.ini 与
  #   Microsoft X-Box 360 pad.cfg 从 dist/ 删掉了, 这两行於是 cp 一个不存在的档、
  #   整个 makeinstall_target 失败(实机: 云编译 30933303280 挂在 446/447)。
  #
  #   ⚠️ 这是【同一个变更只做了一半】: 那两个档现在由键位精灵产生(精灵 -> 转换器 ->
  #      joypad 档 / controls.ini), 固件本来就不该再塞一份写死的进去 ——
  #      本树的 002-es4all-glue 里那两段开机复制也是同一天因为同一个理由删掉的
  #      (它每次开机会把使用者跑精灵的结果盖回出厂值)。膠水那半做了, 这半漏了。

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
