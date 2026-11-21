#!/bin/sh
# R283 LG webOS26: real playback audio-route diagnostic, READ ONLY.
# Run during video playback with DTS selected. No audio playback, restarts or mounts.
# Redacts media titles, private URIs, application arguments and full Luna payload.
set -u
LC_ALL=C
export LC_ALL
root=/var/lib/webosbrew/aleks-dts-r278
printf '=== ALEKS DTS R283 NATIVE AUDIO ROUTE (READ ONLY) ===\n'
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
printf '=== DTS PLUGIN MAPPINGS IN ACTIVE STARFISH ===\n'
count=0
for file in /proc/[0-9]*/comm; do
  [ -r "$file" ] || continue
  comm=$(cat "$file" 2>/dev/null || :)
  case "$comm" in starfish-media-*|starfish-media-pipeline) ;; *) continue ;; esac
  pid=$(basename "$(dirname "$file")")
  count=$((count + 1))
  printf 'STARFISH pid=%s\n' "$pid"
  for lib in libgstaleksdts.so libgstaleksdtscaps.so libgstaleksdtsr130optin.so libgstaleksdts16dec.so; do
    if grep -Fq "$root/plugins/$lib" "/proc/$pid/maps" 2>/dev/null; then
      printf '  MAPPED=%s\n' "$lib"
    fi
  done
done
printf 'STARFISH_COUNT=%s\n' "$count"
printf '=== LG CODEC RESOURCE CONFIG (COUNTS ONLY) ===\n'
cap=/etc/umediaserver/device_codec_capability_config.json
if [ -f "$cap" ]; then
  sha256sum "$cap" 2>/dev/null || :
  for expr in dts pcm ac3 eac3; do
    n=$(grep -Eio "$expr" "$cap" 2>/dev/null | wc -l)
    printf 'CAPABILITY_REFERENCE_%s=%s\n' "$expr" "$n"
  done
else
  printf 'CAPABILITY_CONFIG=ABSENT\n'
fi
printf '=== AUDIO ROUTE QUERY (SAFE FIELDS ONLY) ===\n'
q='luna://com.webos.service.audio/tv/getAudioInputProperty'
sent=no
for sender in luna-send luna-send-pub; do
  command -v "$sender" >/dev/null 2>&1 || continue
  if ! command -v timeout >/dev/null 2>&1; then
    printf 'LUNA_TIMEOUT_UNAVAILABLE\n'
    break
  fi
  response=$(timeout 6 "$sender" -n 1 -w 2500 "$q" '{}' 2>&1)
  ec=$?
  if [ "$ec" -eq 0 ]; then
    sent=yes
    printf 'LUNA_QUERY=RESPONDED sender=%s\n' "$sender"
    # Print ONLY allowlisted codec/routing fields (no private file names/URLs).
    printf '%s\n' "$response" |
      grep -Eo '"(returnValue|audioType|audioFormat|audioCodec|codecType|codec|audioMode|samplingRate|sampleRate|channelCount|channels|mute|muted|output|audioInputType|inputType)"[[:space:]]*:[[:space:]]*("[^"]{0,48}"|[0-9]+|true|false)' |
      head -n 30 || :
    for term in DTS PCM AC3 AAC unknown; do
      if printf '%s\n' "$response" | grep -Fqi "$term"; then
        printf 'LUNA_CODEC_WORD_SEEN=%s\n' "$term"
      fi
    done
    break
  else
    printf 'LUNA_QUERY=UNAVAILABLE sender=%s exit=%s\n' "$sender" "$ec"
  fi
done
[ "$sent" = yes ] || printf 'LUNA_ROUTE_STATUS=UNVERIFIED\n'
printf '=== MEDIA ERRORS IN RECENT SYSTEM JOURNAL (COUNTS ONLY) ===\n'
if command -v journalctl >/dev/null 2>&1; then
  for term in fakeadec acquired-resource no-resource not-negotiated ERROR failed-to-link no-audio; do
    result=$(journalctl --since '-3 min' -n 350 --no-pager -o cat 2>/dev/null |
      grep -Fic "$term" || :)
    printf 'JOURNAL_%s=%s\n' "$term" "$result"
  done
fi
printf 'RESULT=R283_CAPTURED_NO_CHANGES\n'
printf 'NOTE=Luna status may not describe a streaming-app pipeline; absence of a marker does not prove no failure.\n'
