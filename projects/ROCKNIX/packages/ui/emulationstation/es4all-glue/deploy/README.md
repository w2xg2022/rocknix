# es4all ROCKNIX 运行时部署（胶水）

在一台**已刷好 ROCKNIX** 的 MD1000(RK3566) 上，把 es4all ES 及全套键位/菜单/存档/
退出热键胶水部署上去，重开机安全。适用于「不重建镜像、直接覆盖到现有 ROCKNIX」的场景。

## 用法
1. 把编译好的 ES 本体放到设备：`/storage/es4all-emulationstation`
2. 把本目录(含 `assets/`)拷到设备，运行：`bash deploy_es4all_rocknix.sh`
3. `systemctl restart essway` 或重开机验证。

## 原理
ROCKNIX immutable(`/usr` 只读)，故用三种持久手段：
- **bind-mount**：ES 本体、input_sense 挂到 `/usr/bin/*`（临时，靠钩子每次开机重挂）。
- **`/storage` 持久区**：retroarch.cfg、system.cfg、ppsspp/controls.ini 本就在 `/storage`。
- **官方 autostart 钩子**：`/usr/bin/autostart` 结尾会跑 `/storage/.config/autostart/*`
  （在 ES 启动前），装 `es4all.sh` 做上面两个 bind-mount。
- **overlay**：`/tmp/joypads` 是 overlay(upper=`/storage/joypads` 持久)，写入即持久。

## 本脚本做的事（对应本次调试结论）
| 项 | 值 | 说明 |
|---|---|---|
| ES 本体 | bind-mount | es4all(含布局侦测/FPS/InvertGameButtons) |
| 退出热键 | **SELECT+START** | patch input_sense kill 条件 A&&B&&C → B&&C |
| RA 菜单 AB | menu_swap=false | 配合标准对齐 autoconfig，印刷A=确定 |
| RA 语言 | user_language=12 | 简体中文 |
| 进游戏名 | menu_show_load_content_animation=false | 不显示载入动画游戏名 |
| 自动存档 | global.autosave=0 | 关自动读档+自动存档 |
| PSP | ppsspp / ppsspp-sa | 独立模拟器(性能, 避免 libretro 12fps) |
| PSP 手柄 | controls.ini | □/△ 与物理位对齐(西=□ 北=△) |
| 手柄 autoconfig | 标准对齐 | 印刷字母=RetroPad字母, dpad=hat h0 |

## ⚠️ 手柄 autoconfig 是「按手柄」的
`assets/Microsoft X-Box 360 pad.cfg` 只对该测试手柄成立。**关键结论**：ROCKNIX 原厂
autoconfig 走「位置对齐」(input_a_btn=印刷B…) 把印刷字母和 RetroPad 字母错开，之前一堆
补偿(menu_swap/per-core rmp)全是在补它。**治本**=把 autoconfig 改成标准对齐
`input_a_btn=0,b=1,x=2,y=3`(+label A/B/X/Y)，则 stock ROCKNIX 行为自然全对、零补偿。

换其它手柄（如 MD1000 内建 `retrogame_joypad`）需按该手柄实测：
- 按钮号：读 `/dev/input/js0`(linuxraw legacy API, struct js_event) 探 印刷A/B/X/Y → btn 号
- 十字键：`input_joypad_driver=udev`，dpad 是 hat0(evdev code16/17)→用 `input_up_btn="h0up"` 等
  （**不是** linuxraw 的 `input_up_axis`，原厂常写错）
然后据此另存一份标准对齐 autoconfig。

## 相关文件
- `deploy_es4all_rocknix.sh` — 主脚本(幂等)
- `assets/es4all-autostart.sh` — 开机钩子
- `assets/controls.ini` — PSP 独立模拟器手柄映射
- `assets/Microsoft X-Box 360 pad.cfg` — 该测试手柄标准对齐 autoconfig(示例)
