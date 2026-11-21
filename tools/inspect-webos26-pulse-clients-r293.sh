#!/bin/sh
# AlekS DTS R293: read-only identify PulseAudio clients and media process ownership.
# No audio capture, media paths, application titles, IPC mutation or system writes.
set -u
LC_ALL=C;export LC_ALL
echo '=== R293 PULSE CLIENT TO STARFISH ASSOCIATION READ ONLY ==='
if ! command -v pactl >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1;then
 echo 'PULSE_TOOLS_UNAVAILABLE';exit 0
fi
pulse=unix:/var/run/pulse/native
clients=$(timeout 8 pactl -s "$pulse" list clients 2>/dev/null)
ret=$?
if [ "$ret" -ne 0 ];then
 echo 'PULSE_CLIENT_QUERY_ERROR';exit 0
fi
printf '%s\n' "$clients" | awk '
 /^Client #[0-9]+/ {c=$2; sub(/^#/,"",c)}
 /^[[:space:]]*application.process.id =/ {
   s=$0;sub(/^[[:space:]]*application.process.id = "/,"",s);sub(/".*/,"",s);
   if(s ~ /^[0-9]+$/)printf "PULSE_CLIENT_ID=%s PID=%s\n",c,s
 }' | while read -r a b;do
 pid=$(printf '%s\n' "$b"|sed 's/^PID=//')
 if [ -r "/proc/$pid/comm" ];then
   comm=$(cat "/proc/$pid/comm" 2>/dev/null || :)
   printf '%s %s COMM=%s\n' "$a" "$b" "$comm"
 else
   printf '%s %s COMM=EXITED\n' "$a" "$b"
 fi
done
echo '=== STARFISH DTS PROCESS IDENTITIES ==='
for commfile in /proc/[0-9]*/comm;do
 [ -r "$commfile" ] || continue
 name=$(cat "$commfile" 2>/dev/null || :)
 case "$name" in starfish-media-*)
   pid=$(basename "$(dirname "$commfile")")
   if grep -Fq 'libgstaleksdts16dec.so' "/proc/$pid/maps" 2>/dev/null;then
     printf 'STARFISH_DTS_PROCESS_PID=%s\n' "$pid"
   fi
 ;; esac
done
echo 'RESULT=R293_CLIENT_MAP_READONLY'
echo 'NOTE=Absence of a native PulseAudio client does not prove DTS bypasses it; other services may forward sound.'
