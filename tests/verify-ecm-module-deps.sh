#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ ! -r "$1" ]; then
	echo "usage: $0 /path/to/ecm.ko [required-only|pppoe-only]" >&2
	exit 2
fi

module="$1"
profile="${2:-pppoe-only}"
case "$profile" in
	required-only|pppoe-only) ;;
	*)
		echo "usage: $0 /path/to/ecm.ko [required-only|pppoe-only]" >&2
		exit 2
		;;
esac

depends=""
if command -v modinfo >/dev/null 2>&1; then
	depends="$(modinfo -F depends "$module" 2>/dev/null || true)"
fi
if [ -z "$depends" ]; then
	depends="$(strings "$module" | sed -n 's/^depends=//p' | head -n 1)"
fi
depends="$(printf '%s' "$depends" | tr -d '[:space:]')"

if [ -z "$depends" ]; then
	echo "ERROR: Could not read the ecm.ko dependency list" >&2
	exit 1
fi

has_dependency() {
	case ",$depends," in
		*",$1,"*) return 0 ;;
		*) return 1 ;;
	esac
}

if [ "$profile" = pppoe-only ]; then
	for forbidden in pptp l2tp_ppp; do
		if has_dependency "$forbidden"; then
			echo "ERROR: ecm.ko still depends on forbidden tunnel module: ${forbidden}" >&2
			exit 1
		fi
	done
fi

for required in ppp_generic pppoe; do
	if ! has_dependency "$required"; then
		echo "ERROR: ecm.ko lost required PPPoE dependency: ${required}" >&2
		exit 1
	fi
done

echo "ecm.ko dependencies verified: $depends"
