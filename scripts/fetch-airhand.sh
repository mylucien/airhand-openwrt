#!/bin/sh
# 拉取 airhand 源码到指定目录。
#   用法: fetch-airhand.sh <ref> <dest>
#   ref 可以是 tag / 分支 / commit，默认 main
set -eu

REF="${1:-main}"
DEST="${2:-src}"
REPO="${AIRHAND_REPO:-sqlpxc/airhand}"

rm -rf "$DEST"
mkdir -p "$DEST"
git init -q "$DEST"
git -C "$DEST" remote add origin "https://github.com/${REPO}.git"

# 先按 tag/分支取；失败再按 commit 取（--depth 1 对 SHA 也有效）
if ! git -C "$DEST" fetch -q --depth 1 origin "$REF" 2>/dev/null; then
	echo "fetch by ref failed, retrying in case it's a commit sha: $REF" >&2
	git -C "$DEST" fetch -q --depth 1 origin "$REF"
fi
git -C "$DEST" checkout -q FETCH_HEAD

SHA=$(git -C "$DEST" rev-parse HEAD)
VER=$(awk '/^\[workspace.package\]/{f=1;next} /^\[/{f=0} f&&$1=="version"{gsub(/"/,"",$3);print $3;exit}' "$DEST/Cargo.toml" 2>/dev/null || true)
[ -n "${VER:-}" ] || VER=$(awk -F'"' '/^version/{print $2;exit}' "$DEST/Cargo.toml" 2>/dev/null || true)
[ -n "${VER:-}" ] || VER="0.0.0"

echo "airhand ref=${REF} sha=${SHA} version=${VER}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "ref=${REF}"
		echo "sha=${SHA}"
		echo "short=$(echo "$SHA" | cut -c1-7)"
		echo "version=${VER}"
	} >> "$GITHUB_OUTPUT"
fi
