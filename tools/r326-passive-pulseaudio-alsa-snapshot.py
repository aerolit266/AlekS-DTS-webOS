#!/usr/bin/env python3
"""R326: passive PulseAudio->ALSA DTS output provenance and state snapshot.

No microphone, stream recording, PCM reads, player control, sink changes,
log dumps, environment disclosure, service reload or firmware modifications.
For an owner-labeled real cold-start comparison:
  python3 r326.py snapshot silent|audible|unclassified
  python3 r326.py compare silent.json audible.json
Snapshot labels silent/audible describe OWNER observations only.
"""
import datetime
import hashlib
import json
import platform
import re
import subprocess
import sys
import time
from pathlib import Path

SCHEMA = "aleks-dts-r326-pa-v1"
ALLOWED = {"silent", "audible", "unclassified"}
PROC = Path("/proc")
PCM = PROC / "asound/card0/pcm6p/sub0/status"
HW = PROC / "asound/card0/pcm6p/sub0/hw_params"
FORMATS = {"s16le", "s32le", "float32le", "s24le", "s24-32le", "u8"}
STATES = {"RUNNING", "IDLE", "SUSPENDED", "UNLINKED", "INIT"}
KNOWN_COMM = {"pulseaudio", "audiooutputd", "audiod", "umediaserver", "alsa-sink-MARS", "starfish-media-"}
SPEC = re.compile(r"^([a-z][a-z0-9-]{1,30})\s+(\d{1,2})ch\s+(\d{4,6})Hz$")
PA_START = re.compile(r"^\s*(Sink Input|Sink) #(\d{1,6})\s*$")
PA_LINE = re.compile(r"^\s*(Sink|Corked|Mute|Volume|Sample Specification|State|Buffer Latency|Sink Latency):\s*(.*?)\s*$")
INT = re.compile(r"^\d{1,15}$")
ALSA_POINTER = re.compile(r"^\s*(owner_pid|hw_ptr|appl_ptr|delay|avail)\s*:?\s*(\d{1,15})\s*$")


def die(code):
    print("RESULT=R326_FAIL_" + code)
    raise SystemExit(2)


def read_limited(path, limit=32000):
    try:
        with path.open("r", encoding="utf-8", errors="replace") as file:
            return file.read(limit)
    except (OSError, ValueError):
        return ""


def pactl(command):
    try:
        result = subprocess.run(["pactl", "list", command], check=False,
                                capture_output=True, text=True,
                                errors="replace", timeout=6)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0 or len(result.stdout) > 180000:
        return None
    return result.stdout


def parse_pa(text, wanted):
    if text is None:
        return None
    result = []
    block = None
    for line in text.splitlines():
        match = PA_START.match(line)
        if match:
            block = None
            if match.group(1) == wanted and len(result) < 24:
                block = {"id": int(match.group(2))}
                result.append(block)
            continue
        if block is None:
            continue
        field = PA_LINE.match(line)
        if not field:
            continue
        key, val = field.groups()
        if key == "Sink" and wanted == "Sink Input" and INT.fullmatch(val):
            block["sink_id"] = int(val)
        elif key in ("Corked", "Mute") and val.lower() in ("yes", "no"):
            block[key.lower()] = val.lower() == "yes"
        elif key == "Volume":
            pct = [int(value) for value in
                   re.findall(r"/\s*(\d{1,3})%\s*/", val)[:8]]
            if pct and all(0 <= value <= 200 for value in pct):
                block["volume_percent_min"] = min(pct)
                block["volume_percent_max"] = max(pct)
        elif key == "State" and wanted == "Sink" and val in STATES:
            block["state"] = val
        elif key == "Sample Specification":
            spec = SPEC.fullmatch(val)
            if spec and spec.group(1) in FORMATS and int(spec.group(2)) <= 8:
                block["format"] = spec.group(1)
                block["channels"] = int(spec.group(2))
                block["rate"] = int(spec.group(3))
        elif key in ("Buffer Latency", "Sink Latency"):
            m = re.fullmatch(r"(\d{1,12})\s+usec", val)
            if m:
                block[("buffer_latency_us" if key == "Buffer Latency"
                       else "sink_latency_us")] = int(m.group(1))
    return result


def proc_comm(pid):
    if not isinstance(pid, int) or not 1 <= pid <= 1_000_000:
        return "UNKNOWN"
    raw = read_limited(PROC / str(pid) / "comm", 96).strip()
    return raw if raw in KNOWN_COMM else "OTHER"


def alsa_status():
    raw = read_limited(PCM, 4096)
    data = {"available": bool(raw)}
    for line in raw.splitlines():
        match = ALSA_POINTER.fullmatch(line.strip())
        if match:
            data[match.group(1)] = int(match.group(2))
        elif line.startswith("state:"):
            value = line.split(":", 1)[1].strip()
            if value in STATES:
                data["state"] = value
    owner_id = data.pop("owner_pid", None)
    if owner_id is not None:
        data["owner_thread_type"] = proc_comm(owner_id)
        status = read_limited(PROC / str(owner_id) / "status", 4096)
        m = re.search(r"^Tgid:\s*(\d+)\s*$", status, re.M)
        if m:
            data["owner_process_type"] = proc_comm(int(m.group(1)))
            data["is_pulseaudio_sink_thread"] = (
                data["owner_process_type"] == "pulseaudio")
    return data


def media_processes():
    known = {"starfish-media-": 0, "umediaserver": 0,
             "audiooutputd": 0, "pulseaudio": 0}
    mapped = 0
    try:
        entries = list(PROC.iterdir())
    except OSError:
        return {"available": False}
    for entry in entries:
        if not entry.name.isdigit():
            continue
        name = read_limited(entry / "comm", 64).strip()
        if name in known:
            known[name] += 1
            if name == "starfish-media-":
                maps = read_limited(entry / "maps", 1500000)
                if "/aleks-dts-r278/plugins/libgstaleksdts16dec.so" in maps:
                    mapped += 1
    return {"available": True, "process_counts": known,
            "starfish_r278_wrapper_holders": mapped}


def pcm_hw_params():
    content = read_limited(HW, 4096)
    result = {}
    for name, val in re.findall(r"^\s*(format|channels|rate):\s*([^\n]+)", content, re.M):
        if name == "format" and val.strip() in {"S16_LE", "S32_LE"}:
            result[name] = val.strip()
        elif name in ("channels", "rate"):
            numeric = re.match(r"^(\d{1,15})(?:\s|$)", val.strip())
            if numeric:
                result[name] = int(numeric.group(1))
    return result


def sample():
    a = alsa_status()
    time.sleep(0.35)
    b = alsa_status()
    if a.get("state") != "RUNNING" or b.get("state") != "RUNNING":
        return {"state": b.get("state", "UNKNOWN"), "owner_process_type": b.get("owner_process_type", "UNKNOWN")}
    out = {"state": "RUNNING", "owner_process_type": b.get("owner_process_type", "UNKNOWN"),
           "owner_thread_type": b.get("owner_thread_type", "UNKNOWN"),
           "is_pulseaudio_sink_thread": b.get("is_pulseaudio_sink_thread", False),
           "sample_interval_ms": 350}
    for field in ("hw_ptr", "appl_ptr"):
        first, last = a.get(field), b.get(field)
        out[field + "_delta"] = (
            last - first if isinstance(first, int) and isinstance(last, int)
            and last >= first else None
        )
    for key in ("delay", "avail"):
        out[key + "_frames"] = b.get(key)
    out["hw_params"] = pcm_hw_params()
    return out


def boot_fingerprint():
    raw = read_limited(PROC / "sys/kernel/random/boot_id", 128).strip()
    return hashlib.sha256(raw.encode()).hexdigest()[:16] if re.fullmatch(
        r"[0-9a-fA-F-]{36}", raw) else "UNAVAILABLE"


def capture(stage):
    if stage not in ALLOWED or platform.machine().lower() not in (
        "aarch64", "armv7l"):
        die("INVALID_STAGE_OR_ARCH")
    sinks = parse_pa(pactl("sinks"), "Sink")
    inputs = parse_pa(pactl("sink-inputs"), "Sink Input")
    data = {
        "schema": SCHEMA, "stage": stage,
        "observation": "OWNER_LABELED_ONLY" if stage != "unclassified" else "UNCLASSIFIED",
        "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "machine": platform.machine().lower(),
        "boot_fingerprint": boot_fingerprint(),
        "pulse": {
            "query_ok": sinks is not None and inputs is not None,
            "sinks": sinks, "sink_inputs": inputs,
        },
        "alsa_pcm6": sample(),
        "media": media_processes(),
        "gstreamer_live_first_caps_segment": "NOT_ACCESSIBLE_WITH_PROC_PACTL",
        "live_pcm_rms": "NOT_ACCESSIBLE_WITH_PROC_PACTL",
        "microphone_used": False, "recorded_audio_bytes": 0,
    }
    print("R326_JSON=" + json.dumps(data, sort_keys=True, separators=(",", ":")))
    print("RESULT=R326_READ_ONLY_CAPTURE_PASS")


def compare(a, b):
    try:
        aa = json.loads(Path(a).read_text(encoding="utf-8"))
        bb = json.loads(Path(b).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        die("BAD_PAIR_FILES")
    if not isinstance(aa, dict) or not isinstance(bb, dict):
        die("BAD_PAIR_SCHEMA")
    if aa.get("schema") != SCHEMA or bb.get("schema") != SCHEMA:
        die("BAD_PAIR_SCHEMA")
    if aa.get("stage") != "silent" or bb.get("stage") != "audible":
        die("BAD_PAIR_STAGE")
    if aa.get("boot_fingerprint") in (None, "UNAVAILABLE") or aa.get("boot_fingerprint") != bb.get("boot_fingerprint"):
        die("PAIR_DIFFERENT_REBOOT")
    try:
        when_a = datetime.datetime.fromisoformat(aa["utc"])
        when_b = datetime.datetime.fromisoformat(bb["utc"])
    except (ValueError, TypeError, KeyError):
        die("PAIR_TIMESTAMPS")
    if not 0 <= (when_b - when_a).total_seconds() <= 1800:
        die("PAIR_TIMESTAMPS")
    paths = {
        "pcm_state": ("alsa_pcm6", "state"),
        "pcm_owner": ("alsa_pcm6", "owner_process_type"),
        "pcm_format": ("alsa_pcm6", "hw_params", "format"),
        "pcm_channels": ("alsa_pcm6", "hw_params", "channels"),
        "pcm_rate": ("alsa_pcm6", "hw_params", "rate"),
        "starfish_holders": ("media", "starfish_r278_wrapper_holders"),
    }
    changed = 0
    for label, keypath in paths.items():
        x, y = aa, bb
        for key in keypath:
            x = x.get(key) if isinstance(x, dict) else None
            y = y.get(key) if isinstance(y, dict) else None
        if x != y:
            print("R326_CHANGED_" + label.upper() + "=" + str(x) + "->" + str(y))
            changed += 1
    for field in ("sinks", "sink_inputs"):
        av = aa.get("pulse", {}).get(field)
        bv = bb.get("pulse", {}).get(field)
        if av != bv:
            print("R326_CHANGED_PULSE_" + field.upper() + "=YES")
            changed += 1
        else:
            print("R326_CHANGED_PULSE_" + field.upper() + "=NO")
    print("R326_CHANGED_COUNTER=" + str(changed))
    print("R326_NOTE=Identical_Pulse_and_ALSA_metadata_DO_NOT_prove_nonzero_audio")
    print("RESULT=R326_SAME_BOOT_PA_PAIR_COMPARE_PASS")


def selftest():
    raw = """Sink Input #1
  Sink: 1
  Sample Specification: s16le 2ch 48000Hz
  Corked: no
  Mute: no
  Volume: front-left: 65536 / 100% / 0.00 dB, front-right: 65536 / 100% / 0.00 dB
  Buffer Latency: 32000 usec
  Sink Latency: 26096 usec
"""
    inputs = parse_pa(raw, "Sink Input")
    assert inputs == [{"id": 1, "sink_id": 1, "format": "s16le", "channels": 2,
                       "rate": 48000, "corked": False, "mute": False,
                       "buffer_latency_us": 32000, "sink_latency_us": 26096,
                       "volume_percent_min": 100, "volume_percent_max": 100}]
    bad = parse_pa("Sink Input #1\n Name: SECRET_PRIVATE_MOVIE\nSample Specification: s16le 2ch 48000Hz\n", "Sink Input")
    assert "SECRET_PRIVATE_MOVIE" not in json.dumps(bad)
    assert parse_pa(None, "Sink Input") is None
    assert parse_pa("", "Sink Input") == []
    print("RESULT=R326_PARSER_SELFTEST_PASS")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "selftest":
        selftest()
    elif len(sys.argv) == 3 and sys.argv[1] == "capture":
        capture(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == "compare":
        compare(sys.argv[2], sys.argv[3])
    else:
        die("USAGE")
