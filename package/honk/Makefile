#
# OpenWrt package: honk (https://github.com/daeuniverse/honk)
#
# honk is a Rust eBPF transparent proxy engine. Building it from source needs a
# pinned stable Rust toolchain, a second pinned nightly toolchain for the eBPF
# object, bpf-linker, CMake, libclang and libbpf, none of which the OpenWrt
# buildroot provides. This package therefore installs the upstream prebuilt
# static musl binary instead, pinned by SHA256.
#
# The upstream `full` variant embeds the eBPF object, the Clash API, the native
# API and the doona dashboard, so `experimental.native_api.ui: 'embedded'`
# works without any extra files. The `-stock` variant uses the system allocator
# instead of jemalloc, which the upstream documentation recommends for small
# devices where the RSS high-water mark matters more than throughput.
#
# The binary is fully static (no PT_INTERP), so this package deliberately does
# not depend on libstdcpp: there is no musl or libc++ ABI coupling to the
# OpenWrt tree it is installed into.
#
# BTF is not pulled in through vmlinux-btf. That package ships a blob generated
# for one exact kernel release and refuses to install anywhere else. The images
# built here compile BTF into their own kernel instead
# (CONFIG_KERNEL_DEBUG_INFO and CONFIG_KERNEL_DEBUG_INFO_BTF), which is what
# honk reads from /sys/kernel/btf/vmlinux.
#
# This file is free software, licensed under the GNU General Public License v3
# or later.

PKG_DIR:=$(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

include $(TOPDIR)/rules.mk

PKG_NAME:=honk
# apk (OpenWrt 25.12) only understands the underscore pre-release suffix, so the
# package version and the release tag are tracked separately: the asset name and
# the release tag spell the pre-release with dashes, apk uses its own vocabulary.
HONK_ASSET_VERSION:=0.1.0-beta.6
PKG_VERSION:=0.1.0_beta6
PKG_RELEASE:=1
HONK_RELEASE_TAG:=v$(HONK_ASSET_VERSION)

PKG_SOURCE:=honk-core-v$(HONK_ASSET_VERSION)-aarch64-unknown-linux-musl-stock-full.tar.gz
PKG_SOURCE_URL:=https://github.com/daeuniverse/honk/releases/download/$(HONK_RELEASE_TAG)/
PKG_HASH:=d07e51a5c5c6b1cc734c096a48beb3c6a5e31816661047b8b49d3ac03a85dcc4

# honk's own build script passes the release tag, but this package installs the
# prebuilt asset, so only the download URL and the package metadata matter.
PKG_LICENSE:=GPL-3.0-only

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/honk
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=eBPF transparent proxy engine with the embedded doona dashboard
  URL:=https://github.com/daeuniverse/honk
  LICENSE:=GPL-3.0-only
  # The datapath attaches TCX programs to the LAN and WAN devices, creates the
  # dae0/daens veth pair and stages ambiguous UDP packets through NFQUEUE 320.
  # TCX needs CONFIG_NET_XGRESS, which kmod-sched-core's CONFIG_NET_CLS_ACT
  # selects. The geo packages ship the dat files honk links into
  # /usr/share/honk, which it searches before the dae locations.
  DEPENDS:=+kmod-veth +kmod-sched-core +kmod-sched-bpf \
           +kmod-nft-core +kmod-nft-queue +kmod-nfnetlink-queue \
           +kmod-nf-conntrack +v2ray-geoip +v2ray-geosite
endef

define Package/honk/description
 honk-core is an eBPF transparent proxy engine. The embedded eBPF object needs
 kernel BTF for CO-RE relocations, so the kernel of this image is built with
 CONFIG_DEBUG_INFO_BTF. This build serves the doona dashboard from the native
 API on port 9527.
endef

define Package/honk/conffiles
/etc/config/honk
/etc/honk/config.dae
endef

# The release archive holds one top-level directory; strip it so honk-core and
# LICENSE land directly in PKG_BUILD_DIR. Nothing is compiled.
define Build/Prepare
	@case "$(ARCH)" in \
		aarch64*) ;; \
		*) echo "honk: the pinned release asset is aarch64 only, $(ARCH) is unsupported" >&2; exit 1;; \
	esac
	mkdir -p $(PKG_BUILD_DIR)
	tar -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) --strip-components=1
endef

define Build/Compile
endef

define Package/honk/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/honk-core $(1)/usr/bin/honk-core
	$(INSTALL_DIR) $(1)/usr/share/licenses/honk
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE $(1)/usr/share/licenses/honk/LICENSE
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_DIR)/files/honk.init $(1)/etc/init.d/honk
	# No /etc/rc.d link: the service ships disabled. honk is alpha and issue
	# #456 can cut LAN access to the router itself, so the administrator turns
	# it on deliberately with `/etc/init.d/honk enable && /etc/init.d/honk start`
	# after reading the release notes.
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_DIR)/files/honk.config $(1)/etc/config/honk
	$(INSTALL_DIR) $(1)/etc/honk
	$(INSTALL_CONF) $(PKG_DIR)/files/config.dae $(1)/etc/honk/config.dae
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	printf '%s\n' '/etc/honk/data/' > $(1)/lib/upgrade/keep.d/honk
	$(INSTALL_DIR) $(1)/usr/share/honk
	$(LN) ../v2ray/geoip.dat $(1)/usr/share/honk/geoip.dat
	$(LN) ../v2ray/geosite.dat $(1)/usr/share/honk/geosite.dat
endef

$(eval $(call BuildPackage,honk))
