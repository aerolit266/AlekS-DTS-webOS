#!/usr/bin/env python3
"""AlekS DTS R333: read-only bounded LS2 audio route telemetry on LG.

Runs only getter methods, under a private pseudo-terminal for webOS luna-send.
No audio PCM, titles, URLs, media details, original responses or credentials
are output. Does not subscribe or call setters. Does not alter service state.
"""
import json
import os
import pty
import re
import select
import signal
import subprocess
import sys
import time
from typing import Any

QUERIES = (
    ("audiooutput", "luna://com.webos.service.audiooutput/audio/getStatus", {}),
    ("avoutput", "luna://com.webos.service.avoutput/audio/getStatus", {}),
    ("audio", "luna://com.webos.service.audio/getSoundOutput", {}),
    ("tv_audio", "luna://com.webos.audio/getStatus", {}),
    ("stream_policy", "luna://com.webos.service.audio/getStreamStatus", {}),
    ("source_policy", "luna://com.webos.service.audio/getSourceStatus", {}),
    ("master_volume", "luna://com.webos.service.audio/master/getVolume", {}),
)
ALLOWED = {
    "source", "sink", "sourcePort", "outputMode", "muted", "soundOutput",
    "soundOut", "audioType", "volume", "input_codec", "output_codec",
    "returnValue", "errorCode", "inputSource", "inputCodec", "outputCodec",
    "sound_output", "input_source", "audioDirection", "isMuted",
    "streamObject", "sourceObject", "volumeStatus", "inputVolume",
    "activeStatus", "muteStatus", "policyStatus", "streamType",
    "sourceType", "sessionId", "subscribed",
}
MAX_READ = 20000
TIMEOUT_SECONDS = 4.0


def invoke_getter(uri: str, payload: dict) -> str:
    master, slave = pty.openpty()
    proc = None
    output = bytearray()
    try:
        proc = subprocess.Popen(
            ["luna-send", "-n", "1", "-f", uri, json.dumps(payload, separators=(",", ":"))],
            stdin=slave, stdout=slave, stderr=slave,
            close_fds=True, start_new_session=True,
        )
        os.close(slave)
        slave = -1
        deadline = time.monotonic() + TIMEOUT_SECONDS
        while time.monotonic() < deadline and len(output) < MAX_READ:
            readable, _, _ = select.select([master], [], [], min(
                0.3, max(0.0, deadline - time.monotonic())
            ))
            if readable:
                try:
                    chunk = os.read(master, min(2048, MAX_READ - len(output)))
                except OSError:
                    break
                if not chunk:
                    break
                output.extend(chunk)
            if proc.poll() is not None and not readable:
                break
        if proc.poll() is None:
            # Only terminate our own temporary getter, never another process.
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=0.4)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=0.4)
    finally:
        os.close(master)
        if slave >= 0:
            os.close(slave)
        if proc and proc.poll() is None:
            proc.kill()
            proc.wait(timeout=0.5)
    return output.decode("utf-8", "replace")


def parse_objects(output: str) -> list:
    text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", output)
    decoder = json.JSONDecoder()
    found = []
    for index, char in enumerate(text):
        if char != "{":
            continue
        try:
            val, _ = decoder.raw_decode(text[index:])
        except (ValueError, RecursionError):
            continue
        if isinstance(val, dict) and (
            "returnValue" in val or "audio" in val or "soundOutput" in val
        ):
            found.append(val)
    return found


def redact(obj: Any, depth: int = 0) -> Any:
    if depth > 4:
        return None
    if isinstance(obj, list):
        return [redact(v, depth + 1) for v in obj[:24]]
    if not isinstance(obj, dict):
        return None
    out = {}
    for key, val in obj.items():
        if key in ("audio", "streamObject", "sourceObject") and isinstance(val, list):
            out[key] = [redact(x, depth + 1) for x in val[:16]]
            continue
        if key == "volumeStatus" and isinstance(val, dict):
            out[key] = redact(val, depth + 1)
            continue
        if key not in ALLOWED:
            continue
        if isinstance(val, bool):
            out[key] = val
        elif isinstance(val, int) and -1 <= val <= 10000:
            out[key] = val
        elif isinstance(val, str) and len(val) <= 40 and re.fullmatch(
            r"[\w. +:/-]+", val, re.ASCII
        ):
            out[key] = val
    return out


def main() -> int:
    if sys.argv != [sys.argv[0], "snapshot"]:
        print("RESULT=R333_USAGE")
        return 2
    summaries = {}
    for name, uri, payload in QUERIES:
        try:
            replies = parse_objects(invoke_getter(uri, payload))
        except (OSError, ValueError, subprocess.SubprocessError):
            summaries[name] = {"status": "UNAVAILABLE"}
            continue
        if not replies:
            summaries[name] = {"status": "NO_STRUCTURED_REPLY"}
            continue
        selection = redact(replies[-1])
        summaries[name] = {"status": "REPLY", "fields": selection}
    print("R333_AUDIO_ROUTE_JSON=" + json.dumps({
        "schema": "aleks-dts-r333-ls2-allowlisted-v1",
        "queries": summaries,
        "changes": False, "raw_response_exported": False,
        "audio_recorded": False,
    }, sort_keys=True, separators=(",", ":")))
    print("RESULT=R333_READONLY_AUDIO_ROUTE_CAPTURE_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
