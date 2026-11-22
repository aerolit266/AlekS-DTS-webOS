#!/bin/sh
# AlekS DTS R300 — hermetic timeout signal provenance regression.
# On the analysis host ONLY: never accesses TV/SSH/media/audio services.
# Records why a BusyBox timeout code 143 is ambiguous; opt-in USR1
# gives a different signature (138) than a child TERM (143).
set -eu
umask 077
LC_ALL=C; export LC_ALL
for tool in busybox timeout mktemp grep sleep; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'BLOCKED_MISSING=%s\n' "$tool"; exit 2;
  }
done
work=$(mktemp -d /tmp/aleks-dts-r300.XXXXXX) || exit 2
trap 'rm -rf "$work"' EXIT HUP INT TERM

bb_deadline_term=0
busybox timeout 1 sh -c 'printf "Got EOS\n"; exec sleep 4' \
  > "$work/bb_term.log" 2> "$work/bb_term.err" || bb_deadline_term=$?
bb_deadline_usr1=0
busybox timeout -s USR1 1 sh -c 'printf "Got EOS\n"; exec sleep 4' \
  > "$work/bb_usr1.log" 2> "$work/bb_usr1.err" || bb_deadline_usr1=$?
bb_natural_term=0
busybox timeout -s USR1 2 sh -c 'kill -TERM $$' \
  > "$work/natural.log" 2> "$work/natural.err" || bb_natural_term=$?
gnu_deadline_usr1=0
timeout -s USR1 1 sh -c 'printf "Got EOS\n"; exec sleep 4' \
  > "$work/gnu_usr1.log" 2> "$work/gnu_usr1.err" || gnu_deadline_usr1=$?
bb_clean=0
busybox timeout -s USR1 2 sh -c 'exit 0' \
  > "$work/clean.log" 2> "$work/clean.err" || bb_clean=$?

printf 'R300_BUSYBOX_DEFAULT_DEADLINE_EXIT=%s\n' "$bb_deadline_term"
printf 'R300_BUSYBOX_USR1_DEADLINE_EXIT=%s\n' "$bb_deadline_usr1"
printf 'R300_BUSYBOX_USR1_CHILD_TERM_EXIT=%s\n' "$bb_natural_term"
printf 'R300_GNU_USR1_DEADLINE_EXIT=%s\n' "$gnu_deadline_usr1"
printf 'R300_BUSYBOX_USR1_CLEAN_EXIT=%s\n' "$bb_clean"
if [ "$bb_deadline_term" -eq 143 ] &&
   [ "$bb_deadline_usr1" -eq 138 ] &&
   [ "$bb_natural_term" -eq 143 ] &&
   [ "$gnu_deadline_usr1" -eq 124 ] &&
   [ "$bb_clean" -eq 0 ] &&
   grep -q 'Got EOS' "$work/bb_term.log" &&
   grep -q 'Got EOS' "$work/bb_usr1.log" &&
   grep -q 'Got EOS' "$work/gnu_usr1.log"; then
  echo 'RESULT=R300_OFFLINE_TIMEOUT_SIGNAL_DIFFERENTIAL_PASS'
else
  echo 'RESULT=R300_OFFLINE_TIMEOUT_SIGNAL_DIFFERENTIAL_UNEXPECTED'
  exit 1
fi
echo 'NOTE=LG_VERSION_AND_TIMEOUT_CAUSALITY_NOT_VERIFIED; REAL_DTS_AUDIO_NOT_TESTED'
