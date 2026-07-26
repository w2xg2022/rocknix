<img src="https://github.com/ROCKNIX/distribution/blob/next/distributions/ROCKNIX/logos/rocknix-logo.png?raw=yes" width=160>

# ROCKNIX · w2xg2022 定制版

基于上游 [ROCKNIX](https://github.com/ROCKNIX/distribution)（JELOS 血统）二次开发，为 **Rockchip 电视盒/开发板**提供**云编译**的复古游戏固件，前端换成自研的 **ES4All**（EmulationStation 统一分支）。

主力机型：**MD1000（RK3566）**。选择 ROCKNIX 的核心理由是它走 **闭源 libmali + Vulkan** —— 同一颗 Mali-G52，换上 Vulkan 就能把 PSP 跑顺，突破 GLES 天花板。

> ⚠️ 本仓库是 fork，`next` 分支上叠了 MD1000 适配、通用 kernel（RK3566+RK3528）、maxio 千兆网卡修复、ES4All 接线、以及一套**云编译加速 + Release 发布**改造。commit 讯息与 README/文档**一律简体中文**（2026-07-21 起；此前跟随国际上游用英文，已改）。
> 格式惯例：**英文的组件前缀 + 简体正文**，例如 `emulationstation: pin 锚到 tag v1.1`、`CI: 关掉 DEBUG_PACKAGES`、`RK3566: MD1000 启用 AV(3.5mm) 模拟音频`。

---

## 🎯 选型策略：四志愿框架

复古固件好不好用，**GPU 驱动栈 × 图形 API** 决定天花板（尤其 PSP/DC/N64 这类吃 GPU 的模拟器）。按优先级排：

<table width="100%">
<tr><th>志愿</th><th>驱动栈 × API</th><th>代表</th><th>PSP</th></tr>
<tr><td align="center" nowrap>🥇 一</td><td><b>原厂闭源 BSP（libmali）+ Vulkan</b></td><td>RK3566（本仓库主线）</td><td nowrap>高倍数可玩</td></tr>
<tr><td align="center" nowrap>🥈 二</td><td>社区开源（Mesa/Panfrost）+ <b>Vulkan（PanVK）</b></td><td>RK3588（G610/Valhall）</td><td nowrap>同级，且更干净</td></tr>
<tr><td align="center" nowrap>🥉 三</td><td>原厂闭源 BSP + <b>OpenGL ES</b></td><td>Amlogic S905 系列（G31）</td><td nowrap>轻~中量</td></tr>
<tr><td align="center" nowrap>🏅 四</td><td>社区开源（Mesa/Panfrost/Lima）+ <b>OpenGL ES</b></td><td>Mali-450 老 SoC</td><td nowrap>基本无缘</td></tr>
</table>

> **为什么押 Vulkan**：PSP/DC 的性能瓶颈往往是 **GLES 路径的 CPU 驱动开销**而非 Mali 硬件本身。
> Vulkan 砍掉这层开销（弱 A55 受益最大）、显式 render pass 契合 Mali 的 tile 架构，同硬件直接上一个档位。
> 所以这张表的**主要排序键是 API（Vulkan > GLES）**，驱动来源只是次要键。

**三个边界条件**（照搬这张表前先看）：

1. **一、二志愿的顺序会随 GPU 世代翻转**。Bifrost（G31/G52）上 PanVK 仍 non-conformant，闭源稳赢；
   到 Valhall/G610（RK3588）PanVK 已过 Vulkan 1.2 认证，开源那条反而更干净（不必 out-of-tree 的
   `mali_kbase`、Wayland/DRM 整合更好）。**「一 > 二」是当代硬件的结论，不是恒真。**
2. **「有 Vulkan」不等于「Vulkan 能用」**。不成熟的实作可能还不如成熟的 GLES ——
   第二志愿在 Bifrost 上实务常常掉到第三之后。**本表描述的是上限潜力，不是保证值。**
3. **「闭源 > 开源」是 Mali 专属结论，别外推**。Adreno（SM8xxx 机型）的开源 Turnip 是 conformant
   且品质很好，经常胜过 blob；这张表用在 Adreno 上会排错。

> ⚠️ **第一志愿不是白拿的**：走闭源 libmali 要为它打一串补丁 ——
> `ppsspp-lr/007-fix-vulkan-on-libmali.patch`、`wlroots/libmali/001-...allow-zero-stride`、
> `SDL2`/`SDL3` 的 `Support-building-without-hacky-libmali-headers`。

**本仓库定位**：聚焦 **Rockchip + 闭源 libmali/Vulkan（第一志愿）**。Amlogic 闭源 BSP + GLES（第三志愿）那条线在 [w2xg2022/EmuELEC](https://github.com/w2xg2022/EmuELEC)。

---

## 📦 支持机型

<table width="100%">
<tr><th>机型</th><th>芯片</th><th>GPU</th><th>图形栈</th><th>状态</th></tr>
<tr><td nowrap><b>MD1000</b></td><td nowrap>RK3566</td><td nowrap>Mali-G52</td><td nowrap>libmali + Vulkan</td><td>✅ 实机验证（ES4All / 蓝牙 / 千兆网卡）· <a href="https://github.com/w2xg2022/rocknix/releases">固件</a></td></tr>
</table>

> **缝合方案（三层拼接）**：① Armbian eMMC vendor U-Boot 用 `booti` 链载 ROCKNIX kernel（DRAM 已校准保开机）→ ② ROCKNIX mainline kernel + dtb → ③ ROCKNIX 用户空间（RetroArch + Vulkan + **ES4All**）。
>
> 🔄 **双系统一键互切**（eMMC Armbian ⇄ U 盘 ROCKNIX，靠 TRIGGER 档 + `booti`，支持 curl 一键）：见 **[MD1000 双系统切换说明](docs/md1000-dual-boot.md)**。彻底告别 U 盘可用 `installtoemmc` 装进 eMMC。

---

## ☁️ 云编译（GitHub Actions）

四条流水线，按「改了哪一层」选最快的那条。**完整 build 负责产出/刷新基底，其余三条都是叠在基底上的快车道**：

<table width="100%">
<tr><th>工作流</th><th>用途</th><th>耗时</th></tr>
<tr><td nowrap><b>完整</b>（<code>build-nightly.yml</code>）</td><td>完整固件（kernel + 用户空间 + 模拟器 + ES4All），并刷新全部基底</td><td nowrap>~75~85 分</td></tr>
<tr><td nowrap><b>Kernel</b>（<code>build-kernel-image.yml</code>）</td><td>只编 kernel/模块 → 注入现成 image</td><td nowrap>~22 分</td></tr>
<tr><td nowrap><b>ES</b>（<code>build-es-image.yml</code>）</td><td>只编 ES4All → 注入现成 image</td><td nowrap>~15 分</td></tr>
<tr><td nowrap><b>注入</b>（<code>build-inject-image.yml</code>）</td><td>只改 config/散档，<b>零编译</b>（跑 <code>.github/inject/patch.sh</code>）</td><td nowrap>~5 分</td></tr>
</table>

> ES 那条涵盖范围比想像的广：它跑的是**整个 emulationstation 套件的 makeinstall**，
> 所以住在该套件里的东西（ES 界面、胶水脚本、installtoemmc、主题、locale）全部走这条、不必完整 build。
> 住在套件**外面**的纯档案（`system.cfg` 出厂预设、要删掉的模拟器）走注入那条。

**加速要点**：

- **cache 仓必须 public**：ccache / toolchain 树 / userland 树存 [`distribution-cache`](https://github.com/w2xg2022/distribution-cache)，ROCKNIX 用**无认证 curl** 还原，private 会静默失败 → 全冷编。
- **toolchain 树复用**：`toolchain-tree` release（>2GB 分片），kernel 快车道跳过 ~30 分重编。
- **userland 树复用**：`userland-tree` release（完整 build 的 sysroot 快照），ES 快车道只重编 emulationstation、依赖全 stamp 命中。
- **指纹别过度作废**：完整 build 从 177 分降到 ~70 分的关键，是让 userland 指纹只杂凑 sysroot 内核头、
  **不算 linux stamp** —— 否则改一个 dts 就会连锁作废 455 个包、白编 50 分钟。
  **规则**：改 dts / 换 ES pin → 指纹命中；改 options / virtual meta / 换内核版本 → 落空，退回 ~120 分。
- ⚠️ **命名**：`userland-tree`（原 `es-sysroot`）、`fastlane-base`（原 `userspace-base`）2026-07-17 已改名 ——
  旧名按「用途」命名会让人误会内容。规则：`<内容>-tree` 给树、`<用途>-base` 给镜像。

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

**自动发布 Release**：上游 release 任务锁 `owner == 'ROCKNIX'`，fork 上永远 skip。本仓库加了 `release-fork` 任务：手动触发的完整 build 成功后，用默认 token 在本仓库自动建 `fw-<日期>` release（>2GB 自动分片），并标成 **`--latest`** —— 让新固件稳拿 GitHub 的 Latest 徽章、上一版自动降级（以前用 `--prerelease`，结果一个中间产出反而霸占了 Latest）。

> ⚠️ **同一天重复出固件会覆盖资产、不会新建 release**（tag 是 `fw-<日期>`）。判断「装的是哪一颗」要看
> **资产的 `updated_at`**，release 的 `published_at` 停在第一次发布不会动。

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
<tr><td nowrap><a href="https://github.com/w2xg2022/distribution-cache">w2xg2022/distribution-cache</a></td><td>ccache / <code>toolchain-tree</code> / <code>userland-tree</code> / <code>fastlane-base</code>（<b>public</b>）</td></tr>
<tr><td nowrap><a href="https://github.com/w2xg2022/EmuELEC">w2xg2022/EmuELEC</a></td><td>第三志愿线：Amlogic 闭源 BSP + GLES 机型</td></tr>
</table>

---

## 📜 授权

**ROCKNIX** 是 [JELOS](https://github.com/JustEnoughLinuxOS/distribution/) 的 fork，沿用其全部授权并致谢 JELOS / ROCKNIX 团队。本仓库为个人二次开发，仅供学习研究。

上游 README：见 [ROCKNIX/distribution](https://github.com/ROCKNIX/distribution)。
