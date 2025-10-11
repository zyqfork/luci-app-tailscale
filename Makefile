# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2024 asvow
# Lua version for OpenWrt 18.0.3

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI for Tailscale (Lua version)
LUCI_DEPENDS:=+tailscale +luci-base
LUCI_PKGARCH:=all

PKG_VERSION:=1.2.6
PKG_RELEASE:=1

define Package/luci-app-tailscale/description
	LuCI support for Tailscale VPN (OpenWrt 18.0.3 Lua version)
	This is a Lua-based version compatible with older OpenWrt releases.
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
