#!/bin/sh
# AlekS DTS / LG webOS26 - read-only silence investigation during playback.
# Uses procfs, gst-inspect and bounded journal keyword counts only.
# DOES NOT read or modify media files, restart services, or edit system config.
set -u
export LC_ALL=C
home=/var/lib/webosbrew/aleks-dts-r278
printf '%s\n' '=== DTS SILENCE INVESTIGATION (READ ONLY / during playback) ==='
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
if command -v systemctl >/dev/null 2>&1; then
  systemctl show umediaserver.service -p ActiveState -p MainPID --no-pager 2>/dev/null || :
fi

printf '%s\n' '=== CONTENT-NEUTRAL MEDIA PROCESS MAP ==='
seen=0
mapped_total=0
for f in /proc/[0-9]*/comm; do
  [ -r "$f" ] || continue
  p=$(dirname "$f"); pid=$(basename "$p")
  comm=$(head -n 1 "$f" 2>/dev/null || :)
  maps="$p/maps"
  [ -r "$maps" ] || continue
  mapped=0
  for so in libgstaleksdts.so libgstaleksdtscaps.so libgstaleksdtsr130optin.so libgstaleksdts16dec.so; do
    if grep -Fq "$home/plugins/$so" "$maps" 2>/dev/null; then
      mapped=$((mapped+1))
    fi
  done
  case "$comm" in
    umediaserver|starfish-media-*|audiooutputd|*audio*|*Audio*|*media*|*Media*|*gst*|*Gst*|WebAppMgr|webappmanager|WAM|*Player*|*player*|WebOS*|com.webos.*) media=1 ;;
    *) media=0 ;;
  esac
  if [ "$mapped" -gt 0 ] || [ "$media" -eq 1 ]; then
    seen=$((seen+1))
    mapped_total=$((mapped_total+mapped))
    if [ "$seen" -le 26 ]; then
      plugin_env=no; allow_env=no
      if [ -r "$p/environ" ]; then
        tr '\000' '\n' < "$p/environ" | grep -F 'GST_PLUGIN_PATH_1_0=' | grep -Fq "$home/plugins" && plugin_env=yes
        tr '\000' '\n' < "$p/environ" | grep -Fxq 'ALEKS_DTS_R130_ALLOW_AUTOPLUG=YES' && allow_env=yes
      fi
      printf 'PROCESS comm=%s pid=%s ALEKS_SO_MAPPED=%s plugin_env=%s optin_env=%s\n' \
        "$comm" "$pid" "$mapped" "$plugin_env" "$allow_env"
    fi
  fi
done
printf 'MEDIA_PROCESSES_OBSERVED=%s ALEKS_SO_MAPPINGS=%s\n' "$seen" "$mapped_total"

printf '%s\n' '=== LIVE GST PLUGIN DISCOVERY (READ ONLY) ==='
if [ -f "$home/combined.reg" ] && [ -d "$home/plugins" ] &&
   [ -x /usr/bin/gst-inspect-1.0 ]; then
  for element in aleksdts16dec aleksdtsr130optin; do
    if env GST_PLUGIN_PATH_1_0="/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0:$home/plugins" \
       GST_PLUGIN_SYSTEM_PATH_1_0="/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0" \
       GST_REGISTRY_1_0="$home/combined.reg" GST_REGISTRY_UPDATE=no \
       ALEKS_DTS_R130_ALLOW_AUTOPLUG=YES \
       /usr/bin/gst-inspect-1.0 "$element" >/dev/null 2>&1; then
       printf 'PLUGIN_REGISTRY_AVAILABLE=%s\n' "$element"
    else
       printf 'PLUGIN_REGISTRY_MISSING=%s\n' "$element"
    fi
  done
else
  printf 'PLUGIN_REGISTRY_CHECK=UNAVAILABLE\n'
fi

printf '%s\n' '=== STOCK CONTAINER DEMUXER FINGERPRINTS (READ ONLY) ==='
for path in /usr/lib/gstreamer-1.0/libgstmatroska.so /usr/lib/gstreamer-1.0/libgstisomp4.so /mnt/lg/res/lglib/gstreamer-1.0/libgstmatroska.so; do
  if [ -r "$path" ]; then
    sha256sum "$path" || :
  fi
done
printf '%s\n' '=== STOCK MATROSKA DTS CAPABILITY HINTS (READ ONLY) ==='
if [ -x /usr/bin/gst-inspect-1.0 ]; then
  env GST_PLUGIN_PATH_1_0="/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0" \
    GST_PLUGIN_SYSTEM_PATH_1_0="/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0" \
    GST_REGISTRY_1_0="/tmp/aleks-dts-diagnostic-registry-does-not-exist" GST_REGISTRY_UPDATE=no \
    /usr/bin/gst-inspect-1.0 matroskademux 2>/dev/null \
    | grep -Ei 'dts|audio/x-unknown|audio/x-dts' | head -n 8 || :
fi

printf '%s\n' '=== NATIVE SERVICE ERROR MARKERS (15m, counts only) ==='
if command -v journalctl >/dev/null 2>&1; then
  for pattern in 'dts' 'not-negotiated' 'not-linked' 'no decoder' 'unsupported' 'audio/x-raw' 'error'; do
    n=$(journalctl -u umediaserver.service --since '-15 min' --no-pager -o cat 2>/dev/null \
      | grep -Fic "$pattern" || :)
    printf 'JOURNAL_MARKER %s=%s\n' "$pattern" "$n"
  done
else
  printf 'JOURNAL_UNAVAILABLE\n'
fi
printf '%s\n' 'RESULT=DIAGNOSIS_CAPTURED_NO_DEVICE_CHANGE'
printf '%s\n' 'INTERPRETATION: mappings prove plugin load only; zero mappings do not prove lack of decoding.'
