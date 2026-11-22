#!/bin/sh
# R329: full, ephemeral GStreamer 1.24 DTS pad probe QA on public fixtures.
# No package installation, user app/session, TV, service, audio recording, or
# system GStreamer registry modifications.
set -eu
umask 077
LC_ALL=C
export LC_ALL
for tool in curl dpkg-deb sha256sum tar gcc python3 timeout mktemp; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "R329_MISSING_TOOL=$tool"
        exit 2
    }
done
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
source="$root/tools/r329-isolated-gst-pad-probe.c"
framer="$root/tools/r325-r188-framer-time-segment-lab.c"
header="$root/tools/r311-original-r188-dts-framer.h"
probe="$root/tools/r311-real-dts-be16-probe.h"
release="$root/downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz"
printf '%s  %s\n' \
4ec7c59cff56df8a22ca6b88cb17d765064ccf500ea845ffe211796a1a5d2070 "$source" \
e5b615a6e17bb829df035800229dcf3c07a12a1c45066b91a8eeb4e197ae02ce "$framer" \
8fcf17dd9d9890d26542f093a87f91e760e8ea8999619e17b4e56485b04bfa97 "$header" \
57d9d1df5b1ffe0d3fce8ad7ae584a7d95a6cb81f265ab658199a332866b9ed1 "$probe" \
cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1 "$release" |
    sha256sum -c - >/dev/null
echo R329_PUBLIC_RELEASE_AND_SOURCE_SHA256_PASS

work=$(mktemp -d /tmp/aleks-r329-regression.XXXXXX)
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT
trap 'exit 2' HUP INT TERM
mkdir -p "$work/sdk" "$work/src" "$work/fixtures" "$work/plugins"
curl -fLsS --proto '=https' --proto-redir '=https' \
    --connect-timeout 8 --max-time 48 \
    'https://archive.ubuntu.com/ubuntu/pool/main/g/gstreamer1.0/libgstreamer1.0-dev_1.24.2-1ubuntu0.2_amd64.deb' \
    -o "$work/gstreamer.deb"
curl -fLsS --proto '=https' --proto-redir '=https' \
    --connect-timeout 8 --max-time 48 \
    'https://archive.ubuntu.com/ubuntu/pool/main/g/glib2.0/libglib2.0-dev_2.80.0-6ubuntu3.10_amd64.deb' \
    -o "$work/glib.deb"
printf '%s  %s\n' \
616dab4dbd89fb66dda41e5195c5890ddce0b1c9d467d649cf3f7773d46165a8 "$work/gstreamer.deb" \
6d1d88d68192256603c0de05d084b8ef06ed9b16753215ec2c1ef9ef5fa15014 "$work/glib.deb" |
    sha256sum -c - >/dev/null
dpkg-deb -x "$work/gstreamer.deb" "$work/sdk"
dpkg-deb -x "$work/glib.deb" "$work/sdk"
echo R329_PINNED_DEV_HEADERS_PASS
cp "$framer" "$work/src/framer.c"
cp "$header" "$work/src/r188_dts_framer.h"
cp "$probe" "$work/src/r122_dts_core_probe.h"
common="-I$work/sdk/usr/include/gstreamer-1.0 -I$work/sdk/usr/include/glib-2.0 -I$work/sdk/usr/lib/x86_64-linux-gnu/glib-2.0/include"
# Word splitting of the fixed, private temporary include list is intended.
# Paths created by mktemp contain only safe characters.
# shellcheck disable=SC2086
gcc -std=c11 -O2 -Wall -Wextra -Werror -DPACKAGE='"aleks-dts"' \
    $common "$source" -o "$work/probe" -Wl,--no-undefined \
    -l:libgstreamer-1.0.so.0 -l:libgobject-2.0.so.0 \
    -l:libglib-2.0.so.0 -lm
# shellcheck disable=SC2086
gcc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared \
    -DPACKAGE='"aleks-dts"' $common -I"$work/src" \
    "$work/src/framer.c" -o "$work/plugins/libgstaleksdtsr188framer.so" \
    -Wl,--no-undefined -l:libgstreamer-1.0.so.0 \
    -l:libgobject-2.0.so.0 -l:libglib-2.0.so.0
echo R329_STRICT_HOST_BINARY_AND_FRAMER_BUILD_PASS

tar -xOzf "$release" fixtures/dts-stereo.mka >"$work/fixtures/stereo.mka"
tar -xOzf "$release" fixtures/dts-51.mka >"$work/fixtures/surround.mka"
python3 - "$work/fixtures" <<'PY'
import hashlib
from pathlib import Path
import sys

root = Path(sys.argv[1])
cases = (
    ("stereo", 1024,
     "7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae",
     "282d15e11221524f6af40f4202ec6d2a3813d2a12a49de904e7cdfc0c4ce9bda"),
    ("surround", 2048,
     "7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5",
     "8897677d593a5710b62f90919fe0e9888a31621bf55b166e2294a2f36f4fb013"),
)
for name, frame, sha_mka, sha_raw in cases:
    source = (root / (name + ".mka")).read_bytes()
    assert hashlib.sha256(source).hexdigest() == sha_mka
    sync = bytes.fromhex("7ffe8001")
    offsets = []
    start = 0
    while True:
        at = source.find(sync, start)
        if at < 0:
            break
        offsets.append(at)
        start = at + 4
    assert len(offsets) == 94
    raw = b"".join(source[pos:pos + frame] for pos in offsets)
    assert hashlib.sha256(raw).hexdigest() == sha_raw
    (root / (name + ".dts")).write_bytes(raw)
print("R329_STEREO_AND_51_PUBLIC_ENCODED_SHA256_PASS")
PY
GST_PLUGIN_PATH_1_0="$work/plugins"
GST_REGISTRY_1_0="$work/registry.bin"
export GST_PLUGIN_PATH_1_0 GST_REGISTRY_1_0
cases=0
for track in stereo surround; do
    for mode in matroska raw; do
        if [ "$mode" = matroska ]; then
            file="$work/fixtures/$track.mka"
            blocks="0"
        else
            file="$work/fixtures/$track.dts"
            blocks="1 11 97 4096"
        fi
        for block in $blocks; do
            timeout 20 "$work/probe" "$track" "$mode" "$file" "$block" \
                >"$work/run.out" || {
                echo "R329_FAILURE_CASE=$track/$mode/$block"
                grep '^RESULT=' "$work/run.out" || :
                exit 2
            }
            python3 - "$work/run.out" "$track" "$mode" <<'PY'
import sys
from pathlib import Path
v = dict(row.strip().split("=", 1)
         for row in Path(sys.argv[1]).read_text().splitlines() if "=" in row)
track, mode = sys.argv[2:]
channels = 2 if track == "stereo" else 6
assert v["RESULT"] == "R329_PAD_PROBE_PASS"
assert int(v["R329_INPUT_BUFFERS"]) == 94
assert int(v["R329_INPUT_BE16_SYNC"]) == 94
assert int(v["R329_EVENT_ORDER_ERRORS"]) == 0
assert int(v["R329_INPUT_SEGMENT_TIME"]) >= 1
assert int(v["R329_INPUT_SEGMENT_BYTES"]) == 0
assert v["R329_INPUT_CAPS_FAMILY"] == "audio/x-dts"
assert int(v["R329_PCM_SAMPLES"]) == 94 * 512 * channels
assert int(v["R329_PCM_NONZERO"]) > 0
assert int(v["R329_INPUT_MISSING_PTS"]) == (0 if mode == "matroska" else 94)
assert v["R329_RAW_PCM_EXPORTED"] == "NO"
assert v["R329_AUDIO_FILES_CREATED"] == "0"
assert v["R329_CONNECTED_TO_LIVE_MEDIA"] == "NO"
print("R329_CASE=" + track + "/" + mode +
      " RMS=" + v["R329_PCM_RMS_DBFS"] + "dBFS PASS")
PY
            cases=$((cases+1))
        done
    done
done
[ "$cases" -eq 10 ]
echo R329_STEREO_AND_51_ALL_10_PAD_EVENT_PCM_TESTS_PASS
# A corrupted public DTS stream must never satisfy the 94-frame success gate.
python3 - "$work/fixtures/stereo.dts" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
raw = bytearray(p.read_bytes())
raw[0] ^= 0xff
p.write_bytes(raw)
PY
if timeout 20 "$work/probe" stereo raw "$work/fixtures/stereo.dts" 97 \
    >"$work/corrupt.out" 2>/dev/null; then
    echo R329_CORRUPTED_INPUT_FALSE_ACCEPT
    exit 2
fi
grep -Fx 'RESULT=R329_PAD_PROBE_FAIL' "$work/corrupt.out" >/dev/null
echo R329_CORRUPTED_DTS_FAIL_CLOSED_PASS
echo R329_AUDIO_FILES_CREATED=0
echo R329_PRODUCTION_DEVICE_MODIFICATIONS=0
echo RESULT=R329_OFFLINE_REPRODUCIBLE_PAD_QA_PASS
