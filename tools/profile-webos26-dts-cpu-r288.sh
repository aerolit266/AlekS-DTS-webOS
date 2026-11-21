#!/bin/sh
# AlekS DTS R288 working-session CPU profile (read-only).
# Thread CPU deltas only, no user media, args, logs, audio payload or DRM data.
set -eu
LC_ALL=C;export LC_ALL
home=/var/lib/webosbrew/aleks-dts-r278
pid=''
for x in /proc/[0-9]*/comm; do
 [ -r "$x" ] || continue
 v=$(cat "$x" 2>/dev/null || :)
 case "$v" in starfish-media-*)
   n=$(basename "$(dirname "$x")")
   if grep -Fq "$home/plugins/libgstaleksdts16dec.so" "/proc/$n/maps" 2>/dev/null; then pid=$n; break; fi
 ;; esac
done
echo '=== ALEKS DTS R288 READONLY CPU SAMPLE ==='
if [ -z "$pid" ]; then echo 'DTS_STARFISH=NOT_RUNNING'; echo 'RESULT=NO_ACTIVE_DTS'; exit 0; fi
printf 'PID=%s\n' "$pid"
tmp=$(mktemp -d /tmp/aleks-dts-r288.XXXXXX) || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
snap() {
 for f in /proc/$pid/task/[0-9]*/stat; do
  [ -r "$f" ] || continue
  tid=$(basename "$(dirname "$f")")
  # Extract after the FINAL ')' in /proc/stat: supports thread names with spaces.
  ticks=$(sed 's/^.*) //' "$f" 2>/dev/null | awk '{printf "%.0f",$12+$13}')
  [ -n "$ticks" ] || continue
  printf '%s %s\n' "$tid" "$ticks"
 done | sort -n
}
snap > "$tmp/before"
before_count=$(wc -l < "$tmp/before")
sleep 10
if [ ! -d "/proc/$pid/task" ]; then
 echo 'MEDIA_PROCESS_RESTARTED=yes';echo 'RESULT=CPU_BASELINE_INTERRUPTED';exit 0
fi
snap > "$tmp/after"
after_count=$(wc -l < "$tmp/after")
printf 'THREADS_BEFORE=%s THREADS_AFTER=%s\n' "$before_count" "$after_count"
join "$tmp/before" "$tmp/after" |
 awk '{d=$3-$2; if(d>=0) {printf "%s %.0f\n",$1,d;sum+=d;count++}} END {printf "TOTAL_TICKS %.0f\n",sum}' > "$tmp/diff"
printf 'CLK_TCK=%s\n' "$(getconf CLK_TCK 2>/dev/null || echo UNKNOWN)"
grep '^TOTAL_TICKS ' "$tmp/diff" || :
echo '=== TOP 10 MEDIA THREADS BY CPU TICKS IN 10s ==='
grep -v '^TOTAL_TICKS ' "$tmp/diff" | sort -k2,2nr | head -n 10 |
while read -r tid delta; do
  label=$(cat "/proc/$pid/task/$tid/comm" 2>/dev/null | tr -cd 'A-Za-z0-9_.- ' | cut -c1-32)
  printf 'TID=%s THREAD=%s TICKS_DELTA=%s\n' "$tid" "$label" "$delta"
done
echo 'RESULT=R288_CPU_BASELINE_CAPTURED; NO_CHANGES'
echo 'NOTE=Thread CPU is for the entire media pipeline, not isolated DTS decoder.'
