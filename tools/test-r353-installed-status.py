#!/usr/bin/env python3
"""R353: read-only installed status health, does NOT access any LG or install."""
import hashlib
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "install-universal.sh"


def check(value, reason):
    if not value:
        raise AssertionError(reason)


def run(shell, root, cfg, mode):
    # Run only the read-only check function, with synthetic temporary paths.
    cmd = shell + '\ninstalled_status_check "$1" "$2" "$3"\n'
    return subprocess.run(["sh", "-c", cmd, "r353", str(root), str(cfg), mode],
                          capture_output=True, text=True, timeout=6)


def main():
    source = SCRIPT.read_text()
    anchor = "# R353: read-only post-reboot integrity check."
    check(source.count(anchor) == 1, "STATUS_ANCHOR")
    start = source.index("installed_status_check() (")
    end = source.index("\n\nstatus_installed() {", start)
    shell = source[start:end]
    check(subprocess.run(["sh", "-n"], input=shell, text=True, capture_output=True).returncode == 0,
          "STATUS_SH_SYNTAX")
    for forbidden in ("curl ", "mkdir ", "rm -", "mv ", "systemctl restart",
                      "systemctl stop", "systemctl enable", "sed -i"):
        check(forbidden not in shell, "STATUS_WRITES_" + forbidden)
    check("    status)\n        status_installed" in source, "STATUS_CLI_NOT_WIRED")
    check(source.index("    status)") < source.index("stage=$(mktemp -d"),
          "STATUS_AFTER_DOWNLOAD")
    check("SYSTEMD_PAGER=cat systemctl --no-pager" in source, "PAGER_REINTRODUCED")
    check(source.count("RESULT=R352_%s_PASS") == 1, "ORIGINAL_INSTALL_MARKER_CHANGED")
    check("    rollback)" in source and "    install|verify)" in source, "ORIGINAL_MODES_MISSING")

    with tempfile.TemporaryDirectory(prefix="r353-status-fixtures-") as d:
        temp = Path(d)
        root = temp / "r278"
        cfg = temp / "umediaserver.env"
        root.mkdir(mode=0o700)
        (root / "plugins").mkdir()
        (root / "ready").write_text("")
        (root / "installed.env").write_text("GST_PLUGIN_PATH_1_0=/test\n")
        (root / "combined.reg").write_bytes(b"registry")
        (root / "plugins" / "libgstaleksdts.so").write_bytes(b"ELF mock")
        cfg.write_bytes((root / "installed.env").read_bytes())
        names = ["installed.env", "combined.reg", "plugins/libgstaleksdts.so"]
        lines = []
        for name in names:
            lines.append(hashlib.sha256((root / name).read_bytes()).hexdigest() + "  " + name)
        (root / "installed.sha256").write_text("\n".join(lines) + "\n")

        def outcome(expected, reason, sr=root, conf=cfg, state="active"):
            res = run(shell, sr, conf, state)
            check(res.returncode == expected, reason + "_EXIT_" + repr(res.stdout))
            return res.stdout

        valid = outcome(0, "ALL_PASS")
        for marker in ("READY=PASS", "INSTALLED_SHA256=PASS", "ENV_MATCH=PASS",
                       "MEDIA_SERVICE=ACTIVE", "RESULT=R353_STATUS_PASS",
                       "AUDIBLE_DTS=NOT_TESTED_BY_STATUS"):
            check(marker in valid, "MISSING_" + marker)
        print("R353_STATUS_VALID_INSTALL_1_OF_1_PASS")

        failures = 0
        def should_fail(label, marker=None, **kwargs):
            nonlocal failures
            out = outcome(1, label, **kwargs)
            check("RESULT=R353_STATUS_FAIL" in out, label + "_WRONG_STATUS")
            if marker:
                check(marker in out, label + "_MISSING_MARKER")
            failures += 1

        should_fail("INACTIVE", "MEDIA_SERVICE=NOT_ACTIVE", state="inactive")
        (root / "ready").unlink()
        should_fail("NOT_READY", "READY=FAIL")
        (root / "ready").write_text("")
        (root / "plugins/libgstaleksdts.so").write_bytes(b"modified")
        should_fail("MODIFIED_LIBRARY", "INSTALLED_SHA256=FAIL")
        (root / "plugins/libgstaleksdts.so").write_bytes(b"ELF mock")
        cfg.write_text("wrong=1\n")
        should_fail("CHANGED_CONFIG", "ENV_MATCH=FAIL")
        cfg.write_bytes((root / "installed.env").read_bytes())
        (root / "installed.env").unlink()
        (root / "installed.env").symlink_to(cfg)
        should_fail("SYMLINK_INSTALLED_ENV", "INSTALLED_SHA256=FAIL")
        (root / "installed.env").unlink()
        (root / "installed.env").write_bytes(cfg.read_bytes())
        (root / "ready").unlink()
        (root / "ready").symlink_to(cfg)
        should_fail("SYMLINK_READY", "READY=FAIL")
        (root / "ready").unlink()
        (root / "ready").write_text("")
        missing = temp / "missing.env"
        should_fail("MISSING_MEDIA_CONFIG", "ENV_MATCH=FAIL", conf=missing)
        (root / "installed.sha256").unlink()
        should_fail("MISSING_SHA_MANIFEST", "INSTALLED_SHA256=FAIL")
        print(f"R353_STATUS_NEGATIVE_{failures}_OF_{failures}_PASS")

    # Guard the old production path against accidental refactor.
    import subprocess as sp
    old = sp.run(["git", "show", "HEAD:install-universal.sh"],
                 cwd=ROOT, capture_output=True, text=True, timeout=8, check=True).stdout
    before = old.split("stage=$(mktemp -d", 1)[1]
    after = source.split("stage=$(mktemp -d", 1)[1]
    check(before == after, "KNOWN_GOOD_INSTALL_PATH_CHANGED")
    print("R353_LEGACY_INSTALL_VERIFY_CODE_UNCHANGED_PASS")
    print("RESULT=R353_READONLY_STATUS_QA_PASS")


if __name__ == "__main__":
    main()