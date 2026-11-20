#!/bin/sh
# 下载并解压 ImmortalWrt SDK。
#   用法: fetch-sdk.sh <board> <subtarget> [dest]
#   例:   fetch-sdk.sh x86 64 sdk              # 取最新稳定版
#         fetch-sdk.sh airoha an7581 sdk       # 取 snapshot（airoha 只在 snapshot 里有）
# 版本用 IMMORTALWRT_VER 覆盖，值可以是 24.10.6 / 25.12.2 / snapshot。
set -eu

BOARD=${1:?用法: fetch-sdk.sh <board> <subtarget> [dest]}
SUBTARGET=${2:?用法: fetch-sdk.sh <board> <subtarget> [dest]}
DEST=${3:-sdk}
BASES="https://download.immortalwrt.org https://downloads.immortalwrt.org https://mirror.nju.edu.cn/immortalwrt"

VER=${IMMORTALWRT_VER:-}
if [ -z "$VER" ]; then
	for base in $BASES; do
		VER=$(curl -fsSL --max-time 40 "$base/releases/" 2>/dev/null \
			| grep -oE '2[0-9]\.[0-9]+\.[0-9]+' | sort -uV | tail -1) || true
		[ -n "${VER:-}" ] && break
	done
fi
[ -n "${VER:-}" ] || {
	echo "没能确定 ImmortalWrt 版本，用 IMMORTALWRT_VER=25.12.2 指定" >&2
	exit 1
}

case "$VER" in
snapshot) TREE="snapshots/targets/$BOARD/$SUBTARGET" ;;
*)        TREE="releases/$VER/targets/$BOARD/$SUBTARGET" ;;
esac
echo "ImmortalWrt $VER · $BOARD/$SUBTARGET"

URL=""
for base in $BASES; do
	idx=$(curl -fsSL --max-time 40 "$base/$TREE/" 2>/dev/null) || continue
	file=$(printf '%s' "$idx" | grep -oE 'immortalwrt-sdk-[A-Za-z0-9._-]*\.tar\.zst' | sort -u | head -1)
	if [ -n "${file:-}" ]; then
		URL="$base/$TREE/$file"
		break
	fi
done
[ -n "$URL" ] || {
	echo "在 $VER 里找不到 $BOARD/$SUBTARGET 的 SDK" >&2
	echo "（ImmortalWrt 稳定版没有 airoha，airoha/an7581 只在 snapshot 里有）" >&2
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

# 记下这个 SDK 的包格式（snapshot / 25.x 是 apk，24.10 是 opkg）
if [ -d "$DEST/staging_dir/host/bin" ] && [ -x "$DEST/staging_dir/host/bin/apk" ]; then
	echo "包格式: apk"
elif ls "$DEST"/scripts/ipkg >/dev/null 2>&1; then
	echo "包格式: ipk"
fi
echo "sdk=$PWD/$DEST"
