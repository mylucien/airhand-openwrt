#!/bin/sh
# 下载并解压 ImmortalWrt SDK。
#   用法: fetch-sdk.sh <board> <subtarget> [dest]
#   例:   fetch-sdk.sh x86 64 sdk
#         fetch-sdk.sh airoha an7581 sdk
# 版本默认取下载站上最新的 24.10.x，可用 IMMORTALWRT_VER 覆盖。
set -eu

BOARD=${1:?用法: fetch-sdk.sh <board> <subtarget> [dest]}
SUBTARGET=${2:?用法: fetch-sdk.sh <board> <subtarget> [dest]}
DEST=${3:-sdk}
BASES="https://download.immortalwrt.org/releases https://downloads.immortalwrt.org/releases"

VER=${IMMORTALWRT_VER:-}
if [ -z "$VER" ]; then
	for base in $BASES; do
		VER=$(curl -fsSL --max-time 40 "$base/" 2>/dev/null \
			| grep -oE '2[0-9]\.[0-9]+\.[0-9]+' | sort -uV | tail -1) || true
		[ -n "${VER:-}" ] && break
	done
fi
[ -n "${VER:-}" ] || {
	echo "没能确定 ImmortalWrt 版本，用 IMMORTALWRT_VER=24.10.4 指定" >&2
	exit 1
}
echo "ImmortalWrt $VER"

URL=""
for base in $BASES; do
	idx=$(curl -fsSL --max-time 40 "$base/$VER/targets/$BOARD/$SUBTARGET/" 2>/dev/null) || continue
	file=$(printf '%s' "$idx" | grep -oE 'immortalwrt-sdk-[A-Za-z0-9._-]*\.tar\.zst' | sort -u | head -1)
	if [ -n "${file:-}" ]; then
		URL="$base/$VER/targets/$BOARD/$SUBTARGET/$file"
		break
	fi
done
[ -n "$URL" ] || {
	echo "找不到 $VER/$BOARD/$SUBTARGET 的 SDK（可能这个 target 没有 SDK 或目录结构变了）" >&2
	exit 1
}
echo "SDK: $URL"

rm -rf "$DEST"
mkdir -p "$DEST"
curl -fsSL --retry 3 --max-time 1800 "$URL" -o sdk.tar.zst

if tar --zstd -tf sdk.tar.zst >/dev/null 2>&1; then
	tar --zstd -xf sdk.tar.zst -C "$DEST" --strip-components=1
else
	zstd -dc sdk.tar.zst | tar -xf - -C "$DEST" --strip-components=1
fi
rm -f sdk.tar.zst

[ -f "$DEST/Makefile" ] || { echo "解压后没找到 SDK Makefile" >&2; exit 1; }
echo "sdk=$PWD/$DEST"
