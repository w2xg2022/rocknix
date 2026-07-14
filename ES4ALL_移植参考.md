# ES4All → emulationstation-next 移植参考
生成于2026-07-14。目标:把 ES4All(EmuELEC/batocera系)在 ROCKNIX 上的自定义功能,移植到 stock ROCKNIX ES(emulationstation-next,JELOS/batocera系,能在wayland/sway下正常开机)。

## 我们新增的全新文件(stock无→直接加)
- es-core/src/guis/GuiDetectLayout.cpp
- es-core/src/guis/GuiDetectLayout.h
(以 GuiDetectLayout 为核心:手柄布局侦测)

## 共用文件里我们的改动锚点(es4all: 标记)
es-app/src/ApiSystem.cpp:558:	// es4all: 优先取默认路由所在接口的 IP，避免多网卡(如同时接 eth0 + wlan0)时
es-app/src/ApiSystem.cpp:1802:		// es4all: ROCKNIX 用 wifictl(nmcli 后端，命令与 batocera-wifi 兼容)取代 batocera-wifi，
es-app/src/guis/GuiControllersSettings.cpp:63:	// es4all: 「游戏内互换 A/B、X/Y」两个开关已移除（2026-07 手柄三层架构定案）。
es-app/src/guis/GuiMenu.cpp:1277:			// es4all: 版号统一以 PROGRAM_VERSION_STRING(EmulationStation.h)为唯一来源，不再拿
es-app/src/guis/GuiMenu.cpp:2086:	// es4all: InvertGameButtons 开关已移到「手柄和蓝牙设置 → 手柄按键映射」旁（GuiControllersSettings）。
es-app/src/guis/GuiMenu.cpp:2260:			// es4all: 只维护单一 stable 更新线，不做 beta 通道(会造成困惑且无独立内容;
es-app/src/guis/GuiMenu.cpp:2271:		// es4all: BETA 选项已移除(原 updatesTypeList->add(BETA_NAME,...) 删除)。
es-app/src/guis/GuiMenu.cpp:2330:	// es4all: 用 ApiSystem::getTimezones()(直接读 /usr/share/zoneinfo，三边通用)取代
es-app/src/guis/GuiMenu.cpp:3728:	// es4all: SHOW RETROARCH FPS —— 在所有 RetroArch 核心游戏画面显示帧数。
es-core/src/InputConfig.cpp:376:	// es4all: 跟 buttonImage 一致，依 InvertButtons/InvertXYButtons 回傳方位名。
es-core/src/InputConfig.cpp:388:	// es4all: 鍵位圖跟著佈局偵測結果(GuiDetectLayout)走。
es-core/src/Paths.cpp:109:	// es4all: 依 target 指向各自的 config store，避免空路径导致 SystemConf
es-core/src/utils/Platform.h:75:            std::string getShOutput(const std::string& mStr); /* es4all: 所有 target 皆可用(getIpAddress 等依赖) */
es-core/src/utils/Platform.cpp:607:/* es4all: 移出 _ENABLEEMUELEC guard，所有 target 皆可用(getIpAddress 等依赖) */
es-core/src/guis/GuiDetectDevice.cpp:150:				// es4all: 進輸入設定前先偵測手柄佈局(按A定AB、按X定XY)，校準印刷標籤 vs 系統回報。
es-core/src/guis/GuiInputConfig.cpp:128:	// es4all: 依佈局偵測結果(GuiDetectLayout)調整鍵位圖。
es-core/src/guis/GuiInputConfig.cpp:153:		// es4all: A/B 与 X/Y 一致处理——都相信布局侦测(GuiDetectLayout)结果，
es-core/src/guis/GuiDetectLayout.h:12:// es4all: 手柄布局偵測(evdev 版)。
es-core/src/Settings.cpp:196:	// es4all: 游戏内 A/B、X/Y 位置对调（透传到 RetroArch per-core remap，由 setsettings.sh 套用）。
es-core/src/Settings.cpp:199:	// es4all: XY 位置對調（韌體把 X/Y 回報反、或任天堂式 XY 佈局時）。由佈局偵測(GuiDetectLayout)設定。

## 功能清单(来自 git log 的 feat/fix commits)
34ff01b 改用核心层per-core remap做位置对齐(通吃任何手柄)，autoconfig还原标准label
1f88fe3 修复ROCKNIX手柄键位:autoconfig改udev驱动+面键按位置对齐
423ffb0 更新类型只留stable、隐藏BETA选项: 归一updates.type=stable并持久化(清历史残留beta);单一stable线的平台整个更新类型选择器隐藏(仅WIN32保留unstable/stable多选)
9ae3175 主菜单页脚三平台统一: ES4All (<目标>) V<版本>, IP: <ip>——版号以PROGRAM_VERSION_STRING为唯一来源;目标名随ES4ALL_TARGET宏(EmuELEC/ROCKNIX/Armbian);修复armbian/rocknix之前退化成EMULATIONSTATION V1.0(无IP)的遗漏
24ffd7b 手柄配置翻译: 补9条手柄键/热键翻译(简繁) + 停用msgmerge(修pgettext手柄标签条目被xgettext漏抓后剥光的bug)
28b202e 主菜单版号以 PROGRAM_VERSION_STRING 为唯一来源(ES4All V1.0), EmuELEC 底座版本括号注明 [skip ci]
2ed2356 refactor(input): 手柄三层架构定案-移除游戏内AB/XY开关+精灵只问A [skip ci]
586175c i18n: 补齐游戏内互换A/B、X/Y两个开关的简繁翻译 [skip ci]
4c69b7b fix(ui): 手柄配置界面 X/Y 位置显示改为跟 A/B 一致(都信布局侦测) [skip ci]
08fe0b6 Merge x98mini-hotkey-fixes: 手柄互换开关拆AB/XY+补齐布局侦测翻译+摇杆按下文案 [skip ci]
ff3bfe5 fix(ui): 手柄互换开关拆AB/XY两颗+补齐布局侦测精灵翻译+摇杆按下文案统一
8490271 feat(rocknix): 胶水烤进镜像 - 开机hook+主题+服务默认开
b01141a fix(rocknix): getShOutput 移出 _ENABLEEMUELEC guard
bc14ae7 fix(rocknix): GuiMenu.cpp 修 _ENABLEEMUELEC 大括号不平衡
9366139 fix(rocknix): CloudSaves.cpp 补 _ENABLEEMUELEC guard 修非EmuELEC编译
bbfea55 feat(rocknix): 电视盒膠水三件套
61b7347 feat(dc): dreamcast/naomi/atomiswave默认改用独立模拟器flycastsa
f3fa89b feat(psp): psp系统默认改用独立模拟器PPSSPPSDL(其他系统维持libretro)
c51d9b2 fix(emuelec): FPS切换热键从R3改到Y(SELECT+Y切FPS)
3948bec feat: 同步EmuELEC膠水+新增emuelec ES构建，release统一命名es4all
c9865b2 布局侦测改用evdev(读BTN真实位置,含韧体X/Y对调pad); 输入设定表AB可换位/XY维持标准显示(韧体对调pad软件判不出真实位置); 清诊断码
2d15d1f GuiDetectLayout: 修正Renderer.h include路径 + 加临时诊断(写/storage/detectlayout.log印binds/press-id/result,待抓到SDL bind数据后移除)
c91c97e 布局侦测follow-up: 键位图跟着InvertButtons/InvertXYButtons走(buttonImage/buttonDisplayName+GuiInputConfig表用a↔b/x↔y互换,默认零回归)
bb6f82f 手柄布局侦测(A键): 新增 GuiDetectLayout, 按印刷A定AB/按印刷X定XY(SDL GameController反查南东西北), 掛在 GuiDetectDevice→GuiInputConfig 之间; 新增 InvertXYButtons 设定
6b9270d #3适配(2): getIpAddress优先取默认路由接口IP(多网卡不再抓错wlan0); 补FPS描述zh_CN/zh_TW翻译
bc0dce1 #3 ROCKNIX适配(1): SystemConf依target指向对的config store(rocknix→system.cfg,解时区/FPS/游戏设置持久化); 网络菜单batocera-wifi→wifictl(nmcli后端)
54262ca #1 InvertGameButtons开关从开发者选项移到手柄设置(手柄按键映射旁); #4 时区列表改用/usr/share/zoneinfo(三边通用,去除emuelec-utils依赖)
5bc4303 locale: 补 InvertGameButtons 开关的 日/俄/西/葡/法 翻译; msgattrib --no-obsolete 清理全部语言废弃条目
1cd26a1 需求1: FPS開關移至GAME SETTINGS(跨target);需求3: 新增InvertGameButtons遊戲內AB/XY對調開關+預設true
