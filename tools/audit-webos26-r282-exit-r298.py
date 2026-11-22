#!/usr/bin/env python3
"""R298: inspect legacy/new R282 output without accessing LG.

Gate: successful PCM and EOS with exit=143 is NOT a successful gst-launch
process lifecycle; do not equate such cases with complete native DTS playback.
"""
import argparse
import json
from pathlib import Path

MODES = ("db3_stock", "db3_lg", "db3_aleks", "db3_aleks_pcm2")
REQUIRED = ("exit", "DTS_DECODER", "EOS", "PCM6", "PCM_S32LE",
            "PCM2", "NEGOTIATION_ERROR")


def analyze(text):
    result = {}
    duplicates = []
    for raw in text.splitlines():
        if not raw.startswith("CASE="):
            continue
        tokens = {}
        for token in raw.strip().split():
            if "=" in token:
                key, value = token.split("=", 1)
                tokens[key] = value
        mode = tokens.get("CASE")
        if mode not in MODES:
            continue
        if mode in result:
            duplicates.append(mode)
            continue
        missing = [f for f in REQUIRED if f not in tokens]
        if missing:
            result[mode] = {"verdict": "INCOMPLETE_METRICS",
                            "missing": missing}
            continue
        try:
            status = int(tokens["exit"])
        except ValueError:
            result[mode] = {"verdict": "INVALID_EXIT_CODE"}
            continue
        decoder = tokens["DTS_DECODER"] == "yes"
        eos = tokens["EOS"] == "yes"
        caps = (tokens["PCM2"] == "yes" and
                tokens["PCM_S32LE"] == "yes") if mode == "db3_aleks_pcm2" else (
                tokens["PCM6"] == "yes")
        negotiation_ok = tokens["NEGOTIATION_ERROR"] == "no"
        valid = decoder and eos and caps and negotiation_ok
        if status == 0 and valid:
            verdict = "PASS_CLEAN_EXIT_AND_DECODE"
        elif status == 143:
            verdict = "SIGTERM_EXIT_143_NOT_CLEAN"
        elif status == 124:
            verdict = "TIMEOUT_EXIT_124_NOT_CLEAN"
        elif status == 137:
            verdict = "SIGKILL_EXIT_137_NOT_CLEAN"
        elif status != 0:
            verdict = "NONZERO_EXIT_NOT_CLEAN"
        else:
            verdict = "DECODE_OR_CAPS_NOT_PROVEN"
        result[mode] = {
            "exit": status, "decoder": decoder, "eos": eos,
            "expected_pcm": caps, "negotiation_ok": negotiation_ok,
            "verdict": verdict,
        }
    missing_modes = [mode for mode in MODES if mode not in result]
    all_pass = (not duplicates and not missing_modes and
                len(result) == 4 and
                all(row["verdict"] == "PASS_CLEAN_EXIT_AND_DECODE"
                    for row in result.values()))
    return {
        "schema": "aleks.dts.r298.lifecycle.v1",
        "expected_modes": 4,
        "observed_modes": len(result),
        "missing_modes": missing_modes,
        "duplicate_modes": duplicates,
        "cases": result,
        "all_clean": all_pass,
        "native_audio_tested": False,
        "root_cause_proven": False,
        "interpretation": (
            "All four isolated pipelines decoded and exited cleanly."
            if all_pass else
            "EOS/PCM in GStreamer logs is insufficient without exit=0; "
            "SIGTERM 143 does not by itself identify whether timeout, "
            "decoder teardown, or external termination caused the signal."
        )
    }


def make_case(mode, status, *, eos="yes", custom="yes", pcm=True):
    parts = [f"CASE={mode}", "ranks=aleksdts16dec:288,decproxy:300",
             f"exit={status}", f"DTS_DECODER={custom}",
             f"EOS={eos}",
             f"PCM6={'yes' if (pcm and mode != 'db3_aleks_pcm2') else 'no'}",
             f"PCM_S32LE={'yes' if (pcm and mode == 'db3_aleks_pcm2') else 'no'}",
             f"PCM2={'yes' if (pcm and mode == 'db3_aleks_pcm2') else 'no'}",
             "NEGOTIATION_ERROR=no"]
    return " ".join(parts)


def selftest():
    legacy = "\n".join(make_case(m, 143) for m in MODES)
    observed = analyze(legacy)
    assert observed["all_clean"] is False
    assert observed["observed_modes"] == 4
    assert all(x["verdict"] == "SIGTERM_EXIT_143_NOT_CLEAN"
               for x in observed["cases"].values())
    assert all(x["eos"] and x["decoder"] and x["expected_pcm"]
               for x in observed["cases"].values())
    healthy = analyze("\n".join(make_case(m, 0) for m in MODES))
    assert healthy["all_clean"]
    assert all(x["verdict"] == "PASS_CLEAN_EXIT_AND_DECODE"
               for x in healthy["cases"].values())
    assert not analyze("\n".join(make_case(m, 0) for m in MODES[:3]))["all_clean"]
    assert analyze("\n".join([legacy, legacy]))["duplicate_modes"]
    assert not analyze("\n".join(make_case(m, 124) for m in MODES))["all_clean"]
    assert not analyze("\n".join(make_case(m, 0, pcm=False) for m in MODES))["all_clean"]
    assert not analyze("\n".join(make_case(m, 0, eos="no") for m in MODES))["all_clean"]
    assert not analyze("\n".join(make_case(m, 0, custom="no") for m in MODES))["all_clean"]
    assert observed["root_cause_proven"] is False
    assert observed["native_audio_tested"] is False
    print("R298_SELFTEST_PASS assertions=14 legacy_sigterm=INCOMPLETE clean_four=PASS")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_file", nargs="?",
                        help="Saved R282 console output, not full media log")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--strict", action="store_true",
                        help="Exit 2 unless all four cases are clean")
    args = parser.parse_args()
    if args.selftest:
        selftest()
        return
    if not args.input_file:
        parser.error("Specify a saved R282 stdout file, or --selftest.")
    data = analyze(Path(args.input_file).read_text(encoding="utf-8", errors="replace"))
    print(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True))
    if args.strict and not data["all_clean"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
