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
  BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no \
  NETWORKING_STACK=network-manager PREFER_DOCKER=no
```

- 目标组合是 **Debian 13（trixie）+ 6.18.y（`current`）+ minimal**，产物名形如
  `Armbian-unofficial_26.x_Rk3288-digital-reflection_trixie_current_6.18.y_minimal.img`。
- `KERNEL_CONFIGURE=no` 必给：非 tty（ssh 远程）下框架要弹内核配置菜单，没有它就报
  `stdin is not a terminal. can't use dialog`。
- `NETWORKING_STACK=network-manager` 是刻意覆盖：`BUILD_MINIMAL=yes` 默认会切到
  `systemd-networkd`，那样 `nmtui` 就没了。带上这个参数才有 `NetworkManager` + `nmtui`/`nmcli`，
  代价是常驻内存多 15~20MB；纯有线、不想要 TUI 的话去掉它最瘦。
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

沿用已经验证可启动的组合：`BOOTCONFIG="xt-q8l-v10-rk3288_defconfig"` + rockchip 原厂 ddrbin
（`rk3288_ddr_400MHz_v1.08.bin` 代替 u-boot TPL，见板级配置里的 `post_family_config__uboot_config`）。
如果确认本板是 DDR3，可以再试 `firefly-rk3288_defconfig`（TPL 路线），目前未验证。

## 已知问题 / 待验证

- **低速（1.5Mbit）USB 键盘经两层 hub 后按键无反应**；全速设备（Xbox 手柄、U 盘）在同一 hub 上正常。
  属 dwc2 对低速设备周期性 split 的限制，dts 层没有可调参数；可行方向是换全速/无线键盘、或去掉第二层 hub。
- `current` 分支以外的内核（`edge` 7.3）没有对应的 dts 补丁，暂不支持。

## 许可

构建框架本身遵循上游 Armbian build 的许可；新增的板级配置与 dts 采用 GPL-2.0+ / MIT。
