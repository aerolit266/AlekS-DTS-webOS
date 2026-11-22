#!/usr/bin/env python3
"""R315: read-only kitchen LG audio policy telemetry, not a sound detector.
No log dumps, media metadata, playback control, persistent files, or service changes.
Usage: python3 observe-kitchen-dts-policy-r315.py idle|silent|audible
"""
import json
import platform
import re
import subprocess
import sys
from pathlib import Path

if len(sys.argv) != 2 or sys.argv[1] not in ("idle", "silent", "audible"):
    print("R315_INVALID_STAGE")
    sys.exit(2)
stage = sys.argv[1]
if not platform.machine().lower().startswith(("arm", "aarch64")):
    print("R315_NOT_ARM_TV")
    sys.exit(2)
print("STAGE=" + stage)
print("R315_SOUND_LABEL=OWNER_OBSERVED_NOT_VERIFIED_BY_SCRIPT")

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
    # Only count recognized boolean and source/sink fields; discard all unknowns.
    clean = [r for r in rows if isinstance(r, dict)]
    print(prefix + "_COUNT=" + str(len(clean)))
    print(prefix + "_ACTIVE=" + str(sum(r.get("activeStatus") is True for r in clean)))
    print(prefix + "_MUTED=" + str(sum(
        r.get("muteStatus") is True or r.get("muted") is True for r in clean)))
    print(prefix + "_POLICY_PENDING=" + str(sum(
        r.get("policyStatus") is True for r in clean)))
    print(prefix + "_ADEC0_MAIN=" + str(sum(
        r.get("source") == "ADEC0" and r.get("sink") == "MAIN" for r in clean)))

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
        rows = payload.get("audio")
        if isinstance(rows, list):
            print_count("OUTPUT", rows[:64])
        for key, choices in (
            ("source", ("ADEC0", "ADEC1", "AMIXER", "ADEC")),
            ("sink", ("MAIN", "SUB", "ALSA")),
            ("outputMode", ("alsa", "pcm", "passthrough", "auto")),
        ):
            value = payload.get(key)
            if value is None:
                print("OUTPUT_" + key.upper() + "=null" if key in payload else
                      "OUTPUT_" + key.upper() + "=UNAVAILABLE")
            else:
                print("OUTPUT_" + key.upper() + "=" + safe_enum(value, choices))
        print("OUTPUT_MUTED=" + bool_value(payload.get("muted")))
    elif label == "CODEC":
        print("INPUT_CODEC=" + safe_enum(
            payload.get("codec"),
            ("dts", "ac3", "eac3", "aac", "mpeg", "pcm", "DTS", "AC3"),
        ))

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
        match = re.match(r"^([a-z_]+)\s*:\s*([A-Za-z0-9_/. -]{1,48})$", line.strip())
        if match and match.group(1) in whitelist:
            key, value = match.groups()
            print("ALSA_" + key.upper() + "=" + value.strip().replace(" ", "_"))
print("RESULT=R315_READ_ONLY_POLICY_COMPLETE")
