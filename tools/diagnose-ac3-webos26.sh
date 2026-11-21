#!/bin/sh
# AlekS DTS webOS 26 AC3 differential diagnosis (READ-ONLY MEDIA TEST)
# Does not install plugins, edit configuration, mount, restart services or write outside /tmp.
# Intentionally exits 0 after controlled test failures so ares-novacom shows diagnostic stdout.
set -eu
umask 077
LC_ALL=C
export LC_ALL

say() { printf '%s\n' "$*"; }
say '=== ALEKS_DTS_AC3_DIAGNOSTIC_R1 (NO INSTALL) ==='

for tool in curl sha256sum tar mktemp grep tail timeout; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    say "BLOCKED missing command: $tool"
    exit 0
  fi
done
if [ "$(id -u)" != 0 ]; then
  say 'BLOCKED root access required for identical test environment'
  exit 0
fi
if [ ! -x /usr/bin/gst-inspect-1.0 ] || [ ! -x /usr/bin/gst-launch-1.0 ]; then
  say 'BLOCKED GStreamer command missing'
  exit 0
fi
work=$(mktemp -d /tmp/aleks-dts-ac3diag.XXXXXX) || exit 1
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

url=https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/r278/downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz
if ! curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 90 \
  -o "$work/release.tar.gz" "$url"; then
  say 'BLOCKED archive download failure'
  exit 0
fi
if ! printf '%s  %s\n' cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1 "$work/release.tar.gz" | sha256sum -c -; then
  say 'BLOCKED archive SHA256 mismatch'
  exit 0
fi
if ! tar -xmzf "$work/release.tar.gz" -C "$work"; then
  say 'BLOCKED archive extraction failed'
  exit 0
fi
if ! (cd "$work" && printf '%s  %s\n' ab82bf91f6b61fc5a3cdf11ccd1e3bf3b4d91e2a9b7667d97f87e2cc12089a88 fixtures/ac3-51.mka | sha256sum -c -); then
  say 'BLOCKED AC3 fixture SHA256 mismatch'
  exit 0
fi

base=/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0
mkdir -p "$work/cache"
run_gst() {
  mode=$1
  shift
  if [ "$mode" = augmented ]; then
    plugins=$base:$work/plugins
    registry=$work/augmented.reg
  else
    plugins=$base
    registry=$work/native.reg
  fi
  env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
    XDG_CACHE_HOME="$work/cache" \
    GST_REGISTRY_1_0="$registry" \
    GST_REGISTRY_UPDATE=yes \
    GST_PLUGIN_PATH_1_0="$plugins" \
    GST_PLUGIN_SYSTEM_PATH_1_0="$base" \
    ALEKS_DTS_R130_ALLOW_AUTOPLUG=YES \
    timeout 20 "$@"
}

say '=== AC3 ELEMENT INVENTORY (NATIVE / AUGMENTED) ==='
for mode in native augmented; do
  say "MODE=$mode"
  for elem in ac3parse a52dec avdec_ac3 avdec_eac3; do
    log="$work/$mode.$elem.log"
    if run_gst "$mode" /usr/bin/gst-inspect-1.0 "$elem" > "$log" 2>&1; then
      say "FOUND element=$elem mode=$mode"
      grep -E 'Rank +|Long-name:|Filename:' "$log" | head -n 5 || :
    else
      say "NOT_FOUND_OR_ERROR element=$elem mode=$mode"
      tail -n 2 "$log" || :
    fi
  done
done

say '=== ISOLATED AC3 PIPELINE RESULTS ==='
native_ok=0
augmented_ok=0
for mode in native augmented; do
  log="$work/$mode.ac3.log"
  say "RUN_AC3 mode=$mode"
  if run_gst "$mode" /usr/bin/gst-launch-1.0 -v \
    filesrc "location=$work/fixtures/ac3-51.mka" \
    '!' matroskademux name=dm dm.audio_0 '!' queue '!' decodebin '!' fakesink sync=false \
    > "$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 0 ] && grep -Fq 'Got EOS' "$log"; then
    say "PASS_AC3 mode=$mode exit=0 eos=yes"
    if [ "$mode" = native ]; then native_ok=1; else augmented_ok=1; fi
  else
    say "FAIL_AC3 mode=$mode exit=$rc"
  fi
  say "--- diagnostic tail mode=$mode (up to 35 lines) ---"
  tail -n 35 "$log" || :
  say "--- end diagnostic mode=$mode ---"
done

say '=== INTERPRETATION ==='
if [ "$native_ok" -eq 1 ] && [ "$augmented_ok" -eq 1 ]; then
  say 'PASS_BOTH: baseline and AlekS-augmented AC3 pipelines reach EOS'
elif [ "$native_ok" -eq 1 ]; then
  say 'FAIL_AUGMENTED_ONLY: investigate AlekS plugin interactions with AC3'
elif [ "$augmented_ok" -eq 1 ]; then
  say 'FAIL_BASELINE_ONLY: baseline GStreamer AC3 path failed, augmented reached EOS'
else
  say 'FAIL_BOTH: AC3 cannot run in either tested isolated GStreamer environment'
  say 'NOTE: this does not prove native LG TV playback/AC3 is broken'
fi
say 'DIAG_COMPLETE: NO INSTALL, NO MEDIA SERVICE RESTART, NO PERSISTENT CHANGES'
# Explicit zero return so webOS ares-novacom forwards the complete stdout diagnostic.
exit 0
