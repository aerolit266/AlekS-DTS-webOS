#!/bin/sh
# R329: reproducible off-TV ARMv7 EABI soft-float standalone GStreamer probe.
# Requires a verified ARMEL libgstreamer/libgobject/libglib reference directory.
# Does not install or execute anything on LG. Uses a private temporary SDK.
set -eu
umask 077
LC_ALL=C
export LC_ALL
[ "$#" -eq 2 ] && [ "$1" = "--build" ] || {
    echo 'R329_USAGE=R329_REFERENCE_LIBDIR=/verified/armel/lib sh tools/build-r329-armel-pad-probe-lab.sh --build /tmp/aleks-r329-ARM-OUT'
    exit 2
}
dest=$2
case "$dest" in /tmp/aleks-r329-*) : ;; *) echo R329_BAD_OUTPUT_PATH; exit 2;; esac
[ ! -L "$dest" ] || { echo R329_OUTPUT_SYMLINK_REFUSED;exit 2; }
[ -n "$R329_REFERENCE_LIBDIR" ] || { echo R329_NO_REFERENCE_LIBRARY_DIR;exit 2; }
for name in libgstreamer-1.0.so.0 libgobject-2.0.so.0 libglib-2.0.so.0; do
    [ -f "$R329_REFERENCE_LIBDIR/$name" ] || {
        echo "R329_MISSING_REFERENCE_LIBRARY=$name"
        exit 2
    }
done
for tool in sha256sum curl dpkg-deb mktemp arm-linux-gnueabi-gcc arm-linux-gnueabi-readelf; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "R329_MISSING_TOOL=$tool"
        exit 2
    }
done
here=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
source="$here/tools/r329-isolated-gst-pad-probe.c"
printf '%s  %s\n' \
4ec7c59cff56df8a22ca6b88cb17d765064ccf500ea845ffe211796a1a5d2070 "$source" |
    sha256sum -c - >/dev/null
echo R329_PROBE_SOURCE_PIN_PASS
[ ! -e "$dest/r329-pad-probe" ] && [ ! -L "$dest/r329-pad-probe" ] || {
    echo R329_REFUSE_OUTPUT_OVERWRITE
    exit 2
}
work=$(mktemp -d /tmp/aleks-r329-arm-sdk.XXXXXX)
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT
trap 'exit 2' HUP INT TERM
curl -fLsS --proto '=https' --proto-redir '=https' \
    --connect-timeout 8 --max-time 48 \
    'https://ports.ubuntu.com/ubuntu-ports/pool/main/g/gstreamer1.0/libgstreamer1.0-dev_1.24.2-1ubuntu0.2_armhf.deb' \
    -o "$work/gst.deb"
curl -fLsS --proto '=https' --proto-redir '=https' \
    --connect-timeout 8 --max-time 48 \
    'https://deb.debian.org/debian/pool/main/g/glib2.0/libglib2.0-dev_2.74.6-2+deb12u9_armel.deb' \
    -o "$work/glib.deb"
printf '%s  %s\n' \
2813892aa616ead7d499100122fa034872b38ba998dde50fa2f89250f0477f1e "$work/gst.deb" \
1175a6e446f8ea74975ecf709e29a675710a5108becbf28e7c623db971232a8d "$work/glib.deb" |
    sha256sum -c - >/dev/null
echo R329_ARM_SDK_2_OF_2_SHA_PASS
dpkg-deb -x "$work/gst.deb" "$work/gst"
dpkg-deb -x "$work/glib.deb" "$work/glib"
arm-linux-gnueabi-gcc -march=armv7-a -mfloat-abi=soft \
    -std=c11 -O2 -Wall -Wextra -Werror \
    -I"$work/gst/usr/include/gstreamer-1.0" \
    -I"$work/glib/usr/include/glib-2.0" \
    -I"$work/glib/usr/lib/arm-linux-gnueabi/glib-2.0/include" \
    "$source" \
    -L"$R329_REFERENCE_LIBDIR" \
    -Wl,--no-undefined -Wl,-rpath-link="$R329_REFERENCE_LIBDIR" \
    -l:libgstreamer-1.0.so.0 -l:libgobject-2.0.so.0 \
    -l:libglib-2.0.so.0 -lm \
    -o "$work/r329-pad-probe"
arm-linux-gnueabi-readelf -h "$work/r329-pad-probe" |
    grep -q 'Class:.*ELF32'
arm-linux-gnueabi-readelf -h "$work/r329-pad-probe" |
    grep -q 'Machine:.*ARM'
arm-linux-gnueabi-readelf -h "$work/r329-pad-probe" |
    grep -q 'EABI, soft-float ABI'
arm-linux-gnueabi-readelf -A "$work/r329-pad-probe" |
    grep -q 'Tag_CPU_arch: v7'
if arm-linux-gnueabi-readelf -A "$work/r329-pad-probe" |
    grep -q 'Tag_ABI_VFP_args'; then
    echo R329_UNEXPECTED_HARDFLOAT
    exit 2
fi
echo R329_ARM32_SOFTFLOAT_ABI_PASS
mkdir -p "$dest"
chmod 0700 "$dest"
cp "$work/r329-pad-probe" "$dest/r329-pad-probe"
chmod 0700 "$dest/r329-pad-probe"
echo "R329_ARM_BINARY_BYTES=$(wc -c < "$dest/r329-pad-probe" | tr -d ' ')"
echo "R329_ARM_BINARY_SHA256=$(sha256sum "$dest/r329-pad-probe" | awk '{print $1}')"
echo R329_LG_SYSTEM_OR_SERVICES_MODIFIED=NO
echo RESULT=R329_REPRODUCIBLE_ARM_BUILD_PASS
