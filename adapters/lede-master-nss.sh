#!/usr/bin/env bash
# Hardware-only adaptation of the pinned LEDE native ZN-M2 profile.
set -euo pipefail
"${PYTHON:-python3}" - "${1:?usage: lede-master-nss.sh SOURCE_ROOT}" "$(cd "$(dirname "$0")/.." && pwd)" <<'PY'
import hashlib, pathlib, re, sys
source_root = pathlib.Path(sys.argv[1])
root = source_root / 'target/linux/qualcommax'
def require(condition, message):
    if not condition:
        raise ValueError(message)

def read(name):
    return (root / name).read_text()

# LEDE rewrites the context of the NSS PPPoE-offload patch whenever the kernel
# changes around it: 6.12.114 added a function-name to every hunk header, which
# moves nothing but the bytes. Hash the hunk bodies only, so a pure context
# rewrite does not trip the contract while a real content change still does.
def patch_body_digest(path):
    body = []
    for line in path.read_text().splitlines(keepends=True):
        if line.startswith('@@'):
            body.append(line.split('@@')[2] if line.count('@@') >= 3 else '\n')
        else:
            body.append(line)
    return hashlib.sha256(''.join(body).encode()).hexdigest()

# Content digest of the hunk bodies, per kernel version. The bodies differ
# between 6.12 and 6.18 (6.18 reworks the ppp_generic.c hunk around
# rcu_assign_pointer), so one digest cannot cover both.
NSS_PATCH_BODY_SHA256 = {
    '6.12': '569f43ba5f63fcb8c52cca94fbb57d37bbb47cff993ef63e5a977da98f7a8d16',
    '6.18': '8d48b90e4d30bb1e6863e9c1802fcf67199ac252cd7f0ecd49c80c4fab00fd74',
}
try:
    # LEDE switched qualcommax's default kernel from 6.12 to 6.18 on 2026-11-01
    # and kept 6.12 as the testing target. The NSS patches, and therefore the
    # netdevice layout fix they need, live in a versioned directory, so the
    # adapter has to follow KERNEL_PATCHVER instead of assuming 6.12.
    kernel_line = re.search(r'^KERNEL_PATCHVER:=(\S+)$', read('Makefile'), re.M)
    require(kernel_line is not None, 'KERNEL_PATCHVER is missing from the qualcommax Makefile')
    kernel = kernel_line.group(1)
    require(kernel in NSS_PATCH_BODY_SHA256,
            'unsupported LEDE kernel %s: no NSS patch digest and no netdevice layout fix for it' % kernel)

    # Validate the pinned NSS insertion before any source mutation.
    nss_patch = root / ('patches-%s/0600-2-qca-nss-ecm-support-PPPOE-offload.patch' % kernel)
    require(nss_patch.is_file(), 'missing NSS PPPoE patch for kernel %s: %s' % (kernel, nss_patch))
    actual = patch_body_digest(nss_patch)
    require(actual == NSS_PATCH_BODY_SHA256[kernel],
            'unexpected NSS netdevice insertion patch for %s (body sha256 %s)' % (kernel, actual))

    # The layout fix is version-specific: 6.18 added netmem_tx:1 to the same
    # struct_group, so its hunk context differs from 6.12.
    layout_source = 'patches/lede/9999-netdevice-nss-flags-layout.patch'
    if kernel != '6.12':
        layout_source = layout_source.replace('.patch', '-%s.patch' % kernel)
    layout_path = pathlib.Path(sys.argv[2]) / layout_source
    require(layout_path.is_file(), 'missing netdevice layout patch for kernel %s: %s' % (kernel, layout_source))
    layout_name = 'patches-%s/9999-netdevice-nss-flags-layout.patch' % kernel
    layout = layout_path.read_text()
    require(not (root / layout_name).exists() or read(layout_name) == layout, 'conflicting netdevice layout patch')
    # Linux 6.12 builds external modules with -Wmissing-prototypes -Werror, so
    # qca-mcs must see its own init/exit prototypes before defining them.
    mcs_patch_name = '0003-fix-missing-netfilter-prototypes.patch'
    mcs_dir = source_root / 'package/qca/qca-mcs'
    mcs_patch = (pathlib.Path(sys.argv[2]) / 'patches/lede/9999-qca-mcs-netfilter-prototypes.patch').read_text()
    require((mcs_dir / 'Makefile').is_file() and (mcs_dir / 'patches').is_dir(), 'source contract failed: qca-mcs package missing')
    require('PKG_SOURCE_VERSION:=8797823e392ac3d9098c090964afd46805a0eb2b' in (mcs_dir / 'Makefile').read_text(), 'source contract failed: unexpected qca-mcs source version')
    # Linux 6.16 renamed try_to_del_timer_sync() to timer_delete_sync_try()
    # with identical semantics. qca-mcs is an out-of-tree module frozen in
    # 2023, so it needs the old name mapped forward on 6.16 and newer.
    mcs_timer_patch_name = '0004-fix-timer-delete-sync-try.patch'
    mcs_timer_patch = (pathlib.Path(sys.argv[2]) / 'patches/lede/9999-qca-mcs-timer-delete-sync-try.patch').read_text()
    board = read('dts/ipq6018-m2.dts')
    base = read('dts/ipq6018-cmiot.dtsi')
    ram = read('dts/ipq6018-256m.dtsi')
    nss = read('dts/ipq6018-nss.dtsi')
    image = read('image/ipq60xx.mk')
    profile = re.search(r'define Device/zn_m2\n(.*?)\nendef', image, re.S).group(1)
    require(all(x in profile for x in ['Device/FitImage', 'Device/UbiFit', 'ipq6018-m2']), "source contract failed: all(x in profile for x in ['Device/FitImage', 'Device/UbiFit', 'ipq6018-m2'])")
    require('"zn,m2", "qcom,ipq6018"' in board, 'source contract failed: \'"zn,m2", "qcom,ipq6018"\' in board')
    require('#include "ipq6018-cmiot.dtsi"' in board, 'source contract failed: \'#include "ipq6018-cmiot.dtsi"\' in board')
    require(all(x in base for x in ['ipq6018-256m.dtsi', 'ipq6018-nss.dtsi']), "source contract failed: all(x in base for x in ['ipq6018-256m.dtsi', 'ipq6018-nss.dtsi'])")
    require('&q6_region' in ram and '0x4ab00000 0x0 0x2800000' in ram, "source contract failed: '&q6_region' in ram and '0x4ab00000 0x0 0x2800000' in ram")
    require('memory-region = <&nss_region>' in nss, "source contract failed: 'memory-region = <&nss_region>' in nss")
    changes = {layout_name: layout}
    require(not (mcs_dir / 'patches' / mcs_patch_name).exists() or (mcs_dir / 'patches' / mcs_patch_name).read_text() == mcs_patch, 'conflicting qca-mcs prototype patch')
    package_changes = {'patches/' + mcs_patch_name: mcs_patch}
    # The timer shim is guarded by LINUX_VERSION_CODE >= 6.16 inside the
    # header, so installing it on 6.12 too keeps the tree identical across
    # kernels and makes the patch contract simpler to assert.
    require(not (mcs_dir / 'patches' / mcs_timer_patch_name).exists() or
            (mcs_dir / 'patches' / mcs_timer_patch_name).read_text() == mcs_timer_patch,
            'conflicting qca-mcs timer patch')
    package_changes['patches/' + mcs_timer_patch_name] = mcs_timer_patch
    packages = "\tDEVICE_PACKAGES += -kmod-ath11k-ahb -wpad-openssl -kmod-usb3 -kmod-usb-dwc3 -kmod-usb-dwc3-qcom"
    if packages not in profile:
        require('DEVICE_PACKAGES' not in profile, 'unexpected ZN-M2 package override')
        image = image.replace('define Device/zn_m2\n' + profile + '\nendef', 'define Device/zn_m2\n' + profile + '\n' + packages + '\nendef', 1)
    changes['image/ipq60xx.mk'] = image
    netpath = 'ipq60xx/base-files/etc/board.d/02_network'
    net = read(netpath)
    anchor = '\tcase "$board" in\n'
    addition = '\tzn,m2)\n\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"\n\t\t;;\n'
    if addition not in net:
        require('zn,m2' not in net and anchor in net, "source contract failed: 'zn,m2' not in net and anchor in net")
        net = net.replace(anchor, anchor + addition, 1)
    changes[netpath] = net
    # LEDE ships no zn,m2 LED arm, so only the power LED lights up. Its DTS uses
    # the m2:blue: prefix, not the blue: prefix ImmortalWrt and FanchmWrt use.
    ledpath = 'ipq60xx/base-files/etc/board.d/01_leds'
    leds = read(ledpath)
    anchor = 'case "$board" in\n'
    addition = ('zn,m2)\n'
                '\tucidef_set_led_netdev "lan" "LAN" "m2:blue:lan" "br-lan"\n'
                '\tucidef_set_led_netdev "wan" "WAN" "m2:blue:wan" "wan"\n'
                '\t;;\n')
    if addition not in leds:
        require('zn,m2' not in leds and anchor in leds, "source contract failed: 01_leds has no free case anchor")
        leds = leds.replace(anchor, anchor + addition, 1)
    changes[ledpath] = leds
    uppath = 'ipq60xx/base-files/lib/upgrade/platform.sh'
    up = read(uppath)
    anchor = '\tcase "$(board_name)" in\n'
    addition = '\tzn,m2)\n\t\tCI_UBIPART="rootfs"\n\t\tnand_do_upgrade "$1"\n\t\t;;\n'
    if addition not in up:
        require('zn,m2' not in up and anchor in up, "source contract failed: 'zn,m2' not in up and anchor in up")
        up = up.replace(anchor, anchor + addition, 1)
    changes[uppath] = up
    marker = '// ZN-M2 wired-only hardware profile'
    suffix = '\n' + marker + '\n&q6_region { reg = <0x0 0x4ab00000 0x0 0x1000000>; };\n'
    for label in ['wifi', 'usb2', 'usb3', 'qusb_phy_0', 'qusb_phy_1', 'ssphy_0']:
        require('&' + label in base, "source contract failed: '&' + label in base")
        suffix += '&' + label + ' { status = "disabled"; };\n'
    # The shared cmiot dtsi labels phy0 as lan1 and phy3 as lan3. On the ZN-M2
    # panel phy3 is the port next to WAN, so the two labels are swapped. Only
    # the label is wrong: qcom,id and every phy-handle stay untouched.
    for node, label in (('dp2', 'lan3'), ('dp4', 'lan1')):
        require('&' + node + ' {' in base, "source contract failed: '&' + node + ' {' in base")
        suffix += '&%s { label = "%s"; };\n' % (node, label)
    if marker not in board:
        board += suffix
    else:
        require(board.endswith(suffix), 'source contract failed: board.endswith(suffix)')
    changes['dts/ipq6018-m2.dts'] = board
except (OSError, ValueError, AttributeError) as error:
    sys.exit('Unsupported LEDE source layout: ' + str(error))
for name, content in changes.items():
    (root / name).write_text(content)
for name, content in package_changes.items():
    target = mcs_dir / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content.encode())
PY
