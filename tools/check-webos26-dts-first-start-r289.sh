#!/bin/sh
# AlekS DTS webOS26 R289. Passive first-start vs working-session classifier.
# Does not play/pause/restart media, record audio, modify registry or system files.
# Output is safe for public logs: no titles, paths, command lines or raw Luna payload.
set -u
LC_ALL=C; export LC_ALL
root=/var/lib/webosbrew/aleks-dts-r278/plugins
pcm=/proc/asound/card0/pcm6p/sub0
echo '=== ALEKS DTS R289 STARTUP / AUDIO ROUTE SNAPSHOT (READ ONLY) ==='
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
if command -v systemctl >/dev/null 2>&1; then
  printf 'UMS=%s\n' "$(systemctl is-active umediaserver.service 2>/dev/null || :)"
  printf 'OUTPUTD=%s\n' "$(systemctl is-active audiooutputd.service 2>/dev/null || :)"
fi
pid=''
for file in /proc/[0-9]*/comm; do
  [ -r "$file" ] || continue
  label=$(cat "$file" 2>/dev/null || :)
  case "$label" in
    starfish-media-*)
      n=$(basename "$(dirname "$file")")
      if grep -Fq "$root/libgstaleksdts16dec.so" "/proc/$n/maps" 2>/dev/null; then pid=$n; break; fi
    ;;
  esac
done
if [ -z "$pid" ]; then
  echo 'DTS_STARFISH=NOT_FOUND'
else
  printf 'DTS_STARFISH_PID=%s\n' "$pid"
  for lib in libgstaleksdts.so libgstaleksdtsr130optin.so libgstaleksdts16dec.so libgstaleksdtscaps.so; do
    if grep -Fq "$root/$lib" "/proc/$pid/maps" 2>/dev/null; then
      printf 'PLUGIN_%s=LOADED\n' "$lib"
    else
      printf 'PLUGIN_%s=NOT_MAPPED\n' "$lib"
    fi
  done
  awk '/^VmRSS:/{printf "STARFISH_RSS_KIB=%s\n",$2} /^Threads:/{printf "STARFISH_THREADS=%s\n",$2}' "/proc/$pid/status" 2>/dev/null || :
fi
if [ -r "$pcm/status" ]; then
  state=$(awk '$1=="state:"{print $2;exit}' "$pcm/status" 2>/dev/null || :)
  [ -n "$state" ] || state=closed
  printf 'ALSA_PCM6_STATE=%s\n' "$state"
  if [ "$state" = RUNNING ]; then
    awk '$1=="format:"{printf "PCM_FORMAT=%s\n",$2} $1=="channels:"{printf "PCM_CHANNELS=%s\n",$2} $1=="rate:"{printf "PCM_RATE=%s\n",$2}' "$pcm/hw_params" 2>/dev/null || :
    owner=$(awk '$1=="owner_pid"{print $3;exit}' "$pcm/status" 2>/dev/null || :)
    if [ -n "$owner" ] && [ -r "/proc/$owner/comm" ]; then
      owner_name=$(cat "/proc/$owner/comm" 2>/dev/null || :)
      printf 'PCM_OWNER_NAME=%s\n' "$owner_name"
    fi
    h1=$(awk '$1=="hw_ptr"{print $3;exit}' "$pcm/status" 2>/dev/null || :)
    a1=$(awk '$1=="appl_ptr"{print $3;exit}' "$pcm/status" 2>/dev/null || :)
    sleep 4
    h2=$(awk '$1=="hw_ptr"{print $3;exit}' "$pcm/status" 2>/dev/null || :)
    a2=$(awk '$1=="appl_ptr"{print $3;exit}' "$pcm/status" 2>/dev/null || :)
    state2=$(awk '$1=="state:"{print $2;exit}' "$pcm/status" 2>/dev/null || :)
    if [ "$state2" = RUNNING ] && [ -n "$h1" ] && [ -n "$h2" ] && [ "$h2" -ge "$h1" ] 2>/dev/null; then
      printf 'PCM_HW_DELTA_FRAMES=%s\n' "$((h2-h1))"
      if [ "$h2" -gt "$h1" ]; then echo 'PCM_HW_ADVANCE=YES'; else echo 'PCM_HW_ADVANCE=NO'; fi
    else
      echo 'PCM_HW_ADVANCE=INCONCLUSIVE'
    fi
    if [ -n "$a1" ] && [ -n "$a2" ] && [ "$a2" -ge "$a1" ] 2>/dev/null; then
      printf 'PCM_APP_DELTA_FRAMES=%s\n' "$((a2-a1))"
    fi
  fi
else
  echo 'ALSA_PCM6=UNAVAILABLE'
fi
if command -v timeout >/dev/null 2>&1 && command -v luna-send >/dev/null 2>&1; then
  reply=$(timeout 6 luna-send -n 1 -w 2500 \
    luna://com.webos.service.audio/tv/getAudioInputProperty '{}' 2>/dev/null)
  code=$?
  if [ "$code" -eq 0 ]; then
    val=$(printf '%s\n' "$reply" | grep -Eo '"codec"[[:space:]]*:[[:space:]]*"[^"]{1,30}"' | head -n1)
    [ -n "$val" ] && printf 'LG_AUDIO_%s\n' "$val" || echo 'LG_AUDIO_CODEC=NOT_REPORTED'
  else
    echo 'LG_AUDIO_QUERY=UNAVAILABLE'
  fi
else
  echo 'LG_AUDIO_QUERY=UNSUPPORTED'
fi
echo 'RESULT=R289_SAFE_SNAPSHOT_COMPLETE'
echo 'IMPORTANT=PCM pointer movement does not prove nonzero samples or audible sound.'
