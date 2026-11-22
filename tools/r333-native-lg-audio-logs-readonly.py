#!/usr/bin/env python3
"""R333 read-only, redacted summary of native webOS audio and boot logs.

Never prints source log lines, media titles, paths, URLs, tokens, user data or
raw audio. Only counts allowlisted technical concepts and truncated clock
timestamps. Reads 6 fixed current-boot native logs and bounded gz rotations.
"""
from collections import Counter, defaultdict
import gzip
import json
import re
import sys
from pathlib import Path

ROOT = Path("/tmp/var/log")
FILES = ("bootd.log", "initctl.log", "dbg-log", "legacy-log",
         "legacy-log.0.gz", "legacy-log.1.gz", "legacy-log.2.gz",
         "legacy-log.3.gz", "legacy-log.4.gz", "rtd_acpu1.log",
         "rtd_kcpu1.log", "rtd_logfile.log")
MAX_UNCOMPRESSED_PER_FILE = 5_000_000
MAX_LINES = 250000
PATTERNS = {
    "DTS": re.compile(rb"\bdts\b|audio/x-dts|a_dts", re.I),
    "AC3": re.compile(rb"\bac-?3\b|eac3|dolby", re.I),
    "DECODER": re.compile(rb"decproxy|(?:audio|gst).*decod|\badec\b|fakeadec", re.I),
    "RESOURCE": re.compile(rb"acquired.?resource|resource.?acquir|grant|allocat|release.?resource", re.I),
    "AUDIO_ROUTE": re.compile(rb"audiooutputd|audio.?sink|audio.?route|sound.?out|rtkaudio|sink_connect|sink_disconnect", re.I),
    "DSP": re.compile(rb"\bdsp\d*\b|eform_flush|rtk.?audio|rtaudio", re.I),
    "MUTE": re.compile(rb"\bmute\b|unmute|silenc", re.I),
    "PROBLEM": re.compile(rb"\bfail(?:ed|ure)?\b|\berror\b|timeout|underrun|crash|hang|fatal|segfault|not.ready", re.I),
    "FLUSH": re.compile(rb"\bflush\b|\bseek\b|stream.?start", re.I),
}
CLOCK = re.compile(rb"\b([012]?\d):([0-5]\d):([0-5]\d)(?:\.\d+)?\b")


def window(hh: int, mm: int) -> str:
    if hh == 22 and 35 <= mm <= 45:
        return "COLD_BOOT_AND_SILENT_2235_2245"
    if hh == 22 and 46 <= mm <= 54:
        return "AC3_DTS_RECOVERY_2246_2254"
    return "OTHER_TIME"


def scan() -> dict:
    total = 0
    result = {}
    windows = defaultdict(Counter)
    strong = []
    for filename in FILES:
        path = ROOT / filename
        if not path.is_file() or path.is_symlink():
            result[filename] = {"status": "ABSENT"}
            continue
        counts = Counter()
        times = Counter()
        matching = 0
        read_size = 0
        scanned = 0
        try:
            source = gzip.open(path, "rb") if filename.endswith(".gz") else path.open("rb")
            with source:
                for line in source:
                    read_size += len(line)
                    scanned += 1
                    if read_size > MAX_UNCOMPRESSED_PER_FILE or total + scanned > MAX_LINES:
                        counts["TRUNCATED"] += 1
                        break
                    tags = tuple(tag for tag, pattern in PATTERNS.items() if pattern.search(line))
                    if not tags:
                        continue
                    matching += 1
                    counts.update(tags)
                    stamp = CLOCK.search(line[:220])
                    if stamp:
                        hh, mm, ss = (int(x) for x in stamp.groups())
                        if hh <= 23:
                            when = window(hh, mm)
                            windows[when].update(tags)
                            times[f"{hh:02}:{mm:02}"] += 1
                            # Only technical event labels and numeric time are exported.
                            if len(strong) < 65 and (
                                ("DTS" in tags and len(tags) > 1)
                                or ("RESOURCE" in tags and "PROBLEM" in tags)
                                or ("DSP" in tags and "PROBLEM" in tags)
                            ):
                                strong.append({
                                    "source": filename,
                                    "clock": f"{hh:02}:{mm:02}:{ss:02}",
                                    "tags": list(tags),
                                })
                    else:
                        windows["NO_CLOCK"].update(tags)
        except (OSError, EOFError, gzip.BadGzipFile):
            result[filename] = {"status": "ERROR"}
            continue
        result[filename] = {
            "status": "SCANNED",
            "lines": scanned,
            "matched_lines": matching,
            "class_counts": dict(counts),
            "minute_buckets": dict(times.most_common(12)),
        }
        total += scanned
    return {
        "schema": "aleks-dts-r333-redacted-native-logs-v1",
        "files": result,
        "window_tag_counts": {k: dict(v) for k, v in windows.items()},
        "strong_event_time_and_tags": strong,
        "no_raw_logs_exported": True,
        "audio_recorded": False,
        "service_modified": False,
    }


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] != "snapshot":
        print("RESULT=R333_NATIVE_LOG_USAGE")
        return 2
    print("R333_NATIVE_LOG_JSON=" + json.dumps(scan(), sort_keys=True, separators=(",", ":")))
    print("RESULT=R333_NATIVE_LOG_READONLY_SUMMARY_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
