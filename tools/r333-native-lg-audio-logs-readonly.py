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
         "rtd_vcpu1.log", "rtd_vcpu2.log",
         "rtd_kcpu1.log", "rtd_logfile.log")
MAX_UNCOMPRESSED_PER_FILE = 5_000_000
MAX_LINES = 250000
PATTERNS = {
    "DTS_CODEC": re.compile(rb"audio/x-dts|\bA_DTS\b|\baleksdts\w*|\bdtsdec\b|(?:codec|audio-format)[=: ]{1,16}dts(?:-hd)?\b", re.I),
    "DTS_SEAMLESS_FLAG": re.compile(rb"\bdts-seamless\b", re.I),
    "AC3": re.compile(rb"\bac-?3\b|eac3|omxac3dec(?:bin)?|dolby", re.I),
    "DECODER": re.compile(rb"decproxy|(?:audio|gst).*decod|\badec\b|fakeadec", re.I),
    "RESOURCE": re.compile(rb"acquired.?resource|resource.?acquir|grant|allocat|release.?resource", re.I),
    "AUDIO_ROUTE": re.compile(rb"audiooutputd|audio.?sink|audio.?route|sound.?out|rtkaudio|sink_connect|sink_disconnect", re.I),
    "DSP": re.compile(rb"\bdsp\d*\b|eform_flush|rtk.?audio|rtaudio", re.I),
    "MUTE": re.compile(rb"\bmute\b|unmute|silenc", re.I),
    "PROBLEM_TERM": re.compile(rb"\bfail(?:ed|ure)?\b|\berror\b|timeout|underrun|crash|hang|fatal|segfault|not.ready", re.I),
    "WARN_OR_ERROR_LEVEL": re.compile(rb"\buser\.(?:err|warning|crit)\b|\s(?:ERROR|WARN|CRITICAL)\s{2,}", re.I),
    "FLUSH": re.compile(rb"\bflush\b|\bseek\b|stream.?start", re.I),
}
ISO_UTC = re.compile(rb"2026-11-22T([012]\d):([0-5]\d):([0-5]\d)")


def window(hh: int, mm: int) -> str:
    # Timestamps in native legacy-log are UTC, unlike LG ls -l output.
    if hh == 15 and 35 <= mm <= 45:
        return "COLD_BOOT_AND_SILENT_1535_1545_UTC"
    if hh == 15 and 46 <= mm <= 54:
        return "AC3_DTS_RECOVERY_1546_1554_UTC"
    return "OTHER_TIME"


def scan() -> dict:
    total = 0
    result = {}
    windows = defaultdict(Counter)
    strong = []
    minute_tags = defaultdict(Counter)
    seen_per_window = Counter()
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
                    stamp = ISO_UTC.search(line[:160])
                    if stamp:
                        hh, mm, ss = (int(x) for x in stamp.groups())
                        when = window(hh, mm)
                        windows[when].update(tags)
                        minute = f"{hh:02}:{mm:02}"
                        times[minute] += 1
                        minute_tags[minute].update(tags)
                        salient = (
                            ("DTS_CODEC" in tags and len(tags) > 1)
                            or ("AC3" in tags and "DECODER" in tags)
                            or ("RESOURCE" in tags and "WARN_OR_ERROR_LEVEL" in tags)
                            or ("DSP" in tags and "WARN_OR_ERROR_LEVEL" in tags)
                            or ("AUDIO_ROUTE" in tags and "WARN_OR_ERROR_LEVEL" in tags)
                            or ("FLUSH" in tags and "DECODER" in tags)
                        )
                        if salient and seen_per_window[when] < 45:
                            strong.append({
                                "source": filename, "clock": f"{hh:02}:{mm:02}:{ss:02}",
                                "tags": list(tags),
                            })
                            seen_per_window[when] += 1
                    else:
                        windows["NO_ABSOLUTE_UTC_CLOCK"].update(tags)
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
        "strong_event_time_and_tags": sorted(strong, key=lambda x:x["clock"]),
        "minute_tag_counts": {k: dict(v) for k,v in sorted(minute_tags.items())},
        "no_raw_logs_exported": True,
        "audio_recorded": False,
        "service_modified": False,
    }


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in ("snapshot", "compact"):
        print("RESULT=R333_NATIVE_LOG_USAGE")
        return 2
    data = scan()
    if sys.argv[1] == "compact":
        keep = ("DTS_CODEC", "DTS_SEAMLESS_FLAG", "AC3", "DECODER", "RESOURCE",
                "DSP", "WARN_OR_ERROR_LEVEL")
        slim = {
            "schema": data["schema"],
            "windows": {key: {tag: counters.get(tag, 0) for tag in keep}
                        for key, counters in data["window_tag_counts"].items()},
            "codec_minutes": {
                minute: {tag: totals.get(tag, 0) for tag in keep}
                for minute, totals in data["minute_tag_counts"].items()
                if "15:40" <= minute <= "15:54"
            },
            "sample_events": data["strong_event_time_and_tags"][:14],
            "no_raw_logs_exported": True,
            "service_modified": False,
        }
        print("R333_NATIVE_LOG_COMPACT_JSON=" +
              json.dumps(slim, sort_keys=True, separators=(",", ":")))
    else:
        print("R333_NATIVE_LOG_JSON=" +
              json.dumps(data, sort_keys=True, separators=(",", ":")))
    print("RESULT=R333_NATIVE_LOG_READONLY_SUMMARY_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
