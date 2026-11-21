#!/bin/sh
# AlekS DTS R280 probe: show exact plugin mappings/ranks during silent playback.
# READ ONLY: no restart, mounts, registry edits or sound playback.
set -u
LC_ALL=C
export LC_ALL
home=/var/lib/webosbrew/aleks-dts-r278
base=/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0
printf '%s\n' '=== R280 REAL-TIME DTS ROOT CAUSE PROBE (READ ONLY) ==='
n=0
for f in /proc/[0-9]*/comm; do
  [ -r "$f" ] || continue
  pid=$(basename "$(dirname "$f")")
  comm=$(cat "$f" 2>/dev/null || :)
  case "$comm" in starfish-media-*|starfish-media-pipeline) : ;; *) continue ;; esac
  n=$((n+1))
  printf 'PROCESS pid=%s name=%s\n' "$pid" "$comm"
  maps="/proc/$pid/maps"
  [ -r "$maps" ] || { printf 'WARN inaccessible maps\n'; continue; }
  for plugin in libgstaleksdts.so libgstaleksdtscaps.so libgstaleksdtsr130optin.so libgstaleksdts16dec.so; do
    if grep -Fq "$home/plugins/$plugin" "$maps" 2>/dev/null; then
      printf 'ALEKS_PLUGIN %-31s LOADED\n' "$plugin"
    else
      printf 'ALEKS_PLUGIN %-31s NOT_MAPPED\n' "$plugin"
    fi
  done
  # Only basenames of selected GStreamer media libraries; no movie file paths.
  awk '{print $NF}' "$maps" 2>/dev/null |
    grep -E '^(/usr/lib/gstreamer-1.0/|/mnt/lg/res/lglib/gstreamer-1.0/).*\.so' |
    sed 's@.*/@@' | grep -Ei '(dts|dec|demux|codec|audio|proxy|switch|omx|sink)' |
    sort -u | head -n 35 | while IFS= read -r lib; do
      printf 'STOCK_GST_MAPPED=%s\n' "$lib"
    done
done
printf 'STARFISH_PROCESS_COUNT=%s\n' "$n"
printf '%s\n' '=== ELEMENT RANKS AND CAPS TEMPLATES ==='
if [ -x /usr/bin/gst-inspect-1.0 ]; then
  for el in aleksdts16dec aleksdtsr130optin aleksdtscaps decproxy adecswitch audiosink matroskademux; do
    printf 'ELEMENT=%s\n' "$el"
    result=$(env GST_PLUGIN_PATH_1_0="$base:$home/plugins" \
      GST_PLUGIN_SYSTEM_PATH_1_0="$base" \
      GST_REGISTRY_1_0="$home/combined.reg" GST_REGISTRY_UPDATE=no \
      ALEKS_DTS_R130_ALLOW_AUTOPLUG=YES \
      /usr/bin/gst-inspect-1.0 "$el" 2>/dev/null)
    ret=$?
    if [ "$ret" -eq 0 ]; then
      printf '%s\n' "$result" |
        grep -Ei 'Rank|audio/x-raw|audio/x-dts|audio/x-unknown|format:|S16LE|S32LE|F32LE|channels:|codec-id' |
        head -n 18 || :
    else
      printf 'NOT_DISCOVERED\n'
    fi
  done
fi
printf '%s\n' '=== LG DECODER POLICY (NAMES AND RANKS ONLY) ==='
if [ -r /etc/gst/gstcool.conf ]; then
  grep -Ei '(^\[.*decoder.*\]|dts|aleks|decproxy|adecswitch|audiosink)' /etc/gst/gstcool.conf |
    head -n 30 || :
else
  printf 'GSTCOOL_NOT_READABLE\n'
fi
printf '%s\n' 'RESULT=R280_PROBE_CAPTURED; NO_CHANGES'
