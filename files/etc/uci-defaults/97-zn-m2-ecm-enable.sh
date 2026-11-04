#!/bin/sh
# Some upstreams (LEDE) install qca-nss-ecm without registering the service, so
# ECM never loads and NSS offload stays inactive even though the driver is up.
#
# The rc.d scan happens before uci-defaults run, so enabling here only takes
# effect on the next boot. Start the service now as well to cover this boot.
[ -x /etc/init.d/qca-nss-ecm ] || exit 0
/etc/init.d/qca-nss-ecm enable
/etc/init.d/qca-nss-ecm start
exit 0
