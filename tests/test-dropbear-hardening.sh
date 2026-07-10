#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PATCH_PATH="package/network/services/dropbear/patches/600-allow-blank-root-password.patch"
mkdir -p "$TMP_DIR/target/linux/qualcommax" "$TMP_DIR/$(dirname "$PATCH_PATH")"
cat > "$TMP_DIR/target/linux/qualcommax/Makefile" <<'EOF'
KERNEL_PATCHVER:=6.12
EOF

write_upstream_patch() {
	patch_context=" "
	tab="$(printf '\t')"
	trailing_space=" "
	cat > "$TMP_DIR/$PATCH_PATH" <<EOF
--- a/src/svr-auth.c
+++ b/src/svr-auth.c
@@ -122,7 +122,7 @@ void recv_msg_userauth_request() {
${patch_context}${tab}${tab}${tab}${tab}AUTH_METHOD_NONE_LEN) == 0) {
${patch_context}${tab}${tab}TRACE(("recv_msg_userauth_request: 'none' request"))
${patch_context}${tab}${tab}if (valid_user
-${tab}${tab}${tab}${tab}&& svr_opts.allowblankpass
+${tab}${tab}${tab}${tab}&& (svr_opts.allowblankpass || !strcmp(ses.authstate.pw_name, "root"))
${patch_context}${tab}${tab}${tab}${tab}&& !svr_opts.noauthpass
${patch_context}${tab}${tab}${tab}${tab}&& !(svr_opts.norootpass && ses.authstate.pw_uid == 0)${trailing_space}
${patch_context}${tab}${tab}${tab}${tab}&& ses.authstate.pw_passwd[0] == '\0')${trailing_space}
EOF
}

run_hardening() {
	(
		cd "$TMP_DIR"
		awk '
			/^remove_blank_root_ssh_patch$/ { print; exit }
			{ print }
		' "$ROOT_DIR/libwrt.sh" | bash >/dev/null
	)
}

write_upstream_patch
run_hardening
if [ -e "$TMP_DIR/$PATCH_PATH" ]; then
	echo "FAIL: blank-password root SSH patch was not removed" >&2
	exit 1
fi

write_upstream_patch
printf '%s\n' '# unaudited change' >> "$TMP_DIR/$PATCH_PATH"
if run_hardening 2>/dev/null; then
	echo "FAIL: changed blank-root patch bypassed SHA256 validation" >&2
	exit 1
fi

echo "Dropbear authentication hardening tests passed"
