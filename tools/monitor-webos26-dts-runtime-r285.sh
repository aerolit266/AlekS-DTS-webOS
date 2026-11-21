#!/bin/sh
# AlekS DTS R285: short read-only media-process stability monitor.
# Does not start/stop playback or change audio/system configuration.
# No process cmdlines, media names, file paths, raw log payloads or secrets printed.
set -u
LC_ALL=C; export LC_ALL
home=/var/lib/webosbrew/aleks-dts-r278
echo '=== ALEKS DTS R285 READ-ONLY 3-SAMPLE MONITOR ==='
date -u '+START_UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
for iteration in 1 2 3; do
  printf 'SAMPLE=%s\n' "$iteration"
  for service in umediaserver.service audiooutputd.service; do
    if command -v systemctl >/dev/null 2>&1; then
      state=$(systemctl is-active "$service" 2>/dev/null || :)
      printf 'SERVICE=%s STATE=%s\n' "$service" "$state"
    fi
  done
  num=0
  for namefile in /proc/[0-9]*/comm; do
    [ -r "$namefile" ] || continue
    name=$(cat "$namefile" 2>/dev/null || :)
    case "$name" in starfish-media-*|umediaserver|audiooutputd|audiod) : ;; *) continue ;; esac
    pid=$(basename "$(dirname "$namefile")")
    num=$((num + 1))
    [ "$num" -le 12 ] || continue
    statusfile=/proc/$pid/status
    if [ ! -r "$statusfile" ]; then
      printf 'PROCESS_GONE pid=%s\n' "$pid"
      continue
    fi
    rss=$(awk '$1=="VmRSS:" {print $2;found=1} END {if(!found) print "unknown"}' "$statusfile" 2>/dev/null)
    threads=$(awk '$1=="Threads:" {print $2;found=1} END {if(!found) print "unknown"}' "$statusfile" 2>/dev/null)
    state=$(awk '$1=="State:" {print $2;found=1} END {if(!found) print "unknown"}' "$statusfile" 2>/dev/null)
    ticks=$(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null || :)
    printf 'PROCESS name=%s pid=%s state=%s rss_kib=%s threads=%s cpu_ticks=%s\n' "$name" "$pid" "$state" "$rss" "$threads" "$ticks"
    case "$name" in starfish-media-*)
      for lib in libgstaleksdts.so libgstaleksdtsr130optin.so libgstaleksdts16dec.so; do
        if grep -Fq "$home/plugins/$lib" "/proc/$pid/maps" 2>/dev/null; then
          printf 'ALEKS_LOADED pid=%s lib=%s\n' "$pid" "$lib"
        fi
      done
      ;;
    esac
  done
  if command -v luna-send >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
    result=$(timeout 6 luna-send -n 1 -w 2500 luna://com.webos.service.audio/tv/getAudioInputProperty '{}' 2>/dev/null)
    if [ "$?" -eq 0 ]; then
      value=$(printf '%s\n' "$result" | grep -oE '"codec"[[:space:]]*:[[:space:]]*"[^"]{1,32}"' | head -n 1)
      if [ -n "$value" ]; then printf 'LG_AUDIO_%s\n' "$value"; else echo 'LG_AUDIO_CODEC=UNSPECIFIED'; fi
    else echo 'LG_AUDIO_QUERY=UNAVAILABLE'; fi
  fi
  if [ "$iteration" -lt 3 ]; then sleep 5; fi
done
echo 'RESULT=R285_SNAPSHOTS_CAPTURED_NO_CHANGES'
echo 'NOTE=Process stability and reported codec do not measure audible sound.'
