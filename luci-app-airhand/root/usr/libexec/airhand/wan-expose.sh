#!/bin/sh
# 管理「公网访问网页控制台」的防火墙转发（A 方案：把 WAN 的端口直接 DNAT 到路由器自己）。
# 用法: wan-expose.sh on|off [端口]
#
# 只增删自己创建的那一条 redirect（firewall.airhand_wan），不动其它规则。
set -eu

action="${1:-}"
port="$2"

if [ -z "${port:-}" ]; then
	listen=$(uci -q get airhand.web.listen 2>/dev/null) || listen=""
	port="${listen##*:}"
fi
case "$port" in
	''|*[!0-9]*) port=8080 ;;
esac

SEC=airhand_wan

case "$action" in
on)
	ip=$(uci -q get network.lan.ipaddr 2>/dev/null) || ip=""
	[ -n "${ip:-}" ] || ip="192.168.1.1"

	uci -q delete "firewall.$SEC" 2>/dev/null || true
	uci set "firewall.$SEC=redirect"
	uci set "firewall.$SEC.name='airhand-web'"
	uci set "firewall.$SEC.target='DNAT'"
	uci set "firewall.$SEC.src='wan'"
	uci set "firewall.$SEC.src_dport='$port'"
	uci set "firewall.$SEC.dest='lan'"
	uci set "firewall.$SEC.dest_ip='$ip'"
	uci set "firewall.$SEC.dest_port='$port'"
	uci set "firewall.$SEC.proto='tcp'"
	uci commit firewall
	/etc/init.d/firewall reload >/dev/null 2>&1 || true

	echo "已开放：wan:$port/tcp → $ip:$port"
	echo "注意：控制台是端到端加密的终点，公网上唯一的防线就是访问密码，请务必设置一个强密码。"
	;;
off)
	uci -q delete "firewall.$SEC" 2>/dev/null || true
	uci commit firewall
	/etc/init.d/firewall reload >/dev/null 2>&1 || true
	echo "已关闭公网访问（移除 firewall.$SEC）"
	;;
*)
	echo "用法: $0 on|off [端口]" >&2
	exit 1
	;;
esac
