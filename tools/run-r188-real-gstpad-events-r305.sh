#!/bin/sh
# R305: isolated, source-pinned real GStreamer 1.24 GstPad event regression.
# No apt install, service restart, LG/SSH/media output or system registry edit.
# Downloads only 2 development .deb files into a private /tmp directory,
# extracts headers there, builds original R188 lab plugin with a separate
# explicitly NON-DTS-conformant R304 test double, runs 8 real GstPad cases.
set -eu
umask 077
LC_ALL=C;export LC_ALL
for tool in curl sha256sum gcc dpkg-deb mktemp timeout grep; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "R305_BLOCKED_MISSING_TOOL=$tool";exit 2;
    }
done
original=/opt/gamefree24-vps-mcp/src
work=$(mktemp -d /tmp/aleks-dts-r305.XXXXXX) || exit 2
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/native" "$work/asan" "$work/sdk"

curl -fLsS --retry 1 --connect-timeout 8 --max-time 28 \
  https://archive.ubuntu.com/ubuntu/pool/main/g/gstreamer1.0/libgstreamer1.0-dev_1.24.2-1ubuntu0.2_amd64.deb \
  -o "$work/gst.deb"
curl -fLsS --retry 1 --connect-timeout 8 --max-time 28 \
  https://archive.ubuntu.com/ubuntu/pool/main/g/glib2.0/libglib2.0-dev_2.80.0-6ubuntu3.10_amd64.deb \
  -o "$work/glib.deb"
printf '%s  %s\n' \
 '616dab4dbd89fb66dda41e5195c5890ddce0b1c9d467d649cf3f7773d46165a8' "$work/gst.deb" \
 '6d1d88d68192256603c0de05d084b8ef06ed9b16753215ec2c1ef9ef5fa15014' "$work/glib.deb" |
 sha256sum -c -
dpkg-deb -x "$work/gst.deb" "$work/sdk"
dpkg-deb -x "$work/glib.deb" "$work/sdk"

[ -f "$original/r188_dts_framer.h" ] &&
[ -f "$original/r188_gst_framer.c" ] || {
    echo R305_BLOCKED_ORIGINAL_SOURCE_MISSING;exit 2;
}
cp "$original/r188_dts_framer.h" "$work/r188_dts_framer.h"
cp "$original/r188_gst_framer.c" "$work/r188_gst_framer.c"
curl -fLsS --connect-timeout 8 --max-time 25 \
 https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/aaf24680c3985d5235edbd6c814d598c1d8fafb6/tools/r304-synthetic-r122-test-double.h \
 -o "$work/r122_dts_core_probe.h"
curl -fLsS --connect-timeout 8 --max-time 25 \
 https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/f81b2d08f8cd7b469005353de994b137b84c8429/tools/test-r188-real-gstpad-events-r305.c \
 -o "$work/test-r305.c"
printf '%s  %s\n' \
 '8fcf17dd9d9890d26542f093a87f91e760e8ea8999619e17b4e56485b04bfa97' "$work/r188_dts_framer.h" \
 '773aea865d8b49c36b7cf72b8baf56db5615670b80776622b1e5e23ca0146a52' "$work/r188_gst_framer.c" \
 '977f09779d5a3801aca383c876da0d6fe173acfc21823e55f4e9bed3967796fd' "$work/r122_dts_core_probe.h" \
 '935c03e126514559df70642079c859e94abf6f3548d634f1fbe89b7a5af3c0bf' "$work/test-r305.c" |
 sha256sum -c -
echo 'R305_SDK_AND_SOURCE_PIN_PASS'

include="-I$work -I$work/sdk/usr/include/gstreamer-1.0 -I$work/sdk/usr/include/glib-2.0 -I$work/sdk/usr/lib/x86_64-linux-gnu/glib-2.0/include"
libs="-l:libgstreamer-1.0.so.0 -l:libgobject-2.0.so.0 -l:libglib-2.0.so.0"

# Intentional word splitting of trusted, entirely local hardcoded compiler flags.
gcc -std=c11 -O2 -g -Wall -Wextra -Werror -fPIC -shared $include \
  "$work/r188_gst_framer.c" -o "$work/native/libgstaleksdtsr188framer.so" \
  -Wl,--no-undefined $libs
gcc -std=c11 -O2 -g -Wall -Wextra -Werror $include \
  "$work/test-r305.c" -o "$work/native/r305-test" $libs
GST_REGISTRY_FORK=no GST_REGISTRY="$work/native/registry.bin" \
GST_PLUGIN_PATH="$work/native" \
  timeout 18 "$work/native/r305-test" "$work/native/libgstaleksdtsr188framer.so" \
  > "$work/native/results.log" 2>&1
[ "$(grep -c '^R305_.*_PASS$' "$work/native/results.log")" -eq 8 ]
grep -q '^RESULT=R305_GSTPAD_EVENTS_8_OF_8_PASS$' "$work/native/results.log"
echo 'R305_GSTREAMER_NATIVE_O2_8_OF_8_PASS'

gcc -std=c11 -O1 -g -Wall -Wextra -Werror -fPIC -shared \
  -fsanitize=address,undefined -fno-omit-frame-pointer $include \
  "$work/r188_gst_framer.c" -o "$work/asan/libgstaleksdtsr188framer.so" \
  -Wl,--no-undefined $libs
gcc -std=c11 -O1 -g -Wall -Wextra -Werror \
  -fsanitize=address,undefined -fno-omit-frame-pointer $include \
  "$work/test-r305.c" -o "$work/asan/r305-test" $libs
# Forkless scanning keeps sanitized plugin loading inside the sanitized
# main process. Leak detection is off for GLib/GStreamer global allocations;
# ASan and UBSan error detection and abort remain enabled.
ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
GST_REGISTRY_FORK=no GST_REGISTRY="$work/asan/registry.bin" \
GST_PLUGIN_PATH="$work/asan" \
  timeout 18 "$work/asan/r305-test" "$work/asan/libgstaleksdtsr188framer.so" \
  > "$work/asan/results.log" 2>&1
[ "$(grep -c '^R305_.*_PASS$' "$work/asan/results.log")" -eq 8 ]
grep -q '^RESULT=R305_GSTPAD_EVENTS_8_OF_8_PASS$' "$work/asan/results.log"
echo 'R305_GSTREAMER_ASAN_UBSAN_8_OF_8_PASS'
echo 'RESULT=R305_REAL_GSTPAD_EVENT_QA_PASS; SYNTHETIC_HEADER_NO_REAL_DTS_NO_LG'
