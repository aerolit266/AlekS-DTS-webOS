#!/bin/sh
# AlekS DTS webOS26 - read-only live native playback probe.
# Run DURING DTS Core playback in built-in LG Media Player.
# No service restart, no media control, no system writes, no process arguments,
# no private environment values, no playback file titles in the output.
set -u
LC_ALL=C
export LC_ALL
prefix=/var/lib/webosbrew/aleks-dts-r278/plugins
printf '=== ALEKS DTS NATIVE PLAYBACK PROCESS PROBE (READ ONLY) ===\n'
if command -v systemctl >/dev/null 2>&1; then
  state=$(systemctl is-active umediaserver.service 2>/dev/null || :)
  printf 'MEDIA_SERVICE=%s\n' "$state"
fi
count=0
for maps in /proc/[0-9]*/maps; do
  [ -r "$maps" ] || continue
  pid=$(basename "$(dirname "$maps")")
  comm=$(cat "/proc/$pid/comm" 2>/dev/null || :)
  # Only exact AlekS DTS plugin paths are checked; unrelated maps are never printed.
  if grep -Fq "$prefix/libgstaleksdts" "$maps" 2>/dev/null; then
    count=$((count+1))
    printf 'PLUGIN_MAPPED process=%s pid=%s\n' "$comm" "$pid"
    for plugin in libgstaleksdts.so libgstaleksdtscaps.so libgstaleksdtsr130optin.so libgstaleksdts16dec.so; do
      if grep -Fq "$prefix/$plugin" "$maps" 2>/dev/null; then
        printf '  LOADED %s\n' "$plugin"
      fi
    done
  fi
done
if [ "$count" -gt 0 ]; then
  printf 'RESULT=DTS_PLUGIN_MAPPED_IN_%s_PROCESSES; DECODING_AND_SOUND_NOT_PROVEN\n' "$count"
else
  printf 'RESULT=NO_DTS_PLUGIN_MAPPED_AT_SAMPLE_TIME; INCONCLUSIVE\n'
fi
printf 'NOTE=Run during active native LG player DTS playback; audible sound must be tested separately.\n'
exit 0
