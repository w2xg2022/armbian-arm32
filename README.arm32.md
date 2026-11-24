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

```bash
./compile.sh BOARD=rk3288-digital-reflection BRANCH=current RELEASE=bookworm BUILD_MINIMAL=yes BUILD_DESKTOP=no
```

产物在 `output/images/`。板级配置已经写好 `BOOT_FDT_FILE`，生成的 `armbianEnv.txt` 里
`fdtfile=rk3288-digital-reflection.dtb`，不需要再手工替换 dtb。

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
