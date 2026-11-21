#!/bin/sh
# AlekS DTS R290 - read-only LG audio output/mute state during working DTS.
# APIs are queries only. No sound output, volume, mute, service, or firmware changes.
# Only allowlisted fields are printed; no full LS2 response or media paths.
set -u
LC_ALL=C
export LC_ALL
printf '%s\n' '=== R290 AUDIO OUTPUT / MUTE ROUTE READ ONLY ==='
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
if ! command -v luna-send >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
 echo 'LUNA_QUERY=UNAVAILABLE'
 exit 0
fi
query() {
  label=$1
  url=$2
  payload=$3
  printf 'QUERY=%s\n' "$label"
  result=$(timeout 6 luna-send -n 1 -w 2500 "$url" "$payload" 2>/dev/null)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'STATUS=NO_RESPONSE exit=%s\n' "$rc"
    return
  fi
  # Only single, known-small primitive fields. No raw JSON or secret data.
  filtered=$(printf '%s\n' "$result" |
    grep -Eo '"(returnValue|soundOutput|outputMode|muted|mute|volume|codec|errorCode|source|sink)"[[:space:]]*:[[:space:]]*("[A-Za-z0-9_.-]{1,35}"|[0-9]{1,5}|true|false)' |
    head -n 16)
  if [ -n "$filtered" ]; then
    printf '%s\n' "$filtered"
  else
    echo 'STATUS=RESPONSE_NO_ALLOWLISTED_FIELDS'
  fi
}
query 'LG_AUDIO_CODEC' 'luna://com.webos.service.audio/tv/getAudioInputProperty' '{}'
query 'LG_AUDIO_OUTPUT' 'luna://com.webos.service.audio/getSoundOutput' '{"subscribe":false}'
query 'LG_MASTER_VOLUME' 'luna://com.webos.service.audio/master/getVolume' '{"subscribe":false}'
query 'LG_AUDIOOUTPUT_CONNECTIONS' 'luna://com.webos.service.audiooutput/audio/getStatus' '{}'
query 'LG_AUDIOOUTPUT_DEVICE_VOLUME' 'luna://com.webos.service.audiooutput/audio/volume/getStatus' '{}'
echo '=== ALSA CURRENT OUTPUT (NATIVE DRIVER) ==='
status=/proc/asound/card0/pcm6p/sub0/status
if [ -r "$status" ]; then
  state=$(awk '$1=="state:"{print $2;exit}' "$status" 2>/dev/null)
  [ -n "$state" ] || state=closed
  printf 'PCM6_STATE=%s\n' "$state"
else
  echo 'PCM6_STATE=UNAVAILABLE'
fi
echo 'RESULT=R290_QUERY_COMPLETE_NO_CHANGES'
echo 'NOTE=webOS OSE LS2 methods may not exist or be permitted on LG TV firmware.'
