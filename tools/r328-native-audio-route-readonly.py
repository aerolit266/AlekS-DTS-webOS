#!/usr/bin/env python3
"""R328: kitchen LG native DTS audio route provenance, read-only.

Enumerates only bounded allowlisted ALSA/device/process categories and
approved webOS LS2 getters. No PCM data, audio samples, environment,
private app/media metadata, logs, IDs or arbitrary paths are emitted.
No tracing, attachment, service restarts, mixer controls, playback actions
or kernel/firmware modifications.

Usage:
    python3 tools/r328-native-audio-route-readonly.py selftest
    python3 tools/r328-native-audio-route-readonly.py snapshot unclassified

The 'unclassified' stage is not a substitute for owner's audible confirmation.
"""
import datetime
import json
import os
import pathlib
import platform
import re
import subprocess
import sys

PROC = pathlib.Path("/proc")
STATUS_RE = re.compile(r"^(state|owner_pid|hw_ptr|appl_ptr|delay|avail):?\s*(\S+)")
ALSA_NODE_RE = re.compile(r"^card([0-9]{1,2})/pcm([0-9]{1,2})p/sub([0-9]{1,2})$")
VALID_STATE = {"OPEN", "SETUP", "PREPARED", "RUNNING", "XRUN", "DRAINING", "PAUSED", "SUSPENDED", "DISCONNECTED"}
KNOWN_PROC = ("starfish-media-", "audiooutputd", "umediaserver", "pulseaudio")
PLUGIN_DIR = "/var/lib/webosbrew/aleks-dts-r278/plugins/"
WRAPPER = PLUGIN_DIR + "libgstaleksdts16dec.so"
ALLOWED_OUTPUT = {"tv_external_speaker", "tv_speaker", "external_arc", "external_optical",
                  "pcm_output", "headphone", "lineout"}
ALLOWED_MODE = {"alsa", "pcm", "passthrough", "auto", "null"}
ROUTES = (
    ("output", "luna://com.webos.service.audiooutput/audio/getStatus"),
    ("codec", "luna://com.webos.service.audio/tv/getAudioInputProperty"),
    ("sound", "luna://com.webos.service.audio/getSoundOutput"),
    ("stream", "luna://com.webos.service.audio/getStreamStatus"),
)


def failure(reason):
    print("RESULT=R328_READONLY_" + reason)
    raise SystemExit(2)


def read(path, max_bytes):
    try:
        with pathlib.Path(path).open("rb") as f:
            return f.read(max_bytes).decode("utf-8", "replace")
    except (OSError, ValueError):
        return ""


def process_type(pid):
    if type(pid) is not int or not 1 <= pid <= 10000000:
        return "UNKNOWN"
    comm = read(PROC / str(pid) / "comm", 100).strip()
    return comm if comm in KNOWN_PROC else (
        "alsa-sink-MARS" if comm == "alsa-sink-MARS" else "OTHER"
    )


def json_walk(obj):
    q = [(obj, 0)]
    n = 0
    while q and n < 90:
        value, depth = q.pop(0)
        n += 1
        if isinstance(value, dict):
            yield value
            if depth < 5:
                for child in value.values():
                    if isinstance(child, (dict, list)):
                        q.append((child, depth + 1))
        elif isinstance(value, list) and depth < 5:
            for child in value[:64]:
                if isinstance(child, (dict, list)):
                    q.append((child, depth + 1))


def ls2_get(url):
    try:
        p = subprocess.run(
            ["luna-send", "-n", "1", "-w", "2200", url, "{}"],
            capture_output=True, text=True, check=False,
            timeout=4, errors="replace",
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if p.returncode != 0 or len(p.stdout) > 14000:
        return None
    raw = p.stdout
    begin, end = raw.find("{"), raw.rfind("}")
    if begin < 0 or end <= begin:
        return None
    try:
        obj = json.loads(raw[begin:end + 1])
    except ValueError:
        return None
    return obj if isinstance(obj, dict) and obj.get("returnValue") is True else None


def sanitized_ls2(query):
    output = {}
    for label, url in ROUTES:
        data = query(url)
        result = {"available": data is not None}
        if data is None:
            output[label] = result
            continue
        if label == "output":
            entries = data.get("audio", [])
            if not isinstance(entries, list):
                entries = []
            good = [x for x in entries[:64] if isinstance(x, dict)]
            result["route_count"] = len(good)
            matches = [x for x in good if x.get("source") == "ADEC0"
                       and x.get("sink") == "MAIN"]
            result["adec0_main_routes"] = len(matches)
            if len(matches) == 1:
                route = matches[0]
                if type(route.get("muted")) is bool:
                    result["adec0_main_muted"] = route["muted"]
                result["adec0_main_output_mode"] = (
                    route["outputMode"] if route.get("outputMode") in ALLOWED_MODE
                    else "NULL" if "outputMode" in route and route["outputMode"] is None
                    else "OTHER_OR_MISSING"
                )
        elif label == "sound":
            dest = data.get("soundOutput")
            result["output"] = dest if dest in ALLOWED_OUTPUT else "OTHER_OR_MISSING"
        elif label == "codec":
            codecs = [x.get("codec") for x in json_walk(data)
                      if "codec" in x]
            result["codec_fields"] = len(codecs)
            result["dts_codec_fields"] = sum(
                isinstance(x, str) and x.lower() == "dts" for x in codecs)
            result["ac3_codec_fields"] = sum(
                isinstance(x, str) and x.lower() == "ac3" for x in codecs)
        elif label == "stream":
            entries = data.get("streamObject", [])
            good = [x for x in entries[:64] if isinstance(x, dict)] \
                if isinstance(entries, list) else []
            result["streams"] = len(good)
            result["active_known"] = sum(type(x.get("activeStatus")) is bool
                                         for x in good)
            result["active_true"] = sum(x.get("activeStatus") is True
                                        for x in good)
            result["policy_pending_true"] = sum(x.get("policyStatus") is True
                                                for x in good)
        output[label] = result
    return output


def metadata_fds(proc_dir):
    totals = {"alsa_device": 0, "socket": 0, "other": 0}
    try:
        children = list((proc_dir / "fd").iterdir())[:256]
    except OSError:
        return {"available": False}
    for fd in children:
        try:
            dest = os.readlink(fd)
        except OSError:
            continue
        if dest.startswith("/dev/snd/"):
            totals["alsa_device"] += 1
        elif dest.startswith("socket:"):
            totals["socket"] += 1
        else:
            totals["other"] += 1
    return {"available": True, "counts": totals}


def processes():
    counts = {k: 0 for k in KNOWN_PROC}
    holders = 0
    devices = {k: {"alsa_device": 0, "fd_probe_available": 0} for k in KNOWN_PROC}
    mappings = {k: {"libasound_mapped": 0, "libpulse_mapped": 0,
                    "libgst_mapped": 0} for k in KNOWN_PROC}
    try:
        dirs = list(PROC.iterdir())[:16384]
    except OSError:
        return {"available": False}
    for directory in dirs:
        if not directory.name.isdigit():
            continue
        comm = read(directory / "comm", 100).strip()
        if comm not in counts:
            continue
        counts[comm] += 1
        maps = read(directory / "maps", 900000)
        if comm == "starfish-media-" and WRAPPER in maps:
            holders += 1
        known = mappings[comm]
        known["libasound_mapped"] += int("libasound.so" in maps)
        known["libpulse_mapped"] += int("libpulse.so" in maps)
        known["libgst_mapped"] += int("libgstreamer-1.0.so" in maps)
        fd = metadata_fds(directory)
        if fd["available"]:
            devices[comm]["fd_probe_available"] += 1
            devices[comm]["alsa_device"] += fd["counts"]["alsa_device"]
    return {"available": True, "counts": counts, "r278_wrapper_processes": holders,
            "alsa_fds": devices, "library_maps": mappings}


def pcm_status():
    paths = []
    for card in range(3):
        for pcm in range(20):
            for sub in range(3):
                target = PROC / "asound" / ("card%d" % card) / ("pcm%dp" % pcm) / ("sub%d" % sub)
                if (target / "status").is_file():
                    paths.append((card, pcm, sub, target))
    rows = []
    for card, pcm, sub, target in paths[:64]:
        raw = read(target / "status", 4096)
        if not raw:
            continue
        status = {"card": card, "pcm": pcm, "substream": sub}
        for line in raw.splitlines():
            match = STATUS_RE.match(line.strip())
            if not match:
                continue
            key, val = match.groups()
            if key == "state" and val in VALID_STATE:
                status["state"] = val
            elif key == "owner_pid" and val.isdigit():
                owner_id = int(val)
                status["owner_thread_type"] = process_type(owner_id)
                procstat = read(PROC / str(owner_id) / "status", 4096)
                group = re.search(r"^Tgid:\s*(\d+)\s*$", procstat, re.M)
                if group:
                    status["owner_process_type"] = process_type(int(group[1]))
            elif key in ("hw_ptr", "appl_ptr") and val.isdigit():
                status[key + "_present"] = True
        rows.append(status)
    return rows


def capture():
    if platform.machine().lower() != "aarch64":
        failure("EXPECTED_LG_AARCH64")
    data = {
        "schema": "aleks-dts-r328-native-route-v1",
        "stage": "unclassified",
        "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "process": processes(),
        "alsa_playback_devices": pcm_status(),
        "ls2": sanitized_ls2(ls2_get),
        "debug_interfaces": {
            "kernel_debug": pathlib.Path("/sys/kernel/debug").is_dir(),
            "asoc": pathlib.Path("/sys/kernel/debug/asoc").is_dir(),
            "trace_events": pathlib.Path("/sys/kernel/tracing/events").is_dir(),
        },
        "dts_pcm_waveform": "NOT_MEASURED",
        "native_dts_caps_segment": "NOT_MEASURED",
        "acoustic_state": "UNCLASSIFIED",
        "service_or_audio_setting_changes": False,
    }
    print("R328_ROUTE_JSON=" + json.dumps(data, sort_keys=True, separators=(",", ":")))
    print("RESULT=R328_NATIVE_ROUTE_READONLY_PASS")


def selftest():
    sample = {
        "returnValue": True,
        "audio": [
            {"source":"ADEC0","sink":"MAIN","muted":False,"outputMode":None,
             "privatePlaybackUrl":"https://secret.invalid/stream"},
            {"source":"AMIXER","sink":"MAIN","muted":True},
        ],
        "soundOutput": "tv_external_speaker",
        "streamObject": [{"activeStatus":True,"policyStatus":False,
                          "privateTitle":"Secret Movie"},
                         {"activeStatus":False}],
        "codec": {"codec":"dts", "secretField":"token"},
    }
    got = sanitized_ls2(lambda _url: sample)
    assert got["output"]["adec0_main_routes"] == 1
    assert got["output"]["adec0_main_output_mode"] == "NULL"
    assert got["codec"]["dts_codec_fields"] == 1
    assert got["sound"]["output"] == "tv_external_speaker"
    assert got["stream"]["streams"] == 2
    assert "secret" not in json.dumps(got).lower()
    assert "url" not in json.dumps(got).lower()
    assert pcm_status.__name__ == "pcm_status"
    print("RESULT=R328_NATIVE_ROUTE_SELFTEST_PASS")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "selftest":
        selftest()
    elif len(sys.argv) == 2 and sys.argv[1] == "snapshot":
        capture()
    else:
        failure("USAGE")
