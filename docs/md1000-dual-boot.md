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
curl -L https://raw.githubusercontent.com/w2xg2022/rocknix/next/docs/md1000-dualboot/switch-to-rocknix.sh | bash
```

> 没 `curl` 就用 `wget`：`wget -qO- <同一网址> | bash`

**首次运行会自动完成一次性安装**——检测到 `/boot/rocknix/` 缺内核或 `boot.cmd` 没链载块时，脚本会：① 从 U 盘把 `KERNEL` + `rk3566-md1000.dtb` 铺到 eMMC `/boot/rocknix/`；② 往 `/boot/boot.cmd` 插链载块、重编 `boot.scr`（自动备份 `*.armbian-orig`）。装好后再 `touch TRIGGER` + `reboot`。之后每次跑就是纯切换。

### ◀ U 盘 ROCKNIX → eMMC Armbian

在 **ROCKNIX**（`root` / `rocknix`，需联网）里跑。**⚠️ 路径关键**：ROCKNIX 的 `/usr` 是只读 squashfs，脚本要存到**可写且持久的 `/storage`** 再执行：

```bash
curl -L https://raw.githubusercontent.com/w2xg2022/rocknix/next/docs/md1000-dualboot/switch-to-armbian.sh -o /storage/switch-to-armbian.sh && sh /storage/switch-to-armbian.sh
```

脚本会挂载 eMMC boot 分区（`/dev/mmcblk0p1`）、`rm rocknix/TRIGGER`、然后 `reboot`。
（ROCKNIX 是 Linux、有完整 eMMC 存取，所以能删掉 eMMC 上的 TRIGGER；u-boot 才受 USB / ext4write 限制。存 `/storage` 后下次不用再下载，直接 `sh /storage/switch-to-armbian.sh`。）

## 装成常驻命令（可选）

嫌每次 curl 麻烦，可把脚本装到固定位置，之后一句话切换：

| 脚本 | 在哪跑 | 装到（可写路径） | 之后切换命令 |
|------|--------|------------------|--------------|
| [`switch-to-rocknix.sh`](md1000-dualboot/switch-to-rocknix.sh) | **Armbian** | `/usr/local/sbin/`（Armbian rootfs 可写） | `switch-to-rocknix.sh` |
| [`switch-to-armbian.sh`](md1000-dualboot/switch-to-armbian.sh) | **ROCKNIX** | `/storage/`（`/usr` 只读，必须放这） | `sh /storage/switch-to-armbian.sh` |

## 首次安装做了什么（原理，脚本已自动完成）

`switch-to-rocknix.sh` 首次运行时自动做以下几步，一般无需手动：

1. 从 U 盘 ROCKNIX 分区把 `KERNEL` + `device_trees/rk3566-md1000.dtb` 复制到 eMMC 的
   `/boot/rocknix/Image` 与 `/boot/rocknix/rk3566-md1000.dtb`。
   （u-boot 读不到 USB，内核/dtb 必须放 eMMC；U 盘只当 rootfs，ROCKNIX 内核起来后用 Linux 完整 USB3 驱动挂 SYSTEM）
2. 备份 `boot.cmd` / `boot.scr` 为 `*.armbian-orig`，把 [`boot-rocknix-block.txt`](md1000-dualboot/boot-rocknix-block.txt)
   插到 `/boot/boot.cmd` 的 `setenv load_addr` 那行**之前**，用
   `mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr` 重编。
   （需要 `mkimage`；Armbian 上 `apt-get install -y u-boot-tools`）

> **每换新 ROCKNIX 映像**后，把 U 盘的 `KERNEL` 重新铺到 eMMC `/boot/rocknix/Image`（保持 kernel 与 U 盘 SYSTEM 配对）。再跑一次 `switch-to-rocknix.sh` 即可（它会覆盖旧的）。

## 保底 / 救援

- 没插 U 盘 → ROCKNIX booti 失败 → **自动落回 Armbian**，绝不变砖。
- 彻底救援：MASKROM 重刷 Armbian（bootloader / 分区表 / 保留区全程没动，一律可救）。
- 想彻底告别 U 盘：用 `installtoemmc` 把 ROCKNIX 装进 eMMC 变**单系统**（会抹掉 Armbian rootfs，保留 u-boot + BOOT 作 chainload 宿主与 MASKROM 救援）。
