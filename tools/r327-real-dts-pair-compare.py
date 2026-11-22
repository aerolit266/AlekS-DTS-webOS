#!/usr/bin/env python3
"""R327: compare real, owner-confirmed LG kitchen DTS silent/audible captures.

Inputs are private R326 allowlisted metadata/aggregate levels, NOT audio.
No network, playback, microphone, mutation or waveform access.
Report differentiates stable PA/ALSA route facts from natural latency jitter.
Usage: python3 tools/r327-real-dts-pair-compare.py silent.json audible.json
       python3 tools/r327-real-dts-pair-compare.py --selftest
"""
import datetime as dt
import json
import pathlib
import sys

SCHEMA = "aleks-dts-r326-real-pair-v1"
MAX_JSON = 64000
STABLE_INPUT = ("id", "sink_id", "format", "rate", "channels", "mute",
                "corked", "volume_percent_min", "volume_percent_max")
STABLE_SINK = ("id", "state", "format", "rate", "channels", "mute",
               "volume_percent_min", "volume_percent_max")
STABLE_ALSA = ("state", "owner_process_type", "owner_thread_type",
               "is_pulseaudio_sink_thread")
STABLE_PARAMS = ("format", "channels", "rate")
STABLE_MEDIA = ("starfish_r278_wrapper_holders",)


def reject(reason):
    print("RESULT=R327_PAIR_REJECTED_" + reason)
    raise SystemExit(2)


def load(path):
    p = pathlib.Path(path)
    if not p.is_file() or p.stat().st_size > MAX_JSON:
        reject("INPUT_SIZE")
    try:
        obj = json.loads(p.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        reject("BAD_JSON")
    if not isinstance(obj, dict) or obj.get("schema") != SCHEMA:
        reject("BAD_SCHEMA")
    return obj


def stable_pulse(snapshot):
    pa = snapshot["pulse"]
    inputs = pa["sink_inputs"]
    sinks = pa["sinks"]
    if not pa["query_ok"] or len(inputs) != 1:
        reject("NO_SINGLE_PA_INPUT")
    inp = inputs[0]
    out_id = inp["sink_id"]
    matching = [s for s in sinks if s.get("id") == out_id]
    if len(matching) != 1:
        reject("NO_MATCHING_PA_SINK")
    sink = matching[0]
    return {
        "input": {k: inp.get(k) for k in STABLE_INPUT},
        "sink": {k: sink.get(k) for k in STABLE_SINK},
    }


def stable_alsa(snapshot):
    alsa = snapshot["alsa_pcm6"]
    return {**{k: alsa.get(k) for k in STABLE_ALSA},
            "hw_params": {k: alsa.get("hw_params", {}).get(k)
                          for k in STABLE_PARAMS}}


def check_sample(obj, expected):
    if obj.get("classification") != "OWNER_CONFIRMED_REAL_" + expected.upper():
        reject("OWNER_LABEL")
    bef, aft, mon = (obj.get(k) for k in ("before", "after", "monitor"))
    if not all(isinstance(v, dict) for v in (bef, aft, mon)):
        reject("MISSING_STAGE")
    if (bef.get("stage") != expected or aft.get("stage") != expected or
        mon.get("owner_observation") != expected or
        bef.get("observation") != "OWNER_LABELED_ONLY" or
        aft.get("observation") != "OWNER_LABELED_ONLY"):
        reject("OWNER_STAGE_MISMATCH")
    if bef.get("boot_fingerprint") != aft.get("boot_fingerprint"):
        reject("INTRA_STAGE_REBOOT")
    if stable_pulse(bef) != stable_pulse(aft):
        reject("ROUTE_CHANGED_DURING_LEVEL_SAMPLE")
    if stable_alsa(bef) != stable_alsa(aft):
        reject("ALSA_CHANGED_DURING_LEVEL_SAMPLE")
    if not mon.get("raw_pcm_exported") is False or mon.get("audio_files_created") != 0:
        reject("RECORDED_AUDIO_NOT_ALLOWED")
    count, nonzero = mon.get("sample_count"), mon.get("nonzero_sample_count")
    if (not isinstance(count, int) or isinstance(count, bool) or
        not 0 < count <= 200000 or
        not isinstance(nonzero, int) or not 0 <= nonzero <= count):
        reject("INVALID_PCM_COUNTS")
    return bef, mon


def compare(a, b):
    x, energy_a = check_sample(a, "silent")
    y, energy_b = check_sample(b, "audible")
    boot_a, boot_b = x.get("boot_fingerprint"), y.get("boot_fingerprint")
    if not isinstance(boot_a, str) or boot_a in ("", "UNAVAILABLE") or boot_a != boot_b:
        reject("DIFFERENT_BOOTS")
    try:
        stamp_a = dt.datetime.fromisoformat(x["utc"])
        stamp_b = dt.datetime.fromisoformat(y["utc"])
        delta = (stamp_b-stamp_a).total_seconds()
    except (KeyError, TypeError, ValueError):
        reject("TIMESTAMPS")
    if not 0 <= delta <= 1800:
        reject("TIMESTAMPS")
    pa_a, pa_b = stable_pulse(x), stable_pulse(y)
    alsa_a, alsa_b = stable_alsa(x), stable_alsa(y)
    media_a = {k: x["media"].get(k) for k in STABLE_MEDIA}
    media_b = {k: y["media"].get(k) for k in STABLE_MEDIA}
    changes = [name for name, first, last in (
        ("PULSE_ROUTE",pa_a,pa_b),
        ("ALSA_ROUTE",alsa_a,alsa_b),
        ("DTS_WRAPPER_HOLDERS",media_a,media_b),
    ) if first != last]
    zero_a = energy_a["nonzero_sample_count"] == 0
    zero_b = energy_b["nonzero_sample_count"] == 0
    print("R327_SAME_BOOT=PASS")
    print("R327_PAIR_DELTA_SECONDS=" + str(round(delta)))
    print("R327_SILENT_MONITOR_SAMPLES=" + str(energy_a["sample_count"]))
    print("R327_SILENT_MONITOR_NONZERO=" + str(energy_a["nonzero_sample_count"]))
    print("R327_AUDIBLE_MONITOR_SAMPLES=" + str(energy_b["sample_count"]))
    print("R327_AUDIBLE_MONITOR_NONZERO=" + str(energy_b["nonzero_sample_count"]))
    print("R327_PULSE_STABLE_ROUTE_CHANGED=" + ("YES" if pa_a != pa_b else "NO"))
    print("R327_ALSA_STABLE_ROUTE_CHANGED=" + ("YES" if alsa_a != alsa_b else "NO"))
    print("R327_STARFISH_WRAPPER_COUNT_CHANGED=" + ("YES" if media_a != media_b else "NO"))
    print("R327_STABLE_FIELD_CHANGE_COUNT=" + str(len(changes)))
    if zero_a and zero_b:
        classification = "MONITOR_NON_DISCRIMINATING_ZERO_BOTH_OWNER_STATES"
        next_action = "TRACE_CORRECT_NATIVE_AUDIO_ROUTE_OR_PRE_PULSE_PCM"
    elif zero_a and not zero_b:
        classification = "MONITOR_DIFFERENTIATES_STATES"
        next_action = "TRACE_PRE_MIX_DECODER_PCM_AND_POLICY"
    elif not zero_a and zero_b:
        classification = "INCONSISTENT_WITH_AUDIBLE_OWNER_STATE"
        next_action = "VERIFY_OUTPUT_MONITOR_ROUTING_AND_SAMPLE_WINDOW"
    else:
        classification = "MONITOR_BOTH_NONZERO"
        next_action = "COMPARE_PER_STREAM_AND_NATIVE_HARDWARE_ROUTE"
    print("R327_MONITOR_CLASSIFICATION=" + classification)
    print("R327_NEXT_TEST=" + next_action)
    print("R327_NONZERO_PCM_AT_DTS_DECODER=NOT_MEASURED")
    print("R327_LAMPA_INITIAL_CAPS_SEGMENT=NOT_MEASURED")
    print("R327_AC3_DTS_HANDOFF_ROOT_CAUSE=NOT_PROVEN")
    print("RESULT=R327_REAL_OWNER_PAIR_COMPARISON_PASS")
    return classification


def selftest():
    base = {
        "stage": "silent", "observation": "OWNER_LABELED_ONLY",
        "boot_fingerprint": "synthetic001",
        "utc": "2026-11-22T13:25:11+00:00",
        "pulse": {
            "query_ok": True, "sink_inputs": [
                {"id": 1, "sink_id": 1, "mute": False, "corked": False,
                 "volume_percent_min": 100, "volume_percent_max": 100,
                 "rate": 48000, "format": "s16le", "channels": 2,
                 "buffer_latency_us": 50000}],
            "sinks": [
                {"id": 1, "state": "RUNNING", "mute": False,
                 "volume_percent_min": 100, "volume_percent_max": 100,
                 "rate": 48000, "format": "s16le", "channels": 2}],
        },
        "alsa_pcm6": {"state":"RUNNING","owner_process_type":"pulseaudio",
                      "owner_thread_type":"alsa-sink-MARS",
                      "is_pulseaudio_sink_thread": True,
                      "hw_params":{"format":"S16_LE","channels":2,"rate":48000},
                      "hw_ptr_delta":17200},
        "media": {"starfish_r278_wrapper_holders": 1},
    }
    def copy(obj):
        return json.loads(json.dumps(obj))
    silent = {"schema":SCHEMA,"classification":"OWNER_CONFIRMED_REAL_SILENT",
              "before":copy(base),"after":copy(base),
              "monitor":{"sample_count":70000,"nonzero_sample_count":0,
                         "owner_observation":"silent","raw_pcm_exported":False,
                         "audio_files_created":0}}
    audible = copy(silent)
    audible["classification"] = "OWNER_CONFIRMED_REAL_AUDIBLE"
    for stage in ("before", "after"):
        audible[stage]["stage"]="audible"
        audible[stage]["utc"]="2026-11-22T13:26:58+00:00"
        audible[stage]["pulse"]["sink_inputs"][0]["buffer_latency_us"]=60000
        audible[stage]["alsa_pcm6"]["hw_ptr_delta"]=16800
    audible["monitor"]["owner_observation"]="audible"
    assert compare(silent,audible)=="MONITOR_NON_DISCRIMINATING_ZERO_BOTH_OWNER_STATES"
    audible["monitor"]["nonzero_sample_count"]=200
    assert compare(silent,audible)=="MONITOR_DIFFERENTIATES_STATES"
    print("RESULT=R327_COMPARATOR_SYNTHETIC_SELFTEST_PASS")


def main():
    if len(sys.argv)==2 and sys.argv[1]=="--selftest":
        selftest()
    elif len(sys.argv)==3:
        compare(load(sys.argv[1]),load(sys.argv[2]))
    else:
        reject("USAGE")


if __name__ == "__main__":
    main()
