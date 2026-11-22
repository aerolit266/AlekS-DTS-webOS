#!/bin/sh
# R330: end-to-end isolated host regression for DTS->software AC3->DTS.
# Uses only pinned public DTS/AC3 encoded fixtures, fakesink, an ephemeral
# local GStreamer process and registry. No recording, media service changes
# or codec installation. Intended for an explicitly provisioned GStreamer host.
set -eu
umask 077
LC_ALL=C
export LC_ALL
for tool in curl gcc dpkg-deb sha256sum tar timeout python3 mktemp; do
  command -v "$tool" >/dev/null 2>&1 || { echo "R330_MISSING_TOOL=$tool";exit 2; }
done
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
code="$repo/tools/r330-isolated-dts-ac3-dts-sequence.c"
release="$repo/downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz"
printf '%s  %s\n' \
d47b34303c1adbd91f8c1b5212a46c9b4975138b8195116eb142fe117fe4aeb9 "$code" \
cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1 "$release" |
  sha256sum -c - >/dev/null
echo R330_PINNED_PUBLIC_SOURCES_PASS
work=$(mktemp -d /tmp/aleks-r330-hostqa.XXXXXX)
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT
trap 'exit 2' HUP INT TERM
mkdir -m 700 "$work/sdk" "$work/fixtures"
curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 48 \
 'https://archive.ubuntu.com/ubuntu/pool/main/g/gstreamer1.0/libgstreamer1.0-dev_1.24.2-1ubuntu0.2_amd64.deb' -o "$work/gst.deb"
curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 48 \
 'https://archive.ubuntu.com/ubuntu/pool/main/g/glib2.0/libglib2.0-dev_2.80.0-6ubuntu3.10_amd64.deb' -o "$work/glib.deb"
printf '%s  %s\n' \
616dab4dbd89fb66dda41e5195c5890ddce0b1c9d467d649cf3f7773d46165a8 "$work/gst.deb" \
6d1d88d68192256603c0de05d084b8ef06ed9b16753215ec2c1ef9ef5fa15014 "$work/glib.deb" |
 sha256sum -c - >/dev/null
dpkg-deb -x "$work/gst.deb" "$work/sdk"
dpkg-deb -x "$work/glib.deb" "$work/sdk"
echo R330_PINNED_SDK_HEADERS_PASS
gcc -std=c11 -O2 -Wall -Wextra -Werror \
 -I"$work/sdk/usr/include/gstreamer-1.0" \
 -I"$work/sdk/usr/include/glib-2.0" \
 -I"$work/sdk/usr/lib/x86_64-linux-gnu/glib-2.0/include" \
 "$code" -Wl,--no-undefined -l:libgstreamer-1.0.so.0 \
 -l:libgobject-2.0.so.0 -l:libglib-2.0.so.0 -lm \
 -o "$work/r330-sequence"
echo R330_STRICT_HOST_BUILD_PASS
tar -xOzf "$release" fixtures/dts-stereo.mka >"$work/fixtures/stereo.mka"
tar -xOzf "$release" fixtures/ac3-51.mka >"$work/fixtures/ac3.mka"
tar -xOzf "$release" fixtures/dts-51.mka >"$work/fixtures/surround.mka"
printf '%s  %s\n' \
7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae "$work/fixtures/stereo.mka" \
ab82bf91f6b61fc5a3cdf11ccd1e3bf3b4d91e2a9b7667d97f87e2cc12089a88 "$work/fixtures/ac3.mka" \
7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5 "$work/fixtures/surround.mka" |
 sha256sum -c - >/dev/null
echo R330_PUBLIC_FIXTURES_3_OF_3_PASS
GST_REGISTRY_1_0="$work/registry.bin"
export GST_REGISTRY_1_0
timeout 70 "$work/r330-sequence" \
 "$work/fixtures/stereo.mka" "$work/fixtures/ac3.mka" \
 "$work/fixtures/surround.mka" >"$work/qa.log"
python3 - "$work/qa.log" <<'PY'
import sys
from pathlib import Path
rows=Path(sys.argv[1]).read_text().splitlines()
expect=['DTS2_COLD','AC3_PRIME_1','DTS2_AFTER_AC3',
        'DTS51_COLD','AC3_PRIME_2','DTS51_AFTER_AC3']
stages=[row.split('=',1)[1] for row in rows if row.startswith('R330_STAGE=')]
results=[row.split('=',1)[1] for row in rows if row.startswith('R330_STAGE_RESULT=')]
assert stages==expect and results==['PASS']*6
assert 'R330_DTS2_COLD_WARM_SAME_PCM=YES' in rows
assert 'R330_DTS51_COLD_WARM_SAME_PCM=YES' in rows
assert 'R330_AUDIO_FILES_CREATED=0' in rows
assert 'R330_EXTERNAL_STASFISH_ATTACH=NO' in rows
assert 'RESULT=R330_ISOLATED_SEQUENTIAL_QA_PASS' in rows
print('R330_STAGES=6/6_PASS')
print('R330_DTS2_COLD_WARM_PCM_IDENTICAL=PASS')
print('R330_DTS51_COLD_WARM_PCM_IDENTICAL=PASS')
PY
if "$work/r330-sequence" \
 "$work/fixtures/../fixtures/stereo.mka" "$work/fixtures/ac3.mka" \
 "$work/fixtures/surround.mka" >"$work/invalid.log" 2>&1; then
  echo R330_PATH_TRAVERSAL_FALSE_ACCEPT
  exit 2
fi
grep -Fq 'RESULT=R330_INVALID_FIXED_FIXTURES' "$work/invalid.log"
echo R330_PATH_TRAVERSAL_FAIL_CLOSED_PASS
echo R330_LIVE_PLAYER_MODIFIED=NO
echo R330_AUDIO_FILES_CREATED=0
echo RESULT=R330_REPRODUCIBLE_HOST_6_STAGE_PASS
