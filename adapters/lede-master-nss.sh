#!/usr/bin/env bash
# Hardware-only adaptation of the pinned LEDE native ZN-M2 profile.
set -euo pipefail
"${PYTHON:-python3}" - "${1:?usage: lede-master-nss.sh SOURCE_ROOT}" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1]) / 'target/linux/qualcommax'
def require(condition, message):
    if not condition:
        raise ValueError(message)

def read(name):
    return (root / name).read_text()
try:
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
    changes = {}
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
    if marker not in board:
        board += suffix
    else:
        require(board.endswith(suffix), 'source contract failed: board.endswith(suffix)')
    changes['dts/ipq6018-m2.dts'] = board
except (OSError, ValueError, AttributeError) as error:
    sys.exit('Unsupported LEDE source layout: ' + str(error))
for name, content in changes.items():
    (root / name).write_text(content)
PY
