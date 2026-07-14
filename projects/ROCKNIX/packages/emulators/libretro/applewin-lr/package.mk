# SPDX-License-Identifier: GPL-2.0-or-later
# es4all/ROCKNIX: 移植自 EmuELEC 的 applewin 食谱(audetto/AppleWin libretro fork)。
# apple2 系统原本在 ROCKNIX 未定义(mk_es_systems 里没有)、applewin 核心也没编，
# 导致 apple2 完全玩不了。BUILD_LIBRETRO=ON 是唯一不需要 Qt5/Boost 的构建选项。

PKG_NAME="applewin-lr"
PKG_VERSION="f2c22675385a5c2561d7aec1cc8ecf860e20fc5d"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/audetto/AppleWin"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="AppleWin libretro core for Apple II emulation"
PKG_TOOLCHAIN="cmake"

pre_configure_target() {
  PKG_CMAKE_OPTS_TARGET+=" -DCMAKE_BUILD_TYPE=Release -DBUILD_LIBRETRO=ON -DBUILD_QAPPLE=OFF -DBUILD_SA2=OFF -DBUILD_APPLEN=OFF"

  # resource/Cousine-Regular.ttf 在 git 仓库是指向 imgui submodule 的 symlink，
  # archive.tar.gz 不含 submodule 内容 → 解开后变死链接 → xxd 读不到 → build 失败。
  # 直接下载实际字体覆盖死链接（同 EmuELEC 食谱）。
  rm -f ${PKG_BUILD}/resource/Cousine-Regular.ttf
  curl -sL -o ${PKG_BUILD}/resource/Cousine-Regular.ttf \
    https://raw.githubusercontent.com/ocornut/imgui/master/misc/fonts/Cousine-Regular.ttf
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  # find 自动定位 .so(避免 ROCKNIX 与 EmuELEC 的 cmake 输出路径细微差异导致装不到)
  SO=$(find ${PKG_BUILD} -name applewin_libretro.so 2>/dev/null | head -1)
  cp "${SO}" ${INSTALL}/usr/lib/libretro/applewin_libretro.so
}
