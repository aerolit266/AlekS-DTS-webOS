#!/bin/sh
# R324: isolated official R278 libdcadec first-frame and multi-frame QA.
# Uses ONLY public SHA256-pinned LGPL source/archive. No apt/install, TV,
# speaker access, decoded PCM storage, service or firmware changes.
set -eu
umask 077
LC_ALL=C
export LC_ALL
for tool in sha256sum tar gcc make ffmpeg mktemp timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "R324_MISSING_DEPENDENCY=$tool"
        exit 2
    }
done
here=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
release="$here/downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz"
relink="$here/downloads/r278/R278-R56-LGPL-RELINK.tar.gz"
src="$here/tools/r324-libdcadec-packet-cardinality.c"
[ -f "$src" ] && [ -f "$release" ] && [ -f "$relink" ] || {
    echo R324_MISSING_RELEASE_FILE
    exit 2
}
printf '%s  %s\n' \
    cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1 "$release" \
    2723b1cd09b50df367161e5acff6d1d622c76856592c907d79ef606380c98ccf "$relink" |
    sha256sum -c - >/dev/null
echo R324_IMMUTABLE_RELEASE_SOURCES=PASS
tmp=$(mktemp -d /tmp/aleks-r324-dcadec.XXXXXX)
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT
trap 'exit 2' HUP INT TERM
tar -xzf "$relink" -C "$tmp" dcadec
timeout 65 make -s -C "$tmp/dcadec" -j2 lib >"$tmp/compile.log" 2>&1 || {
    echo R324_LIBDCADEC_BUILD_FAIL
    exit 2
}
echo R324_LIBDCADEC_BUILD_PASS
tar -xOzf "$release" fixtures/dts-stereo.mka >"$tmp/dts-stereo.mka"
printf '%s  %s\n' \
    7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae \
    "$tmp/dts-stereo.mka" | sha256sum -c - >/dev/null
timeout 15 ffmpeg -hide_banner -loglevel error -nostdin \
    -i "$tmp/dts-stereo.mka" -map 0:a:0 -c:a copy -f dts "$tmp/dts-encoded.raw"
gcc -std=c11 -O2 -Wall -Wextra -Werror \
    -I"$tmp/dcadec" "$src" "$tmp/dcadec/libdcadec/libdcadec.a" \
    -lm -o "$tmp/probe"
timeout 15 "$tmp/probe" "$tmp/dts-encoded.raw"
echo R324_LAB_ISOLATED_ONLY=PASS
