#!/bin/sh
# R308 kitchen DTS cold-start evidence. READ ONLY. No media playback or
# service, volume, firmware, plugin, mount, registry or recording changes.
# Usage: sh capture-kitchen-dts-first-start-r308.sh silent|audible|idle
set -u
LC_ALL=C; export LC_ALL
case "$1" in silent|audible|idle) stage=$1;;*) echo R308_INVALID_STAGE >&2;exit 2;;esac
arch=$(uname -m 2>/dev/null || :)
case "$arch" in armv7l|armv6l|arm|aarch64) :;;*) echo R308_NOT_AN_ARM_TV;exit 2;;esac
dir=/var/lib/webosbrew/aleks-dts-r278/plugins
printf 'STAGE=%s MACHINE=%s\n' "$stage" "$arch"
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
echo '=== ACTUAL INSTALLED LIBRARY HASHES ==='
for item in \
  'libgstaleksdts.so|5c3b798d4c1109414efc9209276dbf8b23466376f72f5bc71cf4144f3f5a1cbb' \
  'libgstaleksdts16dec.so|dfefb960d49d50ed7629cc4459ffaae8b420509cc9815d8337f6be7faaac18cf' \
  'libgstaleksdtscaps.so|1995a6b6030f6ddb895aeeea4017dcc71db8ebd6caace0107e1c5a33875f0605' \
  'libgstaleksdtsr130optin.so|9b7adb2744a9d7c329669974c15bcfc86ba62daf27efccb95e362c1928d602e0'
do
  name=$(printf '%s' "$item" | cut -d '|' -f 1)
  expected=$(printf '%s' "$item" | cut -d '|' -f 2)
  file=$dir/$name
  if [ -L "$file" ];then printf 'LIB=%s STATUS=SYMLINK_SKIPPED\n' "$name";continue;fi
  if [ ! -r "$file" ];then printf 'LIB=%s STATUS=UNREADABLE\n' "$name";continue;fi
  got=$(sha256sum "$file" 2>/dev/null | cut -d ' ' -f 1)
  if [ "$got" = "$expected" ];then matched=yes;else matched=no;fi
  printf 'LIB=%s SHA256=%s HALL_RELEASE_MATCH=%s\n' "$name" "$got" "$matched"
done
echo '=== PROCESS AND PCM STATE ==='
for service in umediaserver.service audiooutputd.service;do
  value=$(systemctl is-active "$service" 2>/dev/null || :)
  printf 'SERVICE=%s STATUS=%s\n' "$service" "$value"
done
count=0;holders=0
for f in /proc/[0-9]*/comm;do
  [ -r "$f" ] || continue
  label=$(head -n 1 "$f" 2>/dev/null || :)
  case "$label" in starfish-media-*) :;;*) continue;;esac
  count=$((count+1))
  p=$(basename "$(dirname "$f")")
  if grep -Fq "$dir/libgstaleksdts16dec.so" "/proc/$p/maps" 2>/dev/null;then
    holders=$((holders+1))
  fi
done
printf 'STARFISH=%s DTS_WRAPPER_HOLDERS=%s\n' "$count" "$holders"
pcm=/proc/asound/card0/pcm6p/sub0
if [ -r "$pcm/status" ];then
  pcm_state=$(awk '$1=="state:"{print $2;exit}' "$pcm/status")
  printf 'ALSA_PCM6=%s\n' "$pcm_state"
  if [ "$pcm_state" = RUNNING ];then
    a=$(awk '$1=="hw_ptr"{print $3;exit}' "$pcm/status" 2>/dev/null)
    b=$(awk '$1=="appl_ptr"{print $3;exit}' "$pcm/status" 2>/dev/null)
    sleep 2
    c=$(awk '$1=="hw_ptr"{print $3;exit}' "$pcm/status" 2>/dev/null)
    d=$(awk '$1=="appl_ptr"{print $3;exit}' "$pcm/status" 2>/dev/null)
    case "$a:$b:$c:$d" in
      *[!0-9:]*|:*|*::*) echo ALSA_POINTER_DELTA=UNKNOWN ;;
      *) if [ "$c" -ge "$a" ] && [ "$d" -ge "$b" ];then
           printf 'ALSA_HW_FRAMES_2S=%s ALSA_APPL_FRAMES_2S=%s\n' "$((c-a))" "$((d-b))"
         else echo ALSA_POINTER_DELTA=RESET_OR_WRAP;fi ;;
    esac
  fi
else echo ALSA_PCM6=UNAVAILABLE;fi
echo '=== AUDIO POLICY READ ONLY ==='
query() {
  title=$1;url=$2
  printf 'QUERY=%s\n' "$title"
  if ! command -v luna-send >/dev/null 2>&1;then echo QUERY_STATUS=NO_LUNA;return;fi
  data=$(timeout 5 luna-send -n 1 -w 2200 "$url" '{}' 2>/dev/null);rc=$?
  if [ "$rc" -ne 0 ];then printf 'QUERY_STATUS=ERROR_%s\n' "$rc";return;fi
  if printf '%s' "$data" | grep -Eq '"returnValue"[[:space:]]*:[[:space:]]*false';then
    echo QUERY_STATUS=LS2_FAILED;return
  fi
  if ! printf '%s' "$data" | grep -Eq '"returnValue"[[:space:]]*:[[:space:]]*true';then
    echo QUERY_STATUS=UNKNOWN;return
  fi
  printf '%s' "$data" | grep -Eo '"(codec|source|sink|soundOutput|outputMode|muted|streamType)"[[:space:]]*:[[:space:]]*("[A-Za-z0-9_.-]{1,40}"|true|false)' | head -n 16 || :
  echo QUERY_STATUS=VALUES_UNGROUPED
}
query CODEC 'luna://com.webos.service.audio/tv/getAudioInputProperty'
query OUTPUT 'luna://com.webos.service.audiooutput/audio/getStatus'
echo 'RESULT=R308_READ_ONLY_CAPTURE_COMPLETE'
echo 'NOTE=No media audio samples recorded; PCM pointer movement does not prove DTS audibility.'
