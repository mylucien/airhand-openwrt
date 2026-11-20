#!/bin/sh
# 对打好的 ipk 做端到端冒烟测试（只在 x86_64 runner 上跑，能原生执行 musl 二进制）：
#   1. ipk 结构（ar 归档 + control + data）
#   2. 解包后二进制是静态链接、可执行
#   3. 中继能启动、生成证书和数据库、UDP 4433 在监听
#   4. fingerprint.sh 算出的指纹与中继日志里的一致
#   5. 网页控制台能启动、密码生效（401 / 200）、HTTPS 可用、首页能返回 HTML
#
# 用法: smoke-test.sh <ipk>
set -eu

IPK=$1
case "$IPK" in
	/*) ;;
	*) IPK=$(cd "$(dirname "$IPK")" && pwd)/$(basename "$IPK") ;;
esac
[ -f "$IPK" ] || { echo "找不到 $IPK" >&2; exit 1; }

WORK=$(mktemp -d)
SRV_PID=""
WEB_PID=""

cleanup() {
	[ -n "$WEB_PID" ] && kill "$WEB_PID" 2>/dev/null || true
	[ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null || true
	rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

wait_for() {
	_f=$1; _p=$2; _t=${3:-40}; _i=0
	while [ "$_i" -lt $((_t * 2)) ]; do
		[ -f "$_f" ] && grep -q "$_p" "$_f" 2>/dev/null && return 0
		sleep 0.5
		_i=$((_i + 1))
	done
	return 1
}

echo "== 1. ipk 结构 =="
cd "$WORK"
ar x "$IPK" 2>/dev/null || fail "ar 解不开 $IPK"
[ -f debian-binary ] || fail "缺少 debian-binary"
[ -f control.tar.gz ] || fail "缺少 control.tar.gz"
[ -f data.tar.gz ] || fail "缺少 data.tar.gz"
[ "$(cat debian-binary)" = "2.0" ] || fail "debian-binary 内容不是 2.0"

tar xzOf control.tar.gz ./control | grep -q '^Package: luci-app-airhand$' || fail "control 里没有 Package 字段"
tar xzOf control.tar.gz ./control | sed -n 's/^Architecture: //p'
tar xzOf control.tar.gz ./control | sed -n 's/^Version: //p'

mkdir -p root
tar xzf data.tar.gz -C root
[ -x root/usr/bin/airhand-server ] || fail "airhand-server 不是可执行文件"
[ -x root/usr/bin/airhand-web ] || fail "airhand-web 不是可执行文件"
[ -f root/usr/share/airhand/www/index.html ] || fail "缺少网页控制台的 index.html"
[ -f root/etc/init.d/airhand-server ] || fail "缺少中继 init 脚本"
[ -f root/etc/init.d/airhand-web ] || fail "缺少控制台 init 脚本"
[ -f root/usr/share/luci/menu.d/luci-app-airhand.json ] || fail "缺少 LuCI 菜单"
[ -f root/usr/share/rpcd/acl.d/luci-app-airhand.json ] || fail "缺少 ACL"
[ -f root/www/luci-static/resources/view/airhand/overview.js ] || fail "缺少 LuCI 视图"
echo "   ok"

echo "== 2. 静态链接检查 =="
for b in airhand-server airhand-web; do
	if readelf -l "root/usr/bin/$b" 2>/dev/null | grep -q INTERP; then
		fail "$b 是动态链接，不能直接丢进 OpenWrt"
	fi
done
echo "   ok（两个都是静态链接）"

echo "== 3. 启动中继 =="
mkdir -p "$WORK/srv"
AIRHAND_LISTEN=127.0.0.1:4433 \
AIRHAND_CERT="$WORK/srv/cert.pem" \
AIRHAND_KEY="$WORK/srv/key.pem" \
AIRHAND_DB="$WORK/srv/airhand.db" \
AIRHAND_CERT_NAMES="airhand,localhost" \
RUST_LOG=info \
	"$WORK/root/usr/bin/airhand-server" > "$WORK/server.log" 2>&1 &
SRV_PID=$!

wait_for "$WORK/server.log" "Airhand server started on udp://127.0.0.1:4433" 40 || {
	cat "$WORK/server.log" >&2
	fail "中继没起来"
}
[ -s "$WORK/srv/cert.pem" ] || fail "没有生成证书"
[ -s "$WORK/srv/key.pem" ] || fail "没有生成私钥"
[ -s "$WORK/srv/airhand.db" ] || fail "没有生成 SQLite 数据库"
ss -lun 2>/dev/null | grep -q ':4433' || fail "UDP 4433 没在监听"
echo "   ok"

echo "== 4. 指纹一致性 =="
LOG_FP=$(grep -a 'Certificate SHA-256 fingerprint' "$WORK/server.log" | grep -oE '[0-9a-f]{64}' | head -1)
[ -n "$LOG_FP" ] || { cat "$WORK/server.log" >&2; fail "日志里没有指纹行"; }
SH_FP=$(sh "$WORK/root/usr/libexec/airhand/fingerprint.sh" "$WORK/srv/cert.pem")
echo "   log=$LOG_FP"
echo "   sh =$SH_FP"
[ "$LOG_FP" = "$SH_FP" ] || fail "fingerprint.sh 算出的指纹和服务器日志不一致"
echo "   ok"

echo "== 5. 启动网页控制台 =="
mkdir -p "$WORK/web"
AIRHAND_WEB_LISTEN=127.0.0.1:8080 \
AIRHAND_WEB_ROOT="$WORK/root/usr/share/airhand/www" \
AIRHAND_WEB_CERT="$WORK/web/cert.pem" \
AIRHAND_WEB_KEY="$WORK/web/key.pem" \
AIRHAND_WEB_PASSWORD=smoke-test-pw \
AIRHAND_SERVER=127.0.0.1:4433 \
AIRHAND_SERVER_FP="$LOG_FP" \
RUST_LOG=info \
	"$WORK/root/usr/bin/airhand-web" > "$WORK/web.log" 2>&1 &
WEB_PID=$!

wait_for "$WORK/web.log" "Airhand web console listening" 40 || {
	cat "$WORK/web.log" >&2
	fail "网页控制台没起来"
}

code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/) || fail "HTTP 请求失败"
[ "$code" = "401" ] || fail "没设密码时应该 401，实际 $code"
echo "   无凭据 -> 401 ok"

code=$(curl -s -o /dev/null -w '%{http_code}' -u any:smoke-test-pw http://127.0.0.1:8080/)
[ "$code" = "200" ] || fail "带密码访问首页应该 200，实际 $code"
echo "   带凭据 -> 200 ok"

curl -s -u any:smoke-test-pw http://127.0.0.1:8080/ | grep -qi '<div id=' \
	|| fail "首页不是控制台 HTML"
echo "   首页 HTML ok"

code=$(curl -sk -o /dev/null -w '%{http_code}' -u any:smoke-test-pw https://127.0.0.1:8080/)
[ "$code" = "200" ] || fail "HTTPS 访问应该 200，实际 $code"
echo "   HTTPS ok"

echo "== 全部通过 =="
