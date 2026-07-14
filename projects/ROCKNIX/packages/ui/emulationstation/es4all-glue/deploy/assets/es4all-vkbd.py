#!/usr/bin/env python3
# es4all 常驻虚拟键盘 (raw ctypes uinput, 板上无 python-evdev 模块也能用)
# ROCKNIX 面向掌机, 假设板载输入永远在场; 电视盒无内建输入时 ES 不激活手柄导航。
# 本脚本建一个永远在场的虚拟键盘设备并一直握住 fd, 让外接手柄单独可用。
import struct, fcntl, os, time, sys
UINPUT_MAX_NAME_SIZE = 80
EV_SYN = 0; EV_KEY = 1
UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_DEV_CREATE = 0x5501
BUS_USB = 0x03
# ESC,ENTER,SPACE,UP,LEFT,RIGHT,DOWN + 功能/修饰键 + 数字行 + qwerty 字母
keys = [1, 28, 57, 103, 105, 106, 108, 14, 15, 29, 42, 54, 56, 100, 125] \
    + list(range(2, 14)) + list(range(16, 26)) + list(range(30, 39)) + list(range(44, 54))
fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_SYN)
for k in keys:
    fcntl.ioctl(fd, UI_SET_KEYBIT, k)
name = b"es4all-virtual-keyboard".ljust(UINPUT_MAX_NAME_SIZE, b'\x00')
buf = name + struct.pack("HHHH", BUS_USB, 0x1234, 0x5678, 1) + struct.pack("I", 0) + b'\x00' * (4 * 64 * 4)
os.write(fd, buf)
fcntl.ioctl(fd, UI_DEV_CREATE)
sys.stdout.write("es4all-vkbd created, holding device open\n"); sys.stdout.flush()
while True:
    time.sleep(3600)
