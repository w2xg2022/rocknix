#!/bin/bash
# es4all ROCKNIX 运行时部署脚本（幂等）
# 在一台已刷好 ROCKNIX 的 MD1000(RK3566) 上运行一次，即可把 es4all ES 及全套
# 键位/菜单/存档/退出热键胶水部署好，且重开机安全。
#
# 用法：  拷到设备后  bash deploy_es4all_rocknix.sh
# 前提：  /storage/es4all-emulationstation 已存在(编译好的 es4all ES 本体)
#
# 说明：ROCKNIX 为 immutable(/usr 只读)，本脚本用 bind-mount + /storage 持久区 +
#       官方 autostart 钩子(/storage/.config/autostart)实现覆盖，不改动只读镜像。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ASSETS="${HERE}/assets"
log(){ echo "[es4all] $*"; }

RA_CFG="/storage/.config/retroarch/retroarch.cfg"
SYS_CFG="/storage/.config/system/configs/system.cfg"
PSP_CTRL="/storage/.config/ppsspp/PSP/SYSTEM/controls.ini"
JOYPADS="/tmp/joypads"

# 通用：设置一个 key=value(无空格等号)到某 cfg，存在则替换否则追加
set_kv(){ local f="$1" k="$2" v="$3"
  if grep -q "^${k}=" "$f" 2>/dev/null; then sed -i "s#^${k}=.*#${k}=${v}#" "$f"
  else echo "${k}=${v}" >> "$f"; fi; }
# 通用：设置 retroarch 风格   key = "value"
set_ra(){ local f="$1" k="$2" v="$3"
  if grep -q "^${k} = " "$f" 2>/dev/null; then sed -i "s#^${k} = .*#${k} = \"${v}\"#" "$f"
  else echo "${k} = \"${v}\"" >> "$f"; fi; }

### 0) 前提检查 ###########################################################
if [ ! -f /storage/es4all-emulationstation ]; then
  log "错误：/storage/es4all-emulationstation 不存在，请先放入编译好的 ES 本体。"; exit 1
fi

### 1) autostart 钩子：开机重挂 ES 本体 + input_sense + 虚拟键盘 #############
log "安装 autostart 钩子"
mkdir -p /storage/.config/autostart
install -m 0755 "${ASSETS}/es4all-autostart.sh" /storage/.config/autostart/es4all.sh
# 虚拟键盘脚本(电视盒补板载输入，让外接手柄单独可用；由 autostart 钩子拉起)
install -m 0755 "${ASSETS}/es4all-vkbd.py" /storage/es4all-vkbd.py

### 2) input_sense：退出热键改 SELECT+START(2键) ###########################
# 从当前只读 input_sense 生成 patch 版(跟随 ROCKNIX 版本，只放宽 kill 条件)
# 已 patch 过则跳过(避免重跑时 /usr/bin/input_sense 已是本 bind-mount 造成 cp 同文件)
if ! grep -q "es4all: 2键退出" /storage/es4all-input_sense 2>/dev/null; then
  log "生成 2 键退出 input_sense"
  cp -f /usr/bin/input_sense /storage/es4all-input_sense
  python3 - <<'PYEOF'
p="/storage/es4all-input_sense"; s=open(p).read()
s=s.replace('if [ "${HOTKEY_A_PRESSED}" = true ] && [ "${HOTKEY_C_PRESSED}" = true ]; then',
            'if [ "${HOTKEY_C_PRESSED}" = true ]; then  # es4all: 2键退出 SELECT+START')
s=s.replace('if [ "${HOTKEY_A_PRESSED}" = true ] && [ "${HOTKEY_B_PRESSED}" = true ]; then',
            'if [ "${HOTKEY_B_PRESSED}" = true ]; then  # es4all: 2键退出 SELECT+START')
open(p,"w").write(s)
PYEOF
  chmod 0755 /storage/es4all-input_sense
else
  log "input_sense 已 patch, 跳过"
fi

### 3) 立即挂载(本次生效；开机由钩子重挂) ##################################
log "bind-mount ES 本体 + input_sense"
mountpoint -q /usr/bin/emulationstation || mount --bind /storage/es4all-emulationstation /usr/bin/emulationstation
if ! mountpoint -q /usr/bin/input_sense; then
  mount --bind /storage/es4all-input_sense /usr/bin/input_sense
  systemctl restart input.service 2>/dev/null
fi
# 虚拟键盘立即拉起(本次生效；开机由钩子重拉)
if ! grep -q es4all-virtual-keyboard /proc/bus/input/devices; then
  log "启动常驻虚拟键盘"
  python3 /storage/es4all-vkbd.py &
fi
log "RetroArch: 菜单AB不互换 / 简体中文"
set_ra "${RA_CFG}" menu_swap_ok_cancel_buttons false   # 标准对齐 autoconfig 下, 印刷A=确定
set_ra "${RA_CFG}" user_language 12                    # 12 = 简体中文
# 进游戏不显示游戏名载入动画(ROCKNIX 默认已 false, 确保之)
set_ra "${RA_CFG}" menu_show_load_content_animation false

### 5) 系统默认 ##########################################################
log "系统: 关闭自动读/存档"
set_kv "${SYS_CFG}" global.autosave 0                  # 关自动读档+自动存档
log "系统: PSP 用独立模拟器(性能)"
set_kv "${SYS_CFG}" psp.emulator ppsspp
set_kv "${SYS_CFG}" psp.core ppsspp-sa
log "系统: Dreamcast 用独立模拟器(flycast standalone, 性能)"
set_kv "${SYS_CFG}" dreamcast.emulator flycast
set_kv "${SYS_CFG}" dreamcast.core flycast-sa

### 6) PSP 独立模拟器手柄(controls.ini) ###################################
# 修正 □/△ 与物理位置对齐(西=□ 北=△); ✕/○ 本就正确
if [ -f "${PSP_CTRL}" ] && [ -f "${ASSETS}/controls.ini" ]; then
  log "PSP: 安装 controls.ini"
  cp -f "${ASSETS}/controls.ini" "${PSP_CTRL}"
fi

### 7) 手柄 autoconfig 标准对齐 ###########################################
# /tmp/joypads 是 overlay(upper=/storage/joypads 持久)，写入即持久。
# 注意：以下为「Microsoft X-Box 360 pad」测试手柄的标准对齐档(印刷字母=RetroPad字母,
#       dpad=hat h0)。换其它手柄需按该手柄的实际按钮号另做一份(见 README)。
if [ -d "${JOYPADS}" ] && [ -f "${ASSETS}/Microsoft X-Box 360 pad.cfg" ]; then
  log "手柄: 安装标准对齐 autoconfig(Microsoft X-Box 360 pad)"
  cp -f "${ASSETS}/Microsoft X-Box 360 pad.cfg" "${JOYPADS}/Microsoft X-Box 360 pad.cfg"
fi

### 8) 确保隐藏 pico-8 平台 ###############################################
# pico-8 需 Lexaloffle 付费本体才能玩，且 es4all 主题无 pico-8 图；ROCKNIX 出厂
# 本就把它放进 es_settings.cfg 的 HiddenSystems，这里再确保一次(幂等)。
ES_SETTINGS="/storage/.config/emulationstation/es_settings.cfg"
if [ -f "${ES_SETTINGS}" ] && ! grep -q 'HiddenSystems" value="[^"]*pico-8' "${ES_SETTINGS}"; then
  log "隐藏 pico-8 平台"
  sed -i 's#\(HiddenSystems" value="\)#\1pico-8;#' "${ES_SETTINGS}"
fi

log "完成。建议 systemctl restart essway 或重开机验证。"
