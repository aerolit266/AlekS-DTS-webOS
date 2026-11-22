#!/usr/bin/env python3
"""R329: stage only the immutable public R278 DTS Core fixtures in /tmp.

Produces encoded DTS/Matroska fixtures ONLY, not decoded PCM.
No changes to installed GStreamer plugins, LS2, applications or services.
Use only in an isolated GStreamer child process ending with fakesink.

Usage: python3 r329-stage-public-fixtures.py /tmp/aleks-r329-qa-20261122
"""
from hashlib import sha256
from pathlib import Path
import os
import sys

FIXTURES = (
    ("stereo", "dts-stereo.mka", 1024,
     "7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae",
     "282d15e11221524f6af40f4202ec6d2a3813d2a12a49de904e7cdfc0c4ce9bda"),
    ("surround", "dts-51.mka", 2048,
     "7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5",
     "8897677d593a5710b62f90919fe0e9888a31621bf55b166e2294a2f36f4fb013"),
)
SOURCE = Path("/var/lib/webosbrew/aleks-dts-r278/fixtures")
SYNC = bytes.fromhex("7ffe8001")


def write_exclusive(path, data):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags, 0o600)
    with os.fdopen(fd, "wb") as out:
        out.write(data)
    if sha256(path.read_bytes()).digest() != sha256(data).digest():
        raise RuntimeError("WRITE_SHA_MISMATCH")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("R329_EXPECT_ONE_TEMP_DIR")
    dest = Path(sys.argv[1])
    if (not str(dest).startswith("/tmp/aleks-r329-") or
            # Explicit path components only: no traversal or quoting tricks.
            not all(p not in (".", "..", "") for p in dest.parts[1:])):
        raise SystemExit("R329_PATH_NOT_ALLOWED")
    if dest.is_symlink() or dest.exists():
        raise SystemExit("R329_DEST_ALREADY_EXISTS")
    # Validate all original fixtures BEFORE writing any files.
    work = []
    for label, name, frame, fixture_sha, raw_sha in FIXTURES:
        source = SOURCE / name
        if source.is_symlink() or not source.is_file() or source.stat().st_size > 500_000:
            raise SystemExit("R329_BAD_SOURCE_FILE")
        data = source.read_bytes()
        if sha256(data).hexdigest() != fixture_sha:
            raise SystemExit("R329_SOURCE_SHA_MISMATCH")
        locations = []
        cursor = 0
        while True:
            index = data.find(SYNC, cursor)
            if index < 0:
                break
            locations.append(index)
            cursor = index + 4
        if len(locations) != 94 or any(pos + frame > len(data) for pos in locations):
            raise SystemExit("R329_FRAME_COUNT_MISMATCH")
        encoded = b"".join(data[pos:pos + frame] for pos in locations)
        if sha256(encoded).hexdigest() != raw_sha:
            raise SystemExit("R329_RAW_DTS_SHA_MISMATCH")
        work.append((label, data, encoded))
    dest.mkdir(mode=0o700)
    os.chmod(dest, 0o700)
    for label, mka, encoded in work:
        write_exclusive(dest / (label + ".mka"), mka)
        write_exclusive(dest / (label + ".dts"), encoded)
        print("R329_" + label.upper() + "_ENCODED_FRAMES=94")
    print("R329_DECODED_PCM_WRITTEN=NO")
    print("RESULT=R329_PUBLIC_DTS_FIXTURE_STAGE_PASS")


if __name__ == "__main__":
    main()
