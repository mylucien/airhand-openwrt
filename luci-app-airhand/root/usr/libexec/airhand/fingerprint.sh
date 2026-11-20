#!/bin/sh
# 打印中继证书的 SHA-256 指纹，与 airhand-server 启动日志里
# "Certificate SHA-256 fingerprint: ..." 那一行完全一致。
#
# 用法: fingerprint.sh [证书路径]
#   不带参数时读 uci 里 airhand.relay.data_dir 下的 cert.pem
set -eu

cert="${1:-}"

if [ -z "$cert" ]; then
	dir=$(uci -q get airhand.relay.data_dir 2>/dev/null) || dir=""
	[ -n "$dir" ] || dir=/etc/airhand/relay
	cert="$dir/cert.pem"
fi

if [ ! -f "$cert" ]; then
	echo "证书不存在：$cert（请先启动中继服务：/etc/init.d/airhand-server start）" >&2
	exit 1
fi

# 1) busybox / coreutils 的 base64 + sha256sum（OpenWrt 上通常走这条）
if command -v base64 >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1; then
	fp=$(awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' "$cert" \
		| sed '1d;$d' | tr -d ' \r\n' | base64 -d 2>/dev/null | sha256sum | cut -d' ' -f1) || fp=""
	if [ -n "$fp" ]; then
		echo "$fp"
		exit 0
	fi
fi

# 2) openssl（装了 openssl-util 的系统）
if command -v openssl >/dev/null 2>&1; then
	fp=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 2>/dev/null \
		| sed 's/.*=//; s/://g' | tr 'A-F' 'a-f') || fp=""
	if [ -n "$fp" ]; then
		echo "$fp"
		exit 0
	fi
fi

# 3) 兜底：从本次启动的 syslog 里取
fp=$(logread 2>/dev/null | grep -a 'Certificate SHA-256 fingerprint' | tail -1 | grep -oE '[0-9a-f]{64}') || fp=""
if [ -n "$fp" ]; then
	echo "$fp"
	exit 0
fi

echo "无法读取证书指纹：系统没有 base64/openssl，syslog 里也没有记录" >&2
exit 1
