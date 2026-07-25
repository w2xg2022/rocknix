#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

. /etc/profile
set_kill set "-9 ppsspp"

SOURCE_DIR="/usr/config/ppsspp"
CONF_DIR="/storage/.config/ppsspp"
PPSSPP_INI="PSP/SYSTEM/ppsspp.ini"

# Check if conf dir exists
if [ ! -d "${CONF_DIR}" ]
then
  cp -rf ${SOURCE_DIR} ${CONF_DIR}
fi

# Check if savestate dir exists
if [ ! -d "/storage/roms/savestates/psp/ppsspp-sa" ]; then
  mkdir -p "/storage/roms/savestates/psp/ppsspp-sa"
fi

#Emulation Station Features
GAME=$(echo "${1}"| sed "s#^/.*/##")
PLATFORM=$(echo "${2}"| sed "s#^/.*/##")
ASKIP=$(get_setting auto_frame_skip "${PLATFORM}" "${GAME}")
FPS=$(get_setting show_fps "${PLATFORM}" "${GAME}")
IRES=$(get_setting internal_resolution "${PLATFORM}" "${GAME}")
GRENDERER=$(get_setting graphics_backend "${PLATFORM}" "${GAME}")
SKIPB=$(get_setting skip_buffer_effects "${PLATFORM}" "${GAME}")
VSYNC=$(get_setting vsync "${PLATFORM}" "${GAME}")
CLOCK_SPEED=$(get_setting clock_speed "${PLATFORM}" "${GAME}")

#Set the cores to use
CORES=$(get_setting "cores" "${PLATFORM}" "${GAME}")
if [ "${CORES}" = "little" ]; then
  EMUPERF="${SLOW_CORES}"
elif [ "${CORES}" = "big" ]; then
  EMUPERF="${FAST_CORES}"
else
  ### All..
  unset EMUPERF
fi

  #Auto Frame Skip
	if [ "${ASKIP}" = "1" ]; then
		sed -i '/AutoFrameSkip =/c\AutoFrameSkip = True' ${CONF_DIR}/${PPSSPP_INI}
	else
		sed -i '/^AutoFrameSkip =/c\AutoFrameSkip = False' ${CONF_DIR}/${PPSSPP_INI}
        fi

  #Graphics Backend
        if [ "${GRENDERER}" = "opengl" ]; then
                sed -i '/^GraphicsBackend =/c\GraphicsBackend = 0 (OPENGL)' ${CONF_DIR}/${PPSSPP_INI}
        elif [ "${GRENDERER}" = "vulkan" ]; then
                sed -i '/^GraphicsBackend =/c\GraphicsBackend = 3 (VULKAN)' ${CONF_DIR}/${PPSSPP_INI}
        else
		sed -i '/^GraphicsBackend =/c\GraphicsBackend = @GRENDERER@' ${CONF_DIR}/${PPSSPP_INI}
	fi

  #Internal Resolution
	if [ "${IRES}" = "2" ]; then
		sed -i '/^InternalResolution/c\InternalResolution = 2' ${CONF_DIR}/${PPSSPP_INI}
	elif [ "${IRES}" = "3" ]; then
		sed -i '/^InternalResolution/c\InternalResolution = 3' ${CONF_DIR}/${PPSSPP_INI}
	elif [ "${IRES}" = "4" ]; then
                sed -i '/^InternalResolution/c\InternalResolution = 4' ${CONF_DIR}/${PPSSPP_INI}
	else
		sed -i '/^InternalResolution/c\InternalResolution = 1' ${CONF_DIR}/${PPSSPP_INI}
        fi

  #Show FPS
	if [ "${FPS}" = "1" ]; then
		sed -i '/^iShowStatusFlags =/c\iShowStatusFlags = 2' ${CONF_DIR}/${PPSSPP_INI}
	else
		sed -i '/^iShowStatusFlags =/c\iShowStatusFlags = 0' ${CONF_DIR}/${PPSSPP_INI}
	fi

  #Skip Buffer Effects
	if [ "${SKIPB}" = "1" ]; then
		sed -i '/^SkipBufferEffects =/c\SkipBufferEffects = True' ${CONF_DIR}/${PPSSPP_INI}
	else
		sed -i '/^SkipBufferEffects =/c\SkipBufferEffects = False' ${CONF_DIR}/${PPSSPP_INI}
	fi

  #VSYNC
	if [ "${VSYNC}" = "1" ]; then
		sed -i '/^VSyncInterval =/c\VSyncInterval = True' ${CONF_DIR}/${PPSSPP_INI}
	else
		sed -i '/^VSyncInterval =/c\VSyncInterval = False' ${CONF_DIR}/${PPSSPP_INI}
	fi

  #Clock Speed
	if [ "${CLOCK_SPEED}" = "222" ]; then
		sed -i '/^CPUSpeed =/c\CPUSpeed = 222' ${CONF_DIR}/${PPSSPP_INI}
  elif [ "${CLOCK_SPEED}" = "333" ]; then
		sed -i '/^CPUSpeed =/c\CPUSpeed = 333' ${CONF_DIR}/${PPSSPP_INI}
	else
		sed -i '/^CPUSpeed =/c\CPUSpeed = 0' ${CONF_DIR}/${PPSSPP_INI}
	fi

#UI 语言跟随 ES(system.language),比照 setsettings.sh 强制 RetroArch 的做法
# PPSSPP 的语言码 = assets/lang/*.ini 的文件名,与 system.language 基本一致,只有几个别名要转。
# ★ppsspp.ini 有两行 Language★:[General] 里字母值的是 UI 语言,另一行 `Language = 1` 是模拟的
#   PSP 主机语言。sed 必须用 [a-zA-Z] 只锁 UI 那行,别误动数字行。
ESLANG=$(get_setting system.language)
case "${ESLANG}" in
  cs_CZ) PPLANG="cz_CZ" ;;
  en_GB) PPLANG="en_US" ;;
  es_MX|eu_ES) PPLANG="es_ES" ;;
  "") PPLANG="zh_CN" ;;
  *) PPLANG="${ESLANG}" ;;
esac
# 没有对应翻译档就退回默认,别写进一个 PPSSPP 不认得的码
if [ ! -f "${CONF_DIR}/assets/lang/${PPLANG}.ini" ]; then
  PPLANG="zh_CN"
fi
sed -i "/^Language = [a-zA-Z]/c\\Language = ${PPLANG}" ${CONF_DIR}/${PPSSPP_INI}
echo "UI LANGUAGE set to: ${PPLANG} (from system.language=${ESLANG})"

#Hotkey SELECT+X (呼出菜单) —— 跟 ES 的手柄「印刷布局」走
# controls.ini 里的 10-188~191 是 SDL GameController 的语意键(Y/A/B/X),位置本来就
# 跟 ES 对齐(两边都从 gamecontrollerdb 推导),唯独「印着 X 的是哪一颗」只有 ES 知道:
# ES 的布局侦测(GuiDetectLayout,只按一次 A)把结果写进 es_settings.cfg 的 InvertButtons
#   false = Xbox 式印刷(A 在南) → 印刷 X 在西 = SDL X = 10-191
#   true  = 任天堂式印刷(A 在东) → 印刷 X 在北 = SDL Y = 10-188
# 其余组合键(SELECT+START 退出 / SELECT+R1 存档 / SELECT+L1 读档)与印刷无关,
# 写死在 controls.ini 模板里,这里不动。
ES_SETTINGS="/storage/.config/emulationstation/es_settings.cfg"
CONTROLS_INI="${CONF_DIR}/PSP/SYSTEM/controls.ini"
if [ -f "${CONTROLS_INI}" ]; then
  MENU_KEY="10-191"
  if grep -q '"InvertButtons" value="true"' "${ES_SETTINGS}" 2>/dev/null; then
    MENU_KEY="10-188"
  fi
  if grep -q '^Pause = ' "${CONTROLS_INI}"; then
    sed -i "/^Pause = /c\\Pause = 10-196:${MENU_KEY}" "${CONTROLS_INI}"
  else
    echo "Pause = 10-196:${MENU_KEY}" >>"${CONTROLS_INI}"
  fi
  echo "MENU HOTKEY (SELECT+X) set to: 10-196:${MENU_KEY}"
fi

#Retroachievements
/usr/bin/cheevos_ppsspp.sh

ARG=${1//[\\]/}

# Debugging info:
  echo "GAME set to: ${GAME}"
  echo "PLATFORM set to: ${PLATFORM}"
  echo "CONF DIR: ${CONF_DIR}/${PPSSPP_INI}"
  echo "CPU CORES set to: ${EMUPERF}"
  echo "AUTO FRAME SKIP set to: ${ASKIP}"
  echo "GRAPHICS RENDERER set to: ${GRENDERER}"
  echo "INTERNAL RESOLUTION set to: ${IRES}"
  echo "FPS set to: ${FPS}"
  echo "SKIP BUFFER EFFECTS set to: ${SKIPB}"
  echo "VSYNC set to: ${VSYNC}"
  echo "Launching /usr/bin/ppsspp ${ARG}"

${EMUPERF} ppsspp --pause-menu-exit "${ARG}"
