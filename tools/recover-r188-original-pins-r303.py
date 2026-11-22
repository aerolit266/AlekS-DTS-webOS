#!/usr/bin/env python3
"""R303: find exact R188 prerequisites in explicitly selected backups.

No network, TV, SSH or GStreamer calls. Dry-run unless --stage-dir is given.
Only exact original SHA256 matches are eligible; never re-pin/substitute.
Archive members are read in-memory with size caps, NOT extracted by their paths.
"""
import argparse
import hashlib
import io
import json
import os
import stat
import tarfile
import tempfile
import zipfile
from pathlib import Path

# Original R188 ASan/UBSan build's SHA pins. Names are the only output names.
ORIGINAL = {
    "r122_dts_core_probe.h": "83fbf1f002e59e9f844e721bd26fc1d5e2be6933c510a8eded172d96252fe1ca",
    "dts51-audioonly.mkv": "1da49e2e8b74bbaee6892fcf7a13a9ac738abde323200439d197d0abcd7eabb9",
    "dts20-audioonly.mkv": "d53aead1a62255019b9ccad617ed34902d70c874595236853eb36b554cb7685c",
}
MAX_FILE_BYTES = 12 * 1024 * 1024
MAX_MEMBERS = 10000


def hexdigest(data):
    return hashlib.sha256(data).hexdigest()


def safe_member(name):
    # Never use member paths as output paths. Guard even though only basenames
    # and exact hashes can match.
    path = name.replace("\\", "/")
    parts = path.split("/")
    return bool(parts) and not path.startswith("/") and ".." not in parts and not (len(parts[0]) >= 2 and parts[0][1] == ":")


def read_limited(stream, size):
    if size > MAX_FILE_BYTES or size < 0:
        return None
    result = stream.read(MAX_FILE_BYTES + 1)
    return result if len(result) == size and len(result) <= MAX_FILE_BYTES else None


def discover(paths, archives, pins):
    findings = {}
    stats = {"candidate_files": 0, "hash_mismatches": 0,
             "unsafe_entries": 0, "size_rejections": 0,
             "archives_opened": 0, "errors": []}
    for location in paths:
        path = Path(location)
        if path.is_symlink() or not path.exists():
            stats["errors"].append("SOURCE_UNAVAILABLE_OR_SYMLINK")
            continue
        if path.is_dir():
            candidates = (p for p in path.rglob("*") if p.name in pins)
        else:
            candidates = (p for p in (path,) if p.name in pins)
        for candidate in candidates:
            if candidate.name in findings:
                continue
            if candidate.is_symlink() or not candidate.is_file():
                stats["unsafe_entries"] += 1
                continue
            try:
                st = candidate.stat()
                if not stat.S_ISREG(st.st_mode) or st.st_size > MAX_FILE_BYTES:
                    stats["size_rejections"] += 1
                    continue
                data = candidate.read_bytes()
            except OSError:
                stats["errors"].append("SOURCE_READ_ERROR")
                continue
            stats["candidate_files"] += 1
            if hexdigest(data) == pins[candidate.name]:
                findings[candidate.name] = data
            else:
                stats["hash_mismatches"] += 1
    for item in archives:
        archive = Path(item)
        if archive.is_symlink() or not archive.is_file():
            stats["errors"].append("ARCHIVE_UNAVAILABLE_OR_SYMLINK")
            continue
        try:
            if tarfile.is_tarfile(archive):
                with tarfile.open(archive, "r:*") as tf:
                    stats["archives_opened"] += 1
                    for index, member in enumerate(tf):
                        if index >= MAX_MEMBERS:
                            stats["errors"].append("ARCHIVE_MEMBER_LIMIT")
                            break
                        name = member.name.replace("\\", "/")
                        base = name.rsplit("/", 1)[-1]
                        if base not in pins or base in findings:
                            continue
                        if not safe_member(name) or not member.isfile():
                            stats["unsafe_entries"] += 1
                            continue
                        if member.size > MAX_FILE_BYTES:
                            stats["size_rejections"] += 1
                            continue
                        stream = tf.extractfile(member)
                        if stream is None:
                            continue
                        with stream:
                            data = read_limited(stream, member.size)
                        if data is None:
                            stats["size_rejections"] += 1
                            continue
                        stats["candidate_files"] += 1
                        if hexdigest(data) == pins[base]:
                            findings[base] = data
                        else:
                            stats["hash_mismatches"] += 1
            elif zipfile.is_zipfile(archive):
                with zipfile.ZipFile(archive) as zf:
                    stats["archives_opened"] += 1
                    for member in zf.infolist()[:MAX_MEMBERS]:
                        name = member.filename.replace("\\", "/")
                        base = name.rsplit("/", 1)[-1]
                        if base not in pins or base in findings:
                            continue
                        kind = (member.external_attr >> 16) & 0o170000
                        if not safe_member(name) or member.is_dir() or kind == stat.S_IFLNK:
                            stats["unsafe_entries"] += 1
                            continue
                        if member.file_size > MAX_FILE_BYTES:
                            stats["size_rejections"] += 1
                            continue
                        with zf.open(member) as stream:
                            data = read_limited(stream, member.file_size)
                        if data is None:
                            stats["size_rejections"] += 1
                            continue
                        stats["candidate_files"] += 1
                        if hexdigest(data) == pins[base]:
                            findings[base] = data
                        else:
                            stats["hash_mismatches"] += 1
                    if len(zf.infolist()) > MAX_MEMBERS:
                        stats["errors"].append("ARCHIVE_MEMBER_LIMIT")
            else:
                stats["errors"].append("ARCHIVE_FORMAT_UNSUPPORTED")
        except (OSError, tarfile.TarError, zipfile.BadZipFile, RuntimeError, EOFError):
            stats["errors"].append("ARCHIVE_READ_ERROR")
    return findings, stats


def stage(findings, target, pins):
    """Stage only exact matches. Never replace existing files or traverse links."""
    target = Path(target)
    if target.is_symlink():
        raise ValueError("STAGE_DIR_SYMLINK_REJECTED")
    target.mkdir(mode=0o700, parents=True, exist_ok=True)
    if target.is_symlink():
        raise ValueError("STAGE_DIR_SYMLINK_REJECTED")
    status = {}
    for name, data in findings.items():
        if name not in pins or hexdigest(data) != pins[name]:
            raise ValueError("SOURCE_PIN_MISMATCH")
        destination = target / name
        if destination.exists() or destination.is_symlink():
            if destination.is_symlink() or not destination.is_file():
                raise ValueError("EXISTING_NONREGULAR_TARGET_REJECTED")
            if hexdigest(destination.read_bytes()) != pins[name]:
                raise ValueError("EXISTING_TARGET_HASH_CONFLICT")
            status[name] = "ALREADY_VERIFIED"
            continue
        # Exclusive create: no accidental overwrite of an existing artifact.
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        fd = os.open(destination, flags, 0o600)
        try:
            with os.fdopen(fd, "wb") as out:
                out.write(data)
                out.flush()
                os.fsync(out.fileno())
            if hexdigest(destination.read_bytes()) != pins[name]:
                raise ValueError("STAGE_VERIFICATION_FAILED")
        except BaseException:
            destination.unlink(missing_ok=True)
            raise
        status[name] = "STAGED_VERIFIED"
    return status


def selftest():
    pins = {"r122_dts_core_probe.h": hexdigest(b"original-like mock header"),
            "dts51-audioonly.mkv": hexdigest(b"original-like mock audio")}
    with tempfile.TemporaryDirectory(prefix="r303-qa-") as t:
        root = Path(t)
        src = root / "sources"
        src.mkdir()
        (src / "r122_dts_core_probe.h").write_bytes(b"original-like mock header")
        (src / "dts51-audioonly.mkv").write_bytes(b"untrusted")
        archive = root / "samples.tar.gz"
        with tarfile.open(archive, "w:gz") as tf:
            for name, data in (
                ("nested/dts51-audioonly.mkv", b"original-like mock audio"),
                ("../../dts51-audioonly.mkv", b"original-like mock audio")):
                info = tarfile.TarInfo(name)
                info.size = len(data)
                tf.addfile(info, io.BytesIO(data))
        found, counts = discover([src], [archive], pins)
        assert len(found) == 2 and counts["hash_mismatches"] == 1
        assert counts["archives_opened"] == 1
        outputs = stage(found, root / "verified", pins)
        assert all(x == "STAGED_VERIFIED" for x in outputs.values())
        second = stage(found, root / "verified", pins)
        assert all(x == "ALREADY_VERIFIED" for x in second.values())
        (root / "verified" / "dts51-audioonly.mkv").write_bytes(b"changed")
        try:
            stage(found, root / "verified", pins)
        except ValueError as e:
            assert "HASH_CONFLICT" in str(e)
        else:
            raise AssertionError("existing conflict should be rejected")
    print("R303_SELFTEST_PASS exact_hash_tar_nested_stage_idempotency_conflict")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", action="append", default=[], help="Allowlisted local source file/directory")
    p.add_argument("--archive", action="append", default=[], help="Explicit local tar/zip archive")
    p.add_argument("--stage-dir", default=None, help="Optional persistent staging destination")
    p.add_argument("--selftest", action="store_true")
    args = p.parse_args()
    if args.selftest:
        selftest()
        return
    if not args.source and not args.archive:
        p.error("Explicitly provide --source or --archive (no default system-wide scan).")
    found, stats = discover(args.source, args.archive, ORIGINAL)
    staged = stage(found, args.stage_dir, ORIGINAL) if args.stage_dir and found else {}
    result = {"schema": "aleks.dts.r303.original-pins.v1",
              "matching_original_count": len(found),
              "originals_required": len(ORIGINAL),
              "found": sorted(found),
              "missing": sorted(set(ORIGINAL) - set(found)),
              "stats": stats,
              "staged": staged,
              "replay_ready": len(found) == len(ORIGINAL),
              "new_fixture_substituted": False, "real_lg_tested": False}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not result["replay_ready"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
