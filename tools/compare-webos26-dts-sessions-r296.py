#!/usr/bin/env python3
"""R296: compare AlekS DTS R294/R295 read-only session transcripts OFF the TV.

Never controls audio, parses secrets or claims acoustic PASS from telemetry.
Python stdlib only. Use explicit owner hearing labels as separate evidence.
"""
import argparse
import json
import re
from pathlib import Path

FIELDS = ("codec", "plugin", "alsa", "pulse_inputs", "route_source",
          "route_sink", "muted", "output", "hw_frames", "umi_active", "stream_active")


def extract(text):
    result = dict.fromkeys(FIELDS)
    query = ""
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("QUERY="):
            query = line.split("=", 1)[1]
        elif line.startswith("DTS_PLUGIN_HOLDERS="):
            v = line.split("=", 1)[1]
            if v.isdecimal():
                result["plugin"] = int(v) > 0
        elif line.startswith("DTS_PLUGIN_HOLDER_PID="):
            result["plugin"] = True
        elif line.startswith("DTS_STARFISH_PID="):
            result["plugin"] = True
        elif line == "DTS_STARFISH=NOT_FOUND":
            result["plugin"] = False
        elif line.startswith("ALSA_PCM6=") or line.startswith("ALSA_PCM6_STATE=") or line.startswith("PCM6_STATE="):
            result["alsa"] = line.partition("=")[2]
        elif line.startswith("PULSE_INPUT_COUNT="):
            raw = line.partition("=")[2]
            if raw.isdecimal():
                result["pulse_inputs"] = int(raw)
        elif line.startswith("ALSA_HW_FRAMES_3S=") or line.startswith("PCM_HW_DELTA_FRAMES="):
            raw = line.partition("=")[2]
            if raw.isdecimal():
                result["hw_frames"] = int(raw)
        elif line.startswith('"'):
            pair = re.fullmatch(r'"([a-zA-Z0-9]+)"\s*:\s*("[^"]{1,40}"|true|false|-?\d+)', line)
            if not pair:
                continue
            key, value = pair.groups()
            if value.startswith('"'):
                value = value[1:-1]
            elif value in ("true", "false"):
                value = value == "true"
            elif re.fullmatch(r"-?\d+", value):
                value = int(value)
            if key == "codec":
                result["codec"] = value
            elif key in ("source", "sink", "muted") and query in (
                "NATIVE_ROUTE", "LG_AUDIOOUTPUT_CONNECTIONS", "AUDIOOUTPUT_STATUS", "audio"):
                result[{"source": "route_source", "sink": "route_sink", "muted": "muted"}[key]] = value
            elif key == "soundOutput":
                result["output"] = value
            elif key == "activeStatus" and query == "AUDIO_UMI_STATUS":
                result["umi_active"] = value
            elif key == "activeStatus" and query == "AUDIO_STREAM_STATUS":
                result["stream_active"] = value
    return result


def compare(before, after, heard_before, heard_after):
    diff = {key: {"before": before[key], "after": after[key]}
            for key in FIELDS if before[key] != after[key]}
    assessment = []
    if before["codec"] != "dts" or before["plugin"] is not True:
        assessment.append("Before sample is not verified as a DTS-loaded session; do not classify it as first-start DTS failure.")
    if heard_before != "no" or heard_after != "yes":
        assessment.append("No explicit owner-confirmed silent→audible pair; root-cause comparison is incomplete.")
    if heard_before == "no" and heard_after == "yes":
        if before["codec"] == "dts" and after["codec"] == "dts" and before["plugin"] is True and after["plugin"] is True:
            assessment.append("Both sessions recognize DTS and have AlekS libraries mapped; mapping/codec recognition alone cannot explain silence.")
        if before["alsa"] != "RUNNING" and after["alsa"] == "RUNNING" and before["alsa"] is not None:
            assessment.append("ALSA playback state changed to RUNNING. Investigate renderer/resource initialization; this is correlation, not causation.")
        if before["muted"] is True and after["muted"] is False:
            assessment.append("Native mute state differs and merits investigation, but does not alone identify why it changed.")
    if not assessment:
        assessment.append("Telemetry differences are descriptive only; acoustics and decoder→sink provenance not established.")
    return {"fields": diff, "assessment": assessment,
            "root_cause_verified": False,
            "explicit_owner_hearing": {"before": heard_before, "after": heard_after}}


def selftest():
    idle = extract('DTS_PLUGIN_HOLDERS=0\nPULSE_INPUT_COUNT=0\nALSA_PCM6=closed\nQUERY=CODEC\n"codec":"mpeg"\nQUERY=NATIVE_ROUTE\n"source":"ADEC1"\n')
    good = extract('DTS_PLUGIN_HOLDER_PID=20727\nPULSE_INPUT_COUNT=1\nALSA_PCM6=RUNNING\nALSA_HW_FRAMES_3S=144000\nQUERY=CODEC\n"codec":"dts"\nQUERY=NATIVE_ROUTE\n"source":"ADEC0"\n"muted":false\n')
    silent = extract('DTS_PLUGIN_HOLDER_PID=10846\nALSA_PCM6=closed\nQUERY=CODEC\n"codec":"dts"\n')
    assert idle["plugin"] is False and idle["codec"] == "mpeg"
    assert good["plugin"] is True and good["hw_frames"] == 144000
    assert silent["plugin"] is True and silent["alsa"] == "closed"
    res = compare(silent, good, "no", "yes")
    assert any("ALSA playback" in s for s in res["assessment"])
    res2 = compare(idle, good, "unknown", "yes")
    assert any("not verified as a DTS-loaded" in s for s in res2["assessment"])
    assert res["root_cause_verified"] is False
    print("R296_SELFTEST_PASS synthetic_cases=5 root_cause_claim=false")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", nargs="?", help="First read-only R294/R295 transcript")
    parser.add_argument("after", nargs="?", help="Second read-only R294/R295 transcript")
    parser.add_argument("--heard-before", choices=("yes", "no", "unknown"), default="unknown")
    parser.add_argument("--heard-after", choices=("yes", "no", "unknown"), default="unknown")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        selftest()
        return
    if not args.before or not args.after:
        parser.error("Pass two local transcript files; no TV connection is made.")
    before = extract(Path(args.before).read_text(encoding="utf-8", errors="replace"))
    after = extract(Path(args.after).read_text(encoding="utf-8", errors="replace"))
    print(json.dumps({"before": before, "after": after,
                      "comparison": compare(before, after, args.heard_before, args.heard_after)},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
