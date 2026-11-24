#!/usr/bin/env bash
# @description 在镜像落盘前（post_post_debootstrap_tweaks）清掉 apt 索引与文档残留；
# 这些内容在 customize 阶段删掉后会被框架随后的 apt-get update 重新生成。
function post_post_debootstrap_tweaks__rk3288_slim_late() {
	[[ -d "${SDCARD}" ]] || return 0
	display_alert "slim-late: 清 apt 索引 / doc 残留" "${SDCARD}" "info"
	run_host_command_logged rm -rf "${SDCARD}"/var/lib/apt/lists/*
	run_host_command_logged rm -rf "${SDCARD}"/var/cache/apt/archives/*
	run_host_command_logged rm -rf "${SDCARD}"/usr/share/doc/*
	run_host_command_logged rm -rf "${SDCARD}"/usr/share/man/*
	return 0
}
