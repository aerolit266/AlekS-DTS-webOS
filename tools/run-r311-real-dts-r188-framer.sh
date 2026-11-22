#!/bin/sh
# R311: reproducible real DTS Core framing regression using the original
# 2026 R188 C99 + Gst plugin, a newly REAL but restricted R311 header probe,
# and the exact public R278 release DTS stereo and 5.1 fixtures.
# No LG, no services, no apt install, no audio device, no original R122.
set -eu
umask 077
LC_ALL=C;export LC_ALL
for tool in curl sha256sum gcc dpkg-deb gst-inspect-1.0 gst-launch-1.0 ffmpeg python3 cmp mktemp timeout;do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "R311_BLOCKED_MISSING=$tool";exit 2;
    }
done
d=$(mktemp -d /tmp/aleks-r311-real-dts.XXXXXX)
trap 'rm -rf "$d"' EXIT HUP INT TERM
mkdir -p "$d/sdk" "$d/plugins"
root=https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS
curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 24 \
 "$root/739f49dc5fa298d1384a08a941a91f5f18ab820e/tools/r311-original-r188-gst-framer.c" \
 -o "$d/r188_gst_framer.c"
curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 24 \
 "$root/a16ada92cd61bd11a524ea086439e42c8c7c39de/tools/r311-original-r188-dts-framer.h" \
 -o "$d/r188_dts_framer.h"
curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 24 \
 "$root/7be05af8b2520b99d30ec559431720ae130dd0a8/tools/r311-real-dts-be16-probe.h" \
 -o "$d/r122_dts_core_probe.h"
curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 26 \
 "$root/r278/downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz" \
 -o "$d/release.tar.gz"
printf '%s  %s\n' \
 773aea865d8b49c36b7cf72b8baf56db5615670b80776622b1e5e23ca0146a52 "$d/r188_gst_framer.c" \
 8fcf17dd9d9890d26542f093a87f91e760e8ea8999619e17b4e56485b04bfa97 "$d/r188_dts_framer.h" \
 57d9d1df5b1ffe0d3fce8ad7ae584a7d95a6cb81f265ab658199a332866b9ed1 "$d/r122_dts_core_probe.h" \
 cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1 "$d/release.tar.gz" |
 sha256sum -c -
curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 26 \
 https://archive.ubuntu.com/ubuntu/pool/main/g/gstreamer1.0/libgstreamer1.0-dev_1.24.2-1ubuntu0.2_amd64.deb \
 -o "$d/gst-dev.deb"
curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 26 \
 https://archive.ubuntu.com/ubuntu/pool/main/g/glib2.0/libglib2.0-dev_2.80.0-6ubuntu3.10_amd64.deb \
 -o "$d/glib-dev.deb"
printf '%s  %s\n' \
 616dab4dbd89fb66dda41e5195c5890ddce0b1c9d467d649cf3f7773d46165a8 "$d/gst-dev.deb" \
 6d1d88d68192256603c0de05d084b8ef06ed9b16753215ec2c1ef9ef5fa15014 "$d/glib-dev.deb" |
 sha256sum -c -
dpkg-deb -x "$d/gst-dev.deb" "$d/sdk"
dpkg-deb -x "$d/glib-dev.deb" "$d/sdk"
python3 - "$d" <<'PY'
from pathlib import Path
import hashlib,tarfile,sys
p=Path(sys.argv[1])
clips={
'dts-stereo.mka':'7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae',
'dts-51.mka':'7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5'}
with tarfile.open(p/'release.tar.gz') as archive:
 for name,sha in clips.items():
  member=archive.getmember('fixtures/'+name)
  if not member.isfile() or member.size>1000000:raise SystemExit('R311_UNSAFE_FIXTURE')
  data=archive.extractfile(member).read()
  if hashlib.sha256(data).hexdigest()!=sha:raise SystemExit('R311_FIXTURE_BAD_SHA')
  (p/name).write_bytes(data)
  print('R311_FIXTURE_SHA256_PASS',name)
PY
echo R311_ALL_SIX_SOURCE_AND_SDK_PINS_PASS
gcc -std=c11 -O2 -fPIC -shared -Wall -Wextra -Werror \
 -I"$d" -I"$d/sdk/usr/include/gstreamer-1.0" \
 -I"$d/sdk/usr/include/glib-2.0" \
 -I"$d/sdk/usr/lib/x86_64-linux-gnu/glib-2.0/include" \
 "$d/r188_gst_framer.c" -o "$d/plugins/libgstaleksdtsr188framer.so" \
 -Wl,--no-undefined -l:libgstreamer-1.0.so.0 -l:libgobject-2.0.so.0 \
 -l:libglib-2.0.so.0
export GST_PLUGIN_PATH="$d/plugins" GST_REGISTRY="$d/registry.bin" GST_REGISTRY_FORK=no
gst-inspect-1.0 aleksdtsr188framer >"$d/inspect.log" 2>&1
grep -q 'Rank                     none (0)' "$d/inspect.log"
echo R311_UNMODIFIED_R188_PLUGIN_COMPILE_AND_REGISTER_PASS
for track in dts-stereo dts-51;do
 if [ "$track" = dts-stereo ];then channels=2;else channels=6;fi
 ffmpeg -hide_banner -loglevel error -nostdin \
  -i "$d/$track.mka" -map 0:a:0 -c:a copy -f dts "$d/$track.dts"
 # The independent Matroska-decoded PCM is the byte-exact gold baseline.
 timeout 24 gst-launch-1.0 -q \
  filesrc location="$d/$track.mka" blocksize=4096 ! matroskademux ! \
  dtsdec ! audioconvert ! "audio/x-raw,format=S16LE,channels=$channels,rate=48000" ! \
  filesink location="$d/$track-reference.pcm"
 if [ "$track" = dts-stereo ];then
  expected_bytes=192512
  expected_sha=19a367f440beedaed0ffdb3e18403c9ed14124f289e354983036b51b347c0773
 else
  expected_bytes=577536
  expected_sha=d7d992363b866249f7e18790beda1f9e2e5f202d9a7536f5a9e1606c605f28e6
 fi
 [ "$(wc -c < "$d/$track-reference.pcm")" -eq "$expected_bytes" ]
 printf '%s  %s\n' "$expected_sha" "$d/$track-reference.pcm" | sha256sum -c -
 for block in 1 11 97 4096;do
  out="$d/$track-frame-$block.pcm"
  timeout 25 gst-launch-1.0 -q \
   filesrc location="$d/$track.dts" blocksize="$block" ! \
   aleksdtsr188framer ! dtsdec ! audioconvert ! \
   "audio/x-raw,format=S16LE,channels=$channels,rate=48000" ! \
   filesink location="$out"
  cmp -s "$out" "$d/$track-reference.pcm" || {
   echo "R311_FAIL_DIFFERENT_PCM=$track/$block";exit 1;
  }
  echo "R311_COMPLETE_PCM_PASS track=$track block=$block bytes=$expected_bytes"
 done
done
python3 - "$d" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])
raw=(p/'dts-stereo.dts').read_bytes()
(p/'bad-sync.dts').write_bytes(b'\x00'+raw[1:1025])
(p/'truncated.dts').write_bytes(raw[:100])
(p/'bad-second.dts').write_bytes(raw[:1024]+b'\xff'+raw[1025:2048])
PY
for item in bad-sync truncated bad-second;do
 log="$d/failure-$item.log"
 if timeout 14 gst-launch-1.0 -q filesrc location="$d/$item.dts" blocksize=11 ! \
  aleksdtsr188framer ! dtsdec ! fakesink sync=false >"$log" 2>&1; then
  echo "R311_FAIL_ACCEPTED_BAD_DTS=$item";exit 1
 fi
 if [ "$item" = truncated ];then
  grep -q 'R188 incomplete DTS Core frame at EOS' "$log"
 else
  grep -q 'R188 invalid or unframeable DTS Core buffer' "$log"
 fi
 echo "R311_FAIL_CLOSED_PASS=$item"
done
echo "RESULT=R311_REAL_DTS_FRAMING_8_OF_8_PCM_AND_3_OF_3_FAIL_CLOSED_PASS"
echo "SCOPE=LAB_ONLY_VPS_STOCK_DTSDEC_NOT_LG_R278_FIRST_START"
