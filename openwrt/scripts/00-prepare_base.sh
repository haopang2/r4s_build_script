#!/bin/bash -e

# Rockchip - rkbin & u-boot 2023.01
rm -rf package/boot/uboot-rockchip package/boot/arm-trusted-firmware-rockchip
git clone git@github.com:sbwml/package_boot_uboot-rockchip package/boot/uboot-rockchip
git clone git@github.com:sbwml/arm-trusted-firmware-rockchip package/boot/arm-trusted-firmware-rockchip

# Fix linux-5.10
if [ "$version" = "rc" ]; then
    curl -s https://$mirror/openwrt/patch/kernel-5.10/config-5.10 > target/linux/generic/config-5.10
    curl -s https://$mirror/openwrt/patch/kernel-5.10/5.10-video.mk > package/kernel/linux/modules/video.mk
fi

# Fix x86 - CONFIG_ALL_KMODS
if [ "$platform" = "x86_64" ]; then
    sed -i 's/hwmon, +PACKAGE_kmod-thermal:kmod-thermal/hwmon/g' package/kernel/linux/modules/hwmon.mk
fi

# default LAN IP
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# Use nginx instead of uhttpd
sed -i 's/+uhttpd /+luci-nginx /g' feeds/luci/collections/luci/Makefile
sed -i 's/+uhttpd-mod-ubus //' feeds/luci/collections/luci/Makefile
sed -i 's/+uhttpd /+luci-nginx /g' feeds/luci/collections/luci-light/Makefile
sed -i "s/+luci /+luci-nginx /g" feeds/luci/collections/luci-ssl-openssl/Makefile
sed -i "s/+luci /+luci-nginx /g" feeds/luci/collections/luci-ssl/Makefile
if [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    sed -i 's/+uhttpd +uhttpd-mod-ubus /+luci-nginx /g' feeds/packages/net/wg-installer/Makefile
    sed -i '/uhttpd-mod-ubus/d' feeds/luci/collections/luci-light/Makefile
    sed -i 's/+luci-nginx \\$/+luci-nginx/' feeds/luci/collections/luci-light/Makefile
fi

# NIC driver - x86
if [ "$platform" = "x86_64" ]; then
    # r8101
    git clone git@github.com:sbwml/package_kernel_r8101 package/kernel/r8101
fi
# R8168 & R8125 & R8152
git clone git@github.com:sbwml/package_kernel_r8168 package/kernel/r8168
git clone git@github.com:sbwml/package_kernel_r8152 package/kernel/r8152
git clone https://$gitea/sbwml/package_kernel_r8125 package/kernel/r8125

# netifd - fix auto-negotiate by upstream
if [ "$version" = "rc" ] || [ "$version" = "rc2" ] || [ "$version" = "snapshots-23.05" ]; then
    mkdir -p package/network/config/netifd/patches
    curl -s https://$mirror/openwrt/patch/netifd/100-system-linux-fix-autoneg-for-2.5G-5G-10G.patch > package/network/config/netifd/patches/100-system-linux-fix-autoneg-for-2.5G-5G-10G.patch
fi

# Wireless Drivers
rm -rf package/kernel/rtl8812au-ct
git clone git@github.com:sbwml/openwrt-wireless-drivers package/kernel/wireless
if [ "$version" = "rc" ]; then
    # hostapd: make LAR-friendly AP mode for AX200/AX210
    curl -s https://$mirror/openwrt/patch/hostapd-22.03/999-hostapd-2.10-lar.patch > package/network/services/hostapd/patches/999-hostapd-2.10-lar.patch
fi

# Optimization level -Ofast
if [ "$platform" = "rk3328" ]; then
    curl -s https://$mirror/openwrt/patch/target-modify_for_rk3328.patch | patch -p1
elif [ "$platform" = "rk3399" ]; then
    curl -s https://$mirror/openwrt/patch/target-modify_for_rk3399.patch | patch -p1
elif [ "$platform" = "rk3568" ]; then
    curl -s https://$mirror/openwrt/patch/target-modify_for_rk3568.patch | patch -p1
fi

# IF USE GLIBC
if [ "$USE_GLIBC" = "y" ]; then
    # O3 optimization
    git checkout include/target.mk && \
        curl -s https://$mirror/openwrt/patch/target-modify_for_glibc.patch | patch -p1
    # musl-libc
    git clone https://$gitea/sbwml/package_libs_musl-libc package/libs/musl-libc
    # bump fstools version
    rm -rf package/system/fstools
    cp -a ../master/openwrt/package/system/fstools package/system/fstools
    # glibc-common
    curl -s https://$mirror/openwrt/patch/openwrt-6.1/toolchain/glibc-common.patch | patch -p1
    # glibc-common - locale data
    mkdir -p package/libs/toolchain/glibc-locale
    curl -Lso package/libs/toolchain/glibc-locale/locale-archive https://github.com/sbwml/r4s_build_script/releases/download/locale/locale-archive
    [ "$?" -ne 0 ] && echo -e "${RED_COLOR} Locale file download failed... ${RES}"
    # GNU LANG
    mkdir package/base-files/files/etc/profile.d
    echo 'export LANG="en_US.UTF-8" I18NPATH="/usr/share/i18n"' > package/base-files/files/etc/profile.d/sys_locale.sh
    # build - drop `--disable-profile`
    sed -i "/disable-profile/d" toolchain/glibc/common.mk
fi

# Mbedtls AES & GCM Crypto Extensions
if [ ! "$platform" = "x86_64" ]; then
    if [ "$version" = "rc" ]; then
       curl -s https://$mirror/openwrt/patch/mbedtls-22.03/100-Implements-AES-and-GCM-with-ARMv8-Crypto-Extensions.patch > package/libs/mbedtls/patches/100-Implements-AES-and-GCM-with-ARMv8-Crypto-Extensions.patch
       curl -s https://$mirror/openwrt/patch/mbedtls-22.03/mbedtls.patch | patch -p1
    else
       curl -s https://$mirror/openwrt/patch/mbedtls-23.05/200-Implements-AES-and-GCM-with-ARMv8-Crypto-Extensions.patch > package/libs/mbedtls/patches/200-Implements-AES-and-GCM-with-ARMv8-Crypto-Extensions.patch
       curl -s https://$mirror/openwrt/patch/mbedtls-23.05/mbedtls.patch | patch -p1
    fi
fi

# NTFS3
mkdir -p package/system/fstools/patches
curl -s https://$mirror/openwrt/patch/fstools/ntfs3.patch > package/system/fstools/patches/ntfs3.patch
curl -s https://$mirror/openwrt/patch/util-linux/util-linux_ntfs3.patch > package/utils/util-linux/patches/util-linux_ntfs3.patch
if [ "$version" = "rc" ]; then
    curl -s https://$mirror/openwrt/patch/ntfs3-5.10/997-fs-ntfs3-Add-paragon-ntfs3-driver.patch > target/linux/generic/hack-5.10/997-fs-ntfs3-Add-paragon-ntfs3-driver.patch
    curl -s https://$mirror/openwrt/patch/ntfs3-5.10/22.03-add-ntfs3-support.patch | patch -p1
fi

# fstools - enable any device with non-MTD rootfs_data volume
curl -s https://$mirror/openwrt/patch/fstools/block-mount-add-fstools-depends.patch | patch -p1
if [ "$USE_GLIBC" = "y" ]; then
    curl -s https://$mirror/openwrt/patch/fstools/fstools-set-ntfs3-utf8-new.patch > package/system/fstools/patches/ntfs3-utf8.patch
    curl -s https://$mirror/openwrt/patch/fstools/glibc/0001-libblkid-tiny-add-support-for-XFS-superblock.patch > package/system/fstools/patches/0001-libblkid-tiny-add-support-for-XFS-superblock.patch
    curl -s https://$mirror/openwrt/patch/fstools/glibc/0003-block-add-xfsck-support.patch > package/system/fstools/patches/0003-block-add-xfsck-support.patch
else
    [ "$version" = "rc" ] && curl -s https://$mirror/openwrt/patch/fstools/ntfs3-utf8.patch > package/system/fstools/patches/ntfs3-utf8.patch
    [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ] && curl -s https://$mirror/openwrt/patch/fstools/fstools-set-ntfs3-utf8-new.patch > package/system/fstools/patches/ntfs3-utf8.patch
fi
if [ "$version" = "rc" ] || [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    if [ "$USE_GLIBC" = "y" ]; then
        curl -s https://$mirror/openwrt/patch/fstools/22-fstools-support-extroot-for-non-MTD-rootfs_data-new-version.patch > package/system/fstools/patches/22-fstools-support-extroot-for-non-MTD-rootfs_data.patch
    else
        curl -s https://$mirror/openwrt/patch/fstools/22-fstools-support-extroot-for-non-MTD-rootfs_data.patch > package/system/fstools/patches/22-fstools-support-extroot-for-non-MTD-rootfs_data.patch
    fi
fi

# QEMU for aarch64
pushd feeds/packages
if [ "$version" = "rc" ] || [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    curl -s https://$mirror/openwrt/patch/qemu/qemu-aarch64_master.patch > qemu-aarch64.patch
fi
git apply qemu-aarch64.patch && rm qemu-aarch64.patch
popd

# Patch arm64 model name
if [ "$version" = "rc" ]; then
    curl -s https://$mirror/openwrt/patch/kernel-5.10/312-arm64-cpuinfo-Add-model-name-in-proc-cpuinfo-for-64bit-ta.patch > target/linux/generic/hack-5.10/312-arm64-cpuinfo-Add-model-name-in-proc-cpuinfo-for-64bit-ta.patch
elif [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    curl -s https://$mirror/openwrt/patch/kernel-5.15/312-arm64-cpuinfo-Add-model-name-in-proc-cpuinfo-for-64bit-ta.patch > target/linux/generic/hack-5.15/312-arm64-cpuinfo-Add-model-name-in-proc-cpuinfo-for-64bit-ta.patch
fi

# Dnsmasq
if [ "$version" = "rc" ] || [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    # Dnsmasq Latest version
    #DNSMASQ_VERSION=2.89
    #DNSMASQ_HASH=02bd230346cf0b9d5909f5e151df168b2707103785eb616b56685855adebb609
    rm -rf package/network/services/dnsmasq
    cp -a ../master/openwrt/package/network/services/dnsmasq package/network/services/dnsmasq
    #sed -ri "s/(PKG_UPSTREAM_VERSION:=)[^\"]*/\1$DNSMASQ_VERSION/;s/(PKG_HASH:=)[^\"]*/\1$DNSMASQ_HASH/" package/network/services/dnsmasq/Makefile
fi

# Patch FireWall - FullCone
if [ "$version" = "rc" ] || [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    # firewall4
    rm -rf package/network/config/firewall4
    cp -a ../master/openwrt/package/network/config/firewall4 package/network/config/firewall4
    mkdir -p package/network/config/firewall4/patches
    curl -s https://$mirror/openwrt/patch/firewall4/999-01-firewall4-add-fullcone-support.patch > package/network/config/firewall4/patches/999-01-firewall4-add-fullcone-support.patch
    # kernel version
    curl -s https://$mirror/openwrt/patch/firewall4/002-fix-fw4.uc-adept-kernel-version-type-of-x.x.patch > package/network/config/firewall4/patches/002-fix-fw4.uc-adept-kernel-version-type-of-x.x.patch
    # libnftnl
    rm -rf package/libs/libnftnl
    cp -a ../master/openwrt/package/libs/libnftnl package/libs/libnftnl
    mkdir -p package/libs/libnftnl/patches
    curl -s https://$mirror/openwrt/patch/firewall4/libnftnl/001-libnftnl-add-fullcone-expression-support.patch > package/libs/libnftnl/patches/001-libnftnl-add-fullcone-expression-support.patch
    sed -i '/PKG_INSTALL:=1/iPKG_FIXUP:=autoreconf' package/libs/libnftnl/Makefile
    # nftables
    rm -rf package/network/utils/nftables
    cp -a ../master/openwrt/package/network/utils/nftables package/network/utils/nftables
    mkdir -p package/network/utils/nftables/patches
    curl -s https://$mirror/openwrt/patch/firewall4/nftables/002-nftables-add-fullcone-expression-support.patch > package/network/utils/nftables/patches/002-nftables-add-fullcone-expression-support.patch
    # hide nftables warning message
    pushd feeds/luci
        curl -s https://$mirror/openwrt/patch/luci/luci-nftables.patch | patch -p1
    popd
fi

# Patch Kernel - FullCone
if [ "$version" = "rc" ]; then
    curl -s https://$mirror/openwrt/patch/kernel-5.10/952-net-conntrack-events-support-multiple-registrant.patch > target/linux/generic/hack-5.10/952-net-conntrack-events-support-multiple-registrant.patch
elif [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    curl -s https://$mirror/openwrt/patch/kernel-5.15/952-add-net-conntrack-events-support-multiple-registrant.patch > target/linux/generic/hack-5.15/952-add-net-conntrack-events-support-multiple-registrant.patch
fi

# Patch FullCone Option 22
if [ "$version" = "rc" ] || [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    curl -s https://$mirror/openwrt/patch/firewall4/luci-app-firewall_add_fullcone.patch | patch -p1
fi

# FullCone module
if [ "$version" = "rc" ] || [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    git clone https://$gitea/sbwml/nft-fullcone package/new/nft-fullcone
fi

# TCP performance optimizations backport from linux/net-next
if [ "$version" = "rc" ]; then
    curl -s https://$mirror/openwrt/patch/backport-5.10/780-v5.17-tcp-defer-skb-freeing-after-socket-lock-is-released.patch > target/linux/generic/backport-5.10/780-v5.17-tcp-defer-skb-freeing-after-socket-lock-is-released.patch
elif [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    curl -s https://$mirror/openwrt/patch/backport-5.15/680-01-v5.17-tcp-avoid-indirect-calls-to-sock_rfree.patch > target/linux/generic/backport-5.15/680-01-v5.17-tcp-avoid-indirect-calls-to-sock_rfree.patch
    curl -s https://$mirror/openwrt/patch/backport-5.15/680-02-v5.17-tcp-defer-skb-freeing-after-socket-lock-is-released.patch > target/linux/generic/backport-5.15/680-02-v5.17-tcp-defer-skb-freeing-after-socket-lock-is-released.patch
fi

# MGLRU - 5.10
if [ "$version" = "rc" ]; then
  pushd target/linux/generic/pending-5.10
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-00-BACKPORT-mmvmscan.c-use-add_page_to_lru_list().patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-01-BACKPORT-includelinuxmm_inline.h-shuffle-lru-list-addition-and-deletion-functions.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-02-BACKPORT-mm-don't-pass-enum-lru_list-to-lru-list-addition-functions.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-03-UPSTREAM-mmswap.c-don't-pass-enum-lru_list-to-trace_mm_lru_insertion().patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-04-BACKPORT-mmswap.c-don't-pass-enum-lru_list-to-del_page_from_lru_list().patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-05-BACKPORT-mm-add-__clear_page_lru_flags()-to-replace-page_off_lru().patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-06-BACKPORT-mm-VM_BUG_ON-lru-page-flags.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-07-UPSTREAM-includelinuxmm_inline.h-fold-page_lru_base_type()-into-its-sole-caller.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-08-UPSTREAM-mmswap-don't-SetPageWorkingset-unconditionally-during-swapin.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-09-UPSTREAM-includelinuxpage-flags-layout.h-correctly-determine-LAST_CPUPID_WIDTH.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-10-UPSTREAM-includelinuxpage-flags-layout.h-cleanups.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-11-FROMLIST-mm-x86,-arm64-add-arch_has_hw_pte_young().patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-12-FROMLIST-mm-x86-add-CONFIG_ARCH_HAS_NONLEAF_PMD_YOUNG.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-13-FROMLIST-mmvmscan.c-refactor-shrink_node().patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-14-FROMLIST-mm-multi-gen-LRU-groundwork.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-15-FROMLIST-mm-multi-gen-LRU-minimal-implementation.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-16-FROMLIST-mm-multi-gen-LRU-exploit-locality-in-rmap.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-17-FROMLIST-mm-multi-gen-LRU-support-page-table-walks.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-18-FROMLIST-mm-multi-gen-LRU-optimize-multiple-memcgs.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-19-FROMLIST-mm-multi-gen-LRU-kill-switch.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-20-FROMLIST-mm-multi-gen-LRU-thrashing-prevention.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-21-FROMLIST-mm-multi-gen-LRU-debugfs-interface.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-22-FROMLIST-mm-multi-gen-LRU-admin-guide.patch"
    curl -sO "https://$mirror/openwrt/patch/kernel-5.10/MGLRU/020-23-FROMLIST-mm-multi-gen-LRU-design-doc.patch"
  popd
  cat >> target/linux/generic/config-5.10 <<"EOF"
CONFIG_LRU_GEN=y
CONFIG_LRU_GEN_ENABLED=y
# CONFIG_LRU_GEN_STATS is not set
EOF
fi

# OpenSSL
if [ ! "$platform" = "x86_64" ] && [ "$version" = "rc" ]; then
    sed -i "s/O3/Ofast/g" package/libs/openssl/Makefile
    if [ "$version" = "rc" ]; then
        curl -s https://$mirror/openwrt/patch/openssl/11895.patch > package/libs/openssl/patches/11895.patch
        curl -s https://$mirror/openwrt/patch/openssl/14578.patch > package/libs/openssl/patches/14578.patch
        curl -s https://$mirror/openwrt/patch/openssl/16575.patch > package/libs/openssl/patches/16575.patch
        curl -s https://$mirror/openwrt/patch/openssl/999-Ofast.patch > package/libs/openssl/patches/999-Ofast.patch
    fi

    # enable cryptodev
    if [ "$version" = "rc" ]; then
        curl -s https://$mirror/openwrt/patch/openssl/22-openssl_cryptodev.patch | patch -p1
    fi
fi

# Docker
rm -rf feeds/luci/applications/luci-app-dockerman
if [ "$version" = "rc" ]; then
    git clone https://$gitea/sbwml/luci-app-dockerman -b openwrt-22.03 feeds/luci/applications/luci-app-dockerman
else
    git clone https://$gitea/sbwml/luci-app-dockerman -b openwrt-23.05 feeds/luci/applications/luci-app-dockerman
fi
if [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    rm -rf feeds/packages/utils/docker feeds/packages/utils/dockerd feeds/packages/utils/containerd feeds/packages/utils/runc
    cp -a ../master/packages/utils/docker feeds/packages/utils/docker
    cp -a ../master/packages/utils/dockerd feeds/packages/utils/dockerd
    cp -a ../master/packages/utils/containerd feeds/packages/utils/containerd
    cp -a ../master/packages/utils/runc feeds/packages/utils/runc
fi
sed -i '/sysctl.d/d' feeds/packages/utils/dockerd/Makefile
if [ "$version" = "rc" ] || [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    pushd feeds/packages
        curl -s https://$mirror/openwrt/patch/docker/dockerd-fix-bridge-network.patch | patch -p1
    popd
fi
pushd feeds/packages
    curl -s https://$mirror/openwrt/patch/docker/0001-dockerd-defer-starting-docker-service.patch | patch -p1
popd

# haproxy - fix build for 23.05
if [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    rm -rf feeds/packages/net/haproxy
    cp -a ../master/packages/net/haproxy feeds/packages/net/haproxy
fi

# procps-ng - top
sed -i 's/enable-skill/enable-skill --disable-modern-top/g' feeds/packages/utils/procps-ng/Makefile

# TTYD
sed -i 's/services/system/g' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
sed -i '3 a\\t\t"order": 50,' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json

# UPnP - fix 22.03
if [ "$version" = "rc" ] || [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    rm -rf feeds/packages/net/miniupnpd
    git clone https://$gitea/sbwml/miniupnpd feeds/packages/net/miniupnpd
    rm -rf feeds/luci/applications/luci-app-upnp
    git clone https://$gitea/sbwml/luci-app-upnp feeds/luci/applications/luci-app-upnp
    pushd feeds/packages
        curl -s https://$mirror/openwrt/patch/miniupnpd/1.patch | patch -p1
        curl -s https://$mirror/openwrt/patch/miniupnpd/2.patch | patch -p1
        curl -s https://$mirror/openwrt/patch/miniupnpd/3.patch | patch -p1
        curl -s https://$mirror/openwrt/patch/miniupnpd/4.patch | patch -p1
    popd
fi

# UPnP - Move to network
sed -i 's/services/network/g' feeds/luci/applications/luci-app-upnp/root/usr/share/luci/menu.d/luci-app-upnp.json

# iproute2 - fix build with glibc
if [ "$version" = "rc" ]; then
    curl -s https://github.com/openwrt/openwrt/commit/fb15cb4ce9559021d463b5cb3816d8a9eeb8f3f9.patch | patch -p1
fi

# nginx - latest version
rm -rf feeds/packages/net/nginx
git clone git@github.com:sbwml/feeds_packages_net_nginx feeds/packages/net/nginx
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/g;s/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/net/nginx/files/nginx.init

# nginx - ubus
sed -i 's/ubus_parallel_req 2/ubus_parallel_req 6/g' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support
sed -i '/ubus_parallel_req/a\        ubus_script_timeout 600;' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support

# nginx - uwsgi timeout & enable brotli
curl -s https://$mirror/openwrt/nginx/luci.locations > feeds/packages/net/nginx/files-luci-support/luci.locations
curl -s https://$mirror/openwrt/nginx/uci.conf.template > feeds/packages/net/nginx-util/files/uci.conf.template

# uwsgi - bump version
if [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    rm -rf feeds/packages/net/uwsgi
    cp -a ../master/packages/net/uwsgi feeds/packages/net/uwsgi
fi

# uwsgi - fix timeout
sed -i '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-*.ini
sed -i '/limit-as/c\limit-as = 5000' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
# disable error log
sed -i "s/procd_set_param stderr 1/procd_set_param stderr 0/g" feeds/packages/net/uwsgi/files/uwsgi.init

# rpcd bump version
if [ "$version" = "rc" ] && [ "$platform" != "x86_64" ]; then
    rm -rf package/system/rpcd
    cp -a ../master/openwrt/package/system/rpcd package/system/rpcd
fi

# rpcd - fix timeout
sed -i 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config
sed -i 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js

# luci - 20_memory
curl -s https://$mirror/openwrt/patch/luci/20_memory.js.patch | patch -p1

# Luci refresh interval
curl -s https://$mirror/openwrt/patch/luci/luci-refresh-interval.patch | patch -p1

# Luci ui.js
[ "$version" = "rc" ] && curl -s https://$mirror/openwrt/patch/luci/upload-ui.js.patch | patch -p1

# Luci diagnostics.js
sed -i "s/openwrt.org/www.qq.com/g" feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/diagnostics.js

# samba4
if [ "$version" = "rc" ] || [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    # bump version
    SAMBA4_VERSION=4.18.3
    SAMBA4_HASH=c67e1453165a3918ffffad600236ca3966b47bde4798e89ae600ae3903ccc32c
    rm -rf feeds/packages/net/samba4
    cp -a ../master/packages/net/samba4 feeds/packages/net/samba4
    sed -ri "s/(PKG_VERSION:=)[^\"]*/\1$SAMBA4_VERSION/;s/(PKG_HASH:=)[^\"]*/\1$SAMBA4_HASH/" feeds/packages/net/samba4/Makefile
    # enable multi-channel
    sed -i '/workgroup/a \\n\t## enable multi-channel' feeds/packages/net/samba4/files/smb.conf.template
    sed -i '/enable multi-channel/a \\tserver multi channel support = yes' feeds/packages/net/samba4/files/smb.conf.template
fi
sed -i 's/invalid users = root/#invalid users = root/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/bind interfaces only = yes/bind interfaces only = no/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/#create mask/create mask/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/#directory mask/directory mask/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/0666/0644/g;s/0744/0755/g;s/0777/0755/g' feeds/luci/applications/luci-app-samba4/htdocs/luci-static/resources/view/samba4.js
sed -i 's/0666/0644/g;s/0777/0755/g' feeds/packages/net/samba4/files/samba.config
sed -i 's/0666/0644/g;s/0777/0755/g' feeds/packages/net/samba4/files/smb.conf.template

# profile
sed -i 's#\\u@\\h:\\w\\\$#\\[\\e[32;1m\\][\\u@\\h\\[\\e[0m\\] \\[\\033[01;34m\\]\\W\\[\\033[00m\\]\\[\\e[32;1m\\]]\\[\\e[0m\\]\\\$#g' package/base-files/files/etc/profile
sed -ri 's/(export PATH=")[^"]*/\1%PATH%:\/opt\/bin:\/opt\/sbin:\/opt\/usr\/bin:\/opt\/usr\/sbin/' package/base-files/files/etc/profile

# bash
sed -i 's#ash#bash#g' package/base-files/files/etc/passwd
sed -i '\#export ENV=/etc/shinit#a export HISTCONTROL=ignoredups' package/base-files/files/etc/profile
mkdir -p files/root
curl -so files/root/.bash_profile https://$mirror/openwrt/files/root/.bash_profile
curl -so files/root/.bashrc https://$mirror/openwrt/files/root/.bashrc

# rootfs files
mkdir -p files/etc/sysctl.d
curl -so files/etc/sysctl.d/15-vm-swappiness.conf https://$mirror/openwrt/files/etc/sysctl.d/15-vm-swappiness.conf
if [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ]; then
    # fix E1187: Failed to source defaults.vim
    touch files/root/.vimrc
fi

# coreutils
if [ "$version" = "rc" ]; then
    rm -rf feeds/packages/utils/coreutils
    cp -a ../master/packages/utils/coreutils feeds/packages/utils/coreutils
fi

# xfsprogs - 6.2.0
if [ "$version" = "rc" ]; then
    rm -rf feeds/packages/utils/xfsprogs
    git clone git@github.com:sbwml/packages_utils_xfsprogs package/xfsprogs
fi

# NTP
sed -i 's/0.openwrt.pool.ntp.org/time.cloud.tencent.com/g' package/base-files/files/bin/config_generate
sed -i 's/1.openwrt.pool.ntp.org/ntp.aliyun.com/g' package/base-files/files/bin/config_generate
sed -i 's/2.openwrt.pool.ntp.org/ntp.tuna.tsinghua.edu.cn/g' package/base-files/files/bin/config_generate
sed -i 's/3.openwrt.pool.ntp.org/time.apple.com/g' package/base-files/files/bin/config_generate

#############

# drop antfs
rm -rf feeds/packages/kernel/antfs feeds/packages/utils/antfs-mount

# uqmi - fix gcc11
[ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ] && sed -i '/dangling-pointer/d' package/network/utils/uqmi/Makefile
