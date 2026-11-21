#!/bin/sh
# AlekS DTS R278 / webOS 26: ISOLATED VERIFICATION ONLY (R2 AC3).
# Never installs plugins, writes systemd config, mounts files or restarts services.
set -eu
umask 077
LC_ALL=C; export LC_ALL
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
echo 'AlekS DTS R278 isolated compatibility test (NO INSTALL)'
[ "$(id -u)" = 0 ] || fail 'Run with the existing root SDK profile.'
for t in curl sha256sum tar od tr grep mktemp timeout; do
  command -v "$t" >/dev/null 2>&1 || fail "Missing command: $t"
done
[ -r /usr/sbin/umediaserver ] || fail 'umediaserver missing'
[ -x /usr/bin/gst-inspect-1.0 ] || fail 'gst-inspect missing'
[ -x /usr/bin/gst-launch-1.0 ] || fail 'gst-launch missing'
# ELF class 1 = 32 bit, data 1 = little endian; EM_ARM = 0x0028 (40,0).
arm32() {
  [ -r "$1" ] || fail "ELF unreadable: $1"
  header=$(od -An -tu1 -j4 -N2 "$1" | tr -s ' ' | tr -d '\n')
  machine=$(od -An -tu1 -j18 -N2 "$1" | tr -s ' ' | tr -d '\n')
  [ "$header" = ' 1 1' ] && [ "$machine" = ' 40 0' ] ||
    fail "Non-ARM32 media ELF at $1: class/data=[$header] machine=[$machine]"
  printf 'PASS ELF32 ARM: %s\n' "$1"
}
arm32 /usr/sbin/umediaserver
arm32 /usr/bin/gst-inspect-1.0
gstlib=/usr/lib/libgstreamer-1.0.so.0
arm32 "$gstlib"
gstver=$(/usr/bin/gst-inspect-1.0 --version) || fail 'GStreamer version query failed'
printf '%s\n' "$gstver" | head -3
printf '%s\n' "$gstver" | grep -q 'GStreamer 1.24.' ||
  fail 'This verification is intended for the GStreamer 1.24 media stack.'
work=$(mktemp -d /tmp/aleks-dts-r278-isolated.XXXXXX) || fail 'Cannot create isolated working directory'
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
url=https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/r278/downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz
curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 90 -o "$work/release.tar.gz" "$url" ||
  fail 'Cannot download pinned R278 archive'
printf '%s  %s\n' cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1 "$work/release.tar.gz" | sha256sum -c - ||
  fail 'R278 archive SHA256 mismatch'
tar -xmzf "$work/release.tar.gz" -C "$work" || fail 'Unable to unpack archive'
(
  cd "$work"
  cat <<'HASHES' | sha256sum -c -
5c3b798d4c1109414efc9209276dbf8b23466376f72f5bc71cf4144f3f5a1cbb  plugins/libgstaleksdts.so
1995a6b6030f6ddb895aeeea4017dcc71db8ebd6caace0107e1c5a33875f0605  plugins/libgstaleksdtscaps.so
9b7adb2744a9d7c329669974c15bcfc86ba62daf27efccb95e362c1928d602e0  plugins/libgstaleksdtsr130optin.so
dfefb960d49d50ed7629cc4459ffaae8b420509cc9815d8337f6be7faaac18cf  plugins/libgstaleksdts16dec.so
7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae  fixtures/dts-stereo.mka
7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5  fixtures/dts-51.mka
ab82bf91f6b61fc5a3cdf11ccd1e3bf3b4d91e2a9b7667d97f87e2cc12089a88  fixtures/ac3-51.mka
HASHES
) || fail 'Bundled plugin / fixture checksum mismatch'
mkdir -p "$work/cache"
base=/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0
# Crucial: registry and cache are temporary, never the TV's persistent registry.
run_gst() {
  env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
    XDG_CACHE_HOME="$work/cache" \
    GST_REGISTRY_1_0="$work/isolated.reg" \
    GST_REGISTRY_UPDATE=yes \
    GST_PLUGIN_PATH_1_0="$base:$work/plugins" \
    GST_PLUGIN_SYSTEM_PATH_1_0="$base" \
    ALEKS_DTS_R130_ALLOW_AUTOPLUG=YES \
    timeout 20 "$@"
}
inspect() {
  name=$1
  log="$work/$name.log"
  if run_gst /usr/bin/gst-inspect-1.0 "$name" >"$log" 2>&1; then
    printf 'PASS gst-inspect %s\n' "$name"
  else
    printf 'LOAD FAILURE %s (last 25 lines):\n' "$name" >&2
    tail -n 25 "$log" >&2
    fail "Plugin $name not loadable on this TV; no changes made"
  fi
}
inspect aleksdtsr130optin
inspect aleksdts16dec
check_clip() {
  clip=$1
  expected_channels=$2
  log="$work/$clip.log"
  if run_gst /usr/bin/gst-launch-1.0 -v filesrc "location=$work/fixtures/$clip.mka" \
       '!' matroskademux name=dm dm.audio_0 '!' queue '!' decodebin '!' fakesink sync=false >"$log" 2>&1; then
    :
  else
    printf 'PIPELINE FAILURE %s (last 30 lines):\n' "$clip" >&2
    tail -n 30 "$log" >&2
    fail "Pipeline for $clip failed; no changes made"
  fi
  if ! grep -Fq 'Got EOS' "$log"; then
    tail -n 25 "$log" >&2
    fail "$clip did not reach EOS"
  fi
  if [ "$expected_channels" != 0 ]; then
    if ! grep -Fq 'AlekSDts16DecBin' "$log" ||
       ! grep 'GstFakeSink:.*GstPad:sink: caps = audio/x-raw' "$log" | grep -Fq "channels=(int)$expected_channels"; then
      tail -n 30 "$log" >&2
      fail "$clip did not decode with expected AlekS DTS and $expected_channels channels"
    fi
  else
    if grep -Eq 'AlekSDtsR130:|AlekSDts16DecBin' "$log"; then
      fail 'AC3 incorrectly routed through DTS plugin'
    fi
  fi
  printf 'PASS %s\n' "$clip"
}
check_clip dts-stereo 2
check_clip dts-51 6

# webOS 26 native decodebin autoplugs LG's hardware GstOMXAC3Dec.
# Its hardware decoder reached PCM/EOS in both baseline and AlekS-augmented
# tests, but teardown hung until timeout (143). Test the independently exposed
# software avdec_ac3 to distinguish codec function from OMX shutdown.
run_gst_native() {
  env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
    XDG_CACHE_HOME="$work/cache" \
    GST_REGISTRY_1_0="$work/native.reg" \
    GST_REGISTRY_UPDATE=yes \
    GST_PLUGIN_PATH_1_0="$base" \
    GST_PLUGIN_SYSTEM_PATH_1_0="$base" \
    timeout 20 "$@"
}
check_ac3_software() {
  for mode in native augmented; do
    log="$work/ac3-software-$mode.log"
    if [ "$mode" = native ]; then
      run_gst_native /usr/bin/gst-launch-1.0 -v filesrc "location=$work/fixtures/ac3-51.mka" \
        '!' matroskademux name=dm dm.audio_0 '!' queue '!' ac3parse '!' avdec_ac3 \
        '!' fakesink sync=false > "$log" 2>&1 && code=0 || code=$?
    else
      run_gst /usr/bin/gst-launch-1.0 -v filesrc "location=$work/fixtures/ac3-51.mka" \
        '!' matroskademux name=dm dm.audio_0 '!' queue '!' ac3parse '!' avdec_ac3 \
        '!' fakesink sync=false > "$log" 2>&1 && code=0 || code=$?
    fi
    # Validate clean exit + EOS + actual audio PCM on fakesink; not just 
    # decoder discovery or negotiation. No AlekS DTS element should process AC3.
    if [ "$code" -ne 0 ] ||
       ! grep -Fq 'Got EOS' "$log" ||
       ! grep 'GstFakeSink:.*GstPad:sink: caps = audio/x-raw' "$log" | grep -Fq 'rate=(int)48000' ||
       grep -Eq 'AlekSDtsR130:|AlekSDts16DecBin' "$log"; then
      printf 'BLOCKED AC3_SOFTWARE mode=%s exit=%s\n' "$mode" "$code"
      printf '%s\n' 'Last 40 lines of AC3 software decoder log:'
      tail -n 40 "$log" 2>&1 || :
      printf 'RESULT=AC3_REGRESSION_NOT_CLEARED; NO_INSTALL\n'
      exit 0
    fi
    printf 'PASS ac3-software-%s (clean EOS, 48kHz PCM, no AlekS DTS decoder)\n' "$mode"
  done
}

check_ac3_software
printf '\nRESULT=PASS_DTS_AND_AC3_SOFTWARE_ISOLATED; NO_INSTALL\n'
printf 'CAUTION: LG OMX AC3 hardware decoder EOS observed, but teardown timed out in both native and augmented runs.\n'
printf 'Native-player DTS playback is still UNVERIFIED.\n'