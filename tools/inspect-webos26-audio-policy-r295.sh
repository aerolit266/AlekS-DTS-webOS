#!/bin/sh
# R295: passive webOS audio policy / UMI resource probe.
# READ ONLY: no subscribe, audio connect/disconnect, mute, playback or restart.
# Outputs allowlisted scalar fields and counts, never full payload or media IDs.
set -u
LC_ALL=C
export LC_ALL
echo '=== ALEKS DTS R295 NATIVE AUDIO POLICY / UMI PROBE (READ ONLY) ==='
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
if ! command -v luna-send >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
  echo 'RESULT=R295_BLOCKED_NO_LUNA_OR_TIMEOUT'
  exit 0
fi
query() {
  label=$1
  endpoint=$2
  payload=$3
  printf 'QUERY=%s\n' "$label"
  reply=$(timeout 6 luna-send -n 1 -w 2500 "$endpoint" "$payload" 2>/dev/null)
  code=$?
  if [ "$code" -ne 0 ]; then
    printf 'QUERY_STATUS=UNAVAILABLE exit=%s\n' "$code"
    return
  fi
  # According to LS2, returnValue=false is an API failure, NOT a
  # successful status query. Treat missing success as unknown as well.
  if printf '%s\n' "$reply" | grep -Eq '"returnValue"[[:space:]]*:[[:space:]]*false'; then
    echo 'QUERY_STATUS=API_RETURN_FALSE'
    printf '%s\n' "$reply" | grep -Eo '"errorCode"[[:space:]]*:[[:space:]]*-?[0-9]{1,5}' | head -n 1 || :
    return
  fi
  if ! printf '%s\n' "$reply" | grep -Eq '"returnValue"[[:space:]]*:[[:space:]]*true'; then
    echo 'QUERY_STATUS=NO_SUCCESS_MARKER'
    return
  fi
  # Count only, not print the raw arrays or any connection/session IDs.
  count=$(printf '%s\n' "$reply" | grep -oE '"(source|streamType|audioType)"[[:space:]]*:' | wc -l)
  printf 'MATCHING_AUDIO_FIELDS=%s\n' "$count"
  printf '%s\n' "$reply" |
    grep -Eo '"(returnValue|subscribed|codec|source|sourcePort|sink|streamType|audioType|muted|muteStatus|activeStatus|policyStatus|outputMode|inputVolume|errorCode)"[[:space:]]*:[[:space:]]*("[A-Za-z0-9_.-]{1,35}"|-?[0-9]{1,5}|true|false)' |
    head -n 32 || :
  printf 'QUERY_STATUS=RESPONDED_RETURN_TRUE; VALUES_NOT_LINKED_TO_ARRAY_OBJECTS\n'
}
# Both methods documented on webOS OSE; LG consumer firmware may differ.
# No subscription, connection setup or playback requested.
query 'AUDIO_UMI_STATUS' 'luna://com.webos.service.audio/UMI/getStatus' '{}'
query 'AUDIO_STREAM_STATUS' 'luna://com.webos.service.audio/getStreamStatus' '{"subscribe":false}'
query 'AUDIOOUTPUT_STATUS' 'luna://com.webos.service.audiooutput/audio/getStatus' '{}'
query 'AUDIO_INPUT_PROPERTY' 'luna://com.webos.service.audio/tv/getAudioInputProperty' '{}'
echo 'RESULT=R295_POLICY_QUERY_COMPLETED_NO_DEVICE_CHANGES'
echo 'NOTE=Fields are ungrouped and may describe different resources; do not infer which source owns DTS or audible audio.'
