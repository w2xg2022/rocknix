<img src="https://github.com/ROCKNIX/distribution/blob/next/distributions/ROCKNIX/logos/rocknix-logo.png?raw=yes" width=160>

# ROCKNIX · w2xg2022 定制版

基于上游 [ROCKNIX](https://github.com/ROCKNIX/distribution)（JELOS 血统）二次开发，为 **Rockchip 电视盒/开发板**提供**云编译**的复古游戏固件，前端换成自研的 **ES4All**（EmulationStation 统一分支）。

主力机型：**MD1000（RK3566）**。选择 ROCKNIX 的核心理由是它走 **Mesa Panfrost + Vulkan（PanVK）** —— 同一颗 Mali-G52，换上 Vulkan 就能把 PSP 4X 1080p 跑顺，突破 GLES 天花板。

> ⚠️ 本仓库是 fork，`next` 分支上叠了 MD1000 适配、通用 kernel（RK3566+RK3528）、maxio 千兆网卡修复、ES4All 接线、以及一套**云编译加速 + Release 发布**改造。commit 一律英文（跟随国际上游），README/文档用中文。

---

## 🎯 选型策略：四志愿框架

复古固件好不好用，**GPU 驱动栈 × 图形 API** 决定天花板（尤其 PSP/DC/N64 这类吃 GPU 的模拟器）。按优先级排：

<table width="100%">
<tr><th>志愿</th><th>驱动栈 × API</th><th>代表</th><th>PSP</th></tr>
<tr><td align="center" nowrap>🥇 一</td><td>Mesa Panfrost + <b>Vulkan（PanVK）</b></td><td>RK3566/68、RK3576、RK3588</td><td nowrap>4X 1080p 顺</td></tr>
<tr><td align="center" nowrap>🥈 二</td><td>Mesa Panfrost + <b>GLES</b></td><td>无 Vulkan 时的退路</td><td nowrap>中低倍数</td></tr>
<tr><td align="center" nowrap>🥉 三</td><td><b>闭源厂商 BSP + GLES</b></td><td>Amlogic S905 系列</td><td nowrap>受限</td></tr>
<tr><td align="center" nowrap>🏅 四</td><td>软件渲染 / 无加速</td><td>老旧 SoC</td><td nowrap>仅轻量</td></tr>
</table>

> **为什么押 Vulkan**：PSP/DC 的性能瓶颈往往是 **GLES 路径**而非 Mali 硬件本身。ROCKNIX 用 PanVK（`panfrost_icd`）走 Vulkan，同硬件直接上一个档位。

**本仓库定位**：聚焦 **Rockchip + Panfrost/PanVK 生态（第一志愿）**。Amlogic 闭源 BSP（第三志愿）那条线在 [w2xg2022/EmuELEC](https://github.com/w2xg2022/EmuELEC)。

---

## 📦 支持机型

<table width="100%">
<tr><th>机型</th><th>芯片</th><th>GPU</th><th>图形栈</th><th>状态</th></tr>
<tr><td nowrap><b>MD1000</b></td><td nowrap>RK3566</td><td nowrap>Mali-G52</td><td nowrap>Panfrost + PanVK</td><td>✅ 实机验证（ES4All / 蓝牙 / 千兆网卡）· <a href="https://github.com/w2xg2022/rocknix/releases">固件</a></td></tr>
</table>

> **缝合方案（三层拼接）**：① Armbian eMMC vendor U-Boot 用 `booti` 链载 ROCKNIX kernel（DRAM 已校准保开机）→ ② ROCKNIX mainline kernel + dtb → ③ ROCKNIX 用户空间（RetroArch + Vulkan + **ES4All**）。
>
> 🔄 **双系统一键互切**（eMMC Armbian ⇄ U 盘 ROCKNIX，靠 TRIGGER 档 + `booti`，支持 curl 一键）：见 **[MD1000 双系统切换说明](docs/md1000-dual-boot.md)**。彻底告别 U 盘可用 `installtoemmc` 装进 eMMC。

---

## ☁️ 云编译（GitHub Actions）

三条流水线，按「改了哪一层」选最快的那条：

<table width="100%">
<tr><th>工作流</th><th>用途</th><th>耗时</th></tr>
<tr><td nowrap><b>完整</b>（<code>build-nightly.yml</code>）</td><td>完整固件（kernel + 用户空间 + 模拟器 + ES4All）</td><td nowrap>小时级</td></tr>
<tr><td nowrap><b>Kernel</b>（<code>build-kernel-image.yml</code>）</td><td>只编 kernel/模块 → 注入现成 image</td><td nowrap>~22 分</td></tr>
<tr><td nowrap><b>ES</b>（<code>build-es-image.yml</code>）</td><td>只编 ES4All → 注入现成 image</td><td nowrap>~15 分</td></tr>
</table>

**加速要点**：

- **cache 仓必须 public**：ccache / toolchain 树 / sysroot 存 [`distribution-cache`](https://github.com/w2xg2022/distribution-cache)，ROCKNIX 用**无认证 curl** 还原，private 会静默失败 → 全冷编。
- **toolchain 树复用**：`toolchain-tree` release（>2GB 分片），kernel 快车道跳过 ~30 分重编。
- **es-sysroot 复用**：`es-sysroot` release（完整 build 的 sysroot 快照），ES 快车道只重编 emulationstation、依赖全 stamp 命中。

**编译单个机型（自助餐）**：

```
Actions → Build → Run workflow
  RK3566 = true
  BOARD  = rk3566-md1000        # 只编该型号，extlinux 自动指好其 dtb
```

**固件命名**：`ROCKNIX-<DEVICE>.<arch>-<日期>-<后缀>.img.gz`

- 单一 BOARD → 后缀换成型号：`ROCKNIX-RK3566.aarch64-20260707-MD1000.img.gz`（extlinux 已绑 `rk3566-md1000.dtb`）。
- 多个 BOARD → 保留 `-Specific`（一颗共享镜像，靠 `fdtdir` 自动侦测那批 dtb）。
- `-Generic` → 含全 dtb、u-boot 自动侦测，当备援。

**自动发布 Release**：上游 release 任务锁 `owner == 'ROCKNIX'`，fork 上永远 skip。本仓库加了 `release-fork` 任务：手动触发的完整 build 成功后，用默认 token 在本仓库自动建 `fw-<日期>` release（>2GB 自动分片）。

---

## ➕ 添加新机型

1. `projects/ROCKNIX/config.xml` 对应芯片的 `<Specific>` 组加 `<file>rk35xx-你的板</file>`。
2. 放该板 dtb（源码/patch 进 `projects/ROCKNIX/devices/<DEVICE>/patches/linux/`，并加进 dtb Makefile）。
3. 触发 Build 时用 `BOARD=你的板` 单编；`get_fdt` 会让 Specific 镜像 extlinux 直指该板 dtb。

---

## 🎮 自研前端 ES4All

前端换成 [w2xg2022/es4all](https://github.com/w2xg2022/es4all)（`-DES4ALL_TARGET=rocknix`），仅覆盖 `emulationstation` 包的 `package.mk`（胶水档字节相同）。ROCKNIX 面向掌机，电视盒适配额外补了运行时胶水（见 es4all `dist/rocknix/deploy/`）：

- **常驻虚拟键盘（uinput）**：ROCKNIX 假设板载输入常在，电视盒无内建输入时 ES 不激活手柄导航 → 补一个「永远在场的键盘」，外接手柄无需插实体键盘即可单独可用。
- **Dreamcast/PSP 独立模拟器**（flycast-sa / PPSSPP-sa，性能）。
- **手柄键位标准对齐** + SELECT+START 两键退出。
- **隐藏 pico-8**（需付费本体、主题无图）。

---

## 🔗 相关仓库

<table width="100%">
<tr><th>仓库</th><th>说明</th></tr>
<tr><td nowrap><a href="https://github.com/w2xg2022/rocknix">w2xg2022/rocknix</a></td><td>本仓库：发行版构建系统（fork，分支 <code>next</code>）</td></tr>
<tr><td nowrap><a href="https://github.com/w2xg2022/rocknix-kernel">w2xg2022/rocknix-kernel</a></td><td>独立内核源码仓（mainline + patch 转真 git commit，仿 ophub armbian-kernel）</td></tr>
<tr><td nowrap><a href="https://github.com/w2xg2022/es4all">w2xg2022/es4all</a></td><td>自研 EmulationStation 统一分支（ROCKNIX/EmuELEC/Armbian 共用）</td></tr>
<tr><td nowrap><a href="https://github.com/w2xg2022/distribution-cache">w2xg2022/distribution-cache</a></td><td>ccache / toolchain 树 / es-sysroot / 用户空间 base（<b>public</b>）</td></tr>
<tr><td nowrap><a href="https://github.com/w2xg2022/EmuELEC">w2xg2022/EmuELEC</a></td><td>第三志愿线：Amlogic 闭源 BSP + GLES 机型</td></tr>
</table>

---

## 📜 授权

**ROCKNIX** 是 [JELOS](https://github.com/JustEnoughLinuxOS/distribution/) 的 fork，沿用其全部授权并致谢 JELOS / ROCKNIX 团队。本仓库为个人二次开发，仅供学习研究。

上游 README：见 [ROCKNIX/distribution](https://github.com/ROCKNIX/distribution)。
