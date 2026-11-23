#!/usr/bin/env python3
"""Verify the public DTS distribution without installing or connecting to LG."""
from pathlib import Path
import hashlib
import subprocess
import tarfile
import re

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "downloads" / "r278"
EXPECTED = {
    "AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz":
        "cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1",
    "R278-R56-LGPL-RELINK.tar.gz":
        "2723b1cd09b50df367161e5acff6d1d622c76856592c907d79ef606380c98ccf",
    "SOFTWARE-NOTICES.txt":
        "136fcf097dd8059badccd7cdf06bae238ea9c7bb46751c5fe590587fb0070486",
}
KEEP = {
    "README.md", "README.en.md", "PUBLIC-COMPATIBILITY.md", "LICENSE.md",
    "install-universal.sh", ".github/workflows/dts-public-integrity.yml",
    "tools/verify-public-release.py", "downloads/r278/SHA256SUMS",
    *{"downloads/r278/" + name for name in EXPECTED},
}

def ensure(test, detail):
    if not test:
        raise RuntimeError(detail)

def main():
    tracked = subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True).splitlines()
    ensure(set(tracked) == KEEP,
           "Unexpected public file inventory: " + repr(sorted(set(tracked) ^ KEEP)))
    sums = (DIST / "SHA256SUMS").read_text()
    for name, expected in EXPECTED.items():
        path = DIST / name
        ensure(path.is_file(), "Missing public distribution: " + name)
        ensure(hashlib.sha256(path.read_bytes()).hexdigest() == expected,
               "SHA256 mismatch: " + name)
        ensure(f"{expected}  {name}" in sums, "Manifest mismatch: " + name)
    with tarfile.open(DIST / "AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz") as tg:
        names = tg.getnames()
        ensure("install.sh" in names, "Install entrypoint missing")
        ensure(all(not n.startswith("/") and ".." not in Path(n).parts for n in names),
               "Unsafe archive path")
    with tarfile.open(DIST / "R278-R56-LGPL-RELINK.tar.gz") as tg:
        ensure(len(tg.getnames()) > 0, "LGPL source archive empty")
    installer = ROOT / "install-universal.sh"
    ensure(hashlib.sha256(installer.read_bytes()).hexdigest() ==
           "8b370958cf55b84ae3f33c28cd42a6d87759b6540649e0cfe661f233cec723d8",
           "Pinned installer content changed")
    ensure(subprocess.run(["sh", "-n", str(installer)], check=False).returncode == 0,
           "Installer shell syntax")
    for doc in ("README.md", "README.en.md", "PUBLIC-COMPATIBILITY.md"):
        text = (ROOT / doc).read_text()
        for token in ("65NANO766QA", "65NANO896PC", "43NANO85A6A"):
            ensure(token in text, f"Compatibility entry missing: {doc}/{token}")
        for link in re.findall(r"\]\(([^)]+)\)", text):
            if "://" not in link and not link.startswith("#"):
                ensure((ROOT / doc).parent.joinpath(link.split("#")[0]).exists(),
                       f"Broken relative link: {doc}/{link}")
    print("PUBLIC_FILES=" + str(len(tracked)))
    print("RELEASE_SHA256=PASS")
    print("LGPL_RELINK_AVAILABLE=PASS")
    print("BOOTSTRAP_PINNED=PASS")
    print("PUBLIC_COMPATIBILITY=PASS")
    print("RESULT=PUBLIC_DTS_DISTRIBUTION_PASS")

if __name__ == "__main__":
    main()