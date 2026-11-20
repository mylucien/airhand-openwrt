#!/bin/sh
# 把预先编译好的二进制和 LuCI 文件打成一个 .ipk。
#   用法: package-ipk.sh <arch> <bindir> <wwwdir> <version> <outdir>
#   arch    OpenWrt 包架构名：x86_64 / aarch64_cortex-a53
#   bindir  含 airhand-server 和 airhand-web 的目录
#   wwwdir  client/dist 的内容（index.html 在根上）
#   version 形如 0.2.3
set -eu

ARCH="$1"
BINDIR="$2"
WWWDIR="$3"
VERSION="$4"
OUTDIR="$5"

PKG=luci-app-airhand
# 打包修订号跟 Makefile 保持一致，避免 ipk 和 apk 出现两个不同的 -rN
PKGREL=$(sed -n 's/^PKG_RELEASE:=//p' "$HERE/luci-app-airhand/Makefile" 2>/dev/null | head -1)
[ -n "${PKGREL:-}" ] || PKGREL=1
PKGVER="${VERSION}-${PKGREL}"
HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUTDIR"
OUTDIR=$(cd "$OUTDIR" && pwd)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

ROOT="$STAGE/data"
CTRL="$STAGE/control"

# ---- 文件树 ----------------------------------------------------------------
mkdir -p "$ROOT"
cp -a "$HERE/luci-app-airhand/root/." "$ROOT/"

# LuCI 的 JS 资源在 OpenWrt 里落在 /www/luci-static 下
mkdir -p "$ROOT/www"
cp -a "$HERE/luci-app-airhand/htdocs/luci-static" "$ROOT/www/"

mkdir -p "$ROOT/usr/bin" "$ROOT/usr/share/airhand/www"
cp "$BINDIR/airhand-server" "$BINDIR/airhand-web" "$ROOT/usr/bin/"
cp -a "$WWWDIR/." "$ROOT/usr/share/airhand/www/"

[ -f "$ROOT/usr/share/airhand/www/index.html" ] || {
	echo "error: www 目录里没有 index.html" >&2
	exit 1
}

# ---- 权限 ----------------------------------------------------------------
find "$ROOT" -type d -exec chmod 0755 {} +
find "$ROOT" -type f -exec chmod 0644 {} +
chmod 0755 "$ROOT/usr/bin/airhand-server" "$ROOT/usr/bin/airhand-web"
for f in "$ROOT"/etc/init.d/* "$ROOT"/usr/libexec/airhand/* "$ROOT"/etc/uci-defaults/*; do
	[ -f "$f" ] && chmod 0755 "$f"
done
if [ -f "$ROOT/etc/config/airhand" ]; then
	chmod 0644 "$ROOT/etc/config/airhand"
fi

SIZE=$(du -sk "$ROOT" | awk '{print $1}')

# ---- control -------------------------------------------------------------
mkdir -p "$CTRL"
cat > "$CTRL/control" <<EOF
Package: $PKG
Version: $PKGVER
Depends: luci-base
Provides:
Source: https://github.com/${GITHUB_REPOSITORY:-local}/airhand-openwrt
SourceName: $PKG
License: MIT
Section: luci
Architecture: $ARCH
Installed-Size: $SIZE
Maintainer: airhand-openwrt
Description: Airhand 远程桌面（中继 + 网页控制台）的 LuCI 管理界面
 在路由器上运行 airhand-server（QUIC 中继，UDP 4433）和 airhand-web
 （网页控制台，TCP 8080），被控电脑装 Airhand 客户端即可用浏览器控制。
EOF
echo "2.0" > "$STAGE/debian-binary"

# ---- 打包 ----------------------------------------------------------------
mkdir -p "$OUTDIR"
( cd "$CTRL" && tar -czf "$STAGE/control.tar.gz" --owner=0 --group=0 --numeric-owner ./control )
( cd "$ROOT" && tar -czf "$STAGE/data.tar.gz" --owner=0 --group=0 --numeric-owner ./ )

IPK="$OUTDIR/${PKG}_${PKGVER}_${ARCH}.ipk"
rm -f "$IPK"
( cd "$STAGE" && ar -rc "$IPK" debian-binary control.tar.gz data.tar.gz )
echo "built $IPK ($(du -h "$IPK" | awk '{print $1}'))"
