#!/bin/sh
# AlekS DTS R284: observe LG native sink/renderer behavior while film plays.
# NO modifications to TV configuration, audio sink, media processes or registry.
# No media titles, paths, URLs, raw journal lines, full LS payload printed.
set -u
LC_ALL=C
export LC_ALL
echo '=== ALEKS DTS R284 LIVE NATIVE SINK PROBE / READ ONLY ==='
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
if command -v systemctl >/dev/null 2>&1; then
  for service in umediaserver.service audiooutputd.service; do
    printf 'UNIT=%s state=%s\n' "$service" "$(systemctl is-active "$service" 2>/dev/null || :)"
  done
fi
echo '=== LG NATIVE RENDERER EVENT COUNTS / LAST 3000 LOG LINES ==='
log=/var/log/legacy-log
if [ ! -r "$log" ]; then
  echo 'LG_LEGACY_LOG=UNAVAILABLE'
else
  for term in 'lgao_push_first_event' 'Caps is first or updated' 'same caps for normal' 'Connect ES Renderer' 'Restart renderer' 'Set pcm' 'no sound' 'Not negotiated' 'fakeadec' 'acquired-resource' 'DTS' ; do
    hits=$(tail -n 3000 "$log" 2>/dev/null | grep -aFic "$term" || :)
    printf 'LG_EVENT %s=%s\n' "$term" "$hits"
  done
  echo '=== RENDERER CODEC/PCM KEYWORDS IN RECENT MATCHING EVENTS ==='
  # Aggregate identifiers only; source log lines and file names never printed.
  tail -n 3000 "$log" 2>/dev/null |
    grep -aEi 'lgao_push_first_event|Caps is first or updated|same caps for normal|Connect ES Renderer|Restart renderer|Set pcm' |
    tail -n 100 |
    grep -aEoi 'audio/x-(raw|dts|unknown)|S(8|16LE|24LE|32LE)|F(32LE|64LE)|channels[=: ]{1,8}[0-9]{1,2}|rate[=: ]{1,8}[0-9]{4,6}|DTS(-HD)?|AC-?3|EAC3|PCM' |
    sort | uniq -c | head -n 25 || :
fi
echo '=== DSP DECODE MODULES (NAMES ONLY) ==='
if [ -d /proc/aaudio/processors/dsp0 ]; then
  find /proc/aaudio/processors/dsp0 -maxdepth 1 -name 'dec_*' -type d 2>/dev/null |
    sed 's|.*/||' | head -n 25 || :
else
  echo 'DSP_DECODER_DIR=UNAVAILABLE'
fi
echo '=== LG AUDIO INPUT PROPERTY (CODEC ONLY) ==='
if command -v timeout >/dev/null 2>&1; then
  for command_name in luna-send luna-send-pub; do
    command -v "$command_name" >/dev/null 2>&1 || continue
    result=$(timeout 5 "$command_name" -n 1 -w 2500 \
      luna://com.webos.service.audio/tv/getAudioInputProperty '{}' 2>/dev/null)
    code=$?
    [ "$code" -eq 0 ] || continue
    printf 'LUNA_SENDER=%s\n' "$command_name"
    printf '%s\n' "$result" |
      grep -Eo '"(returnValue|codec|audioType|audioFormat|channelCount|channels|mute|muted)"[[:space:]]*:[[:space:]]*("[^"]{0,40}"|[0-9]+|true|false)' |
      head -n 12 || :
    break
  done
fi
echo 'RESULT=R284_NATIVE_SINK_SNAPSHOT_CAPTURED_NO_DEVICE_CHANGES'
echo 'NOTE=Event counts cover a bounded log tail, not a precise time window. Compare DTS vs known-good AC3 playback.'
