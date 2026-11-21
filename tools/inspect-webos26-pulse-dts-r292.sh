#!/bin/sh
# R292: passive PulseAudio vs Starfish vs LG native audio-route correlation.
# No audio capture, no process arguments, media URLs, or identifying metadata.
# Only pactl LIST/INFO, /proc/comm, status and read-only Luna getStatus.
set -u
LC_ALL=C; export LC_ALL
echo '=== R292 LG DTS PULSE / NATIVE AUDIO PATH (READ ONLY) ==='
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
base=/var/lib/webosbrew/aleks-dts-r278/plugins
pid=''
for f in /proc/[0-9]*/comm; do
  [ -r "$f" ] || continue
  x=$(cat "$f" 2>/dev/null || :)
  case "$x" in starfish-media-*)
    p=$(basename "$(dirname "$f")")
    if grep -Fq "$base/libgstaleksdts16dec.so" "/proc/$p/maps" 2>/dev/null; then pid=$p; break; fi
  ;; esac
done
if [ -z "$pid" ]; then echo 'STARFISH_WITH_DTS_PLUGIN=NOT_FOUND'; else
  printf 'STARFISH_WITH_DTS_PLUGIN=%s\n' "$pid"
fi
pulse=unix:/var/run/pulse/native
if command -v pactl >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  echo '=== PULSE SINK INPUTS (FIELDS ONLY) ==='
  tmp=$(timeout 7 pactl -s "$pulse" list sink-inputs 2>/dev/null)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%s\n' "$tmp" | awk '
      /^Sink Input #[0-9]+/ { x=$3; sub(/^#/,"",x); print "INPUT_ID=" x }
      /^[ \t]*Sink:/ {print "INPUT_SINK=" $2}
      /^[ \t]*Sample Specification:/ {sub(/^[ \t]*Sample Specification: /,""); print "INPUT_SAMPLE_SPEC=" $0}
      /^[ \t]*Corked:/ {print "INPUT_CORKED=" $2}
      /^[ \t]*Mute:/ {print "INPUT_MUTED=" $2}
      /^[ \t]*Buffer Latency:/ {print "INPUT_BUFFER_LATENCY_US=" $3}
      /^[ \t]*Sink Latency:/ {print "INPUT_SINK_LATENCY_US=" $3}
      /^[ \t]*application.process.id =/ {
        s=$0; sub(/^[ \t]*application.process.id = "/,"",s); sub(/".*/,"",s);
        if (s ~ /^[0-9]+$/) print "INPUT_OWNER_PID=" s
      }
    '
    printf '%s\n' "$tmp" | awk '/^[ \t]*application.process.id =/ {
       s=$0; sub(/^[ \t]*application.process.id = "/,"",s); sub(/".*/,"",s);
       if (s ~ /^[0-9]+$/) print s
    }' | sort -u | head -n 8 | while read -r owner; do
      [ -r "/proc/$owner/comm" ] || continue
      name=$(cat "/proc/$owner/comm" 2>/dev/null || :)
      printf 'INPUT_OWNER_PROC pid=%s comm=%s\n' "$owner" "$name"
    done
  else
    printf 'PULSE_SINK_INPUT_QUERY=ERROR_%s\n' "$rc"
  fi
  echo '=== PULSE DEFAULT OUTPUT ==='
  timeout 7 pactl -s "$pulse" list short sinks 2>/dev/null |
    awk '$2=="pcm_output" {print "PCM_OUTPUT_SINK_ID=" $1 " DRIVER=" $3 " FORMAT=" $4 " " $5 " " $6 " STATE=" $7}' |
    head -n 2 || :
  timeout 7 pactl -s "$pulse" list short sink-inputs 2>/dev/null |
    awk 'END {print "SINK_INPUT_COUNT=" NR}' || :
fi
echo '=== NATIVE LG ROUTING ==='
query() {
  label=$1; endpoint=$2
  response=$(timeout 6 luna-send -n 1 -w 2500 "$endpoint" '{}' 2>/dev/null)
  if [ "$?" -eq 0 ]; then
    printf 'QUERY=%s\n' "$label"
    printf '%s\n' "$response" |
      grep -Eo '"(returnValue|source|sink|codec|muted|outputMode)"[[:space:]]*:[[:space:]]*("[A-Za-z0-9_.-]{1,32}"|true|false)' |
      head -n 12 || :
  else
    printf 'QUERY=%s ERROR\n' "$label"
  fi
}
if command -v timeout >/dev/null 2>&1 && command -v luna-send >/dev/null 2>&1; then
  query audio 'luna://com.webos.service.audiooutput/audio/getStatus'
  query codec 'luna://com.webos.service.audio/tv/getAudioInputProperty'
fi
echo 'RESULT=R292_TOPOLOGY_CAPTURED_NO_CHANGES'
echo 'NOTE=PulseAudio input PID and Starfish DTS plugin PID may differ; association is not automatically proven.'
