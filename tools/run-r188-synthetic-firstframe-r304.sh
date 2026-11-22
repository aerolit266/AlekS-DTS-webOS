#!/bin/sh
# R304 synthetic-only C99 bounded DTS frame assembler QA.
# No network, LG, DTS playback, firmware changes or original R122 substitution.
# Uses the pinned ORIGINAL R188 header on a local lab host and a visibly
# separate synthetic test double, NEVER stages it into production directories.
set -eu
umask 077
LC_ALL=C; export LC_ALL
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
header=/opt/gamefree24-vps-mcp/src/r188_dts_framer.h
probe="$here/r304-synthetic-r122-test-double.h"
qa="$here/test-r188-synthetic-firstframe-r304.c"
for tool in gcc sha256sum mktemp timeout; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "R304_BLOCKED_MISSING_TOOL=$tool"; exit 2;
  }
done
[ -f "$header" ] && [ ! -L "$header" ] || {
    echo "R304_BLOCKED_ORIGINAL_SOURCE_NOT_REGULAR"; exit 2;
}
[ -f "$probe" ] && [ ! -L "$probe" ] || {
    echo "R304_BLOCKED_TEST_DOUBLE_MISSING"; exit 2;
}
[ -f "$qa" ] && [ ! -L "$qa" ] || {
    echo "R304_BLOCKED_TEST_SOURCE_MISSING"; exit 2;
}
printf '%s  %s\n' \
 '8fcf17dd9d9890d26542f093a87f91e760e8ea8999619e17b4e56485b04bfa97' "$header" \
 '977f09779d5a3801aca383c876da0d6fe173acfc21823e55f4e9bed3967796fd' "$probe" \
 '8b6214e4365df94cb863bec33d1b6537aad15280a621c84d424c12b12e01c39b' "$qa" |
  sha256sum -c - || { echo 'R304_BLOCKED_PIN_MISMATCH'; exit 2; }
work=$(mktemp -d /tmp/aleks-dts-r304.XXXXXX) || exit 2
trap 'rm -rf "$work"' EXIT HUP INT TERM
cp "$header" "$work/r188_dts_framer.h"
cp "$probe" "$work/r122_dts_core_probe.h"
cp "$qa" "$work/test-r304.c"
printf '%s\n' '=== R304 SYNTHETIC FRAME ASSEMBLER OFFLINE QA ==='
# First pass: ASan+UBSan, optimization low enough for useful stack traces.
gcc -std=c11 -O1 -g -Wall -Wextra -Werror \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I "$work" "$work/test-r304.c" -o "$work/r304-asan"
ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
  timeout 20 "$work/r304-asan" > "$work/asan.log"
grep -q '^R304_SYNTHETIC_R188_C99_QA_23_OF_23_PASS$' "$work/asan.log"
grep -q '^R304_REAL_LG_AUDIO_NOT_TESTED$' "$work/asan.log"
echo 'R304_ASAN_UBSAN_23_OF_23_PASS'
# Second pass: optimized C99 without sanitizer runtime to catch optimizer-
# sensitive behavior. It is NOT a native ARM/webOS build.
gcc -std=c11 -O2 -Wall -Wextra -Werror -I "$work" \
  "$work/test-r304.c" -o "$work/r304-o2"
timeout 20 "$work/r304-o2" > "$work/o2.log"
grep -q '^R304_SYNTHETIC_R188_C99_QA_23_OF_23_PASS$' "$work/o2.log"
echo 'R304_OPTIMIZED_C99_23_OF_23_PASS'
echo 'RESULT=R304_SYNTHETIC_OFFLINE_QA_PASS; ORIGINAL_R122_AND_REAL_DTS_UNTESTED'
