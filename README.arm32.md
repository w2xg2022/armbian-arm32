# armbian-arm32

面向 **32 位 ARM（armhf）** 板卡的 Armbian 构建仓库，从 [armbian/build](https://github.com/armbian/build) fork 而来。

本仓库只维护 armhf 板卡的板级配置与内核补丁；arm64 板卡请直接使用上游。
仓库文档默认使用简体中文。

## 板卡一览

| 板卡 ID | 名称 | SoC | 内核分支 | 状态 |
| --- | --- | --- | --- | --- |
| `rk3288-digital-reflection` | Digital Reflection RK3288（DR-RK3288） | RK3288（4×Cortex-A17，2GB） | `current`（6.18.y） | 可用，需自行验证 |

## 本仓库新增的内容

1. `config/boards/rk3288-digital-reflection.tvb`
   —— 板级配置，`BOOT_FDT_FILE="rk3288-digital-reflection.dtb"`
2. `patch/kernel/archive/rockchip-6.18/dt/rk3288-digital-reflection.dts`
   —— 板卡 dts。这个目录受 `0000.patching_config.yaml` 里的 `dts-directories` 机制管理：
   构建时框架会把 `dt/` 下的 dts 原样拷进 `arch/arm/boot/dts/rockchip/`，并自动改 Makefile，
   所以**不需要**自己写 Makefile 补丁。

## 构建

在本机（host）模式构建，不拉 `ghcr.io/armbian/docker-armbian-build` 镜像：实测这条链路只有
~170 KB/s，镜像 3 GB 起步，不划算。host 侧需要 `arm-linux-gnueabihf-` 交叉工具链、`qemu-arm-static`
与 `binfmt`，以及一堆打包工具，一台机器装一次即可：

```bash
sudo env ALLOW_ROOT=yes ./compile.sh requirements
```

`compile.sh` 自己会要 root（Docker 不可用时回落到 sudo），非交互 ssh 下先喂一次 sudo 密码缓存：

```bash
echo "sudo密码" | sudo -S -p "" -v      # 15 分钟内有效
./compile.sh build BOARD=rk3288-digital-reflection BRANCH=current RELEASE=trixie \
  BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no KERNEL_BTF=no \
  NETWORKING_STACK=network-manager PREFER_DOCKER=no
```

- 目标组合是 **Debian 13（trixie）+ 6.18.y（`current`）+ minimal**，产物名形如
  `Armbian-unofficial_26.x_Rk3288-digital-reflection_trixie_current_6.18.y_minimal.img`。
- `KERNEL_CONFIGURE=no` 必给：非 tty（ssh 远程）下框架要弹内核配置菜单，没有它就报
  `stdin is not a terminal. can't use dialog`。
- `NETWORKING_STACK=network-manager` 是刻意覆盖：`BUILD_MINIMAL=yes` 默认会切到
  `systemd-networkd`，那样 `nmtui` 就没了。带上这个参数才有 `NetworkManager` + `nmtui`/`nmcli`，
  代价是常驻内存多 15~20MB；纯有线、不想要 TUI 的话去掉它最瘦。
- `KERNEL_BTF=no` 是给 8GB 以下内存的机器用的：框架会检查 RAM 是否够跑 BTF，不够就直接报
  `Not enough RAM available ... for BTF build` 退出。复古游戏机不需要 BTF，关掉最省事。
- `RELEASE=` 也可用 `bookworm`（Debian 12）、`noble`（Ubuntu 24.04，走 ports.ubuntu.com）。
- 首次构建要拉内核源码（`git.kernel.org` 的 `linux-6.18.y`）、u-boot（`v2026.04`）和 rootfs 包，
  网速慢时常常几十分钟到一两小时；之后增量构建会复用 `cache/` 与 `output/`，中断后重跑同一条命令即可续上。
- 想只看解析出来的配置（不编译）：

```bash
./compile.sh configdump BOARD=rk3288-digital-reflection BRANCH=current RELEASE=trixie \
  BUILD_MINIMAL=yes NETWORKING_STACK=network-manager
```

产物在 `output/images/`。板级配置已经写好 `BOOT_FDT_FILE`，生成的 `armbianEnv.txt` 里
`fdtfile=rk3288-digital-reflection.dtb`，不需要再手工替换 dtb。

## 精简用户空间

`userpatches/customize-image.sh` 会在 rootfs 阶段自动执行，对应《ARM32 盒子-模拟器适配笔记》§6.4
的瘦身清单，目标是把常驻内存从 ~180MB 压到 100MB 以下：

- 删掉：`avahi-daemon`/`avahi-autoipd`/`libnss-mdns`、`modemmanager`、`bluez*`、
  `man-db`/`manpages`/`info`/`groff-base`/`doc-base`、`bash-completion`/`command-not-found`、
  `systemd-coredump`、`cron`、`vim-tiny`、`git`。
- 保留：`openssh-server`（`config/cli/common/main/packages` 本来就有，瘦身清单没碰）、
  `NetworkManager` + `nmtui`/`nmcli`、无线栈（`wpasupplicant`/`iw`/`rfkill`/`wireless-regdb`，
  方便以后插 USB 无线网卡）、`nano`、`alsa-utils`、`u-boot-tools`、`cpufrequtils`。
- 关掉：`getty@tty2..6`、`apt-daily.timer`、`apt-daily-upgrade.timer`、`man-db.timer`。
- `journald` 改 `Storage=volatile` + `SystemMaxUse=16M`，日志写 RAM，保护 eMMC。
- 红线不动：`armbian-zram-config`、`armbian-ramlog`、`alsa-utils`、`u-boot-tools`、`cpufrequtils`、
  `armbian-bsp-cli-*`、`sudo`、`systemd`。

开机后在机上复核：

```bash
free -m                                  # used 目标 < 100MB（不含 cache/buffer）
systemctl --failed                       # 应该没有 failed
ps_mem -S | head -15                     # 谁还在吃内存
```

> 注意：瘦身只在**镜像构建时**生效，已经刷好的卡不会自动变瘦，得重刷或手动照清单处理。

### 体积：从 1348MiB 压到 580MiB

第一版镜像 1348MiB，其中大头根本不是包，是数据文件。三刀下去变成 580MiB（rootfs 实占 397MiB，
镜像内还留 63MB 余量，首次开机 `armbian-resize-filesystem` 会把分区扩到卡的实际容量）：

| 砍的东西 | 省下 | 说明 |
| --- | --- | --- |
| `armbian-firmware` 里的无关固件 | ~488MB | 装完 523MB，其中 `qcom` 一家 323MB（骁龙手机/笔记本的 adsp/modem），还有 ath10k/ath11k/ath12k/mediatek/intel 等。只留 `rockchip`、`rkwifi`、`brcm`、`rtlwifi`、`rtl_nic`，共 33MB |
| `/var/lib/apt/lists` | 57MB | apt 索引，开机 `apt update` 就回来；必须放在收尾阶段删，见下条 |
| `/usr/share/locale` | ~55MB | 110 个语系只留 `en`/`en_GB`/`zh`/`zh_TW`/`zh_CN` |
| `consolefonts`、`hwdb`、`perl` 的 pod、python 的 test/pycache、`X11/xkb`、man/doc | ~35MB | 纯文档/缓存，不影响运行 |

两个坑值得记：

1. 在 `customize-image.sh` 里删 `apt/lists` **没用**——框架随后会 `apt-get update` 又把索引生成回来
   （日志里 `apt_lists_copy_from_host_to_image_and_update` 那一段）。所以另外做了一个收尾 extension
   `userpatches/extensions/rk3288-slim-late.sh`，挂在 `post_post_debootstrap_tweaks` 上，在 `du` 量体积之前删掉。
   板级配置里用 `enable_extension "rk3288-slim-late"` 启用（必须在 extension manager 初始化前调用）。
2. 想固定镜像体积就用 `FIXED_IMAGE_SIZE=<MiB>`。但别贴着 rootfs 实占给：第一次试 `580` 时 rootfs 还有
   455MiB，剩 4.3MB 空间，`mkimage` 写 `uInitrd` 直接 `No space left on device` 挂掉。留 15% 以上比较稳。


## 硬件与 Firefly-RK3288 的差异

本板硬件布局接近 Firefly-RK3288，因此 dts 以 `rk3288-firefly.dtsi` 为底，只叠加差异：

| 项目 | 改动 | 原因 |
| --- | --- | --- |
| 千兆网口（RTL8211E，RGMII） | `rx_delay` 由 `0x10` 改为 `0x18` | 原值在 1000M 下出现 `mmc_rx_crc_error`、1400B 包丢 60%；`0x18` 实测 CRC 0、丢包 0 |
| USB A 口（板载 hub，`usb_host1` / ff540000） | 打开 `snps,usb2-enable-hub-mode`，设定 FIFO，`vbus-supply = vcc_host_5v` | 单 A 口经板载 USB 2.0 hub 转出 |
| USB OTG 口（`usb_otg` / ff580000） | `dr_mode = "host"`，PHY 复位走 GPIO7_B0，`vbus-supply = vcc_otg_5v` | 该口焊死为 host |
| HDMI 音频 | 新增 `hdmi-sound`（simple-audio-card，`i2s` → `hdmi`），启用 `i2s` | 上游 firefly 没开 i2s，HDMI 无声 |
| 5V 供电 | `vcc_host_5v` / `vcc_otg_5v` 加 `startup-delay-us = <100000>` | 让 hub 上电稳定后再枚举 |

## u-boot

本板用自己的 defconfig：`patch/u-boot/v2026.04/defconfig/rk3288-digital-reflection_defconfig`
（内容就是上游 `xt-q8l-v10-rk3288_defconfig` 的 121 行，外加一行 `CONFIG_SPL_RAM=y`）。
板级配置里的 `BOOTCONFIG` 指向它，还是用 rockchip 原厂 ddrbin
（`rk3288_ddr_400MHz_v1.08.bin` 代替 u-boot TPL，见 `post_family_config__uboot_config`）。

2026.04 上踩到两个坑，都已经在仓库里修好：

1. **`CONFIG_SYS_SPI_U_BOOT_OFFS` 未定义导致 dts 编译失败**：
   上游 `arch/arm/dts/rockchip-u-boot.dtsi` 无条件写 `offset = <CONFIG_SYS_SPI_U_BOOT_OFFS>;`，
   而该符号在 `common/spl/Kconfig` 里依赖 `SPL_SPI_LOAD`/`SPL_SPI_SUNXI`。rk3288 各目标虽然
   `select ROCKCHIP_SPI_IMAGE`，但都没有开 SPL SPI 载入 → 符号不存在 →
   `Lexical error ... Unexpected 'CONFIG_SYS_SPI_U_BOOT_OFFS'`。
   修法：`patch/u-boot/v2026.04/general-rockchip-guard-spi-u-boot-offset.patch` 把它用 `#ifdef` 包起来。
2. **SPL 链接找不到 `dram_init` / `board_get_usable_ram_top`**：
   2026.04 的 `arch/arm/mach-rockchip/spl.c` 在非 TPL 配置下会调这两个函数，但提供实现的
   `sdram.c` 只有 `CONFIG_SPL_RAM=y` 时才编进 SPL。原 xt-q8l 配置没开 → 链接失败。
   修法：自家 defconfig 加上 `CONFIG_SPL_RAM=y`（和上游 `evb-rk3288_defconfig` 一致）。

只想验证 u-boot、不编整张镜像时：

```bash
./compile.sh uboot BOARD=rk3288-digital-reflection BRANCH=current KERNEL_CONFIGURE=no PREFER_DOCKER=no
```

如果确认本板是 DDR3，可以再试 `firefly-rk3288_defconfig`（TPL 路线），目前未验证。

## 构建实测（2026-11-25）

在 8 核 / 8GB 的 Ubuntu 24.04 虚拟机上用上面的命令跑通，全程 **48 分钟**，产出：

```
Armbian-unofficial_26.11.0-trunk_Rk3288-digital-reflection_trixie_current_6.18.65_minimal.img   580 MiB（rootfs 397MiB，余量 63MB）
```

镜像内已核对：`sshd` 在、`nmtui` / `nmcli` 在、NetworkManager 启用、`/boot/dtb/rk3288-digital-reflection.dtb`
在、`armbianEnv.txt` 里 `fdtfile=rk3288-digital-reflection.dtb`、journald 走 volatile + 16M、
`getty@tty2..6` 与 `apt-daily*` 已 mask；`cron`/`man-db`/`git`/`vim-tiny`/`avahi`/`modemmanager`/`bluez` 均未安装。

### 拉源码包被打断时怎么办

从 `ghcr.io` 拉 git 浅层包（`linux-shallow-6.18.git.tar`，约 320MiB）如果网络抖，
ORAS 会整包从头重来、反复报：

```
copy failed: stream error: stream ID 1; PROTOCOL_ERROR; received from peer
```

绕过办法：先让 `./compile.sh` 跑到报错（它会打印 blob 的 `sha256:` 和大小），然后自己用 curl 断点续传：

```bash
URL="https://ghcr.io/v2/armbian/shallow/kernel-git-shallow-6.18/blobs/sha256:<digest>"
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:armbian/shallow/kernel-git-shallow-6.18:pull" | jq -r .token)
curl -L --http1.1 -C - --retry-all-errors -H "Authorization: Bearer $TOKEN" -o /tmp/linux-shallow-6.18.git.tar "$URL"
# 校验 sha256 后放进 cache，并手动展开成 "bare tree"（其实是带 .git 的普通仓库）
mv /tmp/linux-shallow-6.18.git.tar cache/git-bundles/kernel/
mkdir -p cache/git-bare/shallow-kernel-6.18
tar -xf cache/git-bundles/kernel/linux-shallow-6.18.git.tar -C cache/git-bare/shallow-kernel-6.18
touch cache/git-bare/shallow-kernel-6.18/.git/armbian-bare-tree-done
```

再跑构建时会报 `bare tree already exists`，直接跳过下载。加 `KERNEL_GIT=shallow` 可以避免默认去拉
2.7GB 的完整 git 包（本板用主线内核，浅层树足够）。

## 已知问题 / 待验证

- **低速（1.5Mbit）USB 键盘经两层 hub 后按键无反应**；全速设备（Xbox 手柄、U 盘）在同一 hub 上正常。
  属 dwc2 对低速设备周期性 split 的限制，dts 层没有可调参数；可行方向是换全速/无线键盘、或去掉第二层 hub。
- `current` 分支以外的内核（`edge` 7.3）没有对应的 dts 补丁，暂不支持。
- 镜像里 `/usr/share/man`、`/usr/share/doc` 还残留约 2MB：自定义脚本跑完之后框架又装了 bsp-cli 等包，
  会带回少量文档。想彻底干净就在开机后手动删一次，或忽略（对体积影响可忽略）。

## 许可

构建框架本身遵循上游 Armbian build 的许可；新增的板级配置与 dts 采用 GPL-2.0+ / MIT。
