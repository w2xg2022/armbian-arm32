#!/bin/bash
#
# 精简用户空间（参考《ARM32 盒子-模拟器适配笔记》§6.4）
#
# Armbian build 会把本文件拷到镜像的 /tmp 下，在 chroot 里以 root 执行：
#   customize-image.sh $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP $ARCH
#
# 目标：常驻内存从 ~180MB 压到 100MB 以下，同时保住开机、测声卡、切 governor 需要的东西。
# 红灯项一律不动：armbian-zram-config、armbian-ramlog、alsa-utils、u-boot-tools、
# cpufrequtils、armbian-bsp-cli、sudo、systemd。
#
# 本脚本对所有 Debian/Ubuntu release 都安全：只删真正装了的包，重复执行无副作用。

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

set -u
export DEBIAN_FRONTEND=noninteractive

purge_if_installed() {
	local list="" pkg
	for pkg in "$@"; do
		if dpkg -s "${pkg}" >/dev/null 2>&1; then
			list="${list} ${pkg}"
		fi
	done
	if [ -n "${list}" ]; then
		echo "==> purge:${list}"
		apt-get purge -y ${list} >/dev/null
	fi
}

echo "==> 精简用户空间：${RELEASE} / ${BOARD} / ${LINUXFAMILY}"

# A 绿灯清单
#   avahi/libnss-mdns      mDNS 局域网发现，模拟器机不需要
#   modemmanager           3G/4G 数据机管理，盒子没有
#   bluez/bluez-firmware   没有蓝牙
#   man-db/manpages/info/groff-base/doc-base 文档系统
#   bash-completion/command-not-found        shell 便利功能
#   systemd-coredump       崩溃转储
#   cron                   没有排程任务
#   vim-tiny               只留 nano
#   git                    编译在 x86 上做，机上不需要
#
# 刻意“不删”无线栈（wpasupplicant / iw / rfkill / wireless-regdb）：
# 镜像用的是 NetworkManager + nmtui，插个 USB 无线网卡就能在 nmtui 里直接连，省这几 MB 不值得。
purge_if_installed \
	avahi-daemon libnss-mdns avahi-autoipd \
	modemmanager \
	bluez bluez-firmware bluetooth \
	man-db manpages manpages-dev info groff-base doc-base \
	bash-completion command-not-found \
	systemd-coredump cron vim-tiny git

apt-get autoremove --purge -y >/dev/null 2>&1 || true
apt-get clean

# D systemd 层：多余 getty 与定时任务（chroot 里只能 offline 操作，不碰 --now）
for tty in 2 3 4 5 6; do
	systemctl mask "getty@tty${tty}.service" >/dev/null 2>&1 || true
done
for unit in apt-daily.timer apt-daily-upgrade.timer man-db.timer; do
	systemctl mask "${unit}" >/dev/null 2>&1 || true
done

# journald 写 RAM 并限大小，减少 eMMC 磨损
if [ -f /etc/systemd/journald.conf ]; then
	sed -i 's/^#\?Storage=.*/Storage=volatile/' /etc/systemd/journald.conf
	sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=16M/' /etc/systemd/journald.conf
	sed -i 's/^#\?RuntimeMaxUse=.*/RuntimeMaxUse=16M/' /etc/systemd/journald.conf
fi

# 顺手清掉 man/doc 残留正文
rm -rf /usr/share/man/* /usr/share/doc/* 2>/dev/null || true

echo "==> 精简完成"
