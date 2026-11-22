#!/bin/sh
# R298: offline integration regression of the R282 strict lifecycle verdict.
# The REAL R282 source is copied into a private temp directory and only
# the temp copy is redirected to mock gst executables and a fake fixture.
# NEVER contacts an LG, plays audio, or changes GStreamer/global registry.
set -eu
umask 077
LC_ALL=C; export LC_ALL
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_file="$here/test-webos26-decodebin3-pcm-r282.sh"
[ -r "$source_file" ] || { echo 'R298_MISSING_R282_SOURCE';exit 2; }
for tool in python3 sha256sum mktemp grep; do
  command -v "$tool" >/dev/null 2>&1 || { echo "R298_MISSING=$tool";exit 2; }
done
work=$(mktemp -d /tmp/aleks-dts-r282-offline.XXXXXX) || exit 2
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/install/fixtures" "$work/install/plugins" "$work/mockbin"
printf 'isolated-offline-test-not-valid-DTS\n' > "$work/install/fixtures/dts-51.mka"
(cd "$work/install" && sha256sum fixtures/dts-51.mka > installed.sha256)
touch "$work/install/ready"
hash=$(sha256sum "$work/install/fixtures/dts-51.mka" | awk '{print $1}')
cat > "$work/mockbin/gst-inspect-1.0" <<'INSPECT'
#!/bin/sh
echo 'Rank primary (256)'
INSPECT
cat > "$work/mockbin/gst-launch-1.0" <<'LAUNCH'
#!/bin/sh
echo 'AlekSDts16DecBin'
case "$*" in
 *'audio/x-raw,format=S32LE,channels=2'*)
   echo 'GstFakeSink:gstfakesink0.GstPad:sink: caps = audio/x-raw, format=(string)S32LE, channels=(int)2' ;;
 *)
   echo 'GstFakeSink:gstfakesink0.GstPad:sink: caps = audio/x-raw, format=(string)S16LE, channels=(int)6' ;;
esac
echo 'Got EOS from element "pipeline0".'
if [ -e "$MOCK_MARKER" ];then exit 143;fi
echo 'Setting pipeline to NULL ...'
echo 'Freeing pipeline ...'
exit 0
LAUNCH
# Do not inherit any externally supplied marker or mock-path value.
# The mock gst-launch reads a fixed location inserted in the temporary copy.
sed -i "s@\\\$MOCK_MARKER@$work/simulate-sigterm@g" "$work/mockbin/gst-launch-1.0"
chmod 700 "$work/mockbin/gst-inspect-1.0" "$work/mockbin/gst-launch-1.0"
python3 - "$source_file" "$work/r282-isolated.sh" "$work/install" "$work/mockbin" "$hash" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text()
target, root, mockbin, checksum = sys.argv[2:]
old_root = "root=/var/lib/webosbrew/aleks-dts-r278"
old_path = "PATH=/bin:/usr/bin:/sbin:/usr/sbin"
old_checksum = "7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5"
for name in (old_root, old_path, old_checksum):
    if src.count(name) != 1:
        raise RuntimeError("Unsupported source layout for mock: " + name)
src = src.replace(old_root, "root=" + root)
src = src.replace(old_path, "PATH=" + mockbin + ":/bin:/usr/bin:/sbin:/usr/sbin")
src = src.replace(old_checksum, checksum)
pathlib.Path(target).write_text(src)
PY
sh -n "$work/r282-isolated.sh"
# POSITIVE control: all four faked pipelines reach EOS/PCM AND return exit0.
PATH="$work/mockbin:$PATH" sh "$work/r282-isolated.sh" > "$work/clean.out"
[ "$(grep -c 'CLEAN_EXIT_AND_DECODE_PASS' "$work/clean.out")" -eq 4 ]
grep -q '^R282_CLEAN_CASES=4/4 SIGTERM_EXIT_COUNT=0$' "$work/clean.out"
grep -q '^RESULT=R282_ISOLATED_DECODEBIN3_AND_PCM_PROBE_PASS;' "$work/clean.out"
[ "$(grep -c '^LIFECYCLE=.*pipeline_free_seen=yes' "$work/clean.out")" -eq 4 ]
[ "$(grep -c '^LIFECYCLE=.*null_transition_seen=yes' "$work/clean.out")" -eq 4 ]
echo 'R298_R282_EOS_EXIT0_FULL_PASS'
# NEGATIVE control: log still claims EOS/PCM, but process returns 143.
touch "$work/simulate-sigterm"
rc=0
PATH="$work/mockbin:$PATH" sh "$work/r282-isolated.sh" > "$work/sigterm.out" || rc=$?
[ "$rc" -ne 0 ]
[ "$(grep -c 'SIGTERM_EXIT_143' "$work/sigterm.out")" -eq 4 ]
grep -q '^R282_CLEAN_CASES=0/4 SIGTERM_EXIT_COUNT=4$' "$work/sigterm.out"
grep -q '^RESULT=R282_ISOLATED_DECODEBIN3_AND_PCM_PROBE_INCOMPLETE;' "$work/sigterm.out"
[ "$(grep -c '^LIFECYCLE=.*pipeline_free_seen=no' "$work/sigterm.out")" -eq 4 ]
[ "$(grep -c '^LIFECYCLE=.*deadline_compatible=no' "$work/sigterm.out")" -eq 4 ]
echo 'R298_R282_EOS_EXIT143_REJECTED_PASS'
# R300: USR1 mode is opt-in only; a child exiting 143 is distinct from
# a wrapper which was configured to send SIGUSR1 on expiration.
rc=0
R300_TIMEOUT_SIGNAL=USR1 PATH="$work/mockbin:$PATH" sh "$work/r282-isolated.sh" > "$work/usr1-natural-term.out" || rc=$?
[ "$rc" -ne 0 ]
[ "$(grep -c 'WRAPPER_REQUESTED_USR1_NOT_TERM' "$work/usr1-natural-term.out")" -eq 4 ]
[ "$(grep -c '^LIFECYCLE=.*timeout_signal=USR1' "$work/usr1-natural-term.out")" -eq 4 ]
grep -q '^TIMEOUT_QA_SIGNAL=USR1 BUDGET_SECONDS=12 DISTINCT_SIGNAL_MODE=yes
 "$work/usr1-natural-term.out"
echo 'R300_USR1_OPTIN_NATURAL_SIGTERM_143_DISTINGUISHED_PASS'
rm -f "$work/simulate-sigterm"
R300_TIMEOUT_SIGNAL=USR1 PATH="$work/mockbin:$PATH" sh "$work/r282-isolated.sh" > "$work/usr1-clean.out"
[ "$(grep -c 'CLEAN_EXIT_AND_DECODE_PASS' "$work/usr1-clean.out")" -eq 4 ]
echo 'R300_USR1_OPTIN_CLEAN_EXIT0_PASS'
rc=0
R300_TIMEOUT_SIGNAL=INVALID PATH="$work/mockbin:$PATH" sh "$work/r282-isolated.sh" > "$work/invalid.out" 2>&1 || rc=$?
[ "$rc" -eq 2 ]
grep -q 'BLOCKED: unsupported R300_TIMEOUT_SIGNAL=INVALID' "$work/invalid.out"
echo 'R300_INVALID_SIGNAL_BLOCKED_PASS'
echo 'RESULT=R298_OFFLINE_R282_STRICT_LIFECYCLE_QA_PASS; REAL_LG_NOT_TESTED'
