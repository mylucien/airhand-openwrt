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

# 先取出 PEM 正文。这一步是必须的：base64 -d 失败时 sha256sum 会把空输入
# 哈希成 e3b0c44298fc1c14…b855（空字符串的 SHA-256），看起来像个正常指纹。
body=$(awk '/-----BEGIN CERTIFICATE-----/{f=1;next} /-----END CERTIFICATE-----/{f=0} f' "$cert" \
	| tr -d ' \r\n')
if [ -z "$body" ]; then
	echo "$cert 里没有找到 PEM 证书内容" >&2
	exit 1
fi

EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

# 1) busybox / coreutils 的 base64 + sha256sum（OpenWrt 上通常走这条）
if command -v base64 >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1; then
	fp=$(printf '%s' "$body" | base64 -d 2>/dev/null | sha256sum | cut -d' ' -f1) || fp=""
	if [ "$fp" = "$EMPTY_SHA" ] || [ "${#fp}" -ne 64 ]; then
		fp=""
	fi
	if [ -n "$fp" ]; then
		echo "$fp"
		exit 0
	fi
fi

# 2) openssl（装了 openssl-util 的系统）
if command -v openssl >/dev/null 2>&1; then
	fp=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 2>/dev/null \
		| sed 's/.*=//; s/://g' | tr 'A-F' 'a-f') || fp=""
	if [ "${#fp}" -ne 64 ]; then
		fp=""
	fi
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

echo "无法读取证书指纹：base64/openssl 都不可用或都失败，syslog 里也没有记录" >&2
exit 1
