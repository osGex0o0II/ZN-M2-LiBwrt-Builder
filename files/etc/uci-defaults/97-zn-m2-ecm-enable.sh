#!/bin/sh
# Some upstreams (LEDE) install qca-nss-ecm without registering the service, so
# ECM never loads and NSS offload stays inactive even though the driver is up.
[ -x /etc/init.d/qca-nss-ecm ] || exit 0
/etc/init.d/qca-nss-ecm enable

# LEDE orders qca-nss-drv at S70 but the ECM package registers S19, so ECM runs
# before the driver exists and fails silently. Run it once everything is up.
for link in /etc/rc.d/S*qca-nss-ecm; do
	[ -L "$link" ] && rm -f "$link"
done
ln -sf ../init.d/qca-nss-ecm /etc/rc.d/S99qca-nss-ecm
exit 0
