#!/bin/sh
# AlekS DTS R287: bounded 60s media/ALSA stability monitor.
# READ ONLY: no recording, playback control, service restart, kernel flag changes.
# User's media paths, network URLs, process command lines and log entries are not read.
set -u
LC_ALL=C
export LC_ALL
home=/var/lib/webosbrew/aleks-dts-r278
out=/proc/asound/card0/pcm6p/sub0
printf '%s\n' '=== R287 DTS / ALSA REAL-TIME PASSIVE STABILITY (6x10s) ==='
date -u '+BEGIN_UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
echo 'INFO=No playback interruption; no samples or sound captured'
prev_pid=''
prev_hw=''
prev_cpu=''
all_codec_dts=1
pid_changes=0
running=0
forward=0
readings=0
first_rss=''
last_rss=''
for i in 1 2 3 4 5 6; do
  printf 'SAMPLE=%s\n' "$i"
  date -u '+UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
  if command -v systemctl >/dev/null 2>&1; then
    printf 'UMS=%s OUTPUTD=%s\n' "$(systemctl is-active umediaserver.service 2>/dev/null || :)" "$(systemctl is-active audiooutputd.service 2>/dev/null || :)"
  fi
  pid=''
  for f in /proc/[0-9]*/comm; do
    [ -r "$f" ] || continue
    comm=$(cat "$f" 2>/dev/null || :)
    case "$comm" in
      starfish-media-*)
        n=$(basename "$(dirname "$f")")
        if grep -Fq "$home/plugins/libgstaleksdts16dec.so" "/proc/$n/maps" 2>/dev/null; then
          pid=$n
          break
        fi
      ;;
    esac
  done
  if [ -n "$pid" ]; then
    rss=$(awk '$1=="VmRSS:" {print $2; exit}' "/proc/$pid/status" 2>/dev/null || :)
    th=$(awk '$1=="Threads:" {print $2; exit}' "/proc/$pid/status" 2>/dev/null || :)
    cpu=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null || :)
    printf 'DTS_STARFISH pid=%s rss_kib=%s threads=%s cpu_ticks=%s\n' "$pid" "$rss" "$th" "$cpu"
    for lib in libgstaleksdts.so libgstaleksdtsr130optin.so libgstaleksdts16dec.so; do
      if grep -Fq "$home/plugins/$lib" "/proc/$pid/maps" 2>/dev/null; then
        printf 'LIB_LOADED=%s\n' "$lib"
      else
        printf 'LIB_MISSING=%s\n' "$lib"
      fi
    done
    [ -z "$first_rss" ] && first_rss=$rss
    last_rss=$rss
    if [ -n "$prev_pid" ] && [ "$prev_pid" != "$pid" ]; then
      pid_changes=$((pid_changes+1))
    fi
    if [ -n "$prev_cpu" ] && [ -n "$cpu" ]; then
      printf 'CPU_TICKS_DELTA=%s\n' "$((cpu-prev_cpu))"
    fi
    prev_pid=$pid
    prev_cpu=$cpu
  else
    echo 'DTS_STARFISH=NOT_FOUND'
  fi
  state=''
  hw=''
  if [ -r "$out/status" ]; then
    state=$(awk '$1=="state:"{print $2;exit}' "$out/status" 2>/dev/null || :)
    [ -n "$state" ] || state=closed
    if [ "$state" = RUNNING ]; then
      running=$((running+1))
      hw=$(awk '$1=="hw_ptr"{print $3;exit}' "$out/status" 2>/dev/null || :)
      if [ -n "$hw" ] && [ -n "$prev_hw" ]; then
        if [ "$hw" -ge "$prev_hw" ]; then
          delta=$((hw-prev_hw))
          [ "$delta" -gt 0 ] && forward=$((forward+1))
          printf 'ALSA_HW_DELTA_FRAMES=%s\n' "$delta"
        else
          echo 'ALSA_HW_PTR_RESET_OR_WRAP=yes'
        fi
      fi
      prev_hw=$hw
    fi
  else
    state=unavailable
  fi
  printf 'ALSA_PCM6_STATE=%s HW_PTR=%s\n' "$state" "$hw"
  if command -v luna-send >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
    result=$(timeout 5 luna-send -n 1 -w 2500 luna://com.webos.service.audio/tv/getAudioInputProperty '{}' 2>/dev/null)
    codec=$(printf '%s\n' "$result" | grep -oE '"codec"[[:space:]]*:[[:space:]]*"[^"]{1,20}"' | head -n 1)
    printf 'LG_AUDIO_%s\n' "$codec"
    [ "$codec" = '"codec":"dts"' ] || all_codec_dts=0
  else
    all_codec_dts=0
    echo 'LG_AUDIO_CODEC=UNKNOWN'
  fi
  readings=$((readings+1))
  [ "$i" = 6 ] || sleep 10
done
printf 'SUMMARY samples=%s dts_pid_changes=%s alsa_running_samples=%s alsa_advance_intervals=%s\n' "$readings" "$pid_changes" "$running" "$forward"
printf 'SUMMARY_STARFISH_RSS first_kib=%s last_kib=%s\n' "$first_rss" "$last_rss"
printf 'SUMMARY_LUNA_CODEC_DTS_ALL=%s\n' "$all_codec_dts"
echo 'RESULT=R287_PASSIVE_MONITOR_COMPLETED; AUDIBILITY_NOT_MEASURED'
