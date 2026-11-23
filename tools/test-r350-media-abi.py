#!/usr/bin/env python3
"""R350 safe ELF ABI + original R278 patch regression. Never installs to a device."""
import argparse
import hashlib
import pathlib
import re
import subprocess
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
ARCHIVE_SHA = "cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1"


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def elf_bytes(klass, machine, endian=1, magic=b"\x7fELF"):
    b = bytearray(20)
    b[0:4] = magic
    b[4:7] = bytes([klass, endian, 1])
    b[18:20] = machine.to_bytes(2, "little")
    return bytes(b)


def test_classifier(source):
    match = re.search(r"^elf_media_abi\(\) \{\n.*?^\}", source, flags=re.M | re.S)
    check(match, "MISSING_PURE_ELF_PROBE")
    code = match.group(0)
    cases = (
        ("arm32", elf_bytes(1, 40), "ARM32_LE"),
        ("arm64", elf_bytes(2, 183), "ARM64_LE"),
        ("x8632", elf_bytes(1, 3), "UNSUPPORTED_ELF"),
        ("x8664", elf_bytes(2, 62), "UNSUPPORTED_ELF"),
        ("arm32_big_endian", elf_bytes(1, 40, 2), "UNSUPPORTED_ELF"),
        ("wrong_magic", elf_bytes(1, 40, magic=b"WHAT"), "NOT_ELF"),
        ("empty", b"", "NOT_ELF"),
        ("truncated", elf_bytes(1, 40)[:12], "NOT_ELF"),
        ("missing", None, "UNREADABLE"),
    )
    with tempfile.TemporaryDirectory(prefix="aleks-r350-elf-") as temp:
        for name, payload, expected in cases:
            path = pathlib.Path(temp) / name
            if payload is not None:
                path.write_bytes(payload)
            result = subprocess.run(
                ["sh", "-c", code + '\nelf_media_abi "$1"\n', "r350", str(path)],
                text=True, capture_output=True, timeout=4, check=False)
            check(result.returncode == 0 and result.stdout.strip() == expected,
                  "ELF_" + name + "_" + result.stdout.strip())
    print("R350_ELF_CLASSIFIER_9_OF_9_PASS")


def test_wrapper(source, archive):
    check(hashlib.sha256(archive.read_bytes()).hexdigest() == ARCHIVE_SHA,
          "PINNED_R278_ARCHIVE_MISMATCH")
    check('[ "$(uname -m)" = armv7l ]' not in source, "OLD_UNAME_GATE_REMAINS")
    check("requires a separately compiled package" not in source,
          "MISLEADING_ERROR_REMAINS")
    check("require_arm32_media\nfor tool in" in source,
          "FIRST_PREFLIGHT_NOT_BEFORE_DOWNLOAD")
    check("=== MEDIA ELF ABI (read-only) ===" in source, "DIAG_MISSING")
    check("sha256sum -c -" in source, "ARCHIVE_INTEGRITY_REMOVED")
    check("created_env_dirs" in source and "sh ./install.sh" in source,
          "ROLLBACK_PATH_REMOVED")
    shell = subprocess.run(["sh", "-n"], input=source, text=True, capture_output=True,
                           timeout=4, check=False)
    check(shell.returncode == 0, "WRAPPER_SH_SYNTAX")
    platform = re.search(
        r"cat > platform.universal <<'PLATFORM'\n(.*?)\nPLATFORM\n",
        source, flags=re.S)
    check(platform, "PATCH_SOURCE_MISSING")
    awk = re.search(
        r"awk -v replacement=platform.universal '(.*?)' install.sh > install.patched",
        source, flags=re.S)
    check(awk, "PATCH_AWK_MISSING")
    with tempfile.TemporaryDirectory(prefix="aleks-r350-real-r278-") as temp:
        p = pathlib.Path(temp)
        with tarfile.open(archive, mode="r:gz") as tf:
            original = tf.extractfile("install.sh").read()
        (p / "install.sh").write_bytes(original)
        (p / "platform.universal").write_text(platform.group(1) + "\n")
        patched = subprocess.run(
            ["awk", "-v", "replacement=platform.universal", awk.group(1), "install.sh"],
            cwd=temp, capture_output=True, timeout=4, check=False)
        check(patched.returncode == 0, "REAL_PATCH_AWK_FAILED")
        text = patched.stdout.decode()
        check(text.count("platform() {") == 1, "PATCH_PLATFORM_CARDINALITY")
        for marker in (
            "Media executable is not ELF32 little-endian ARM:",
            '[ "${19}" = 40 ]', '[ "${20}" = 0 ]',
            "verify_pipeline", "rollback", "replace_config", "before_matches",
        ):
            check(marker in text, "PATCH_LOST_" + marker)
        check("R278 contains ARMv7-only plugins." not in text,
              "INNER_UNAME_GATE_REMAINS")
        shell = subprocess.run(["sh", "-n"], input=patched.stdout,
                               capture_output=True, timeout=4, check=False)
        check(shell.returncode == 0, "PATCHED_R278_SH_SYNTAX")
        check((p / "install.sh").read_bytes() == original, "ORIGINAL_R278_CHANGED")
    print("R350_REAL_R278_WRAPPER_AND_PATCH_PASS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=pathlib.Path,
                        default=ROOT / "install-universal.sh")
    parser.add_argument("--archive", type=pathlib.Path,
                        default=ROOT / "downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz")
    args = parser.parse_args()
    src = args.source.read_text(encoding="utf-8")
    test_classifier(src)
    test_wrapper(src, args.archive)
    print("RESULT=R350_OFFDEVICE_QA_PASS_NO_INSTALL")


if __name__ == "__main__":
    main()