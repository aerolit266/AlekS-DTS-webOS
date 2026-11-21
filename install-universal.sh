#!/bin/sh
# AlekS DTS webOS - model/firmware independent installation front-end for R278.
# Copyright 2026 AlekS / GameFree24 (@aerolit266)
# Does not replace platform binaries. Tests plugins in isolation before enabling.
set -eu
umask 077
export LC_ALL=C

url='https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/r278/downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz'
sha='cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1'
installed='/var/lib/webosbrew/aleks-dts-r278/install.sh'

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$#" -eq 1 ] || fail 'Usage: sh install-universal.sh verify | install | rollback'
case "$1" in
    rollback)
        [ "$(id -u)" = 0 ] || fail 'Root SSH is required.'
        [ -f "$installed" ] && [ ! -L "$installed" ] || fail 'Installed rollback script not found.'
        exec sh "$installed" rollback
        ;;
    install|verify) action=$1 ;;
    *) fail 'Usage: sh install-universal.sh verify | install | rollback' ;;
esac

[ "$(id -u)" = 0 ] || fail 'Root SSH is required.'
[ "$(uname -m)" = armv7l ] || fail 'The existing R278 binary plugins are ARMv7-only. This TV requires a separately compiled package.'
for tool in curl sha256sum tar awk grep mktemp sh; do
    command -v "$tool" >/dev/null 2>&1 || fail "Missing tool: $tool"
done

stage=$(mktemp -d /tmp/aleks-dts-universal.XXXXXX) || fail 'Cannot create temporary directory.'
trap 'rm -rf -- "$stage"' EXIT
trap 'exit 1' HUP INT TERM
cd "$stage"

curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 120 \
    -o release.tar.gz "$url" || fail 'Cannot download pinned R278 archive.'
printf '%s  %s\n' "$sha" release.tar.gz | sha256sum -c - || fail 'Archive integrity check failed.'
tar -xmzf release.tar.gz || fail 'Cannot unpack archive.'
[ -f install.sh ] && [ ! -L install.sh ] || fail 'Installer missing from archive.'
grep -Fq "fail 'Unsupported model or firmware.'" install.sh || fail 'Unexpected R278 installer: refusing an unverified patch.'
grep -Fq 'hash 46a353723ec66894596d9ce0822c3f2273422731ad0426fc6ff16beb349162bc /usr/sbin/umediaserver' install.sh ||
    fail 'Unexpected firmware compatibility checks: refusing an unverified patch.'

# Replace only the original platform() gate. All integrity checks for shipped
# plugins, protected systemd configuration and recovery logic remain unchanged.
cat > platform.universal <<'PLATFORM'
platform() {
    [ "$(id -u)" = 0 ] || fail 'Root is required.'
    [ "$(uname -m)" = armv7l ] || fail 'R278 contains ARMv7-only plugins.'
    [ -x /usr/sbin/umediaserver ] || fail 'Native umediaserver is not available.'
    [ -x /usr/sbin/starfish-media-pipeline ] || fail 'Native media pipeline is not available.'
    [ -x /usr/bin/gst-inspect-1.0 ] || fail 'GStreamer inspector is missing.'
    [ -x /usr/bin/gst-launch-1.0 ] || fail 'GStreamer launcher is missing.'
}
PLATFORM

awk -v replacement=platform.universal '
    /^platform\(\) \{$/ {
        seen++
        if (seen != 1) exit 70
        while ((getline line < replacement) > 0) print line
        close(replacement)
        skip=1
        next
    }
    skip && /^}$/ { skip=0; next }
    skip { next }
    { print }
    END { if (seen != 1 || skip) exit 70 }
' install.sh > install.patched || fail 'Cannot patch platform check safely.'
sh -n install.patched || fail 'Patched installer has a shell syntax error.'
if grep -Fq 'Unsupported model or firmware.' install.patched ||
   grep -Fq '46a353723ec66894596d9ce0822c3f2273422731ad0426fc6ff16beb349162bc' install.patched; then
    fail 'Fixed-firmware checks remain after patch.'
fi
mv install.patched install.sh
chmod 0700 install.sh
printf 'AlekS DTS R278 universal: model/firmware gate removed.\n'
printf 'Hardware ABI and DTS/AC3 tests remain mandatory.\n'
sh ./install.sh "$action"
