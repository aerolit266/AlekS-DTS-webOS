#!/bin/sh
# R286: Read-only LG/ALSA audio output FIFO movement check.
# Does not record audio, open sound devices or change playback/sink settings.
# Hardware pointer movement is not proof that samples are nonzero or audible.
set -u
LC_ALL=C; export LC_ALL
echo '=== ALEKS DTS R286: NATIVE AUDIO OUTPUT SNAPSHOT (READ ONLY) ==='
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
f=''
for candidate in /proc/asound/card*/pcm*p/sub*/status; do
  [ -r "$candidate" ] || continue
  state=$(awk '$1=="state:"{print $2;exit}' "$candidate" 2>/dev/null)
  if [ "$state" = RUNNING ]; then
    f=$candidate
    break
  fi
done
if [ -z "$f" ]; then
  echo 'ALSA_PLAYBACK_STREAM=NO_RUNNING_STREAM_DISCOVERED'
  echo 'RESULT=R286_ALSA_STREAM_UNAVAILABLE; MAY_USE_SEPARATE_DSP_PATH'
  exit 0
fi
owner=$(awk '$1=="owner_pid" {print $3;exit}' "$f" 2>/dev/null)
name=unknown
if [ -n "$owner" ] && [ -r "/proc/$owner/comm" ]; then
  name=$(cat "/proc/$owner/comm" 2>/dev/null)
fi
hwfile="$(dirname "$f")/hw_params"
format=$(awk '$1=="format:"{print $2;exit}' "$hwfile" 2>/dev/null)
channels=$(awk '$1=="channels:"{print $2;exit}' "$hwfile" 2>/dev/null)
rate=$(awk '$1=="rate:"{print $2;exit}' "$hwfile" 2>/dev/null)
printf 'STREAM=%s\n' "$f"
printf 'OWNER_NAME=%s OWNER_PID=%s\n' "$name" "$owner"
printf 'FORMAT=%s CHANNELS=%s RATE_HZ=%s\n' "$format" "$channels" "$rate"
h1=$(awk '$1=="hw_ptr"{print $3;exit}' "$f" 2>/dev/null)
a1=$(awk '$1=="appl_ptr"{print $3;exit}' "$f" 2>/dev/null)
t1=$(awk '$1=="tstamp"{print $3;exit}' "$f" 2>/dev/null)
printf 'SAMPLE1_HW_PTR=%s APPL_PTR=%s\n' "$h1" "$a1"
sleep 5
state2=$(awk '$1=="state:"{print $2;exit}' "$f" 2>/dev/null)
h2=$(awk '$1=="hw_ptr"{print $3;exit}' "$f" 2>/dev/null)
a2=$(awk '$1=="appl_ptr"{print $3;exit}' "$f" 2>/dev/null)
t2=$(awk '$1=="tstamp"{print $3;exit}' "$f" 2>/dev/null)
printf 'SAMPLE2_STATE=%s HW_PTR=%s APPL_PTR=%s\n' "$state2" "$h2" "$a2"
if [ "$state2" = RUNNING ] && [ -n "$h1" ] && [ -n "$h2" ] &&
   [ "$h2" -ge "$h1" ] 2>/dev/null; then
  delta=$((h2-h1))
  printf 'HW_FRAMES_ADVANCED=%s\n' "$delta"
  if [ -n "$t1" ] && [ -n "$t2" ]; then
    awk -v frames="$delta" -v t1="$t1" -v t2="$t2" 'BEGIN{dt=t2-t1;if(dt>0) printf "HW_POINTER_RATE_FPS=%.0f OBSERVED_SECONDS=%.3f\n",frames/dt,dt;else print "HW_POINTER_RATE=UNAVAILABLE"}'
  fi
  [ "$delta" -gt 0 ] && echo 'ALSA_HW_POINTER=ADVANCING' ||
    echo 'ALSA_HW_POINTER=STATIONARY'
else
  echo 'ALSA_HW_POINTER=INCONCLUSIVE_OR_DEVICE_CHANGED'
fi
if command -v luna-send >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  reply=$(timeout 5 luna-send -n 1 -w 2500 \
    luna://com.webos.service.audio/tv/getAudioInputProperty '{}' 2>/dev/null)
  if [ "$?" -eq 0 ]; then
    codec=$(printf '%s\n' "$reply" | grep -oE '"codec"[[:space:]]*:[[:space:]]*"[^"]{1,30}"' | head -n1)
    printf 'LG_AUDIO_%s\n' "$codec"
  fi
fi
echo 'RESULT=R286_READ_ONLY_ALSA_OUTPUT_MEASURED; AUDIBILITY_NOT_MEASURED'
