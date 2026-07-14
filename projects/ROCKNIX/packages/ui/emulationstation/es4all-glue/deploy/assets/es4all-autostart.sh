#!/bin/bash
# es4all ROCKNIX 持久化钩子 (autostart 在 ES 启动前执行)
# 1) es4all EmulationStation 本体
ES4ALL_BIN="/storage/es4all-emulationstation"
if [ -f "${ES4ALL_BIN}" ] && ! mountpoint -q /usr/bin/emulationstation; then
    mount --bind "${ES4ALL_BIN}" /usr/bin/emulationstation
fi
# 2) input_sense: 退出热键改 SELECT+START (2键)
ES4ALL_INSENSE="/storage/es4all-input_sense"
if [ -f "${ES4ALL_INSENSE}" ] && ! mountpoint -q /usr/bin/input_sense; then
    mount --bind "${ES4ALL_INSENSE}" /usr/bin/input_sense
    systemctl restart input.service 2>/dev/null
fi
# 3) 虚拟键盘: ROCKNIX 面向掌机(板载输入常在)，电视盒无内建输入时 ES 不激活手柄
#    导航。此常驻虚拟键盘模拟"永远在场的板载键盘"，让外接手柄单独可用(无需插实体键盘)。
#    必须在 ES 启动前拉起并等设备注册好，避免 ES 抢跑扫不到。
VKBD_PY="/storage/es4all-vkbd.py"
if [ -f "${VKBD_PY}" ] && ! grep -q es4all-virtual-keyboard /proc/bus/input/devices; then
    python3 "${VKBD_PY}" &
    for i in $(seq 1 50); do
        grep -q es4all-virtual-keyboard /proc/bus/input/devices && break
        sleep 0.1
    done
fi
