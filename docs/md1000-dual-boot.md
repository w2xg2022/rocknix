# MD1000 双系统切换（Armbian ⇄ ROCKNIX）

MD1000（RK3566）的[缝合方案](../README.md#-支持机型)：**eMMC 装 Armbian、U 盘装 ROCKNIX**，eMMC 的 vendor u-boot（DRAM 已校准，保开机）用 `booti` 链载 ROCKNIX 内核。一个 **TRIGGER 档**决定这次开哪个系统，两边都能一键互切。

## 原理

eMMC 的 `/boot/boot.cmd`（u-boot 脚本）开机时先检查 eMMC boot 分区上的 `rocknix/TRIGGER`：

- **有 TRIGGER** → 载入 eMMC 的 `rocknix/Image` + dtb，`booti` 链载 ROCKNIX（rootfs 从 U 盘 `LABEL=ROCKNIX` / `STORAGE`）。
- **没 TRIGGER**（或没插 U 盘导致 booti 失败）→ 落回 Armbian。**保底：绝不变砖。**

> **为什么用 booti 不用 kexec**：kexec 会把 GPU/显示留成脏状态，ROCKNIX 到 sway 初始化 DRM 时整台硬冻结（黑屏）。booti 由 u-boot 干净初始化硬件，是唯一验证过能跑的路径。

## 一键切换（curl 下载即执行）

> 两个方向的脚本在 [`docs/md1000-dualboot/`](md1000-dualboot/)。

### ▶ Armbian → U 盘 ROCKNIX

在 **Armbian**（`root` / `1234`，需联网、U 盘要插着）里跑：

```bash
curl -fsSL https://raw.githubusercontent.com/w2xg2022/rocknix/next/docs/md1000-dualboot/switch-to-rocknix.sh -o /tmp/switch-to-rocknix.sh && sh /tmp/switch-to-rocknix.sh
```

> 没 `curl` 就用 `wget`：`wget -O /tmp/switch-to-rocknix.sh <同一网址> && sh /tmp/switch-to-rocknix.sh`
>
> ★先下载再执行, 别用 `curl | sh`★：管线执行看不到脚本的错误输出、失败了也不能原地重跑，
> 而且脚本内部呼叫的 helper 会继承那条管线当 stdin —— 一旦它读走 stdin，剩下的脚本内容就没了，
> 表现是「跑到一半安静结束、什么都没发生」。

**首次运行会自动完成一次性安装** —— 见[首次运行装了什么](#首次运行装了什么)。之后每次跑就只是「同步 payload、放 TRIGGER、重开」。

### ◀ U 盘 ROCKNIX → eMMC Armbian

在 **ROCKNIX**（`root` / `rocknix`，需联网）里跑。**⚠️ 路径关键**：ROCKNIX 的 `/usr` 是只读 squashfs，脚本要存到**可写且持久的 `/storage`** 再执行：

```bash
curl -L https://raw.githubusercontent.com/w2xg2022/rocknix/next/docs/md1000-dualboot/switch-to-armbian.sh -o /storage/switch-to-armbian.sh && sh /storage/switch-to-armbian.sh
```

脚本会挂载 eMMC boot 分区（`/dev/mmcblk0p1`）、`rm rocknix/TRIGGER`、然后 `reboot`。
（ROCKNIX 是 Linux、有完整 eMMC 存取，所以能删掉 eMMC 上的 TRIGGER；u-boot 才受 USB / ext4write 限制。存 `/storage` 后下次不用再下载，直接 `sh /storage/switch-to-armbian.sh`。）

## TRIGGER 是常驻的，不是一次性的

u-boot 只【读】TRIGGER、不删它。所以放下去之后**每次开机都进 ROCKNIX**，
直到你在 ROCKNIX 里跑 `switch-to-armbian.sh` 把它删掉为止。

这是刻意的：万一 ROCKNIX 那边出问题，机器不会「重开一次就莫名其妙回到 Armbian」，
你能靠开机结果本身判断是哪个系统在跑 —— MD1000 的 u-boot 不往 HDMI 输出，
看不到任何开机讯息，这一点尤其重要。

## 装成常驻命令（可选）

嫌每次 curl 麻烦，可把脚本装到固定位置，之后一句话切换：

| 脚本 | 在哪跑 | 装到（可写路径） | 之后切换命令 |
|------|--------|------------------|--------------|
| [`switch-to-rocknix.sh`](md1000-dualboot/switch-to-rocknix.sh) | **Armbian** | `/usr/local/sbin/`（Armbian rootfs 可写） | `switch-to-rocknix.sh` |
| [`switch-to-armbian.sh`](md1000-dualboot/switch-to-armbian.sh) | **ROCKNIX** | `/storage/`（`/usr` 只读，必须放这） | `sh /storage/switch-to-armbian.sh` |

## 链载需要的配套档就只有两个

u-boot 从 eMMC 只读这两个：

```
/boot/rocknix/Image               内核映像 —— initramfs 就包在里面
/boot/rocknix/rk3566-md1000.dtb   设备树，档名要跟链载块里写的一致
```

其余一概不需要：`SYSTEM`、`oemsplash-*.png`、`*.md5` 全都是 initramfs 起来之后从
`/flash`（也就是 U 盘本身）读的，那时内核早就跑起来了。

> U 盘上的 dtb 在 boot 分区的 **`device_trees/` 子目录**底下。
> ★EmuELEC 是放在根目录，别把那边的假设搬过来★。

## ★刷了新映像却还在跑旧内核★

这是整套设计必须防的坑。链载读的是 **eMMC** 上那份，而刷新映像只换掉 **U 盘** 上那份，
两者没有任何东西会自动配对。结果是 `/etc/os-release` 显示新版本、实际跑的却是旧内核 ——
而且因为 **initramfs 包在 Image 里面**，内核层与 initramfs 层的修改会全部静默失效，
看起来就像「你的修正没生效」。

2026-07-23 实机就是这样被坑：AV 的 dts 明明是对的、新固件里的 dtb 也确实含修正，
但 `/proc/device-tree` 是旧的（12 组 pinctrl、无 `rk809-sound`），白白怀疑了好几轮。

三道防线，按触发顺序：

1. **Armbian 上的 [`rocknix-chainload-sync.service`](md1000-dualboot/rocknix-chainload-sync.service)**
   （由 `switch-to-rocknix.sh` 装）。**开机与关机各跑一次**。★关机那次才是关键★：
   惯用流程是「开 Armbian → 写新映像到 U 盘 → 重开进 ROCKNIX」，只在开机同步的话，
   那次同步发生在写映像**之前**，必然漏掉。
2. **`switch-to-rocknix.sh` 每次运行都同步**，不是只在 eMMC 上还没副本时才做。
3. **ROCKNIX 里的 `rocknix-kernel-sync.service`**
   （`projects/ROCKNIX/devices/RK3566/packages/rocknix-chainload-sync/`）从另一边做同样的事，
   所以只要进过一次 ROCKNIX，之后刷映像就会自愈。日志在
   `/storage/.config/logs/kernel-sync.log`。
   （同 DEVICE 底下那些掌机没有 eMMC payload，脚本执行期判断得出来，是纯 no-op。）

> 判定一律用 **md5，绝不用时间戳** —— 时间戳会被 FAT 分区、时区处理、以及映像的写入
> 方式弄失真。手工核对：`md5sum /flash/KERNEL` 与 eMMC 上那份比一比。

> **同步完要下次开机才生效** —— u-boot 早在任何同步发生之前就已经载入旧内核了。
> 所以刷完新映像要**重开两次**。★验证内核层的修改时，第一件事永远是先确认自己跑的是
> 哪一颗★：`uname -a`（看建置时间戳，不是只看版本号）。

## 首次运行装了什么

`switch-to-rocknix.sh` 首次执行时自动做以下几步，一般无需手动：

1. 把 [`rocknix-chainload-sync.sh`](md1000-dualboot/rocknix-chainload-sync.sh) 装到
   `/usr/local/sbin/`，并启用
   [`rocknix-chainload-sync.service`](md1000-dualboot/rocknix-chainload-sync.service)。
2. 备份 `boot.cmd` / `boot.scr` 为 `*.armbian-orig`，把 [`boot-rocknix-block.txt`](md1000-dualboot/boot-rocknix-block.txt)
   插到 `/boot/boot.cmd` 第一处 `setenv load_addr` **之前**，用
   `mkimage -C none -A arm -T script -n 'flatmax load script' -d /boot/boot.cmd /boot/boot.scr` 重编。
   （需要 `mkimage`；Armbian 上 `apt-get install -y u-boot-tools`）
3. 从 U 盘 ROCKNIX 分区把 `KERNEL` + `device_trees/rk3566-md1000.dtb` 复制到 eMMC 的
   `/boot/rocknix/Image` 与 `/boot/rocknix/rk3566-md1000.dtb`。
   （u-boot 读不到 USB，内核/dtb 必须放 eMMC；U 盘只当 rootfs，ROCKNIX 内核起来后用 Linux 完整 USB3 驱动挂 SYSTEM）

## 保底 / 救援

- 没插 U 盘 → ROCKNIX booti 失败 → **自动落回 Armbian**，绝不变砖。
- 彻底救援：MASKROM 重刷 Armbian（bootloader / 分区表 / 保留区全程没动，一律可救）。
- 想彻底告别 U 盘：用 `installtoemmc` 把 ROCKNIX 装进 eMMC 变**单系统**（会抹掉 Armbian rootfs，保留 u-boot + BOOT 作 chainload 宿主与 MASKROM 救援）。
