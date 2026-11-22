#!/usr/bin/env python3
"""R334 real Starfish first-DTS diagnostic: fast read-only native log edge scan.

Usage: r334-live-lg-codec-event-snapshot.py selftest
       r334-live-lg-codec-event-snapshot.py cold
       r334-live-lg-codec-event-snapshot.py recovered

No record of raw log lines/media titles/URLs/audio data. Only UTC times,
technical event labels, numeric resource-port IDs and counts. No service,
registry or kernel change. A fresh capture must occur soon after DTS selection
before LG log rotation evicts the first-decode events.
"""
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
import gzip
import json
import re
import sys

BASE = Path("/tmp/var/log")
ROTATIONS = ("legacy-log", "legacy-log.0.gz", "legacy-log.1.gz",
             "legacy-log.2.gz", "legacy-log.3.gz", "legacy-log.4.gz")
ISO = re.compile(rb"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.\d+)?Z")
PORT = re.compile(rb"(?:audio-port|dec_port)[ =:]+(?:\(int\))?(\d{1,2})", re.I)
SECONDS = 8 * 60
MAX_BYTES_PER_FILE = 2600000
MAX_EVENT_OUTPUT = 45


def labels(line: bytes) -> tuple:
    low = line.lower()
    ans = []
    if b"acquired-resource" in low:
        ans.append("AUDIO_RESOURCE_GRANT")
    if b"resource-info" in low and (b"gst_rtk_codec_bin_set_property" in low
                                   or b"gstomxaudiodec" in low):
        ans.append("DECODER_RESOURCE_BIND")
    if b"omxac3decbin" in low and (b" init " in low or b"gst_rtk_codec_bin_init" in low):
        ans.append("HW_AC3_BIN_INIT")
    if b"success to switch decoder" in low:
        ans.append("DECODER_SWITCH_SUCCESS")
    if b"aleksdts" in low or b"libgstaleksdts" in low:
        ans.append("ALEKS_DTS_PLUGIN")
    if b"audio/x-dts" in low or b"a_dts" in low:
        ans.append("REAL_DTS_CODEC_CAPS")
    if b"dts-seamless" in low:
        ans.append("DTS_SEAMLESS_PARAMETER")
    if b"stream-start" in low and b"decproxy" in low:
        ans.append("DECODER_STREAM_START")
    if b"caps event" in low and b"decproxy" in low:
        ans.append("DECODER_CAPS")
    if b"sndout_disconnect" in low or b"sink_disconnect" in low:
        ans.append("AUDIO_SINK_DISCONNECT")
    if b"sndout_connect" in low or b"sink_connect" in low:
        ans.append("AUDIO_SINK_CONNECT")
    if (b"eform_flush" in low or b"dsp0" in low) and (
        b"error" in low or b"fail" in low or b"hang" in low
    ):
        ans.append("DSP_ERROR_CONTEXT")
    if b"starfish-media" in low and (b" user.err " in low or b" error " in low):
        ans.append("MEDIA_ERROR_SEVERITY")
    return tuple(ans)


def scan(now: datetime, root: Path) -> dict:
    since = now - timedelta(seconds=SECONDS)
    counts = Counter()
    events = []
    scanned = {}
    for filename in ROTATIONS:
        p = root / filename
        if not p.is_file() or p.is_symlink():
            continue
        total = 0
        observed = 0
        try:
            opener = gzip.open if filename.endswith(".gz") else open
            with opener(p, "rb") as stream:
                for line in stream:
                    total += len(line)
                    if total > MAX_BYTES_PER_FILE:
                        break
                    stamp = ISO.match(line)
                    if not stamp:
                        continue
                    moment = datetime.fromisoformat(stamp.group(1).decode("ascii")).replace(
                        tzinfo=timezone.utc)
                    if not since <= moment <= now + timedelta(seconds=15):
                        continue
                    kinds = labels(line)
                    if not kinds:
                        continue
                    observed += 1
                    counts.update(kinds)
                    if len(events) < 500:
                        port = PORT.search(line)
                        event = {
                            "utc": moment.strftime("%H:%M:%S"),
                            "kind": list(kinds),
                        }
                        if port:
                            event["port"] = int(port.group(1))
                        events.append(event)
        except (OSError, EOFError, gzip.BadGzipFile, ValueError):
            scanned[filename] = "READ_ERROR"
            continue
        scanned[filename] = observed
    events.sort(key=lambda x: x["utc"])
    return {
        "schema": "aleks-dts-r334-first-dts-event-edge-v1",
        "window_seconds": SECONDS,
        "clock_utc": now.strftime("%H:%M:%S"),
        "technical_event_counts": dict(counts),
        "event_timeline": events[:MAX_EVENT_OUTPUT],
        "file_event_counts": scanned,
        "no_original_log_lines": True,
        "no_audio_or_media_metadata": True,
        "production_changes": False,
    }


def selftest() -> None:
    lines = (
        b"2026-11-22T15:50:34.090Z gstdecproxy2 got resource-info : acquired-resource, "
        b"audio-port=(int)0",
        b"2026-11-22T15:50:34.112Z GstOMXAc3DecBin init",
        b"2026-11-22T15:50:34.118Z Success to switch decoder(omxac3decbin1)",
        b"2026-11-22T15:50:34.485Z buffer pts 0:08:15, dts 0:08:15",
        b"2026-11-22T15:50:34.147Z dts-seamless=0",
    )
    assert "AUDIO_RESOURCE_GRANT" in labels(lines[0])
    assert PORT.search(lines[0]).group(1) == b"0"
    assert "HW_AC3_BIN_INIT" in labels(lines[1])
    assert "DECODER_SWITCH_SUCCESS" in labels(lines[2])
    assert labels(lines[3]) == ()  # decoding time stamp is not DTS codec
    assert "REAL_DTS_CODEC_CAPS" not in labels(lines[4])
    assert "DTS_SEAMLESS_PARAMETER" in labels(lines[4])
    print("RESULT=R334_SELFTEST_6_OF_6_PASS")


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in ("cold", "recovered", "selftest"):
        print("RESULT=R334_USAGE")
        return 2
    if sys.argv[1] == "selftest":
        selftest()
        return 0
    state = scan(datetime.now(timezone.utc), BASE)
    state["phase_label"] = sys.argv[1]
    print("R334_TELEMETRY=" + json.dumps(state, sort_keys=True, separators=(",", ":")))
    print("RESULT=R334_READONLY_FAST_EDGE_CAPTURE_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
