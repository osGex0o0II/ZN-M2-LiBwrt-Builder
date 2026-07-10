#!/bin/sh
set -eu

if [ "$#" -ne 1 ] || [ ! -r "$1" ]; then
	echo "usage: $0 /path/to/qca-nss-drv.ko" >&2
	exit 2
fi
if ! command -v readelf >/dev/null 2>&1; then
	echo "ERROR: readelf is required for NSS driver symbol validation" >&2
	exit 2
fi

module="$1"
defined="$(mktemp)"
forbidden="${defined}.forbidden"
trap 'rm -f "$defined" "$forbidden"' EXIT HUP INT TERM

LC_ALL=C readelf --wide --symbols "$module" |
	awk '$5 == "GLOBAL" && $7 != "UND" { print $8 }' > "$defined"

forbidden_pattern='^(nss_(pptp|l2tpv2|gre|crypto)_|nss_(register|unregister)_(pptp|l2tpv2)_if$)'
if grep -E "$forbidden_pattern" "$defined" > "$forbidden"; then
	echo "ERROR: qca-nss-drv.ko still defines a disabled tunnel or crypto symbol" >&2
	cat "$forbidden" >&2
	exit 1
fi

echo "NSS driver symbols verified: PPTP/L2TP/GRE/crypto absent"
