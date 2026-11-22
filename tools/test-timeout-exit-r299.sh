#!/bin/sh
# R299: independent OFFLINE timeout-exit provenance test.
# No LG, DTS stream, GStreamer plugin, audio or external SSH access.
# Demonstrates that EOS marker + exit143 may be caused by a timeout wrapper.
set -eu
umask 077
LC_ALL=C
export LC_ALL
work=$(mktemp -d /tmp/aleks-dts-r299.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
echo '=== R299 TIMEOUT EXIT STATUS PROVENANCE (OFFLINE) ==='
for cmd in timeout busybox sleep grep; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "RESULT=R299_DEPENDENCY_MISSING_$cmd"
    exit 2
  }
done
busybox --help 2>&1 | head -n 2 || :
# The time limit is one second. The mock only prints the same EOS phrase
# as gst-launch and then sleeps; exec prevents orphan subprocesses.
gnu_code=0
timeout 1 sh -c 'printf "Got EOS from element pipeline0\n"; exec sleep 4' \
    > "$work/gnu.log" 2> "$work/gnu.err" || gnu_code=$?
bb_code=0
busybox timeout 1 sh -c 'printf "Got EOS from element pipeline0\n"; exec sleep 4' \
    > "$work/busybox.log" 2> "$work/busybox.err" || bb_code=$?
printf 'GNU_TIMEOUT_EXPIRED_EXIT=%s EOS_MARKER=%s\n' "$gnu_code" \
    "$(grep -c 'Got EOS' "$work/gnu.log" || :)"
printf 'BUSYBOX_TIMEOUT_EXPIRED_EXIT=%s EOS_MARKER=%s\n' "$bb_code" \
    "$(grep -c 'Got EOS' "$work/busybox.log" || :)"
# A child which itself chooses exit 143 returns exactly the same code as
# BusyBox timing out. Thus a numeric exit143 alone cannot prove provenance.
natural_code=0
busybox timeout 2 sh -c 'exit 143' > "$work/natural.log" 2>&1 || natural_code=$?
echo "BUSYBOX_CHILD_EXPLICIT_143_EXIT=$natural_code"
clean_code=0
busybox timeout 2 sh -c 'exit 0' > "$work/clean.log" 2>&1 || clean_code=$?
echo "BUSYBOX_CHILD_CLEAN_EXIT=$clean_code"

if [ "$gnu_code" -eq 124 ] && [ "$bb_code" -eq 143 ] &&
   [ "$natural_code" -eq 143 ] && [ "$clean_code" -eq 0 ] &&
   grep -q 'Got EOS' "$work/gnu.log" &&
   grep -q 'Got EOS' "$work/busybox.log"; then
  echo 'RESULT=R299_OFFLINE_TIMEOUT_SEMANTICS_PASS'
else
  echo 'RESULT=R299_TIMEOUT_SEMANTICS_DIFFER; NOT_ALL_IMPLEMENTATIONS_MATCH'
  exit 1
fi
echo 'INTERPRETATION=EOS_PLUS_143_COMPATIBLE_WITH_BUSYBOX_DEADLINE'
echo 'CAUSAL_PROOF=NO; ACTUAL_LG_TIMEOUT_IMPLEMENTATION=NOT_CHECKED'
