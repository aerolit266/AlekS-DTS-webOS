#!/bin/sh
# AlekS DTS webOS26 R281: ISOLATED GStreamer rank/AUTOPLUG test.
# Never edits umediaserver.env or production registry, never calls native sound sink.
set -eu
umask 077
LC_ALL=C; export LC_ALL
root=/var/lib/webosbrew/aleks-dts-r278
base=/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0
clip=$root/fixtures/dts-51.mka
fail() { printf 'BLOCKED %s\n' "$*" >&2; exit 1; }
for t in gst-inspect-1.0 gst-launch-1.0 sha256sum mktemp timeout sed grep; do
  command -v "$t" >/dev/null 2>&1 || fail "missing $t"
done
[ -f "$root/ready" ] && [ -r "$clip" ] && [ -f "$root/installed.sha256" ] ||
  fail 'installed R278 fixtures/manifest not available'
(cd "$root" && sha256sum -c installed.sha256 >/dev/null) || fail 'Installed binary integrity mismatch'
printf '7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5  %s\n' "$clip" | sha256sum -c - ||
  fail 'DTS-51 fixture checksum mismatch'
work=$(mktemp -d /tmp/aleks-dts-r281.XXXXXX) || fail 'Cannot allocate isolated test directory'
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir "$work/cache"
printf '%s\n' '=== ISOLATED R281 (NO MEDIA SERVICE CHANGE) ==='
echo "GST_VERSION=$(gst-inspect-1.0 --version | grep 'GStreamer 1.24' | head -1)"
printf 'config decproxy (not factory rank): '
if [ -r /etc/gst/gstcool.conf ]; then
  grep -E '^decproxy=' /etc/gst/gstcool.conf || :
else
  echo UNREADABLE
fi

run() {
  rank=$1; shift
  env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
    HOME="$work" XDG_CACHE_HOME="$work/cache" \
    GST_PLUGIN_PATH_1_0="$base:$root/plugins" \
    GST_PLUGIN_SYSTEM_PATH_1_0="$base" \
    GST_REGISTRY_1_0="$work/test.reg" GST_REGISTRY_UPDATE=yes \
    ALEKS_DTS_R130_ALLOW_AUTOPLUG=YES \
    GST_PLUGIN_FEATURE_RANK="$rank" \
    timeout 10 "$@"
}
# First validate that the R281 variable can override BOTH element ranks in
# this firmware's GStreamer; otherwise the experiment must not imply anything.
for setting in \
  'aleksdts16dec:288,decproxy:0' \
  'aleksdts16dec:288,decproxy:300' \
  'aleksdts16dec:350,decproxy:300'; do
  printf 'RANK_SETTING=%s\n' "$setting"
  for factory in aleksdts16dec decproxy; do
    log="$work/rank.out"
    if run "$setting" gst-inspect-1.0 "$factory" > "$log" 2>&1; then
      value=$(grep -m1 'Rank ' "$log" | sed 's/^[[:space:]]*//' || :)
      printf 'FACTORY=%s %s\n' "$factory" "$value"
    else
      printf 'FACTORY=%s DISCOVERY_FAILED\n' "$factory"
    fi
  done
done
printf '%s\n' '=== DTS fixture to fakesink, no speaker access ==='
for mode in stock_rank lg_decproxy_300 aleks_decoder_350; do
  case "$mode" in
    stock_rank) ranks='aleksdts16dec:288,decproxy:0' ;;
    lg_decproxy_300) ranks='aleksdts16dec:288,decproxy:300' ;;
    aleks_decoder_350) ranks='aleksdts16dec:350,decproxy:300' ;;
  esac
  log="$work/$mode.out"
  if run "$ranks" gst-launch-1.0 -v \
      filesrc "location=$clip" '!' matroskademux name=dm \
      dm.audio_0 '!' queue '!' decodebin '!' fakesink sync=false \
      > "$log" 2>&1; then
      code=0
  else
      code=$?
  fi
  if grep -Fq 'AlekSDts16DecBin' "$log"; then custom=yes; else custom=no; fi
  if grep -Fq 'Got EOS' "$log"; then eos=yes; else eos=no; fi
  if grep 'GstFakeSink:.*GstPad:sink: caps = audio/x-raw' "$log" |
       grep -Fq 'channels=(int)6'; then pcm6=yes; else pcm6=no; fi
  printf 'CASE=%s exit=%s custom_decoder=%s eos=%s pcm6=%s\n' "$mode" "$code" "$custom" "$eos" "$pcm6"
  # Filter only fixed diagnostic tokens; never print user media paths.
  grep -E 'ERROR|not-negotiated|not-linked|Internal data stream error' "$log" |
    sed -E 's@(/[^[:space:]]+)+@<path>@g' | tail -n 3 || :
done
echo 'RESULT=ISOLATED_RANK_DIFFERENTIAL_RECORDED; NO_NATIVE_AUDIO_TEST'
