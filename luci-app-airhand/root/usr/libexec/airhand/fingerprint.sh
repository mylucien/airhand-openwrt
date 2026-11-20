#!/bin/sh
# 打印中继证书的 SHA-256 指纹，与 airhand-server 启动日志里
# "Certificate SHA-256 fingerprint: ..." 那一行完全一致。
# 用法: fingerprint.sh [证书路径]
set -eu

cert="$1"

if [ -z "${cert:-}" ]; then
	dir=$(uci -q get airhand.relay.data_dir 2>/dev/null) || dir=""
	[ -n "${dir:-}" ] || dir=/etc/airhand/relay
	cert="$dir/cert.pem"
fi

if [ ! -f "$cert" ]; then
	echo "证书还没生成：先启动一次中继（/etc/init.d/airhand-server start）" >&2
	exit 1
fi

awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' "$cert" \
	| sed '1d;$d' \
	| tr -d ' \r\n' \
	| base64 -d \
	| sha256sum \
	| cut -d' ' -f1
