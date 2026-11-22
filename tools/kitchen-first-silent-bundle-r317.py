#!/usr/bin/env python3
"""R317: single offline/pinned FIRST SILENT and AUDIBLE LG DTS snapshot.
One-file payload: bundles exact SHA-pinned R308+R316 sources, requires no
network on TV, performs only getters, /proc reads, and temporary subprocesses.
No playback changes, audio content, application metadata, or raw logs saved.
Owner supplies stage; no microphone/acoustic verification.
Usage: python3 r317.py capture silent|audible|idle
       python3 r317.py compare private-silent.json private-audible.json
"""
import datetime
import hashlib
import json
import platform
import re
import subprocess
import sys

R308_SOURCE = "#!/bin/sh\n# R308 kitchen DTS cold-start evidence. READ ONLY. No media playback or\n# service, volume, firmware, plugin, mount, registry or recording changes.\n# Usage: sh capture-kitchen-dts-first-start-r308.sh silent|audible|idle\nset -u\nLC_ALL=C; export LC_ALL\ncase \"$1\" in silent|audible|idle) stage=$1;;*) echo R308_INVALID_STAGE >&2;exit 2;;esac\narch=$(uname -m 2>/dev/null || :)\ncase \"$arch\" in armv7l|armv6l|arm|aarch64) :;;*) echo R308_NOT_AN_ARM_TV;exit 2;;esac\ndir=/var/lib/webosbrew/aleks-dts-r278/plugins\nprintf 'STAGE=%s MACHINE=%s\\n' \"$stage\" \"$arch\"\ndate -u '+UTC=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :\necho '=== ACTUAL INSTALLED LIBRARY HASHES ==='\nfor item in \\\n  'libgstaleksdts.so|5c3b798d4c1109414efc9209276dbf8b23466376f72f5bc71cf4144f3f5a1cbb' \\\n  'libgstaleksdts16dec.so|dfefb960d49d50ed7629cc4459ffaae8b420509cc9815d8337f6be7faaac18cf' \\\n  'libgstaleksdtscaps.so|1995a6b6030f6ddb895aeeea4017dcc71db8ebd6caace0107e1c5a33875f0605' \\\n  'libgstaleksdtsr130optin.so|9b7adb2744a9d7c329669974c15bcfc86ba62daf27efccb95e362c1928d602e0'\ndo\n  name=$(printf '%s' \"$item\" | cut -d '|' -f 1)\n  expected=$(printf '%s' \"$item\" | cut -d '|' -f 2)\n  file=$dir/$name\n  if [ -L \"$file\" ];then printf 'LIB=%s STATUS=SYMLINK_SKIPPED\\n' \"$name\";continue;fi\n  if [ ! -r \"$file\" ];then printf 'LIB=%s STATUS=UNREADABLE\\n' \"$name\";continue;fi\n  got=$(sha256sum \"$file\" 2>/dev/null | cut -d ' ' -f 1)\n  if [ \"$got\" = \"$expected\" ];then matched=yes;else matched=no;fi\n  printf 'LIB=%s SHA256=%s HALL_RELEASE_MATCH=%s\\n' \"$name\" \"$got\" \"$matched\"\ndone\necho '=== PROCESS AND PCM STATE ==='\nfor service in umediaserver.service audiooutputd.service;do\n  value=$(systemctl is-active \"$service\" 2>/dev/null || :)\n  printf 'SERVICE=%s STATUS=%s\\n' \"$service\" \"$value\"\ndone\ncount=0;holders=0\nfor f in /proc/[0-9]*/comm;do\n  [ -r \"$f\" ] || continue\n  label=$(head -n 1 \"$f\" 2>/dev/null || :)\n  case \"$label\" in starfish-media-*) :;;*) continue;;esac\n  count=$((count+1))\n  p=$(basename \"$(dirname \"$f\")\")\n  if grep -Fq \"$dir/libgstaleksdts16dec.so\" \"/proc/$p/maps\" 2>/dev/null;then\n    holders=$((holders+1))\n  fi\ndone\nprintf 'STARFISH=%s DTS_WRAPPER_HOLDERS=%s\\n' \"$count\" \"$holders\"\npcm=/proc/asound/card0/pcm6p/sub0\nif [ -r \"$pcm/status\" ];then\n  pcm_state=$(awk '$1==\"state:\"{print $2;exit}' \"$pcm/status\")\n  printf 'ALSA_PCM6=%s\\n' \"$pcm_state\"\n  if [ \"$pcm_state\" = RUNNING ];then\n    a=$(awk '$1==\"hw_ptr\"{print $3;exit}' \"$pcm/status\" 2>/dev/null)\n    b=$(awk '$1==\"appl_ptr\"{print $3;exit}' \"$pcm/status\" 2>/dev/null)\n    sleep 2\n    c=$(awk '$1==\"hw_ptr\"{print $3;exit}' \"$pcm/status\" 2>/dev/null)\n    d=$(awk '$1==\"appl_ptr\"{print $3;exit}' \"$pcm/status\" 2>/dev/null)\n    case \"$a:$b:$c:$d\" in\n      *[!0-9:]*|:*|*::*) echo ALSA_POINTER_DELTA=UNKNOWN ;;\n      *) if [ \"$c\" -ge \"$a\" ] && [ \"$d\" -ge \"$b\" ];then\n           printf 'ALSA_HW_FRAMES_2S=%s ALSA_APPL_FRAMES_2S=%s\\n' \"$((c-a))\" \"$((d-b))\"\n         else echo ALSA_POINTER_DELTA=RESET_OR_WRAP;fi ;;\n    esac\n  fi\nelse echo ALSA_PCM6=UNAVAILABLE;fi\necho '=== AUDIO POLICY READ ONLY ==='\nquery() {\n  title=$1;url=$2\n  printf 'QUERY=%s\\n' \"$title\"\n  if ! command -v luna-send >/dev/null 2>&1;then echo QUERY_STATUS=NO_LUNA;return;fi\n  data=$(timeout 5 luna-send -n 1 -w 2200 \"$url\" '{}' 2>/dev/null);rc=$?\n  if [ \"$rc\" -ne 0 ];then printf 'QUERY_STATUS=ERROR_%s\\n' \"$rc\";return;fi\n  if printf '%s' \"$data\" | grep -Eq '\"returnValue\"[[:space:]]*:[[:space:]]*false';then\n    echo QUERY_STATUS=LS2_FAILED;return\n  fi\n  if ! printf '%s' \"$data\" | grep -Eq '\"returnValue\"[[:space:]]*:[[:space:]]*true';then\n    echo QUERY_STATUS=UNKNOWN;return\n  fi\n  printf '%s' \"$data\" | grep -Eo '\"(codec|source|sink|soundOutput|outputMode|muted|streamType)\"[[:space:]]*:[[:space:]]*(\"[A-Za-z0-9_.-]{1,40}\"|true|false)' | head -n 16 || :\n  echo QUERY_STATUS=VALUES_UNGROUPED\n}\nquery CODEC 'luna://com.webos.service.audio/tv/getAudioInputProperty'\nquery OUTPUT 'luna://com.webos.service.audiooutput/audio/getStatus'\necho '=== LAST 4 MIN NATIVE MEDIA ERROR COUNTS (LOG CONTENT NOT PRINTED) ==='\n# Distinguish an early R130 CAPS/header guard failure from output routing.\n# Events from other processes can also be counted: no pid/stream ownership.\nif command -v journalctl >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1;then\n  lines=$(timeout 7 journalctl --since '-4 min' --no-pager -n 400 -o cat 2>/dev/null)\n  rc=$?\n  if [ \"$rc\" -eq 0 ];then\n    printf '%s\\n' \"$lines\" | awk '\n      BEGIN { limit=0;missing=0;unrecognized=0;negotiate=0;sink=0;decoder=0;total=0 }\n      {\n        total++\n        row=tolower($0)\n        if(index(row,\"dts initial event limit reached\"))limit++\n        if(index(row,\"dts without input caps\"))missing++\n        if(index(row,\"unrecognized dts input caps\"))unrecognized++\n        if(index(row,\"not-negotiated\"))negotiate++\n        if(index(row,\"failed to acquire\") || index(row,\"failed to open audio\") ||\n           index(row,\"audiooutput error\"))sink++\n        if(index(row,\"dcadec\") && (index(row,\"error\") || index(row,\"fail\")))decoder++\n      }\n      END {\n        printf \"NATIVE_EVENT_ROWS=%d\\n\",total\n        printf \"R130_INITIAL_EVENT_LIMIT=%d\\n\",limit\n        printf \"R130_NO_INPUT_CAPS=%d\\n\",missing\n        printf \"R130_UNRECOGNIZED_CAPS=%d\\n\",unrecognized\n        printf \"GST_NOT_NEGOTIATED=%d\\n\",negotiate\n        printf \"NATIVE_AUDIO_SINK_ERROR_HINT=%d\\n\",sink\n        printf \"DCADEC_ERROR_HINT=%d\\n\",decoder\n      }'\n    echo 'NATIVE_LOG_COUNTS=AVAILABLE_NOT_ATTRIBUTED_TO_A_SINGLE_MEDIA_STREAM'\n  else\n    printf 'NATIVE_LOG_COUNTS=UNAVAILABLE_EXIT_%s\\n' \"$rc\"\n  fi\nelse\n  echo 'NATIVE_LOG_COUNTS=UNAVAILABLE_NO_JOURNAL_TOOL'\nfi\necho 'RESULT=R308_READ_ONLY_CAPTURE_COMPLETE'\necho 'NOTE=No media audio samples recorded; PCM pointer movement does not prove DTS audibility.'\n"
R316_SOURCE = "#!/usr/bin/env python3\n\"\"\"R316: read-only kitchen LG audio policy telemetry, not a sound detector.\nNo log dumps, media metadata, playback control, persistent files, or service changes.\nUsage: python3 observe-kitchen-dts-policy-r316.py idle|silent|audible\n\"\"\"\nimport json\nimport platform\nimport re\nimport subprocess\nimport sys\nfrom pathlib import Path\n\nif len(sys.argv) != 2 or sys.argv[1] not in (\"idle\", \"silent\", \"audible\"):\n    print(\"R316_INVALID_STAGE\")\n    sys.exit(2)\nstage = sys.argv[1]\nif not platform.machine().lower().startswith((\"arm\", \"aarch64\")):\n    print(\"R316_NOT_ARM_TV\")\n    sys.exit(2)\nprint(\"STAGE=\" + stage)\nprint(\"R316_SOUND_LABEL=OWNER_OBSERVED_NOT_VERIFIED_BY_SCRIPT\")\n\n# Queries below are getters. Never call connect/disconnect/mute/set methods.\nROUTES = (\n    (\"STREAM\", \"luna://com.webos.service.audio/getStreamStatus\"),\n    (\"UMI\", \"luna://com.webos.service.audio/UMI/getStatus\"),\n    (\"SOURCE\", \"luna://com.webos.service.audio/getSourceStatus\"),\n    (\"SOUND\", \"luna://com.webos.service.audio/getSoundOutput\"),\n    (\"OUTPUT\", \"luna://com.webos.service.audiooutput/audio/getStatus\"),\n    (\"CODEC\", \"luna://com.webos.service.audio/tv/getAudioInputProperty\"),\n)\n\ndef safe_enum(value, allowed):\n    if not isinstance(value, str):\n        return \"UNAVAILABLE\"\n    return value if value in allowed else \"OTHER\"\n\ndef bool_value(value):\n    return \"true\" if value is True else \"false\" if value is False else \"UNKNOWN\"\n\ndef request(url):\n    try:\n        result = subprocess.run(\n            [\"luna-send\", \"-n\", \"1\", \"-w\", \"2200\", url, \"{}\"],\n            check=False, text=True, capture_output=True, timeout=4,\n        )\n    except FileNotFoundError:\n        return \"NO_LUNA\", None\n    except subprocess.TimeoutExpired:\n        return \"TIMEOUT\", None\n    except (OSError, ValueError):\n        return \"EXEC_ERROR\", None\n    if result.returncode != 0:\n        return \"LS2_EXIT_\" + str(min(abs(result.returncode), 99)), None\n    # Consume only a single bounded reply. Do not print source payload.\n    raw = result.stdout[:12000]\n    start, end = raw.find(\"{\"), raw.rfind(\"}\")\n    if start < 0 or end < start:\n        return \"NO_JSON\", None\n    try:\n        data = json.loads(raw[start:end + 1])\n    except (ValueError, TypeError):\n        return \"JSON_ERROR\", None\n    if not isinstance(data, dict):\n        return \"NOT_OBJECT\", None\n    if data.get(\"returnValue\") is not True:\n        return \"RETURN_FALSE\", None\n    return \"OK\", data\n\ndef print_count(prefix, rows):\n    # Report a known-value denominator. A missing field is UNKNOWN, not false.\n    clean = [r for r in rows if isinstance(r, dict)]\n    print(prefix + \"_COUNT=\" + str(len(clean)))\n    tests = (\n        (\"ACTIVE\", \"activeStatus\"),\n        (\"POLICY_PENDING\", \"policyStatus\"),\n    )\n    for name, key in tests:\n        known = [r[key] for r in clean if type(r.get(key)) is bool]\n        print(prefix + \"_\" + name + \"_KNOWN=\" + str(len(known)))\n        print(prefix + \"_\" + name + \"_TRUE=\" + str(sum(known)))\n    muted = []\n    for row in clean:\n        for key in (\"muteStatus\", \"muted\"):\n            if type(row.get(key)) is bool:\n                muted.append(row[key])\n                break\n    print(prefix + \"_MUTED_KNOWN=\" + str(len(muted)))\n    print(prefix + \"_MUTED_TRUE=\" + str(sum(muted)))\n    print(prefix + \"_ADEC0_MAIN=\" + str(sum(\n        r.get(\"source\") == \"ADEC0\" and r.get(\"sink\") == \"MAIN\" for r in clean)))\n    for cls in (\"ADEC1\", \"AMIXER\"):\n        print(prefix + \"_\" + cls + \"_MAIN=\" + str(sum(\n            r.get(\"source\") == cls and r.get(\"sink\") == \"MAIN\" for r in clean)))\n    print(prefix + \"_ACTIVE_MAIN=\" + str(sum(\n        r.get(\"sink\") == \"MAIN\" and r.get(\"activeStatus\") is True for r in clean)))\n\ndef walk_objects(root):\n    # Read bounded nested JSON objects. Unknown keys and values never reach stdout.\n    todo = [(root, 0)]\n    visited = 0\n    while todo and visited < 128:\n        obj, depth = todo.pop(0)\n        visited += 1\n        if isinstance(obj, dict):\n            yield obj\n            if depth < 5:\n                for v in obj.values():\n                    if isinstance(v, (dict, list)):\n                        todo.append((v, depth + 1))\n        elif isinstance(obj, list) and depth < 5:\n            for v in obj[:64]:\n                if isinstance(v, (dict, list)):\n                    todo.append((v, depth + 1))\n\nfor label, url in ROUTES:\n    status, payload = request(url)\n    print(\"LS2_\" + label + \"=\" + status)\n    if status != \"OK\":\n        continue\n    if label in (\"STREAM\", \"UMI\", \"SOURCE\"):\n        key = {\"STREAM\": \"streamObject\", \"UMI\": \"audio\", \"SOURCE\": \"sourceObject\"}[label]\n        raw = payload.get(key)\n        if isinstance(raw, list):\n            print_count(label, raw[:64])\n            print(label + \"_TRUNCATED=\" + bool_value(len(raw) > 64))\n        else:\n            print(label + \"_COLLECTION=UNAVAILABLE\")\n    elif label == \"SOUND\":\n        print(\"SOUND_OUTPUT=\" + safe_enum(\n            payload.get(\"soundOutput\"), (\n                \"tv_speaker\", \"external_optical\", \"external_arc\",\n                \"tv_external_speaker\", \"headphone\", \"lineout\", \"pcm_output\",\n            )))\n    elif label == \"OUTPUT\":\n        # On actual kitchen LG, getStatus returns properties INSIDE audio[].\n        raw = payload.get(\"audio\")\n        rows = raw[:64] if isinstance(raw, list) else [payload]\n        print_count(\"OUTPUT\", rows)\n        matched = [r for r in rows if isinstance(r, dict) and\n                   r.get(\"source\") == \"ADEC0\" and r.get(\"sink\") == \"MAIN\"]\n        print(\"OUTPUT_ADEC0_MAIN_ROWS=\" + str(len(matched)))\n        if len(matched) == 1:\n            selected = matched[0]\n            print(\"OUTPUT_ADEC0_MAIN_MUTED=\" + bool_value(selected.get(\"muted\")))\n            mode = selected.get(\"outputMode\")\n            if mode is None:\n                print(\"OUTPUT_ADEC0_MAIN_MODE=\" +\n                      (\"null\" if \"outputMode\" in selected else \"UNAVAILABLE\"))\n            else:\n                print(\"OUTPUT_ADEC0_MAIN_MODE=\" +\n                      safe_enum(mode, (\"alsa\", \"pcm\", \"passthrough\", \"auto\", \"null\")))\n        else:\n            print(\"OUTPUT_ADEC0_MAIN_MUTED=UNKNOWN\")\n            print(\"OUTPUT_ADEC0_MAIN_MODE=UNAVAILABLE\")\n    elif label == \"CODEC\":\n        codecs = [x[\"codec\"] for x in walk_objects(payload) if \"codec\" in x]\n        print(\"INPUT_CODEC_DTS=\" + str(sum(c in (\"dts\", \"DTS\") for c in codecs)))\n        print(\"INPUT_CODEC_AC3=\" + str(sum(c in (\"ac3\", \"AC3\") for c in codecs)))\n        print(\"INPUT_CODEC_FIELDS=\" + str(len(codecs)))\n\npcm = Path(\"/proc/asound/card0/pcm6p/sub0\")\nfor name in (\"status\", \"hw_params\"):\n    try:\n        raw = (pcm / name).read_text(encoding=\"utf-8\", errors=\"ignore\")[:4096]\n    except OSError:\n        print(\"ALSA_\" + name.upper() + \"=UNAVAILABLE\")\n        continue\n    whitelist = {\n        \"status\": {\"state\"},\n        \"hw_params\": {\"access\", \"format\", \"subformat\", \"channels\", \"rate\"},\n    }[name]\n    for line in raw.splitlines():\n        match = re.match(r\"^([a-z_]+)\\s*:\\s*([A-Za-z0-9_/.]+)(?:\\s|$)\", line.strip())\n        if match and match.group(1) in whitelist:\n            key, value = match.groups()\n            print(\"ALSA_\" + key.upper() + \"=\" + value.strip().replace(\" \", \"_\"))\nprint(\"RESULT=R316_READ_ONLY_POLICY_COMPLETE\")\n"
R308_SHA = "1235dc9ff013ae73f0089cecac93056ac0ce00ffa8d049ce2e0c8d9b027ed7bc"
R316_SHA = "62990f6669e52e0c1ccd4544348e223debf632511c344d8ec4cee07a10954560"
SCHEMA = "aleks-dts-r317-v1"
MACHINE_KNOWN = ("aarch64", "armv7l", "armv6l", "arm")
ALLOWED_R308 = (
    "STARFISH", "DTS_WRAPPER_HOLDERS", "ALSA_PCM6", "ALSA_HW_FRAMES_2S",
    "ALSA_APPL_FRAMES_2S", "R130_INITIAL_EVENT_LIMIT", "R130_NO_INPUT_CAPS",
    "R130_UNRECOGNIZED_CAPS", "GST_NOT_NEGOTIATED",
    "NATIVE_AUDIO_SINK_ERROR_HINT", "DCADEC_ERROR_HINT", "NATIVE_LOG_COUNTS",
    "NATIVE_EVENT_ROWS",
)
ALLOWED_R316 = (
    "LS2_STREAM", "STREAM_COUNT", "STREAM_ACTIVE_KNOWN", "STREAM_ACTIVE_TRUE",
    "STREAM_MUTED_KNOWN", "STREAM_MUTED_TRUE",
    "STREAM_POLICY_PENDING_KNOWN", "STREAM_POLICY_PENDING_TRUE",
    "STREAM_ADEC0_MAIN", "STREAM_ADEC1_MAIN", "STREAM_AMIXER_MAIN",
    "STREAM_ACTIVE_MAIN", "LS2_UMI", "UMI_COUNT", "LS2_SOURCE",
    "LS2_SOUND", "SOUND_OUTPUT", "LS2_OUTPUT", "OUTPUT_COUNT",
    "OUTPUT_ADEC0_MAIN", "OUTPUT_ADEC1_MAIN", "OUTPUT_AMIXER_MAIN",
    "OUTPUT_ADEC0_MAIN_ROWS", "OUTPUT_ADEC0_MAIN_MUTED",
    "OUTPUT_ADEC0_MAIN_MODE", "LS2_CODEC", "INPUT_CODEC_DTS",
    "INPUT_CODEC_AC3", "INPUT_CODEC_FIELDS",
    "ALSA_STATE", "ALSA_ACCESS", "ALSA_FORMAT", "ALSA_CHANNELS",
    "ALSA_RATE",
)
VALUE_PATTERN = re.compile(r"^[A-Za-z0-9_./:-]{1,96}$")
NUM_PATTERN = re.compile(r"^[0-9]{1,15}$")


def fatal(reason):
    print("R317_ERROR=" + reason)
    sys.exit(2)


def source_check():
    for code, expected in ((R308_SOURCE, R308_SHA), (R316_SOURCE, R316_SHA)):
        got = hashlib.sha256(code.encode("utf-8")).hexdigest()
        if got != expected:
            fatal("EMBEDDED_SOURCE_SHA256_MISMATCH")


def safe_fields(out, allowed):
    result = {}
    for line in out.splitlines():
        for word in line.split():
            if "=" not in word:
                continue
            key, val = word.split("=", 1)
            if key in allowed and VALUE_PATTERN.fullmatch(val):
                result[key] = val
    return result


def capture(stage):
    if stage not in ("silent", "audible", "idle"):
        fatal("INVALID_STAGE")
    machine = platform.machine().lower()
    if machine not in MACHINE_KNOWN:
        fatal("NOT_ARM_TV")
    source_check()
    try:
        p = subprocess.run(
            ["sh", "-s", "--", stage], input=R308_SOURCE, text=True,
            capture_output=True, timeout=32, check=False,
        )
        q = subprocess.run(
            [sys.executable, "-c", R316_SOURCE, stage], text=True,
            capture_output=True, timeout=32, check=False,
        )
    except subprocess.TimeoutExpired:
        fatal("CHILD_TIMEOUT")
    except OSError:
        fatal("CHILD_EXEC_ERROR")
    if (p.returncode != 0 or
            "RESULT=R308_READ_ONLY_CAPTURE_COMPLETE" not in p.stdout or
            "STAGE=" + stage not in p.stdout):
        fatal("R308_INCOMPLETE")
    if (q.returncode != 0 or
            "RESULT=R316_READ_ONLY_POLICY_COMPLETE" not in q.stdout or
            "STAGE=" + stage not in q.stdout):
        fatal("R316_INCOMPLETE")
    old = safe_fields(p.stdout, ALLOWED_R308)
    new = safe_fields(q.stdout, ALLOWED_R316)
    matches = 0
    seen = 0
    for line in p.stdout.splitlines():
        if line.startswith("LIB=") and "HALL_RELEASE_MATCH=" in line:
            seen += 1
            if "HALL_RELEASE_MATCH=yes" in line.split():
                matches += 1
    old["LIB_RELEASE_MATCHES"] = str(matches)
    old["LIB_CHECKED"] = str(seen)
    complete = (matches == 4 and seen == 4 and
                old.get("DTS_WRAPPER_HOLDERS") is not None and
                new.get("LS2_STREAM") == "OK" and
                new.get("LS2_OUTPUT") == "OK" and
                new.get("LS2_CODEC") == "OK" and
                new.get("INPUT_CODEC_DTS") is not None)
    data = {
        "schema": SCHEMA,
        "stage": stage,
        "stage_provenance": "OWNER_OBSERVATION_NOT_MICROPHONE",
        "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "machine": machine,
        "coverage": "FULL" if complete else "PARTIAL",
        "r308": old,
        "r316": new,
    }
    # This JSON contains only strict allowlisted scalar fields; never raw LS2 replies.
    print("R317_JSON=" + json.dumps(data, ensure_ascii=True, sort_keys=True, separators=(",", ":")))
    print("RESULT=R317_CAPTURE_" + data["coverage"])


def validate_file(path, stage):
    if path == "-" or len(path) > 1024:
        fatal("INVALID_COMPARISON_FILE")
    try:
        with open(path, "r", encoding="utf-8") as h:
            data = json.load(h)
    except (OSError, ValueError):
        fatal("BAD_COMPARISON_JSON")
    if not isinstance(data, dict) or data.get("schema") != SCHEMA or data.get("stage") != stage:
        fatal("BAD_COMPARISON_STAGE")
    if data.get("stage_provenance") != "OWNER_OBSERVATION_NOT_MICROPHONE":
        fatal("BAD_PROVENANCE")
    for key in ("r308", "r316"):
        if not isinstance(data.get(key), dict):
            fatal("BAD_COMPARISON_METRICS")
    return data


def compare(silent_path, audible_path):
    a = validate_file(silent_path, "silent")
    b = validate_file(audible_path, "audible")
    if a.get("machine") != b.get("machine") or a.get("machine") not in MACHINE_KNOWN:
        fatal("DIFFERENT_MACHINES")
    try:
        t1 = datetime.datetime.fromisoformat(a["utc"])
        t2 = datetime.datetime.fromisoformat(b["utc"])
        gap = (t2 - t1).total_seconds()
    except (KeyError, ValueError, TypeError):
        fatal("BAD_TIMESTAMPS")
    if not 0 <= gap <= 1800:
        fatal("PAIR_TIMESTAMP_WINDOW")
    diff = 0
    for part, names in (("r308", ALLOWED_R308 + ("LIB_RELEASE_MATCHES", "LIB_CHECKED")),
                        ("r316", ALLOWED_R316)):
        for name in names:
            left = a[part].get(name, "UNAVAILABLE")
            right = b[part].get(name, "UNAVAILABLE")
            if not (isinstance(left, str) and isinstance(right, str) and
                    VALUE_PATTERN.fullmatch(left) and VALUE_PATTERN.fullmatch(right)):
                fatal("BAD_METRIC_VALUE")
            if left != right:
                diff += 1
                print("CHANGED=" + part.upper() + "." + name +
                      " SILENT=" + left + " AUDIBLE=" + right)
    print("CHANGED_METRICS=" + str(diff))
    print("CAPTURE_COVERAGE=" + a.get("coverage", "UNKNOWN") + "," +
          b.get("coverage", "UNKNOWN"))
    print("NOTE=Counter_changes_and_LS2_state_do_not_prove_audio_causality")
    print("RESULT=R317_COMPARE_COMPLETE")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "capture":
        capture(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == "compare":
        source_check()
        compare(sys.argv[2], sys.argv[3])
    else:
        fatal("USAGE_CAPTURE_OR_COMPARE")
