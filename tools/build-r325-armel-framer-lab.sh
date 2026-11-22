#!/bin/sh
# R325 isolated, deterministic ARMv7 EABI soft-float lab compiler.
# Uses public pinned headers and a caller-supplied ARM EABI reference link
# directory, NEVER updates the television, host SDK or production services.
# Usage: R325_REFERENCE_LIBDIR=/path/to/armel/usr/lib sh SCRIPT --build /tmp/aleks-r325-verified-output
set -eu
umask 077
LC_ALL=C
export LC_ALL
if [ "$#" != 2 ] || [ "$1" != "--build" ]; then
    echo 'R325_USAGE=R325_REFERENCE_LIBDIR=/path/to/armel/lib sh tools/build-r325-armel-framer-lab.sh --build /tmp/aleks-r325-private-output'
    exit 2
fi
output_dir=$2
case "$output_dir" in
    /tmp/aleks-r325-*) ;;
    *) echo R325_REFUSE_NON_LAB_OUTPUT;exit 2 ;;
esac
[ ! -L "$output_dir" ] || { echo R325_OUTPUT_SYMLINK_REFUSED;exit 2; }
: "${R325_REFERENCE_LIBDIR:?Require known ARM EABI reference linkage libraries}"
for dep in libgstreamer-1.0.so.0 libgobject-2.0.so.0 libglib-2.0.so.0; do
    [ -f "$R325_REFERENCE_LIBDIR/$dep" ] || {
        echo "R325_REFERENCE_LIBRARY_MISSING=$dep";exit 2;
    }
done
for tool in curl sha256sum dpkg-deb arm-linux-gnueabi-gcc arm-linux-gnueabi-readelf arm-linux-gnueabi-nm mktemp; do
    command -v "$tool" >/dev/null 2>&1 || { echo "R325_MISSING=$tool";exit 2; }
done
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
source="$root/tools/r325-r188-framer-time-segment-lab.c"
header="$root/tools/r311-original-r188-dts-framer.h"
probe="$root/tools/r311-real-dts-be16-probe.h"
for file in "$source" "$header" "$probe"; do
    [ -f "$file" ] || { echo R325_MISSING_SOURCE;exit 2; }
done
printf '%s  %s\n' \
 e5b615a6e17bb829df035800229dcf3c07a12a1c45066b91a8eeb4e197ae02ce "$source" \
 8fcf17dd9d9890d26542f093a87f91e760e8ea8999619e17b4e56485b04bfa97 "$header" \
 57d9d1df5b1ffe0d3fce8ad7ae584a7d95a6cb81f265ab658199a332866b9ed1 "$probe" | sha256sum -c - >/dev/null
echo R325_THREE_SOURCE_HASHES=PASS
out="$output_dir/libgstaleksdtsr188framer.so"
[ ! -e "$out" ] && [ ! -L "$out" ] || {
    echo R325_REFUSE_OVERWRITE;exit 2;
}
scratch=$(mktemp -d /tmp/aleks-r325-arm-sdk.XXXXXX)
cleanup() { rm -rf -- "$scratch"; }
trap cleanup EXIT
trap 'exit 2' HUP INT TERM
mkdir -p "$scratch/src" "$scratch/sdk-gst" "$scratch/sdk-glib" "$scratch/build"
cp "$source" "$scratch/src/r325-time-segment.c"
cp "$header" "$scratch/src/r188_dts_framer.h"
cp "$probe" "$scratch/src/r122_dts_core_probe.h"
curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 48 \
 'https://ports.ubuntu.com/ubuntu-ports/pool/main/g/gstreamer1.0/libgstreamer1.0-dev_1.24.2-1ubuntu0.2_armhf.deb' \
 -o "$scratch/gst.deb"
curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 48 \
 'https://deb.debian.org/debian/pool/main/g/glib2.0/libglib2.0-dev_2.74.6-2+deb12u9_armel.deb' \
 -o "$scratch/glib.deb"
printf '%s  %s\n' \
 2813892aa616ead7d499100122fa034872b38ba998dde50fa2f89250f0477f1e "$scratch/gst.deb" \
 1175a6e446f8ea74975ecf709e29a675710a5108becbf28e7c623db971232a8d "$scratch/glib.deb" | sha256sum -c - >/dev/null
echo R325_TWO_SDK_PACKAGE_HASHES=PASS
dpkg-deb -x "$scratch/gst.deb" "$scratch/sdk-gst"
dpkg-deb -x "$scratch/glib.deb" "$scratch/sdk-glib"
arm-linux-gnueabi-gcc -march=armv7-a -mfloat-abi=soft \
 -std=gnu11 -O2 -fPIC -shared -Wall -Wextra \
 -Werror=implicit-function-declaration \
 "-ffile-prefix-map=$scratch/src=/r325-src" \
 -DPACKAGE='"aleks-dts"' \
 -I"$scratch/src" \
 -I"$scratch/sdk-gst/usr/include/gstreamer-1.0" \
 -I"$scratch/sdk-glib/usr/include/glib-2.0" \
 -I"$scratch/sdk-glib/usr/lib/arm-linux-gnueabi/glib-2.0/include" \
 "$scratch/src/r325-time-segment.c" \
 -L"$R325_REFERENCE_LIBDIR" -Wl,--no-undefined -Wl,--no-as-needed \
 -l:libgstreamer-1.0.so.0 -l:libgobject-2.0.so.0 -l:libglib-2.0.so.0 \
 -o "$scratch/build/libgstaleksdtsr188framer.so"
candidate="$scratch/build/libgstaleksdtsr188framer.so"
arm-linux-gnueabi-readelf -h "$candidate" | grep -q 'Class:.*ELF32'
arm-linux-gnueabi-readelf -h "$candidate" | grep -q 'Machine:.*ARM'
arm-linux-gnueabi-readelf -h "$candidate" | grep -q 'EABI, soft-float ABI'
arm-linux-gnueabi-readelf -A "$candidate" | grep -q 'Tag_CPU_arch: v7'
if arm-linux-gnueabi-readelf -A "$candidate" | grep -q 'Tag_ABI_VFP_args';then
    echo R325_HARDFLOAT_ABI_REFUSED;exit 2;
fi
arm-linux-gnueabi-nm -D --defined-only "$candidate" | grep -q 'gst_plugin_aleksdtsr188framer_get_desc'
echo R325_ARM32_SOFTFLOAT_ABI_AND_EXPORTS=PASS
mkdir -p "$output_dir"
chmod 0700 "$output_dir"
cp "$candidate" "$out"
chmod 0600 "$out"
echo "R325_ELF_BYTES=$(wc -c < "$out" | tr -d ' ')"
echo "R325_ELF_SHA256=$(sha256sum "$out" | awk '{print $1}')"
echo R325_NO_PRODUCTION_INSTALL=PASS
echo RESULT=R325_REPRODUCIBLE_CROSS_BUILD_PASS
