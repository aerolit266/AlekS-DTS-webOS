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
          "route_sink", "muted", "output", "hw_frames")


def extract(text):
    """Parse one read-only transcript. Missing fields are UNKNOWN, never FALSE.

    R295 flattens potentially unrelated UMI array entries: do not attribute
    its 'activeStatus'/'muteStatus' flags to DTS or combine resource objects.
    For LS2 queries, accept only successful returnValue=true responses.
    """
    result = dict.fromkeys(FIELDS)
    result["transcript_complete"] = False
    result["transcript_warning"] = None
    lines = [line.strip() for line in text.splitlines()]
    statuses = [line.partition("=")[2] for line in lines if line.startswith("RESULT=")]
    allowed = {"R294_SNAPSHOT_COMPLETE_NO_CHANGES", "R289_SAFE_SNAPSHOT_COMPLETE",
               "R292_TOPOLOGY_CAPTURED_NO_CHANGES",
               "R295_POLICY_QUERY_COMPLETED_NO_DEVICE_CHANGES"}
    result["transcript_complete"] = len(statuses) == 1 and statuses[0] in allowed
    if not result["transcript_complete"]:
        result["transcript_warning"] = "missing, unexpected or multiple RESULT markers"

    for line in lines:
        if line.startswith("DTS_PLUGIN_HOLDERS="):
            v = line.partition("=")[2]
            if v.isdecimal():
                result["plugin"] = int(v) > 0
        elif line.startswith(("DTS_PLUGIN_HOLDER_PID=", "DTS_STARFISH_PID=",
                              "STARFISH_WITH_DTS_PLUGIN=")):
            v = line.partition("=")[2]
            if v.isdecimal():
                result["plugin"] = True
        elif line == "DTS_STARFISH=NOT_FOUND":
            result["plugin"] = False
        elif line.startswith(("ALSA_PCM6=", "ALSA_PCM6_STATE=", "PCM6_STATE=")):
            v = line.partition("=")[2]
            if v in ("RUNNING", "closed", "SUSPENDED", "PREPARED", "unavailable"):
                result["alsa"] = v
        elif line.startswith(("PULSE_INPUT_COUNT=", "SINK_INPUT_COUNT=")):
            v = line.partition("=")[2]
            if v.isdecimal():
                result["pulse_inputs"] = int(v)
        elif line.startswith(("ALSA_HW_FRAMES_3S=", "PCM_HW_DELTA_FRAMES=",
                              "HW_FRAMES_ADVANCED=")):
            v = line.partition("=")[2]
            if v.isdecimal():
                result["hw_frames"] = int(v)
        elif line.startswith("LG_AUDIO_") and '"codec"' in line:
            # Earlier R289 explicitly emitted LG_AUDIO_"codec":"dts".
            m = re.search(r'"codec"\s*:\s*"([A-Za-z0-9_-]{1,30})"', line)
            if m:
                result["codec"] = m.group(1)

    # Group LS2 values by QUERY. A failed/false response must not provide
    # apparent codec or route evidence. Do not flatten unrelated UMI arrays.
    blocks = re.split(r'(?=^QUERY=)', text, flags=re.MULTILINE)
    pair_re = re.compile(
        r'^"([A-Za-z0-9]+)"\s*:\s*("[^"]{1,40}"|true|false|-?\d+)$')
    for block in blocks[1:]:
        rows = block.splitlines()
        if not rows or not rows[0].startswith("QUERY="):
            continue
        label = rows[0].partition("=")[2].strip()
        values = {}
        for raw in rows[1:]:
            line = raw.strip()
            if line.startswith(("QUERY=", "RESULT=")):
                break
            m = pair_re.fullmatch(line)
            if not m:
                continue
            key, raw_value = m.groups()
            if raw_value.startswith('"'):
                value = raw_value[1:-1]
            elif raw_value in ("true", "false"):
                value = raw_value == "true"
            else:
                value = int(raw_value)
            values[key] = value
        if values.get("returnValue") is not True:
            continue
        if label in ("CODEC", "AUDIO_INPUT_PROPERTY", "LG_AUDIO_CODEC", "codec"):
            if isinstance(values.get("codec"), str):
                result["codec"] = values["codec"]
        elif label in ("NATIVE_ROUTE", "LG_AUDIOOUTPUT_CONNECTIONS",
                       "AUDIOOUTPUT_STATUS", "audio"):
            for src, dest in (("source", "route_source"), ("sink", "route_sink"),
                              ("muted", "muted")):
                if src in values:
                    result[dest] = values[src]
        elif label in ("OUTPUT", "LG_AUDIO_OUTPUT", "LG_MASTER_VOLUME"):
            if isinstance(values.get("soundOutput"), str):
                result["output"] = values["soundOutput"]
    return result

def compare(before, after, heard_before, heard_after):
    diff = {key: {"before": before[key], "after": after[key]}
            for key in FIELDS if before[key] != after[key]}
    assessment = []
    if not before.get("transcript_complete") or not after.get("transcript_complete"):
        assessment.append("At least one transcript lacks a complete, supported RESULT marker; do not treat this comparison as validated.")
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
    # R294 actual idle field layout (sanitized; from witnessed TV output).
    idle = extract("""=== R294 ===
STARFISH_PROCESSES=1 DTS_PLUGIN_HOLDERS=0
PULSE_INPUT_COUNT=0
ALSA_PCM6=closed
QUERY=CODEC
"returnValue":true
"codec":"mpeg"
QUERY=NATIVE_ROUTE
"returnValue":true
"source":"ADEC1"
"muted":false
"sink":"MAIN"
QUERY=OUTPUT
"returnValue":true
"soundOutput":"tv_external_speaker"
RESULT=R294_SNAPSHOT_COMPLETE_NO_CHANGES
""")
    # Real R289 working-session shape; its codec was LG_AUDIO_ prefixed.
    healthy = extract("""=== R289 ===
DTS_STARFISH_PID=20727
ALSA_PCM6_STATE=RUNNING
PCM_HW_DELTA_FRAMES=194560
LG_AUDIO_"codec":"dts"
RESULT=R289_SAFE_SNAPSHOT_COMPLETE
""")
    # Synthetic silent case: real historical silence lacked a PCM measurement.
    unknown_pcm_silence = extract("""DTS_PLUGIN_HOLDERS=1
QUERY=CODEC
"returnValue":true
"codec":"dts"
RESULT=R294_SNAPSHOT_COMPLETE_NO_CHANGES
""")
    assert idle["plugin"] is False and idle["codec"] == "mpeg"
    assert idle["pulse_inputs"] == 0 and idle["route_source"] == "ADEC1"
    assert healthy["plugin"] is True and healthy["codec"] == "dts"
    assert healthy["alsa"] == "RUNNING" and healthy["hw_frames"] == 194560
    assert healthy["transcript_complete"] is True
    assert unknown_pcm_silence["alsa"] is None
    # API failure MUST NOT be interpreted as real codec/route/mute state.
    bad_query = extract("""QUERY=CODEC
"returnValue":false
"codec":"dts"
QUERY=NATIVE_ROUTE
"returnValue":false
"source":"ADEC0"
"muted":true
RESULT=R295_POLICY_QUERY_COMPLETED_NO_DEVICE_CHANGES
""")
    assert bad_query["codec"] is None and bad_query["route_source"] is None
    assert bad_query["muted"] is None
    # UMI may list different resources. Never infer one cohesive "DTS route".
    mixed_resources = extract("""QUERY=AUDIO_UMI_STATUS
"returnValue":true
"source":"ADEC0"
"activeStatus":true
"sink":"MAIN"
"source":"ADEC1"
"activeStatus":false
RESULT=R295_POLICY_QUERY_COMPLETED_NO_DEVICE_CHANGES
""")
    assert mixed_resources["route_source"] is None and mixed_resources["muted"] is None
    # No synthetic first-start failure may be mislabeled as the witnessed one.
    from_idle = compare(idle, healthy, "unknown", "yes")
    assert any("not verified as a DTS-loaded" in s for s in from_idle["assessment"])
    uncertain = compare(unknown_pcm_silence, healthy, "no", "yes")
    assert not any("ALSA playback state changed" in s for s in uncertain["assessment"])
    assert from_idle["root_cause_verified"] is False
    incomplete = extract('QUERY=CODEC\n"returnValue":true\n"codec":"dts"\n')
    assert incomplete["transcript_complete"] is False
    diff = compare(incomplete, healthy, "no", "yes")
    assert any("lacks a complete" in s for s in diff["assessment"])
    print("R296_SELFTEST_PASS assertions=15 real_field_shapes=2 acoustic_inference=false root_cause_claim=false")

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
