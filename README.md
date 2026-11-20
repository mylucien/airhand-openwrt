# airhand-openwrt

把 [Airhand](https://github.com/sqlpxc/airhand) 的**中继服务器**和**网页控制台**做成一个 OpenWrt / LuCI 插件，
在路由器上跑起来，然后用浏览器控制局域网里的电脑。

被控电脑仍然要装 Airhand 客户端（Windows / macOS / Linux / Android 都行），路由器负责中继和网页入口。

## 支持范围

| 架构 | OpenWrt 包名 | 对应设备 | 包格式 |
|---|---|---|---|
| `x86_64` | `x86_64` | x86 软路由、PVE/ESXi 虚拟机、N100/N5105 之类 | ipk（24.10）/ apk（25.12） |
| `aarch64_cortex-a53` | `aarch64_cortex-a53` | **airoha an7581**（EN7581，四核 A55） | **只有 apk** |

⚠️ **ImmortalWrt 的稳定版（24.10.x、25.12.x）都没有 `airoha` target**，只有 snapshot 才有
`targets/airoha/an7581`。所以：

- 跑 an7581 的机器必然在 snapshot（或基于它的第三方固件）上 → 只能用 **apk**，且是 apk v3 格式。
- 24.10 及更老的系统用 **opkg**，只能装 ipk。
- 25.12 起 ImmortalWrt 也换成了 apk。

LuCI 侧跟随 **ImmortalWrt 24.10 及以上的 LuCI JS 框架**（客户端渲染）。18.06 / 19.07 那种 Lua 视图不兼容。

## 它是怎么连的

```
浏览器 ──https://公网IP:8080──> airhand-web（路由器，TCP 8080）
                                    │
                                    ├─ QUIC/UDP 4433 ─> airhand-server（同一台路由器）
                                    └─ 直连（LAN 内打洞成功时，视频不走中继）
                                                    │
被控电脑（LAN 内）── QUIC/UDP 4433 ─────────────────┘
```

- **中继必须存在**：6 位控制码由它分配和解析，没有中继控制端找不到被控端。但它只做信令，直连打通后视频不经过它。
- 中继绑在 LAN 侧就够了，**不需要暴露到公网**。公网只需要开 `8080/tcp` 一个端口。
- 网页控制台是端到端加密的**终点**，跑控制台的那台机器能看到画面 —— 所以密码是唯一防线。

## 安装

从 [Releases](../../releases) 下对应架构的包：

| 文件 | 用在哪 |
|---|---|
| `*.ipk` | OpenWrt / ImmortalWrt **24.10**（opkg） |
| `*.apk` | ImmortalWrt **25.12 / snapshot**（apk），an7581 只有这个可选 |

```sh
# 24.10（opkg）
opkg install luci-app-airhand_<ver>-1_x86_64.ipk

# 25.12 / snapshot（apk，包没有签名，必须 --allow-untrusted）
apk add --allow-untrusted luci-app-airhand-<ver>-r1.apk
```

**版本必须和被控端客户端一致**。上游已经发布了 `v0.3.1`，所以现在两端都用 0.3.1：

| 路由器包 | 对应客户端 |
|---|---|
| airhand **0.3.1**（推荐） | `Airhand_0.3.1_x64-setup.exe` |
| airhand 0.2.3 | `Airhand_0.2.3_x64-setup.exe` |

混装（比如 0.3.1 服务端配 0.2.3 客户端）会连不上 —— 0.3.x 起要求中继、控制台、客户端同 revision。
`weekly` 跟的是上游 main，只在 main 与最新 tag 之间有新提交时才和 tag 不同。

装完之后 LuCI 里会出现 **服务 → Airhand**，两个服务默认已启用（`airhand-server`、`airhand-web`）。
服务日志：`logread -e airhand`。

卸载：

```sh
opkg remove luci-app-airhand
```

`/etc/airhand/` 下的证书和数据库不会自动删 —— 想彻底清掉就 `rm -rf /etc/airhand`，
注意删了它等于换了一套身份，配过对的电脑都要重新配对。

## 配置

### 路由器（LuCI 页面里改）

**中继服务器**

| 项 | 默认 | 说明 |
|---|---|---|
| 监听地址 | `0.0.0.0:4433` | UDP。只想内网用可以改 `127.0.0.1:4433` |
| 每台被控端最多会话数 | `4` | 同一台被控电脑允许几个控制端同时连 |
| 证书 SAN | `airhand,localhost` | 只影响自签名证书里的名字，客户端按指纹校验 |
| 数据目录 | `/etc/airhand/relay` | 证书 + `airhand.db`（控制码绑定表），**要持久保存** |

页面上的「证书指纹」按钮会算出中继证书的 SHA-256 指纹，和服务器日志里
`Certificate SHA-256 fingerprint:` 那一行一致。

**网页控制台**

| 项 | 默认 | 说明 |
|---|---|---|
| 监听地址 | `0.0.0.0:8080` | TCP，同一端口同时支持 HTTP 和 HTTPS |
| 中继地址 | `127.0.0.1:4433` | 控制台连的中继 |
| 中继证书指纹 | 空 | 空 = 首次连接时记住中继证书（TOFU） |
| 显示名称 | `Airhand Web` | 被控端托盘里「谁在控制」显示的名字 |
| 访问密码 | 空 | **一定要设**。浏览器弹登录框，用户名随意 |
| HTTPS 证书 SAN | 空 | 填你实际访问用的 IP / 域名，减少浏览器告警 |
| 数据目录 | `/etc/airhand/web` | 证书、`controller-key.txt`（控制台身份）、`server-trust.txt` |

改完点「重启控制台」/「重启中继」生效。

### 被控电脑（Windows 客户端）

装好官方客户端后改 `C:\Program Files\Airhand\config.toml`：

```toml
server = "192.168.1.1:4433"        # 路由器地址
server_fp = "<中继证书指纹>"         # 或用页面上的「证书指纹」按钮算出来
```

**`server_fp` 必须一起改。** 官方安装包里内置的是作者的公益服务器指纹，只改 `server` 不改指纹会被
直接拒连，而且报错看不出原因。不想固定指纹就写 `server_fp = ""`（首次连接时记住）。

改完重启客户端，托盘菜单里能看到 6 位控制码。

## 公网访问

**端口映射不归插件管**，用 OpenWrt 自己的方式做：LuCI → 网络 → 防火墙 → 端口转发，
把 `wan:8080/tcp` 转到 `<路由器 LAN IP>:8080`。等价命令行：

```sh
uci add firewall redirect
uci set firewall.@redirect[-1].name='airhand-web'
uci set firewall.@redirect[-1].target='DNAT'
uci set firewall.@redirect[-1].src='wan'
uci set firewall.@redirect[-1].src_dport='8080'
uci set firewall.@redirect[-1].dest='lan'
uci set firewall.@redirect[-1].dest_ip='192.168.1.1'
uci set firewall.@redirect[-1].dest_port='8080'
uci set firewall.@redirect[-1].proto='tcp'
uci commit firewall && /etc/init.d/firewall reload
```

从外网访问就是 `https://<公网 IP 或 DDNS>:8080`。

> ⚠️ **这一步是整条链路最危险的地方。** 网页控制台是端到端加密的终点，公网上唯一的防线就是那个密码；
> 上游只给控制码做了防爆破，网页控制台没有登录限速。真要从公网用，建议至少做到：
> 换掉 8080 这个默认端口、用强密码（页面上「生成密码」）、有条件的话套一层 WireGuard/Tailscale
> 或反向代理加 IP 白名单。

## 浏览器要求

Chrome / Edge、Safari 16.4+、Firefox 130+。**从别的电脑访问必须用 `https://`** ——
WebCodecs 硬解只在安全上下文可用，用 `http://` 打开页面会把你引到 https 地址。
自签名证书第一次会告警，继续即可。

## CI

`.github/workflows/build.yml`：

| 触发 | 行为 |
|---|---|
| push 到 `main` / PR | 编译两个架构 + 打包 + 冒烟测试 + **SDK 里真编一遍**，产物存 artifact |
| push `v*` tag | 同上，并发 Release |
| **每周一 03:23 UTC（定时）** | 拉 airhand **最新 main 源码**重新编译，覆盖 `weekly` 这个预发布 Release |
| 手动 dispatch | 可指定 `ref`（tag/分支/commit），勾 `release` 才发布 |

编译方式是 **cargo-zigbuild + musl 静态链接**，产物无动态依赖，直接丢进 OpenWrt 就能跑。
冒烟测试在 x86_64 runner 上真实拉起两个服务：检查 UDP 4433 在听、证书和 SQLite 生成、
指纹脚本和日志一致、网页控制台 401/200/HTTPS 首页正常，以及 ipk 结构和静态链接。

`SDK` 那两个 job 会下载对应 target 的 ImmortalWrt SDK，把本仓库的 `luci-app-airhand/`
当普通 package 塞进去，`make package/luci-app-airhand/compile`，然后检查产出包的架构对不对：

| 架构 | SDK | 产出 |
|---|---|---|
| `x86_64` | `25.12.2` / `x86/64` | `luci-app-airhand-<ver>-r1.apk` |
| `aarch64_cortex-a53` | `snapshot` / `airoha/an7581` | `luci-app-airhand-<ver>-r1.apk` |

也就是说 `Makefile` 不是摆设，每次 CI 都拿真 SDK 编一遍，编出来的包还必须架构正确。
另外 x86_64 的 ipk 会被解包实机跑（见上），所以二进制本身的行为也是真的测过的。

### 版本兼容很重要

airhand 是 WIP 项目，协议会变：

- `main`（0.3.x）明确要求**中继、控制台、客户端同 revision**，混搭会连不上。
- `v0.2.3` 起协议支持版本协商，`0.2.3` 的客户端能配 `0.2.3` 的服务端。

所以：**用官方 0.2.3 安装包当被控端时，就用按 `ref=v0.2.3` 构建的那个 release**，
不要用 `weekly`（那是 main）。等上游出正式版，改 `ref` 重新 dispatch 一次就行。

## 在 SDK / 固件里编译（可选）

不想用现成 ipk、想自己编固件把插件烤进去的话，`luci-app-airhand/` 是一个标准的 OpenWrt package：

```sh
# 拿 SDK（版本和 target 自己按需改）
sh scripts/fetch-sdk.sh x86 64 sdk        # 或 airoha an7581

# 把包放进 SDK，并准备好预编译二进制（不准备就从 release 的 bin 标签下载）
cp -r luci-app-airhand sdk/package/
mkdir -p sdk/package/luci-app-airhand/prebuilt/x86_64
cp airhand-x86_64.tar.gz sdk/package/luci-app-airhand/prebuilt/x86_64/

cd sdk
make defconfig
make package/luci-app-airhand/compile V=s
```

放进固件编译树也是同样两步：把 `luci-app-airhand/` 扔进 `package/`，二进制按架构放进
`prebuilt/<arch>/`，然后在 menuconfig 里勾上 `LuCI → 3. Applications → luci-app-airhand`。

`Makefile` 里的 `PKG_VERSION` 只是包的版本号，二进制来源由 `prebuilt/` 或 `AIRHAND_BIN_TAG`
（默认 `bin` 这个滚动 release）决定。**二进制必须和客户端版本对得上**，见上一节。

## 目录结构

```
.github/workflows/build.yml           CI
scripts/fetch-airhand.sh              按 ref 拉上游源码，解析版本号
scripts/fetch-sdk.sh                  下 ImmortalWrt SDK 并解压（CI 的 SDK job 用）
scripts/package-ipk.sh                打 ipk（ar + control.tar.gz + data.tar.gz）
scripts/smoke-test.sh                 解包 ipk 并实机跑两个服务
luci-app-airhand/Makefile             OpenWrt 包定义（SDK / 源码树里编译用）
luci-app-airhand/root/                UCI 配置、init 脚本、辅助脚本、menu.d、acl.d
luci-app-airhand/htdocs/              LuCI JS 视图（/www/luci-static/resources/view/airhand/）
docs/luci-preview.html                LuCI 页面静态预览（不打包进 ipk）
```

## 已知限制

- 只在 24.10 的 LuCI JS 框架下验证过，更老的 Lua 版 LuCI 不兼容。
- 中文/英文界面跟随 LuCI 语言设置；本插件只有中文文案。
- aarch64 产物只做了静态链接检查，运行时冒烟测试只在 x86_64 上做。
- 上游 0.3.x 的协议变动可能让旧客户端连不上，出包时注意 `ref`。

## 许可

MIT。Airhand 本身也是 MIT，本仓库只做打包分发，不改上游代码。
