#!/bin/sh
# R294 AlekS DTS - unified safe first-start / idle audio snapshot.
# PASSIVE: no playback or volume control, no service writes, no audio capture.
# Logs no media paths, titles, source URLs, process cmdlines or raw Luna JSON.
set -u
LC_ALL=C
export LC_ALL
plugin_dir=/var/lib/webosbrew/aleks-dts-r278/plugins
pcm=/proc/asound/card0/pcm6p/sub0
pulse=unix:/var/run/pulse/native
echo '=== ALEKS DTS R294 UNIFIED AUDIO SESSION SNAPSHOT (READ ONLY) ==='
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
uptime_seconds=$(awk '{printf "%.0f",$1}' /proc/uptime 2>/dev/null || :)
printf 'BOOT_UPTIME_SECONDS=%s\n' "$uptime_seconds"
for svc in umediaserver.service audiooutputd.service; do
  state=$(systemctl is-active "$svc" 2>/dev/null || :)
  printf 'SERVICE_%s=%s\n' "$svc" "$state"
done
starfish_total=0
mapped=0
for f in /proc/[0-9]*/comm; do
  [ -r "$f" ] || continue
  comm=$(cat "$f" 2>/dev/null || :)
  case "$comm" in
    starfish-media-*)
      starfish_total=$((starfish_total+1))
      pid=$(basename "$(dirname "$f")")
      if grep -Fq "$plugin_dir/libgstaleksdts16dec.so" "/proc/$pid/maps" 2>/dev/null; then
        mapped=$((mapped+1))
        printf 'DTS_PLUGIN_HOLDER_PID=%s\n' "$pid"
      fi
    ;;
  esac
done
printf 'STARFISH_PROCESSES=%s DTS_PLUGIN_HOLDERS=%s\n' "$starfish_total" "$mapped"
if command -v pactl >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  rows=$(timeout 7 pactl -s "$pulse" list short sink-inputs 2>/dev/null)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%s\n' "$rows" | awk 'NF>0 {n++;if(n<=8)printf "PA_INPUT_ID=%s SINK_ID=%s\n",$1,$2} END{printf "PULSE_INPUT_COUNT=%d\n",n}'
  else
    printf 'PULSE_QUERY=FAILED_%s\n' "$rc"
  fi
  owners=$(timeout 7 pactl -s "$pulse" list sink-inputs 2>/dev/null |
    grep -E '^[[:space:]]*application.process.id = "[0-9]+"' |
    sed -E 's/.*"([0-9]+)".*/\1/' | sort -u | head -n 8)
  for owner in $owners; do
    [ -r "/proc/$owner/comm" ] || continue
    label=$(cat "/proc/$owner/comm" 2>/dev/null || :)
    printf 'PA_INPUT_OWNER_PID=%s COMM=%s\n' "$owner" "$label"
  done
fi
if [ -r "$pcm/status" ]; then
  state=$(awk '$1=="state:" {print $2;exit}' "$pcm/status" 2>/dev/null)
  [ -n "$state" ] || state=closed
  printf 'ALSA_PCM6=%s\n' "$state"
  if [ "$state" = RUNNING ]; then
    h1=$(awk '$1=="hw_ptr"{print $3;exit}' "$pcm/status" 2>/dev/null || :)
    sleep 3
    h2=$(awk '$1=="hw_ptr"{print $3;exit}' "$pcm/status" 2>/dev/null || :)
    if [ -n "$h1" ] && [ -n "$h2" ] && [ "$h2" -ge "$h1" ] 2>/dev/null; then
      printf 'ALSA_HW_FRAMES_3S=%s\n' "$((h2-h1))"
    else
      echo 'ALSA_HW_FRAMES_3S=UNKNOWN'
    fi
  fi
else
  echo 'ALSA_PCM6=UNAVAILABLE'
fi
if command -v timeout >/dev/null 2>&1 && command -v luna-send >/dev/null 2>&1; then
  query() {
    label=$1
    url=$2
    reply=$(timeout 6 luna-send -n 1 -w 2500 "$url" '{}' 2>/dev/null)
    if [ "$?" -eq 0 ]; then
      printf 'QUERY=%s\n' "$label"
      printf '%s\n' "$reply" |
        grep -Eo '"(returnValue|codec|source|sink|muted|outputMode|soundOutput)"[[:space:]]*:[[:space:]]*("[A-Za-z0-9_.-]{1,40}"|true|false)' |
        head -n 12 || :
    else
      printf 'QUERY=%s UNAVAILABLE\n' "$label"
    fi
  }
  query CODEC 'luna://com.webos.service.audio/tv/getAudioInputProperty'
  query NATIVE_ROUTE 'luna://com.webos.service.audiooutput/audio/getStatus'
  query OUTPUT 'luna://com.webos.service.audio/getSoundOutput'
fi
if [ "$mapped" -eq 0 ]; then
  echo 'CLASSIFICATION=NO_DTS_PLUGIN_HOLDER_OBSERVED'
else
  echo 'CLASSIFICATION=DTS_PLUGIN_MAPPED; DECODING_AND_AUDIBILITY_UNPROVEN'
fi
echo 'RESULT=R294_SNAPSHOT_COMPLETE_NO_CHANGES'
echo 'NOTE=Running PCM, codec metadata and mappings cannot alone prove decoded DTS reaches the speakers.'
