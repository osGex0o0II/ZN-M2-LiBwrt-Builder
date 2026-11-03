#!/bin/sh
# Some upstreams (LEDE) install qca-nss-ecm without registering the service, so
# ECM never loads and NSS offload stays inactive even though the driver is up.
[ -x /etc/init.d/qca-nss-ecm ] || exit 0
/etc/init.d/qca-nss-ecm enable
exit 0
