#!/bin/sh
# AlekS DTS R291: ARC/eARC read-only audio routing checkpoint.
# No volume, sound output, ARC, firmware or service changes.
# Print only non-sensitive scalar fields, not full Luna data or device IDs.
set -u
LC_ALL=C; export LC_ALL
echo '=== ALEKS DTS R291 ARC/EARC ROUTING / READ ONLY ==='
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
if command -v luna-send >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  for name in arc audio; do
    if [ "$name" = arc ]; then
      endpoint='luna://com.webos.service.arccontroller/getARCState'
    else
      endpoint='luna://com.webos.service.audio/getSoundOutput'
    fi
    printf 'QUERY=%s\n' "$name"
    result=$(timeout 6 luna-send -n 1 -w 2500 "$endpoint" '{}' 2>/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ]; then
      printf 'QUERY_STATUS=UNAVAILABLE exit=%s\n' "$rc"
      continue
    fi
    # Do not dump ARCs detailed hardware capabilities or fingerprint device.
    vals=$(printf '%s\n' "$result" |
      grep -Eo '"(returnValue|arcActivation|audioDeviceType|earcMatProfile|earcATMOS|soundOutput|earcEnable|earcStatus|arcStatus|earcState|arcState)"[[:space:]]*:[[:space:]]*("[A-Za-z0-9_.-]{1,35}"|[0-9]{1,5}|true|false)' | head -n 20)
    if [ -n "$vals" ]; then
      printf '%s\n' "$vals"
    else
      echo 'QUERY_RESULT=NO_ALLOWLISTED_FIELDS'
    fi
  done
else
  echo 'LUNA_QUERY=UNAVAILABLE'
fi
echo '=== ALSA EARC MIXER GET (READ ONLY) ==='
if command -v amixer >/dev/null 2>&1; then
  for control in 'Sndout EARC OnOff' 'Sndout EARC Outputtype'; do
    printf 'MIXER_CONTROL=%s\n' "$control"
    result=$(timeout 6 amixer -c0 cget "name=$control" 2>/dev/null)
    code=$?
    if [ "$code" -ne 0 ]; then
      echo 'MIXER_QUERY=UNAVAILABLE'
      continue
    fi
    printf '%s\n' "$result" |
      grep -E '^[[:space:]]*:[[:space:]]*values=' |
      grep -Eo 'values=[A-Za-z0-9_, -]{1,50}' |
      head -n 2 || :
  done
else
  echo 'AMIXER=NOT_AVAILABLE'
fi
echo 'RESULT=R291_AUDIO_ROUTING_CAPTURED_NO_CHANGES'
echo 'NOTE=EARC enabled in software does not prove a receiver handshake or DTS bitstream passthrough.'
