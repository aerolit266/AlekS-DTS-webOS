#!/usr/bin/env python3
"""R650 private LAB package staging. Not a webOS installer."""
import argparse
import hashlib
import io
import os
from pathlib import Path
import shutil
import stat
import tarfile
import tempfile
import uuid

EXPECTED = "9eec2fcb6f9a0a1735ca28fd9e6e924b9ef4e2074af9efc5ddb61927114ef920"
FILES = frozenset({
    "README.md", "DEPLOYMENT-GATES.md", "RELEASE-GATE.json",
    "PROVENANCE.md", "QA-SUMMARY.md", "SHA256SUMS",
    "verify.sh", "qa-offline.sh",
    "payload/libgstaleksdts16dec.so", "payload/libgstaleksdtscaps.so",
})
MAX_ARCHIVE = 1024 * 1024

def require(ok, message):
    if not ok:
        raise ValueError(message)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def verified_archive(path):
    with open(path, "rb") as f:
        data = f.read(MAX_ARCHIVE + 1)
    require(len(data) <= MAX_ARCHIVE, "archive too large")
    require(sha(data) == EXPECTED, "archive SHA256 mismatch")
    out = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as t:
        for member in t:
            require(member.name in FILES, "unexpected archive path")
            require(member.name not in out, "duplicate archive path")
            require(member.isfile() and member.size <= MAX_ARCHIVE, "unsafe member")
            out[member.name] = t.extractfile(member).read()
    require(set(out) == FILES, "incomplete archive")
    check_contents(out)
    return out

def check_contents(out):
    manifest = {}
    for line in out["SHA256SUMS"].decode("utf-8").splitlines():
        digest, name = line.split("  ", 1)
        require(name in FILES - {"SHA256SUMS"} and name not in manifest,
                "invalid manifest path")
        require(sha(out[name]) == digest, "manifest mismatch: " + name)
        manifest[name] = digest
    require(set(manifest) == FILES - {"SHA256SUMS"}, "incomplete manifest")
    import json
    gate = json.loads(out["RELEASE-GATE.json"])
    require(gate.get("install_allowed") is False, "unexpected TV release gate")
    require(gate.get("publication_allowed") is False, "unexpected publication gate")

def owned_dir(p):
    s = p.lstat()
    require(stat.S_ISDIR(s.st_mode) and s.st_uid == os.getuid()
            and not (s.st_mode & 0o022), "unsafe directory: " + str(p))

def read_stage(p):
    owned_dir(p)
    owned_dir(p / "payload")
    found = {str(f.relative_to(p)) for f in p.iterdir()}
    require(found == (FILES - {n for n in FILES if "/" in n}) | {"payload"},
            "unexpected stage entries")
    require({f.name for f in (p / "payload").iterdir()} ==
            {Path(n).name for n in FILES if "/" in n}, "unexpected payload entries")
    out = {}
    for name in FILES:
        f = p / name
        s = f.lstat()
        require(stat.S_ISREG(s.st_mode) and s.st_uid == os.getuid()
                and s.st_nlink == 1 and not (s.st_mode & 0o022)
                and s.st_size <= MAX_ARCHIVE, "unsafe staged file: " + name)
        out[name] = f.read_bytes()
    check_contents(out)
    return out

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["verify", "install", "status", "rollback"])
    parser.add_argument("archive", nargs="?", type=Path)
    args = parser.parse_args()
    require(os.name == "posix" and os.getuid() != 0, "use a non-root Linux lab account")
    if args.action in {"verify", "install"}:
        require(args.archive is not None, "local R650 archive required")
        data = verified_archive(args.archive)
        if args.action == "verify":
            print("ARCHIVE_VERIFIED=PASS\nTV_INSTALL_ALLOWED=NO")
            return
    else:
        require(args.archive is None, "unexpected archive argument")
    # Only one private lab directory directly below the current user's home.
    home = Path.home()
    owned_dir(home)
    root = home / ".aleks-dts-r650-lab"
    if args.action == "install":
        root.mkdir(mode=0o700, exist_ok=True)
    owned_dir(root)
    stage = root / "staged"
    lock = root / ".lock"
    lock.mkdir(mode=0o700)
    try:
        if args.action == "install":
            require(not os.path.lexists(stage), "stage exists; rollback first")
            tmp = Path(tempfile.mkdtemp(prefix=".tmp-", dir=root))
            try:
                (tmp / "payload").mkdir(mode=0o700)
                for name, blob in data.items():
                    with (tmp / name).open("xb") as f:
                        f.write(blob)
                    (tmp / name).chmod(0o600)
                require(read_stage(tmp) == data, "stage verification failed")
                tmp.rename(stage)
                print("LAB_STAGE=PASS")
            finally:
                if tmp.exists():
                    shutil.rmtree(tmp)
        elif args.action == "status":
            if not os.path.lexists(stage):
                print("LAB_STAGE=ABSENT")
            else:
                read_stage(stage)
                print("LAB_STAGE=VERIFIED")
        else:
            require(os.path.lexists(stage), "nothing staged")
            # Preserve the exact lab directory; do not delete or touch system files.
            owned_dir(stage)
            dst = root / ("rollback-" + uuid.uuid4().hex)
            stage.rename(dst)
            print("LAB_ROLLBACK=PASS")
            print("RETAINED_COPY=" + dst.name)
        print("TV_INSTALL_ALLOWED=NO")
    finally:
        lock.rmdir()

if __name__ == "__main__":
    os.umask(0o077)
    try:
        main()
    except (OSError, ValueError, tarfile.TarError, UnicodeError) as e:
        raise SystemExit("ERROR: " + str(e))
