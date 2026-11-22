#!/usr/bin/env python3
"""R316: read-only kitchen LG audio policy telemetry, not a sound detector.
No log dumps, media metadata, playback control, persistent files, or service changes.
Usage: python3 observe-kitchen-dts-policy-r316.py idle|silent|audible
"""
import json
import platform
import re
import subprocess
import sys
from pathlib import Path

if len(sys.argv) != 2 or sys.argv[1] not in ("idle", "silent", "audible"):
    print("R316_INVALID_STAGE")
    sys.exit(2)
stage = sys.argv[1]
if not platform.machine().lower().startswith(("arm", "aarch64")):
    print("R316_NOT_ARM_TV")
    sys.exit(2)
print("STAGE=" + stage)
print("R316_SOUND_LABEL=OWNER_OBSERVED_NOT_VERIFIED_BY_SCRIPT")

# Queries below are getters. Never call connect/disconnect/mute/set methods.
ROUTES = (
    ("STREAM", "luna://com.webos.service.audio/getStreamStatus"),
    ("UMI", "luna://com.webos.service.audio/UMI/getStatus"),
    ("SOURCE", "luna://com.webos.service.audio/getSourceStatus"),
    ("SOUND", "luna://com.webos.service.audio/getSoundOutput"),
    ("OUTPUT", "luna://com.webos.service.audiooutput/audio/getStatus"),
    ("CODEC", "luna://com.webos.service.audio/tv/getAudioInputProperty"),
)

def safe_enum(value, allowed):
    if not isinstance(value, str):
        return "UNAVAILABLE"
    return value if value in allowed else "OTHER"

def bool_value(value):
    return "true" if value is True else "false" if value is False else "UNKNOWN"

def request(url):
    try:
        result = subprocess.run(
            ["luna-send", "-n", "1", "-w", "2200", url, "{}"],
            check=False, text=True, capture_output=True, timeout=4,
        )
    except FileNotFoundError:
        return "NO_LUNA", None
    except subprocess.TimeoutExpired:
        return "TIMEOUT", None
    except (OSError, ValueError):
        return "EXEC_ERROR", None
    if result.returncode != 0:
        return "LS2_EXIT_" + str(min(abs(result.returncode), 99)), None
    # Consume only a single bounded reply. Do not print source payload.
    raw = result.stdout[:12000]
    start, end = raw.find("{"), raw.rfind("}")
    if start < 0 or end < start:
        return "NO_JSON", None
    try:
        data = json.loads(raw[start:end + 1])
    except (ValueError, TypeError):
        return "JSON_ERROR", None
    if not isinstance(data, dict):
        return "NOT_OBJECT", None
    if data.get("returnValue") is not True:
        return "RETURN_FALSE", None
    return "OK", data

def print_count(prefix, rows):
    # Report a known-value denominator. A missing field is UNKNOWN, not false.
    clean = [r for r in rows if isinstance(r, dict)]
    print(prefix + "_COUNT=" + str(len(clean)))
    tests = (
        ("ACTIVE", "activeStatus"),
        ("POLICY_PENDING", "policyStatus"),
    )
    for name, key in tests:
        known = [r[key] for r in clean if type(r.get(key)) is bool]
        print(prefix + "_" + name + "_KNOWN=" + str(len(known)))
        print(prefix + "_" + name + "_TRUE=" + str(sum(known)))
    muted = []
    for row in clean:
        for key in ("muteStatus", "muted"):
            if type(row.get(key)) is bool:
                muted.append(row[key])
                break
    print(prefix + "_MUTED_KNOWN=" + str(len(muted)))
    print(prefix + "_MUTED_TRUE=" + str(sum(muted)))
    print(prefix + "_ADEC0_MAIN=" + str(sum(
        r.get("source") == "ADEC0" and r.get("sink") == "MAIN" for r in clean)))

def walk_objects(root):
    # Read bounded nested JSON objects. Unknown keys and values never reach stdout.
    todo = [(root, 0)]
    visited = 0
    while todo and visited < 128:
        obj, depth = todo.pop(0)
        visited += 1
        if isinstance(obj, dict):
            yield obj
            if depth < 5:
                for v in obj.values():
                    if isinstance(v, (dict, list)):
                        todo.append((v, depth + 1))
        elif isinstance(obj, list) and depth < 5:
            for v in obj[:64]:
                if isinstance(v, (dict, list)):
                    todo.append((v, depth + 1))

for label, url in ROUTES:
    status, payload = request(url)
    print("LS2_" + label + "=" + status)
    if status != "OK":
        continue
    if label in ("STREAM", "UMI", "SOURCE"):
        key = {"STREAM": "streamObject", "UMI": "audio", "SOURCE": "sourceObject"}[label]
        raw = payload.get(key)
        if isinstance(raw, list):
            print_count(label, raw[:64])
            print(label + "_TRUNCATED=" + bool_value(len(raw) > 64))
        else:
            print(label + "_COLLECTION=UNAVAILABLE")
    elif label == "SOUND":
        print("SOUND_OUTPUT=" + safe_enum(
            payload.get("soundOutput"), (
                "tv_speaker", "external_optical", "external_arc",
                "tv_external_speaker", "headphone", "lineout", "pcm_output",
            )))
    elif label == "OUTPUT":
        # On actual kitchen LG, getStatus returns properties INSIDE audio[].
        raw = payload.get("audio")
        rows = raw[:64] if isinstance(raw, list) else [payload]
        print_count("OUTPUT", rows)
        matched = [r for r in rows if isinstance(r, dict) and
                   r.get("source") == "ADEC0" and r.get("sink") == "MAIN"]
        print("OUTPUT_ADEC0_MAIN_ROWS=" + str(len(matched)))
        if len(matched) == 1:
            selected = matched[0]
            print("OUTPUT_ADEC0_MAIN_MUTED=" + bool_value(selected.get("muted")))
            mode = selected.get("outputMode")
            if mode is None:
                print("OUTPUT_ADEC0_MAIN_MODE=" +
                      ("null" if "outputMode" in selected else "UNAVAILABLE"))
            else:
                print("OUTPUT_ADEC0_MAIN_MODE=" +
                      safe_enum(mode, ("alsa", "pcm", "passthrough", "auto")))
        else:
            print("OUTPUT_ADEC0_MAIN_MUTED=UNKNOWN")
            print("OUTPUT_ADEC0_MAIN_MODE=UNAVAILABLE")
    elif label == "CODEC":
        codecs = [x["codec"] for x in walk_objects(payload) if "codec" in x]
        print("INPUT_CODEC_DTS=" + str(sum(c in ("dts", "DTS") for c in codecs)))
        print("INPUT_CODEC_AC3=" + str(sum(c in ("ac3", "AC3") for c in codecs)))
        print("INPUT_CODEC_FIELDS=" + str(len(codecs)))

pcm = Path("/proc/asound/card0/pcm6p/sub0")
for name in ("status", "hw_params"):
    try:
        raw = (pcm / name).read_text(encoding="utf-8", errors="ignore")[:4096]
    except OSError:
        print("ALSA_" + name.upper() + "=UNAVAILABLE")
        continue
    whitelist = {
        "status": {"state"},
        "hw_params": {"access", "format", "subformat", "channels", "rate"},
    }[name]
    for line in raw.splitlines():
        match = re.match(r"^([a-z_]+)\s*:\s*([A-Za-z0-9_/.]+)(?:\s|$)", line.strip())
        if match and match.group(1) in whitelist:
            key, value = match.groups()
            print("ALSA_" + key.upper() + "=" + value.strip().replace(" ", "_"))
print("RESULT=R316_READ_ONLY_POLICY_COMPLETE")
