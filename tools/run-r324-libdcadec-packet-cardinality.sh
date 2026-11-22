#!/bin/sh
# R324: isolated official R278 libdcadec first-frame and multi-frame QA.
# Uses ONLY public SHA256-pinned LGPL source/archive. No apt/install, TV,
# speaker access, decoded PCM storage, service or firmware changes.
set -eu
umask 077
LC_ALL=C
export LC_ALL
for tool in sha256sum tar gcc make python3 mktemp timeout; do
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
# Only these immutable R278 fixtures are in scope. The reconstructed
# encoded DTS raw SHA values were cross-checked against FFmpeg stream-copy.
for track in stereo surround_51; do
    case "$track" in
        stereo)
            file=dts-stereo.mka
            fixture_sha=7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae
            raw_sha=282d15e11221524f6af40f4202ec6d2a3813d2a12a49de904e7cdfc0c4ce9bda
            frame_bytes=1024
            set --
            ;;
        surround_51)
            file=dts-51.mka
            fixture_sha=7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5
            raw_sha=8897677d593a5710b62f90919fe0e9888a31621bf55b166e2294a2f36f4fb013
            frame_bytes=2048
            set -- -DR324_SURROUND_51
            ;;
    esac
    tar -xOzf "$release" "fixtures/$file" >"$tmp/input.mka"
    printf '%s  %s\n' "$fixture_sha" "$tmp/input.mka" |
        sha256sum -c - >/dev/null
    python3 - "$tmp/input.mka" "$tmp/dts-encoded.raw" \
        "$frame_bytes" "$raw_sha" <<'PY'
import hashlib
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_bytes()
frame_bytes = int(sys.argv[3])
assert frame_bytes in (1024, 2048)
sync = bytes.fromhex("7ffe8001")
positions = []
offset = 0
while True:
    index = source.find(sync, offset)
    if index < 0:
        break
    positions.append(index)
    offset = index + len(sync)
if len(positions) != 94 or any(k + frame_bytes > len(source)
                                 for k in positions):
    raise SystemExit("R324_MATROSKA_FRAME_COUNT_MISMATCH")
encoded = b"".join(source[k:k + frame_bytes] for k in positions)
if hashlib.sha256(encoded).hexdigest() != sys.argv[4]:
    raise SystemExit("R324_ENCODED_DTS_REFERENCE_SHA_MISMATCH")
Path(sys.argv[2]).write_bytes(encoded)
print("R324_FFMPEG_INDEPENDENT_RAW_SHA=PASS")
PY
    gcc -std=c11 -O2 -Wall -Wextra -Werror "$@" \
        -I"$tmp/dcadec" "$src" "$tmp/dcadec/libdcadec/libdcadec.a" \
        -lm -o "$tmp/probe"
    timeout 15 "$tmp/probe" "$tmp/dts-encoded.raw"
done
echo R324_LAB_ISOLATED_ONLY=PASS
