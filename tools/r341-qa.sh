#!/usr/bin/env bash
# R341: host-only virtual-pad GStreamer proof. Does NOT access LG/ALSA/uMS.
set -euo pipefail
srcdir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
command -v pkg-config >/dev/null
pkg-config --exists gstreamer-1.0
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aleks-r341-qa.XXXXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
cc="${CC:-cc}"
read -r -a gst_cflags <<< "$(pkg-config --cflags gstreamer-1.0)"
read -r -a gst_libs <<< "$(pkg-config --libs gstreamer-1.0)"
common=(-std=c11 -Wall -Wextra -Werror -pedantic -fno-omit-frame-pointer)
"$cc" "${common[@]}" -O2 "${gst_cflags[@]}" \
  "$srcdir/r341-gst-grant-bridge.c" \
  "$srcdir/r341-gst-grant-bridge-qa.c" \
  "${gst_libs[@]}" -o "$tmp/r341-normal"
"$tmp/r341-normal"
"$cc" "${common[@]}" -O1 -g -fsanitize=address,undefined \
  "${gst_cflags[@]}" "$srcdir/r341-gst-grant-bridge.c" \
  "$srcdir/r341-gst-grant-bridge-qa.c" "${gst_libs[@]}" -o "$tmp/r341-sanitized"
ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1 "$tmp/r341-sanitized"
printf 'R341_HOST_NORMAL_AND_ASAN_UBSAN=PASS\n'