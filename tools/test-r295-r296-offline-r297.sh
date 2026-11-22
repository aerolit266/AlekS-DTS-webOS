#!/bin/sh
# R297 hermetic OFFLINE QA for R295 and R296.
# Does not connect to any television, send LS2 to a real service,
# start media, or require privileged access. Python3 + POSIX tools only.
set -eu
LC_ALL=C
export LC_ALL
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dir=$(mktemp -d /tmp/aleks-dts-r297-qa.XXXXXX)
trap 'rm -rf "$dir"' EXIT HUP INT TERM

for p in python3 timeout grep; do
    command -v "$p" >/dev/null 2>&1 || { echo "R297_MISSING=$p"; exit 2; }
done
[ -f "$here/inspect-webos26-audio-policy-r295.sh" ] || { echo R295_MISSING; exit 2; }
[ -f "$here/compare-webos26-dts-sessions-r296.py" ] || { echo R296_MISSING; exit 2; }
sh -n "$here/inspect-webos26-audio-policy-r295.sh"
python3 -B "$here/compare-webos26-dts-sessions-r296.py" --selftest

# Only our local temporary LS2 stub is executable. PATH is prepended.
cat > "$dir/luna-send" <<'MOCK'
#!/bin/sh
case "$*" in
    *UMI/getStatus*) echo '{"returnValue":false,"errorCode":15,"audio":[{"source":"LEAK_SENTINEL","muted":true}]}' ;;
    *getStreamStatus*) echo '{"streamObject":[{"source":"LEAK_NO_SUCCESS"}]}' ;;
    *audiooutput/audio/getStatus*) echo '{"returnValue":true,"audio":[{"source":"ADEC0","sink":"MAIN","muted":false,"outputMode":"null"}]}' ;;
    *getAudioInputProperty*) echo '{"returnValue":true,"codec":"dts"}' ;;
    *) exit 5 ;;
esac
MOCK
chmod 700 "$dir/luna-send"
PATH="$dir:$PATH" sh "$here/inspect-webos26-audio-policy-r295.sh" > "$dir/r295.txt"
grep -q '^QUERY_STATUS=API_RETURN_FALSE$' "$dir/r295.txt"
grep -q '^QUERY_STATUS=NO_SUCCESS_MARKER$' "$dir/r295.txt"
grep -q '"source":"ADEC0"' "$dir/r295.txt"
grep -q '"codec":"dts"' "$dir/r295.txt"
if grep -q 'LEAK_SENTINEL\|LEAK_NO_SUCCESS' "$dir/r295.txt"; then
    echo R297_R295_UNTRUSTED_RESPONSE_LEAK
    exit 1
fi
printf '%s\n' 'R297_R295_MOCK_SUCCESS_FAIL_CLOSED_PASS'

# Real output shape, sanitized: R294 after reboot with NO DTS playback.
cat > "$dir/idle.txt" <<'IDLE'
STARFISH_PROCESSES=1
DTS_PLUGIN_HOLDERS=0
PULSE_INPUT_COUNT=0
ALSA_PCM6=closed
QUERY=CODEC
"returnValue":true
"codec":"mpeg"
QUERY=NATIVE_ROUTE
"returnValue":true
"source":"ADEC1"
"sink":"MAIN"
RESULT=R294_SNAPSHOT_COMPLETE_NO_CHANGES
IDLE
# R289 live working-session shape. DTS sound was separately owner-reported.
cat > "$dir/working.txt" <<'WORKING'
DTS_STARFISH_PID=20727
ALSA_PCM6_STATE=RUNNING
PCM_HW_DELTA_FRAMES=194560
LG_AUDIO_"codec":"dts"
RESULT=R289_SAFE_SNAPSHOT_COMPLETE
WORKING
python3 -B "$here/compare-webos26-dts-sessions-r296.py" \
    "$dir/idle.txt" "$dir/working.txt" \
    --heard-before unknown --heard-after yes > "$dir/comparison.json"
python3 -B - "$dir/comparison.json" <<'ASSERT'
import json, sys
r = json.load(open(sys.argv[1], encoding="utf-8"))
a, b, c = r["before"], r["after"], r["comparison"]
assert a["plugin"] is False and a["codec"] == "mpeg"
assert b["plugin"] is True and b["codec"] == "dts"
assert a["transcript_complete"] and b["transcript_complete"]
assert c["root_cause_verified"] is False
assert c["explicit_owner_hearing"] == {"before": "unknown", "after": "yes"}
assert any("not verified as a DTS-loaded session" in s for s in c["assessment"])
print("R297_R296_E2E_CLI_PASS idle_is_not_silent_DTS=true")
ASSERT
echo 'R297_OFFLINE_QA_PASS; REAL_TV_AUDIO_NOT_TESTED'
