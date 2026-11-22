#!/usr/bin/env python3
"""R335: correlate owner-labelled cold silent and recovered DTS log edges.

No original log lines, player metadata or PCM exported. Read only. Exact UTC
scope grounded in the two R334 captures, not guessed local wall clock.
"""
from collections import Counter
import gzip
import json
from pathlib import Path
import re
import sys

ROOT = Path("/tmp/var/log")
FILES = ("legacy-log", "legacy-log.0.gz", "legacy-log.1.gz",
         "legacy-log.2.gz", "legacy-log.3.gz", "legacy-log.4.gz")
UTC = re.compile(rb"^2026-11-22T(16:\d\d:\d\d)(?:\.\d+)?Z")
PORT = re.compile(rb"audio-port=\(int\)(\d{1,2})")
COLD_START = "16:18:45"
BEFORE = "16:20:14"
AFTER = "16:24:28"
MAX_BYTES = 6000000
MAX_EVENTS = 80


def classify(raw: bytes) -> tuple:
    line = raw.lower()
    out = []
    if b"audio/x-dts" in line or b"a_dts" in line:
        out.append("REAL_DTS_CAPS")
    if b"libgstaleksdts" in line or b"aleksdts" in line:
        out.append("ALEKS_DTS_PLUGIN")
    if b"acquired-resource" in line:
        out.append("AUDIO_RESOURCE_GRANTED")
    if b"gst_rtk_codec_bin_set_property" in line and b"resource-info" in line:
        out.append("RESOURCE_BIND")
    if b"omxac3decbin" in line and b"init" in line:
        out.append("AC3_DECODER_INITIALIZATION")
    if b"success to switch decoder" in line:
        out.append("DECODER_SWITCH_SUCCESS")
    if b"gstdecproxy" in line and b"stream-start" in line:
        out.append("STREAM_START")
    if b"gstdecproxy" in line and b"caps event" in line:
        out.append("CAPS_EVENT")
    if b"audiooutputd" in line and (b"connect" in line or b"disconnect" in line):
        out.append("AUDIOOUTPUT_ROUTE_CHANGE")
    if b"starfish-media" in line and (b"user.err" in line or b" error " in line):
        out.append("ERROR_LEVEL")
    return tuple(out)


def run() -> dict:
    counts=Counter()
    timeline=[]
    cold_counts=Counter()
    cold_timeline=[]
    files_seen={}
    for filename in FILES:
        file=ROOT / filename
        if not file.is_file() or file.is_symlink():
            continue
        scanned=0
        included=0
        try:
            opener=gzip.open if filename.endswith(".gz") else open
            with opener(file,"rb") as f:
                for raw in f:
                    scanned+=len(raw)
                    if scanned>MAX_BYTES:
                        break
                    match=UTC.match(raw)
                    if not match:
                        continue
                    stamp=match.group(1).decode("ascii")
                    if not COLD_START<=stamp<=AFTER:
                        continue
                    kinds=classify(raw)
                    if not kinds:
                        continue
                    included+=1
                    p=PORT.search(raw)
                    event={"utc":stamp,"event":list(kinds)}
                    if p: event["audio_port"]=int(p.group(1))
                    if stamp<=BEFORE:
                        cold_counts.update(kinds)
                        if len(cold_timeline)<500: cold_timeline.append(event)
                    else:
                        counts.update(kinds)
                        if len(timeline)<500: timeline.append(event)
        except (OSError,EOFError,gzip.BadGzipFile):
            files_seen[filename]="READ_ERROR"
            continue
        files_seen[filename]=included
    timeline.sort(key=lambda ev:ev["utc"])
    cold_timeline.sort(key=lambda ev:ev["utc"])
    return {
      "schema":"aleks-dts-r335-transition-diff-v1",
      "before_snapshot_utc":BEFORE,
      "recovered_snapshot_utc":AFTER,
      "cold_before_first_snapshot_from_utc":COLD_START,
      "cold_counts":dict(cold_counts),
      "cold_events":cold_timeline[-MAX_EVENTS:],
      "counts":dict(counts),
      "last_events":timeline[-MAX_EVENTS:],
      "source_file_event_counts":files_seen,
      "original_log_lines_exported":False,
      "audio_samples_exported":False,
      "tv_modified":False,
    }


def selftest():
    assert classify(b"dts 0:08:15 dts-seamless=0")==()
    assert "REAL_DTS_CAPS" in classify(b"GST CAPS audio/x-dts")
    assert "AUDIO_RESOURCE_GRANTED" in classify(b"acquired-resource audio-port=(int)0")
    assert PORT.search(b"acquired-resource audio-port=(int)0").group(1)==b"0"
    assert "DECODER_SWITCH_SUCCESS" in classify(b"Success to switch decoder(omxac3decbin1)")
    assert "AC3_DECODER_INITIALIZATION" in classify(b"GstOMXAc3DecBin init")
    print("RESULT=R335_SELFTEST_6_6_PASS")


if __name__=="__main__":
    if sys.argv[1:]==["selftest"]:
        selftest()
    elif sys.argv[1:]==["snapshot"]:
        print("R335_TRANSITION="+json.dumps(run(),sort_keys=True,separators=(",",":")))
        print("RESULT=R335_READONLY_TRANSITION_SNAPSHOT_PASS")
    else:
        print("RESULT=R335_USAGE")
        sys.exit(2)
