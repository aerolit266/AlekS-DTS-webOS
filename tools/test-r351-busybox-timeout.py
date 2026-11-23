#!/usr/bin/env python3
"""R351 isolated regression for BusyBox timeout ABI in immutable R278 installer."""
import hashlib
import pathlib
import re
import subprocess
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
RELEASE = ROOT / "downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz"
WRAPPER = ROOT / "install-universal.sh"
SHA = "cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1"


def run(argv, **kw):
    return subprocess.run(argv, timeout=8, capture_output=True, **kw)


def check(flag, label):
    if not flag:
        raise AssertionError(label)


def main():
    src = WRAPPER.read_text()
    check(hashlib.sha256(RELEASE.read_bytes()).hexdigest() == SHA, "R278_SHA")
    with tarfile.open(RELEASE, "r:gz") as tg:
        immutable = tg.extractfile("install.sh").read()
    check(immutable.count(b'timeout -t 20 "$@"') == 1, "ORIGINAL_TIMEOUT_CARDINALITY")
    platform = re.search(r"cat > platform.universal <<'PLATFORM'\n(.*?)\nPLATFORM", src, re.S)
    p_awk = re.search(r"awk -v replacement=platform.universal '(.*?)' install.sh > install.patched", src, re.S)
    t_awk = re.search(r"awk '\n(.*?)\n' install.patched > install.timeout-patched", src, re.S)
    check(platform is not None and p_awk is not None and t_awk is not None,
          "R351_PINNED_SOURCE_PATCH_BLOCKS")
    check(any(("R%s_%%s_PASS" % v) in src for v in (351, 352)) and "failed with exit code" in src,
          "R351_RESULT_STATUS_REPORTING")
    check(run(["sh", "-n"], input=src.encode()).returncode == 0, "WRAPPER_SH_N")
    with tempfile.TemporaryDirectory(prefix="r351-qa-") as work:
        d = pathlib.Path(work)
        (d / "install.sh").write_bytes(immutable)
        (d / "platform.universal").write_text(platform.group(1) + "\n")
        p = run(["awk", "-v", "replacement=platform.universal",
                 p_awk.group(1), "install.sh"], cwd=d)
        check(p.returncode == 0, "R350_PLATFORM_STAGE")
        (d / "install.patched").write_bytes(p.stdout)
        res = run(["awk", t_awk.group(1), "install.patched"], cwd=d)
        check(res.returncode == 0, "R351_TIMEOUT_PATCH")
        check(res.stdout.count(b'timeout 20 "$@"') == 1, "PORTABLE_TIMEOUT_CARDINALITY")
        check(b'timeout -t 20' not in res.stdout, "LEGACY_TIMEOUT_REMAINS")
        check(run(["sh", "-n"], input=res.stdout).returncode == 0,
              "PATCHED_SHELL_SYNTAX")
        for term in [b"verify_pipeline", b"rollback", b"verify_files",
                     b"before_matches", b"replace_config"]:
            check(term in res.stdout, "R278_SAFETY_REGRESSION_" + term.decode())
        check((d / "install.sh").read_bytes() == immutable, "R278_CHANGED")

        # Require exactly one expected invocation: modified/unknown source fails closed.
        for damaged in (
            p.stdout.replace(b'timeout -t 20 "$@"', b'timeout 21 "$@"'),
            p.stdout.replace(b'timeout -t 20 "$@"', b'timeout -t 21 "$@"'),
            p.stdout + b'\ntimeout -t 20 "$@"\n',
        ):
            (d / "install.patched").write_bytes(damaged)
            no = run(["awk", t_awk.group(1), "install.patched"], cwd=d)
            check(no.returncode != 0, "UNPINNED_PATCH_MUST_FAIL")
        print("R351_R278_PATCH_FAIL_CLOSED_3_OF_3_PASS")

        # No BusyBox binary required on CI: a strict mock of BusyBox 1.31.1 CLI.
        mock = d / "timeout"
        mock.write_text(
            '#!/bin/sh\n'
            '[ "$#" -ge 2 ] || exit 51\n'
            'case "$1" in -t) exit 52 ;; 20) shift ;; *) exit 53 ;; esac\n'
            'exec "$@"\n')
        mock.chmod(0o700)
        accepted = run([str(mock), "20", "sh", "-c", 'printf "PORTABLE_OK"'])
        check(accepted.returncode == 0 and accepted.stdout == b"PORTABLE_OK",
              "MOCK_BUSYBOX_TIMEOUT_20")
        rejected = run([str(mock), "-t", "20", "sh", "-c", "exit 0"])
        check(rejected.returncode == 52, "MOCK_BUSYBOX_MUST_REJECT_OLD_OPTION")
        gnu = run(["timeout", "1", "sh", "-c", 'printf "GNU_OK"'])
        check(gnu.returncode == 0 and gnu.stdout == b"GNU_OK",
              "GNU_TIMEOUT_ONE_SECOND")
        print("R351_BUSYBOX_CLI_AND_GNU_TIMEOUT_3_OF_3_PASS")

    print("RESULT=R351_PORTABLE_TIMEOUT_OFFDEVICE_PASS_NO_INSTALL")


if __name__ == "__main__":
    main()