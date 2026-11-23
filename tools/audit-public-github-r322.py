#!/usr/bin/env python3
"""AlekS DTS R322: deterministic, offline public GitHub integrity guard.

Run from a checked-out AlekS-DTS-webOS repository root. Verifies archive/
manifest/plugin SHA256, shell syntax, Python syntax, Markdown relative links,
read-only triage links, documented immutable universal installer pin and
historical/original R278 model gate, and the updated R350 installer pin. Does NOT run installation code, alter
production, download anything or read users' private data.
"""
import hashlib
import pathlib
import re
import subprocess
import sys
import tarfile
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
RELEASE = ROOT / "downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz"
RELINK = ROOT / "downloads/r278/R278-R56-LGPL-RELINK.tar.gz"
NOTICES = ROOT / "downloads/r278/SOFTWARE-NOTICES.txt"
MANIFEST = ROOT / "downloads/r278/SHA256SUMS"
BOOTSTRAP_SHA = "541a1b6ff33423768aeb14e7eee803c32b9c877148801953cd0b4f4456a4c6af"
BOOTSTRAP_COMMIT = "c8d6a5606de8bee33efef4c7856f7aa124731380"
EXPECTED = {
    "AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz":
        "cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1",
    "R278-R56-LGPL-RELINK.tar.gz":
        "2723b1cd09b50df367161e5acff6d1d622c76856592c907d79ef606380c98ccf",
    "SOFTWARE-NOTICES.txt":
        "136fcf097dd8059badccd7cdf06bae238ea9c7bb46751c5fe590587fb0070486",
}
PLUGIN_SHA = {
    "plugins/libgstaleksdts.so":
        "5c3b798d4c1109414efc9209276dbf8b23466376f72f5bc71cf4144f3f5a1cbb",
    "plugins/libgstaleksdts16dec.so":
        "dfefb960d49d50ed7629cc4459ffaae8b420509cc9815d8337f6be7faaac18cf",
    "plugins/libgstaleksdtscaps.so":
        "1995a6b6030f6ddb895aeeea4017dcc71db8ebd6caace0107e1c5a33875f0605",
    "plugins/libgstaleksdtsr130optin.so":
        "9b7adb2744a9d7c329669974c15bcfc86ba62daf27efccb95e362c1928d602e0",
    "fixtures/dts-stereo.mka":
        "7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae",
    "fixtures/dts-51.mka":
        "7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5",
    "fixtures/ac3-51.mka":
        "ab82bf91f6b61fc5a3cdf11ccd1e3bf3b4d91e2a9b7667d97f87e2cc12089a88",
}
PUBLIC_DOCS = ("README.md", "README.en.md", "PUBLIC-COMPATIBILITY.md")


def ensure(condition, code):
    if not condition:
        raise ValueError(code)


def digest(path):
    with path.open("rb") as h:
        return hashlib.file_digest(h, "sha256").hexdigest()


def check_release():
    recorded = {}
    for ln in MANIFEST.read_text().splitlines():
        parts = ln.strip().split()
        ensure(len(parts) == 2, "BAD_SHA256_MANIFEST_FORMAT")
        recorded[parts[1].lstrip("*")] = parts[0]
    ensure(recorded == EXPECTED, "RELEASE_MANIFEST_MISMATCH")
    for name, expected in EXPECTED.items():
        ensure(digest(MANIFEST.parent / name) == expected,
               "RELEASE_SHA_MISMATCH_" + name)
    print("R322_RELEASE_ARCHIVES_AND_MANIFEST=3_PASS")
    with tarfile.open(RELEASE, "r:gz") as tar:
        for name, expected in PLUGIN_SHA.items():
            member = tar.getmember(name)
            ensure(member.isfile() and 0 < member.size < 2000000,
                   "RELEASE_MEMBER_UNSAFE_" + name)
            with tar.extractfile(member) as f:
                payload = f.read(2000001)
            ensure(len(payload) == member.size and
                   hashlib.sha256(payload).hexdigest() == expected,
                   "RELEASE_PLUGIN_OR_FIXTURE_SHA_MISMATCH_" + name)
        installer = tar.extractfile("install.sh").read().decode("utf-8")
    print("R322_RELEASE_4_PLUGINS_AND_3_FIXTURES=7_PASS")
    ensure("65NANO896PC" in installer and "03.60.96" in installer and
           "6.6.0" in installer and "Unsupported model or firmware" in installer,
           "ORIGINAL_RELEASE_GATE_MISSING")
    ensure("before_matches" in installer and
           "replace_config" in installer and
           "rollback" in installer and "verify_pipeline" in installer,
           "ORIGINAL_INSTALLER_BACKOUT_MISSING")
    print("R322_MODEL_BOUND_ORIGINAL_AND_ROLLBACK=PASS")


def check_sources():
    shell = list(ROOT.rglob("*.sh"))
    for script in shell:
        result = subprocess.run(["sh", "-n", str(script)], capture_output=True,
                                timeout=4, check=False)
        ensure(result.returncode == 0, "SHELL_SYNTAX_" + str(script.relative_to(ROOT)))
    py = list(ROOT.rglob("*.py"))
    for script in py:
        compile(script.read_bytes(), str(script.relative_to(ROOT)), "exec")
    print("R322_SHELL_SYNTAX_PASS=" + str(len(shell)))
    print("R322_PYTHON_SYNTAX_PASS=" + str(len(py)))
    current = (ROOT / "install-universal.sh").read_text()
    ensure(hashlib.sha256(current.encode()).hexdigest() == BOOTSTRAP_SHA,
           "DOCUMENTED_BOOTSTRAP_SHA_HAS_CHANGED")
    ensure("EnvironmentFiles" in current and "created_env_dirs" in current and
           "sh ./install.sh" in current and
           "rollback" in current and
           "verify_pipeline" not in current,  # must rely on unchanged R278 install.sh verification
           "UNIVERSAL_INSTALLER_GATE_DRIFT")
    ensure("require_arm32_media" in current and "=== MEDIA ELF ABI" in current and
           '[ "$(uname -m)" = armv7l ]' not in current,
           "R350_NATIVE_MEDIA_ABI_GATE_MISSING")
    print("R322_UNIVERSAL_INSTALLER_SHA_AND_GATES=PASS")


def check_docs():
    count = 0
    for path in ROOT.rglob("*.md"):
        body = path.read_text(encoding="utf-8")
        for link in re.findall(r"(?<!!)\[[^\]\n]+\]\(([^)]+)\)", body):
            link = link.strip().split()[0].strip("<>")
            if not link or link.startswith(("#", "http:", "https:", "mailto:")):
                continue
            candidate = urllib.parse.unquote(link.split("#", 1)[0])
            if not candidate:
                continue
            dest = (path.parent / candidate).resolve()
            ensure(dest.is_relative_to(ROOT) and dest.exists(),
                   "BROKEN_DOC_LINK_" + str(path.relative_to(ROOT)) + "_" + candidate)
            count += 1
    print("R322_DOCUMENT_RELATIVE_LINKS_PASS=" + str(count))
    for name in PUBLIC_DOCS:
        doc = (ROOT / name).read_text()
        for key in ("R318", "R320", "R321"):
            ensure(key in doc, "STALE_COMPATIBILITY_" + name + "_" + key)
    for name in ("README.md", "README.en.md"):
        text = (ROOT / name).read_text()
        ensure(BOOTSTRAP_COMMIT + "/install-universal.sh" in text,
               "UNPINNED_BOOTSTRAP_" + name)
        ensure("/main/install-universal.sh" not in text,
               "MUTABLE_BOOTSTRAP_" + name)
    print("R322_REPRODUCIBLE_BOOTSTRAP_AND_FIELD_STATUS=PASS")


def main():
    ensure(MANIFEST.is_file() and RELEASE.is_file(), "NOT_REPOSITORY_ROOT")
    check_release()
    check_sources()
    check_docs()
    print("RESULT=R322_PUBLIC_GITHUB_AUDIT_PASS")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, SyntaxError, subprocess.SubprocessError,
            tarfile.TarError) as exc:
        print("RESULT=R322_PUBLIC_GITHUB_AUDIT_FAIL")
        print("REASON=" + str(exc).split("\n")[0][:240])
        sys.exit(2)
