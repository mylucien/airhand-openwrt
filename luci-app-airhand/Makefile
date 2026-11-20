# SPDX-License-Identifier: MIT
#
# Airhand（中继 + 网页控制台）的 OpenWrt 包定义。
#
# 两个二进制不走 buildroot 编译：Rust + npm 在 buildroot 里交叉编译代价太大，
# 由 CI 用 cargo-zigbuild 编成 musl 静态文件随 release 分发。这个 Makefile 只负责
# 把二进制取回来、和 LuCI 文件一起装进 ipk。
#
# 二进制的两种来源，按优先级：
#   1. ./prebuilt/$(ARCH_PACKAGES)/airhand-$(ARCH_PACKAGES).tar.gz  （CI 里就是这么塞的）
#   2. 从 GitHub release 的 bin 标签下载

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-airhand
PKG_VERSION:=0.2.3
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=airhand-openwrt

AIRHAND_BIN_TAG?=bin
AIRHAND_BIN_BASE?=https://github.com/mylucien/airhand-openwrt/releases/download/$(AIRHAND_BIN_TAG)

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-airhand
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Airhand 远程桌面（中继 + 网页控制台）
  DEPENDS:=+luci-base @(TARGET_x86||TARGET_airoha)
  URL:=https://github.com/mylucien/airhand-openwrt
endef

define Package/luci-app-airhand/description
 在路由器上跑 airhand-server（QUIC 中继，UDP 4433）和 airhand-web（网页控制台，
 TCP 8080）。被控电脑装 Airhand 客户端、把中继地址指向本机，就能用浏览器控制。
 端到端加密在客户端和网页控制台之间协商，中继看不到画面。
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	@case "$(ARCH_PACKAGES)" in x86_64|aarch64_cortex-a53) ;; *) \
		echo "luci-app-airhand: 架构 $(ARCH_PACKAGES) 没有预编译二进制"; exit 1 ;; esac
	if [ -f ./prebuilt/$(ARCH_PACKAGES)/airhand-$(ARCH_PACKAGES).tar.gz ]; then \
		cp ./prebuilt/$(ARCH_PACKAGES)/airhand-$(ARCH_PACKAGES).tar.gz $(PKG_BUILD_DIR)/ ; \
	else \
		echo "下载 $(AIRHAND_BIN_BASE)/airhand-$(ARCH_PACKAGES).tar.gz" ; \
		$(CURL) -fsSL "$(AIRHAND_BIN_BASE)/airhand-$(ARCH_PACKAGES).tar.gz" \
			-o $(PKG_BUILD_DIR)/airhand-$(ARCH_PACKAGES).tar.gz ; \
	fi
	$(TAR) -xzf $(PKG_BUILD_DIR)/airhand-$(ARCH_PACKAGES).tar.gz -C $(PKG_BUILD_DIR)/
endef

define Build/Compile
endef

define Package/luci-app-airhand/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/airhand-server $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/airhand-web $(1)/usr/bin/

	$(INSTALL_DIR) $(1)/usr/share/airhand/www
	$(CP) $(PKG_BUILD_DIR)/www/. $(1)/usr/share/airhand/www/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/airhand $(1)/etc/config/airhand

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/airhand-server $(1)/etc/init.d/airhand-server
	$(INSTALL_BIN) ./root/etc/init.d/airhand-web $(1)/etc/init.d/airhand-web

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/95-luci-app-airhand $(1)/etc/uci-defaults/95-luci-app-airhand

	$(INSTALL_DIR) $(1)/usr/libexec/airhand
	$(INSTALL_BIN) ./root/usr/libexec/airhand/fingerprint.sh $(1)/usr/libexec/airhand/fingerprint.sh

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-airhand.json $(1)/usr/share/luci/menu.d/
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-airhand.json $(1)/usr/share/rpcd/acl.d/

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/airhand
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/airhand/overview.js \
		$(1)/www/luci-static/resources/view/airhand/overview.js
endef

$(eval $(call BuildPackage,luci-app-airhand))
