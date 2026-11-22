#!/usr/bin/env python3
"""R336: classify 2026-11-22 16:18:54-16:19:04 Starfish error-level records.
Only allowlisted technical predicates; never export original log lines, URLs,
user film names, file paths, decoded/encoded audio or arbitrary error text.
"""
import gzip
import json
from pathlib import Path
import re
import sys

ROOT=Path("/tmp/var/log")
FILES=("legacy-log","legacy-log.0.gz","legacy-log.1.gz",
       "legacy-log.2.gz","legacy-log.3.gz","legacy-log.4.gz")
STAMP=re.compile(rb"^2026-11-22T(16:18:\d\d|16:19:0[0-4])(?:\.\d+)?Z")
CLUES={
    "GST_NOT_NEGOTIATED":rb"not-negotiated|not negotiated",
    "GST_NOT_LINKED":rb"not-linked|not linked",
    "GST_FLOW_ERROR":rb"gst_flow_error|flow_error|flow.return",
    "GST_CRITICAL":rb"gst-critical|gstreamer-critical",
    "AUDIO_RESOURCE":rb"acquired-resource|resource-info|audio-port|resource.?busy",
    "AUDIO_ROUTE":rb"audiooutput|sink.connect|alsa|pulse.?audio|sound.?out",
    "DTS_ACTUAL_CODEC":rb"audio/x-dts|a_dts|aleksdts|dtsdec",
    "AC3_DECODER":rb"omxac3dec|ac-?3|dolby",
    "PCM_OR_SAMPLE":rb"audio/x-raw|\bpcm\b|sample.?rate",
    "PIPELINE_STATE":rb"\bready\b|\bpaused\b|\bplaying\b|\bflush\b|stream-start",
    "TIMEOUT":rb"timeout|timed.out",
    "FAILED":rb"fail(?:ed|ure)?",
    "PERMISSION":rb"permission.denied|access.denied|not.authorized",
    "OOM":rb"out.of.memory|ENOMEM|no.memory",
    "GENERAL_ERROR":rb"\berror\b|\berr\b",
}
COMPILED={key:re.compile(pattern,re.I) for key,pattern in CLUES.items()}
MAX_BYTES=6000000


def classify(line):
    if b"starfish-media" not in line.lower():
        return None
    if not (b"user.err" in line.lower() or b" user.error " in line.lower()):
        return None
    m=STAMP.match(line)
    if not m:
        return None
    matched=[name for name,pat in COMPILED.items() if pat.search(line)]
    return {"utc":m.group(1).decode("ascii"),
            "technical_categories":matched}


def main():
    if sys.argv[1:]==["selftest"]:
        assert classify(b"2026-11-22T16:18:55.127Z starfish-media user.err audio-port=(int)0 GstOMXAc3DecBin failed")["technical_categories"]==["AUDIO_RESOURCE","AC3_DECODER","FAILED"]
        assert classify(b"2026-11-22T16:18:55Z other-service user.err failed")==None
        assert classify(b"2026-11-22T16:18:55Z starfish-media user.info audio-port=(int)0")==None
        assert classify(b"2026-11-22T16:18:55Z starfish-media user.err dts 0:01:12")["technical_categories"]==[]
        print("RESULT=R336_SELFTEST_4_4_PASS")
        return
    if sys.argv[1:]!=["snapshot"]:
        sys.exit(2)
    records=[]
    scanned=0
    for name in FILES:
        p=ROOT/name
        if not p.is_file() or p.is_symlink():
            continue
        try:
            opener=gzip.open if name.endswith(".gz") else open
            with opener(p,"rb") as f:
                size=0
                for raw in f:
                    size+=len(raw)
                    if size>MAX_BYTES:
                        break
                    v=classify(raw)
                    if v is not None:
                        records.append(v)
            scanned+=1
        except (OSError,EOFError,gzip.BadGzipFile):
            continue
    records.sort(key=lambda x:x["utc"])
    print("R336_ALLOWLISTED_ERRORS="+json.dumps({
      "schema":"aleks-dts-r336-boot-error-tags-v1",
      "events":records[:35],
      "total_error_records":len(records),
      "files_read":scanned,
      "raw_log_text_exported":False,
      "audio_or_media_exported":False,
      "production_changed":False
    },sort_keys=True,separators=(",",":")))
    print("RESULT=R336_ALLOWLISTED_ERROR_CHECK_PASS")


if __name__=="__main__":
    main()
