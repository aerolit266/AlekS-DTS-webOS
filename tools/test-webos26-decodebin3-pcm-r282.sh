#!/bin/sh
# AlekS DTS R282: isolated decodebin3 / LG decoder rank / PCM format differential.
# Safe by design: test fixture only, fakesink only, temporary GStreamer registry.
# No system changes, no device sound, no service restart.
set -eu
umask 077
LC_ALL=C
export LC_ALL
root=/var/lib/webosbrew/aleks-dts-r278
base=/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0
fail() { printf 'BLOCKED: %s\n' "$*" >&2; exit 1; }
for tool in sha256sum mktemp timeout grep sed gst-launch-1.0 gst-inspect-1.0; do
  command -v "$tool" >/dev/null 2>&1 || fail "Tool missing: $tool"
done
[ -f "$root/ready" ] && [ -f "$root/installed.sha256" ] || fail 'R278 not installed'
(cd "$root" && sha256sum -c installed.sha256 >/dev/null) || fail 'Installed plugin integrity mismatch'
fixture="$root/fixtures/dts-51.mka"
[ -f "$fixture" ] || fail 'DTS 5.1 test fixture missing'
printf '%s  %s\n' 7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5 "$fixture" | sha256sum -c - || fail 'DTS fixture hash mismatch'
work=$(mktemp -d /tmp/aleks-dts-r282.XXXXXX) || fail 'Staging failed'
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir "$work/cache"
printf '%s\n' '=== R282 DECODER PATH DIFFERENTIAL (NO LIVE AUDIO) ==='

run() {
  ranks=$1; shift
  env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin LC_ALL=C \
    HOME="$work" XDG_CACHE_HOME="$work/cache" \
    GST_PLUGIN_PATH_1_0="$base:$root/plugins" \
    GST_PLUGIN_SYSTEM_PATH_1_0="$base" \
    GST_REGISTRY_1_0="$work/isolated.reg" GST_REGISTRY_UPDATE=yes \
    ALEKS_DTS_R130_ALLOW_AUTOPLUG=YES \
    GST_PLUGIN_FEATURE_RANK="$ranks" \
    timeout 12 "$@"
}
printf '%s\n' '=== CHECK ELEMENT DISCOVERY ==='
for elem in decodebin decodebin3 audioconvert; do
  if run 'aleksdts16dec:288,decproxy:300' gst-inspect-1.0 "$elem" >/dev/null 2>&1; then
    printf 'FACTORY %s=AVAILABLE\n' "$elem"
  else
    printf 'FACTORY %s=UNAVAILABLE\n' "$elem"
  fi
done
for mode in db3_stock db3_lg db3_aleks db3_aleks_pcm2; do
  case "$mode" in
    db3_stock) ranks='aleksdts16dec:288,decproxy:0' ;;
    db3_lg) ranks='aleksdts16dec:288,decproxy:300' ;;
    db3_aleks|db3_aleks_pcm2) ranks='aleksdts16dec:350,decproxy:300' ;;
  esac
  logfile="$work/$mode.log"
  if [ "$mode" = db3_aleks_pcm2 ]; then
    run "$ranks" gst-launch-1.0 -v filesrc "location=$fixture" \
       '!' matroskademux name=dm dm.audio_0 '!' queue '!' decodebin3 \
       '!' audioconvert '!' 'audio/x-raw,format=S32LE,channels=2' \
       '!' fakesink sync=false >"$logfile" 2>&1 && code=0 || code=$?
  else
    run "$ranks" gst-launch-1.0 -v filesrc "location=$fixture" \
       '!' matroskademux name=dm dm.audio_0 '!' queue '!' decodebin3 \
       '!' fakesink sync=false >"$logfile" 2>&1 && code=0 || code=$?
  fi
  if grep -Fq 'AlekSDts16DecBin' "$logfile"; then decoder=yes; else decoder=no; fi
  if grep -Fq 'Got EOS' "$logfile"; then eos=yes; else eos=no; fi
  if grep 'GstFakeSink:.*GstPad:sink: caps = audio/x-raw' "$logfile" | grep -Fq 'channels=(int)6'; then pcm6=yes; else pcm6=no; fi
  if grep 'GstFakeSink:.*GstPad:sink: caps = audio/x-raw' "$logfile" | grep -Fq 'format=(string)S32LE'; then s32=yes; else s32=no; fi
  if grep 'GstFakeSink:.*GstPad:sink: caps = audio/x-raw' "$logfile" | grep -Fq 'channels=(int)2'; then stereo=yes; else stereo=no; fi
  if grep -Eiq 'not-negotiated|not-linked|Internal data stream error' "$logfile"; then failed_caps=yes; else failed_caps=no; fi
  printf 'CASE=%s ranks=%s exit=%s DTS_DECODER=%s EOS=%s PCM6=%s PCM_S32LE=%s PCM2=%s NEGOTIATION_ERROR=%s\n' \
    "$mode" "$ranks" "$code" "$decoder" "$eos" "$pcm6" "$s32" "$stereo" "$failed_caps"
done
printf '%s\n' '=== SELECTED LG SINK FACTORY TEMPLATES (NO INSTANTIATION) ==='
for elem in tsinkbin tsink audiosink alsasink pulsesink; do
  details=$(run 'aleksdts16dec:288,decproxy:300' gst-inspect-1.0 "$elem" 2>/dev/null) || continue
  printf 'ELEMENT=%s\n' "$elem"
  printf '%s\n' "$details" | grep -Ei 'Rank|audio/x-raw|format:|channels:|S16LE|S32LE|F32LE' | head -n 18 || :
done
echo 'RESULT=R282_ISOLATED_DECODEBIN3_AND_PCM_PROBE_COMPLETE; NATIVE_SOUND_UNTESTED'
