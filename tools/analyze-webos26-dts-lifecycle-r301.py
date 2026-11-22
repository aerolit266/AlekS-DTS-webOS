#!/usr/bin/env python3
"""R301: correlate R282 CASE and LIFECYCLE lines (offline, stdlib only).

Only parses a supplied text transcript. Does NOT connect to a TV, read
audio, replay a video or alter GStreamer. Results describe *evidence*,
not the root cause of a real DTS audio failure.
"""
import argparse
import importlib.util
import json
from pathlib import Path

MODES = ("db3_stock", "db3_lg", "db3_aleks", "db3_aleks_pcm2")
REQUIRED = ("elapsed_wall_s", "timeout_limit_s", "timeout_signal",
            "null_transition_seen", "pipeline_free_seen",
            "deadline_compatible")
SUMMARY_PASS = "R282_ISOLATED_DECODEBIN3_AND_PCM_PROBE_PASS"
SUMMARY_INCOMPLETE = "R282_ISOLATED_DECODEBIN3_AND_PCM_PROBE_INCOMPLETE"


def load_legacy_auditor():
    path = Path(__file__).with_name("audit-webos26-r282-exit-r298.py")
    spec = importlib.util.spec_from_file_location("aleks_dts_r298", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("R298 module must be beside R301")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def tokens(line):
    fields = {}
    for term in line.strip().split():
        if "=" in term:
            k, value = term.split("=", 1)
            fields[k] = value
    return fields


def interpret_lifecycle(row, exit_code, eos):
    """Classifications intentionally never assert a root cause."""
    if row is None:
        return "NO_LIFECYCLE_EVIDENCE", "UNKNOWN"
    try:
        elapsed = int(row["elapsed_wall_s"])
        budget = int(row["timeout_limit_s"])
    except (ValueError, TypeError):
        return "INVALID_TIMING", "UNKNOWN"
    signal = row["timeout_signal"]
    null = row["null_transition_seen"]
    freed = row["pipeline_free_seen"]
    if elapsed < 0 or budget <= 0 or signal not in ("TERM", "USR1"):
        return "INVALID_TIMING_OR_SIGNAL", "UNKNOWN"
    if null not in ("yes", "no") or freed not in ("yes", "no"):
        return "INVALID_MARKER_VALUE", "UNKNOWN"
    if freed == "yes" and null == "no":
        return "INCONSISTENT_FREE_WITHOUT_NULL", "UNKNOWN"
    if exit_code == 0 and eos and freed == "yes" and null == "yes":
        stage = "EOS_NULL_FREE_RECORDED"
    elif eos and null == "yes" and freed == "no":
        stage = "EOS_NULL_NO_FREE_MARKER"
    elif eos and null == "no":
        stage = "EOS_NO_NULL_MARKER"
    elif eos and freed == "yes":
        stage = "EOS_FREE_MARKER_WITH_UNUSUAL_STATE"
    elif not eos and (null == "yes" or freed == "yes"):
        stage = "TEARDOWN_WITHOUT_EOS"
    else:
        stage = "EOS_NOT_SEEN"
    near_deadline = elapsed >= budget - 1
    if exit_code == 0:
        cause = "CHILD_EXIT_ZERO"
    elif exit_code == 143 and signal == "TERM":
        cause = ("BUSYBOX_TIMEOUT_OR_OTHER_TERM_COMPATIBLE" if near_deadline
                 else "TERM_EXIT_EARLY_OR_TIMING_INCOMPLETE")
    elif exit_code == 143 and signal == "USR1":
        cause = "TERM_EXIT_WHILE_WRAPPER_CONFIGURED_FOR_USR1"
    elif exit_code == 138 and signal == "USR1":
        cause = ("BUSYBOX_USR1_DEADLINE_COMPATIBLE" if near_deadline
                 else "USR1_EXIT_NOT_NEAR_DEADLINE")
    elif exit_code == 124:
        cause = ("GNU_TIMEOUT_DEADLINE_COMPATIBLE" if near_deadline
                 else "EXIT124_NOT_NEAR_DEADLINE")
    else:
        cause = "NONZERO_EXIT_OR_UNKNOWN_CAUSE"
    return stage, cause


def analyze(text):
    legacy = load_legacy_auditor().analyze(text)
    snapshots, repeated = {}, []
    headers = []
    summaries = []
    for line in text.splitlines():
        if line.startswith("TIMEOUT_QA_SIGNAL="):
            headers.append(tokens(line))
        if line.startswith("LIFECYCLE="):
            row = tokens(line)
            mode = row.get("LIFECYCLE")
            if mode not in MODES:
                continue
            if mode in snapshots:
                repeated.append(mode)
                continue
            snapshots[mode] = row
        if line.startswith("RESULT="):
            summaries.append(line.partition("=")[2].split(";")[0].strip())
    cases = {}
    for mode in MODES:
        old = legacy["cases"].get(mode)
        row = snapshots.get(mode)
        if old is None:
            cases[mode] = {"verdict": "MISSING_CASE"}
            continue
        if row is not None:
            missing = [key for key in REQUIRED if key not in row]
            if missing:
                cases[mode] = {"verdict": "PARTIAL_LIFECYCLE",
                               "missing": missing, "old_verdict": old["verdict"]}
                continue
        stage, cause = interpret_lifecycle(
            row, old.get("exit"), old.get("eos"))
        cases[mode] = {
            "previous_verdict": old["verdict"],
            "exit": old.get("exit"),
            "eos": old.get("eos"),
            "phase_evidence": stage,
            "exit_origin": cause,
            "elapsed_wall_s": int(row["elapsed_wall_s"]) if (
                row is not None and row.get("elapsed_wall_s", "").isdecimal()) else None,
            "configured_signal": row.get("timeout_signal") if row else None,
        }
    marker = summaries[0] if len(summaries) == 1 else None
    full = (
        legacy["all_clean"] and
        len(snapshots) == len(MODES) and
        not repeated and
        len(headers) == 1 and
        marker == SUMMARY_PASS and
        all(cases[m].get("phase_evidence") == "EOS_NULL_FREE_RECORDED"
            and cases[m].get("exit_origin") == "CHILD_EXIT_ZERO"
            for m in MODES)
    )
    return {
        "schema": "aleks.dts.r301.timeline.v1",
        "source": "R282 diagnostic stdout supplied offline",
        "expected_cases": len(MODES),
        "seen_cases": legacy["observed_modes"],
        "seen_lifecycles": len(snapshots),
        "duplicated_lifecycles": repeated,
        "result_marker": marker,
        "cases": cases,
        "r298_all_clean": legacy["all_clean"],
        "r301_complete_qa": full,
        "real_lg_tested": False,
        "acoustic_output_tested": False,
        "decoder_root_cause_proven": False,
        "limits": ("Exit143 may be a BusyBox timeout or another TERM event. "
                   "Elapsed wall seconds are coarse. Presence/absence of "
                   "NULL/FREE messages cannot alone prove actual resource "
                   "reclamation, and does not test Starfish's native sink."),
    }


def make_fixture(exit_code, *, signal="TERM", elapsed=2, null="yes",
                 freed="yes", eos="yes", marker=SUMMARY_PASS,
                 missing_lifecycle=False, duplicate=False):
    lines = [f"TIMEOUT_QA_SIGNAL={signal} BUDGET_SECONDS=12"]
    for m in MODES:
        pcm2 = m == "db3_aleks_pcm2"
        lines.append(
            f"CASE={m} exit={exit_code} DTS_DECODER=yes EOS={eos} "
            f"PCM6={'no' if pcm2 else 'yes'} "
            f"PCM_S32LE={'yes' if pcm2 else 'no'} "
            f"PCM2={'yes' if pcm2 else 'no'} NEGOTIATION_ERROR=no")
        if not missing_lifecycle:
            row = (f"LIFECYCLE={m} elapsed_wall_s={elapsed} "
                   f"timeout_limit_s=12 timeout_signal={signal} "
                   f"null_transition_seen={null} pipeline_free_seen={freed} "
                   f"deadline_compatible={'yes' if elapsed >= 11 else 'no'}")
            lines.append(row)
            if duplicate and m == "db3_stock":
                lines.append(row)
    if marker:
        lines.append(f"RESULT={marker}; NATIVE_SOUND_UNTESTED")
    return "\n".join(lines)


def selftest():
    clean = analyze(make_fixture(0))
    assert clean["r301_complete_qa"]
    assert all(c["phase_evidence"] == "EOS_NULL_FREE_RECORDED"
               for c in clean["cases"].values())
    assert not analyze(make_fixture(143, elapsed=12, null="no", freed="no",
                                   marker=SUMMARY_INCOMPLETE))["r301_complete_qa"]
    bb = analyze(make_fixture(143, elapsed=12, null="no", freed="no",
                              marker=SUMMARY_INCOMPLETE))
    assert all(c["exit_origin"] == "BUSYBOX_TIMEOUT_OR_OTHER_TERM_COMPATIBLE"
               for c in bb["cases"].values())
    usr1 = analyze(make_fixture(138, signal="USR1", elapsed=12,
                                null="yes", freed="no",
                                marker=SUMMARY_INCOMPLETE))
    assert all(c["exit_origin"] == "BUSYBOX_USR1_DEADLINE_COMPATIBLE"
               for c in usr1["cases"].values())
    term = analyze(make_fixture(143, signal="USR1", elapsed=2,
                                null="yes", freed="no",
                                marker=SUMMARY_INCOMPLETE))
    assert all(c["exit_origin"] == "TERM_EXIT_WHILE_WRAPPER_CONFIGURED_FOR_USR1"
               for c in term["cases"].values())
    assert not analyze(make_fixture(0, missing_lifecycle=True))["r301_complete_qa"]
    assert not analyze(make_fixture(0, duplicate=True))["r301_complete_qa"]
    assert not analyze(make_fixture(0, marker=None))["r301_complete_qa"]
    assert not analyze(make_fixture(0, freed="no"))["r301_complete_qa"]
    inconsistent = analyze(make_fixture(0, null="no", freed="yes"))
    assert all(c["phase_evidence"] == "INCONSISTENT_FREE_WITHOUT_NULL"
               for c in inconsistent["cases"].values())
    assert clean["acoustic_output_tested"] is False
    assert clean["decoder_root_cause_proven"] is False
    print("R301_SELFTEST_PASS assertions=13 "
          "legacy_missing_timeline=UNKNOWN timeout_causes=COMPATIBLE_ONLY")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("transcript", nargs="?", help="Saved stdout from R282")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        selftest()
        return
    if not args.transcript:
        parser.error("Provide a saved R282 diagnostic transcript, or --selftest")
    data = analyze(Path(args.transcript).read_text(
        encoding="utf-8", errors="replace"))
    print(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True))
    if args.strict and not data["r301_complete_qa"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
