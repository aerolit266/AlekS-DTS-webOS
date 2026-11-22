#!/usr/bin/env python3
"""R302: audit whether R188 DTS clock/sanitizer QA can be replayed after VPS reboot.

Reads exactly five allowlisted source/fixture paths. No TV, network, SSH,
media playback, compilation, or alterations to existing source files.
"""
import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path

PINS = (
    ("r188_framer_header", "source", "r188_dts_framer.h",
     "8fcf17dd9d9890d26542f093a87f91e760e8ea8999619e17b4e56485b04bfa97"),
    ("r188_clock_qa", "source", "r188_clock_qa.c",
     "55e8d1480ceb965fa78f06a020df19d6159dbc171e4178ae56bce051ded0e41a"),
    ("r122_core_probe", "header", "r122_dts_core_probe.h",
     "83fbf1f002e59e9f844e721bd26fc1d5e2be6933c510a8eded172d96252fe1ca"),
    ("dts_51_owner_fixture", "fixture", "dts51-audioonly.mkv",
     "1da49e2e8b74bbaee6892fcf7a13a9ac738abde323200439d197d0abcd7eabb9"),
    ("dts_20_owner_fixture", "fixture", "dts20-audioonly.mkv",
     "d53aead1a62255019b9ccad617ed34902d70c874595236853eb36b554cb7685c"),
)


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def evaluate(targets):
    """Status must distinguish missing prerequisites from wrong source hashes."""
    findings = []
    for name, kind, basename, expected in PINS:
        path = targets[kind] / basename
        if path.is_symlink():
            state, actual = "SYMLINK_REJECTED", None
        elif not path.exists():
            state, actual = "MISSING", None
        elif not path.is_file():
            state, actual = "NOT_REGULAR_FILE", None
        else:
            try:
                actual = digest(path)
                state = "SHA256_PASS" if actual == expected else "SHA256_MISMATCH"
            except (PermissionError, OSError):
                state, actual = "READ_ERROR", None
        findings.append({"id": name, "kind": kind, "filename": basename,
                         "state": state, "expected_sha256": expected,
                         "actual_sha256": actual})
    ready = all(x["state"] == "SHA256_PASS" for x in findings)
    return {"schema": "aleks.dts.r302.replay-prereqs.v1",
            "ready_for_original_r188_test": ready,
            "checked": len(findings),
            "sha256_pass": sum(x["state"] == "SHA256_PASS" for x in findings),
            "missing": sum(x["state"] == "MISSING" for x in findings),
            "mismatch": sum(x["state"] == "SHA256_MISMATCH" for x in findings),
            "findings": findings,
            "conclusion": ("R188_ORIGINAL_QA_PREREQUISITES_READY" if ready else
                           "R188_QA_BLOCKED_BY_PREREQUISITES_NOT_A_DECODER_FAILURE"),
            "real_lg_tested": False,
            "dts_audio_tested": False,
            "production_modified": False}


def selftest():
    with tempfile.TemporaryDirectory(prefix="aleks-r302-selftest-") as temp:
        root = Path(temp)
        for key in ("source", "header", "fixture"):
            (root / key).mkdir()
        targets = {k: root / k for k in ("source", "header", "fixture")}
        initially = evaluate(targets)
        assert initially["missing"] == len(PINS)
        assert not initially["ready_for_original_r188_test"]
        name, kind, filename, _ = PINS[0]
        (targets[kind] / filename).write_bytes(b"deliberately wrong test content")
        mismatch = evaluate(targets)
        assert mismatch["mismatch"] == 1
        assert mismatch["missing"] == len(PINS)-1
        (targets[kind] / filename).unlink()
        # Reject symlinks rather than following them into unexpected paths.
        symlink_supported = True
        try:
            (targets[kind] / filename).symlink_to(root / "missing-target")
        except (NotImplementedError, OSError):
            symlink_supported = False
        if symlink_supported:
            blocked = evaluate(targets)
            assert blocked["findings"][0]["state"] == "SYMLINK_REJECTED"
        final = evaluate({"source": targets["source"],
                          "header": targets["header"],
                          "fixture": targets["fixture"]})
        assert not final["ready_for_original_r188_test"]
        assert final["conclusion"].endswith("NOT_A_DECODER_FAILURE")
        assert final["real_lg_tested"] is False
        print("R302_SELFTEST_PASS missing_mismatch_symlink_and_result_guards")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-root", default="/opt/gamefree24-vps-mcp/src")
    p.add_argument("--header-root", default="/tmp/aleks-r120-armel-qa")
    p.add_argument("--fixture-root", default="/tmp/aleks-r171-sdk/qa")
    p.add_argument("--strict", action="store_true",
                   help="Exit 2 when any prerequisite is unavailable or mismatched")
    p.add_argument("--selftest", action="store_true")
    args = p.parse_args()
    if args.selftest:
        selftest()
        return
    results = evaluate({"source": Path(args.source_root),
                        "header": Path(args.header_root),
                        "fixture": Path(args.fixture_root)})
    print(json.dumps(results, indent=2, ensure_ascii=False))
    if args.strict and not results["ready_for_original_r188_test"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
