#
# Copyright (C) 2008-2014 The LuCI Team <luci@lists.subsignal.org>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=Kedi Theme (purple, dark/light/auto)
LUCI_DEPENDS:=+luci-base

PKG_LICENSE:=Apache-2.0

define Package/luci-theme-kedi/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	uci -q delete luci.themes.Kedi
	uci commit luci
}
endef

include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature
