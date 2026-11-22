#!/usr/bin/env python3
"""R307: verify the published R278 plugin ABI and DTS fixture packet boundary coverage.

Runs ON AN ISOLATED LINUX LAB HOST, NOT ON LG. Pulls 348 KB SHA-pinned
release archive, verifies 4 ARM32 plugin and 2 real DTS fixture hashes,
and feeds fixtures to stock GStreamer dtsdec: packetized Matroska vs
raw extracted DTS split into arbitrary input blocks. All test data are
generated/extracted under a temporary directory and deleted on exit.
Neither original LG Starfish nor its installed R278 runtime is tested.
"""
import hashlib
import json
import shutil
import struct
import subprocess
import tarfile
import tempfile
from pathlib import Path

RELEASE_URL = (
    "https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/r278/"
    "downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz"
)
RELEASE_SHA256 = "cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1"
FILES = {
    "plugins/libgstaleksdts.so": "5c3b798d4c1109414efc9209276dbf8b23466376f72f5bc71cf4144f3f5a1cbb",
    "plugins/libgstaleksdts16dec.so": "dfefb960d49d50ed7629cc4459ffaae8b420509cc9815d8337f6be7faaac18cf",
    "plugins/libgstaleksdtscaps.so": "1995a6b6030f6ddb895aeeea4017dcc71db8ebd6caace0107e1c5a33875f0605",
    "plugins/libgstaleksdtsr130optin.so": "9b7adb2744a9d7c329669974c15bcfc86ba62daf27efccb95e362c1928d602e0",
    "fixtures/dts-stereo.mka": "7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae",
    "fixtures/dts-51.mka": "7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5",
}
CAPS = {
    "libgstaleksdts16dec.so": (b"AlekSDts16DecBin", b"aleksdtsdec", b"audioconvert", b"capsfilter"),
    "libgstaleksdts.so": (b"dcadec_context_parse", b"gst_audio_decoder_finish_frame"),
    "libgstaleksdtsr130optin.so": (b"gst_pad_push", b"audio/x-dts", b"A_DTS"),
    "libgstaleksdtscaps.so": (b"audio/x-unknown", b"audio/x-dts", b"A_DTS"),
}
BLOCKS = (11, 97, 4096)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(args, limit=24):
    p = subprocess.run(args, capture_output=True, text=True, timeout=limit)
    if p.returncode:
        raise RuntimeError(
            f"LAB_COMMAND_FAILED code={p.returncode} tool={Path(args[0]).name} "
            f"stderr_tail={p.stderr[-1200:]!r}")
    return p.stdout


def source_to_pcm(root, name, path, channels, mode, block):
    out = root / f"{name}-{mode}-{block}.pcm"
    cmd = ["gst-launch-1.0", "-q", "filesrc", f"location={path}",
           f"blocksize={block}", "!"]
    if mode == "packetized":
        cmd += ["matroskademux", "!"]
    cmd += ["dtsdec", "!", "audioconvert", "!",
            f"audio/x-raw,format=S16LE,channels={channels},rate=48000",
            "!", "filesink", f"location={out}"]
    run(cmd, limit=22)
    size = out.stat().st_size
    if not size or size % (channels * 2):
        raise ValueError("PCM_MISALIGNED_OR_EMPTY")
    with out.open("rb") as handle:
        digest = hashlib.file_digest(handle, "sha256").hexdigest()
    return {"frames": size // (channels * 2), "bytes": size,
            "sha256": digest}


def assert_arch(elf, name):
    if not (elf[:4] == b"\x7fELF" and elf[4] == 1 and elf[5] == 1
            and struct.unpack_from("<H", elf, 18)[0] == 40):
        raise ValueError(f"NOT_ARM32_LITTLE_ENDIAN:{name}")
    missing = [s.decode("ascii") for s in CAPS[name] if s not in elf]
    if missing:
        raise ValueError(f"EXPECTED_STATIC_MARKERS_NOT_PRESENT:{name}:{missing}")
    return {"format": "ELF32_ARM_LE",
            "markers_found": [s.decode("ascii") for s in CAPS[name]],
            "proof_of_live_pipeline": False}


def main():
    for program in ("curl", "ffmpeg", "ffprobe", "gst-launch-1.0"):
        if shutil.which(program) is None:
            raise SystemExit(f"R307_MISSING_PROGRAM={program}")
    for elem in ("dtsdec", "matroskademux", "audioconvert", "filesink"):
        # gst-inspect is a diagnostic, not a mutation of the system registry.
        if shutil.which("gst-inspect-1.0") is None:
            raise SystemExit("R307_MISSING_GST_INSPECT")
        run(["gst-inspect-1.0", elem])
    with tempfile.TemporaryDirectory(prefix="aleks-r307-release-") as tmp:
        root = Path(tmp)
        archive = root / "R278-release.tar.gz"
        run(["curl", "-fLsS", "--proto", "=https", "--proto-redir", "=https",
             "--connect-timeout", "8", "--max-time", "25",
             RELEASE_URL, "-o", str(archive)], limit=32)
        if sha(archive.read_bytes()) != RELEASE_SHA256:
            raise ValueError("R278_RELEASE_SHA256_FAILED")
        payload = {}
        with tarfile.open(archive, "r:gz") as t:
            for name, expected in FILES.items():
                member = t.getmember(name)
                if not member.isfile() or member.size > 1500000:
                    raise ValueError("R278_RELEASE_MEMBER_UNSAFE")
                with t.extractfile(member) as stream:
                    data = stream.read(1500001)
                if sha(data) != expected or len(data) != member.size:
                    raise ValueError(f"R278_MEMBER_HASH_FAILED:{name}")
                payload[name] = data
        static = {}
        clips = {}
        for name, data in payload.items():
            if name.startswith("plugins/"):
                static[Path(name).name] = assert_arch(data, Path(name).name)
        for label, channels, filename in (
                ("stereo", 2, "fixtures/dts-stereo.mka"),
                ("surround", 6, "fixtures/dts-51.mka")):
            mka = root / (label + ".mka")
            mka.write_bytes(payload[filename])
            stream = json.loads(run([
                "ffprobe", "-v", "error",
                "-show_entries", "stream=codec_name,channels,sample_rate",
                "-of", "json", str(mka)]))["streams"][0]
            if (stream["codec_name"] != "dts"
                    or int(stream["channels"]) != channels
                    or int(stream["sample_rate"]) != 48000):
                raise ValueError("RELEASE_FIXTURE_CODEC_MISMATCH")
            raw = root / (label + ".dts")
            run(["ffmpeg", "-hide_banner", "-loglevel", "error",
                 "-nostdin", "-i", str(mka), "-map", "0:a:0",
                 "-c:a", "copy", "-f", "dts", str(raw)])
            packetized = {}
            raw_slices = {}
            for block in BLOCKS:
                packetized[block] = source_to_pcm(root,label,mka,channels,"packetized",block)
                raw_slices[block] = source_to_pcm(root,label,raw,channels,"raw",block)
            expected = packetized[4096]
            if not all(item == expected for item in packetized.values()):
                raise ValueError("PACKETIZED_BLOCK_VARIANCE")
            if raw_slices[4096] != expected:
                raise ValueError("RAW_BASELINE_4096_DISAGREEMENT")
            clips[label] = {
                "channels": channels, "rate_hz": 48000,
                "original_r278_fixture_sha256": FILES[filename],
                "raw_extracted_bytes": raw.stat().st_size,
                "packetized_pcm": expected,
                "packetized_blocks_identical": True,
                "raw_input": {
                    str(block): {
                        **item, "lost_pcm_frames": expected["frames"] - item["frames"],
                        "pcm_identical_to_packetized": item == expected
                    } for block, item in raw_slices.items()
                },
            }
        report = {
            "schema": "aleks.dts.r307.release.abi-packet-boundaries.v1",
            "release": "R278-65NANO896PC-03.60.96",
            "release_sha256": RELEASE_SHA256,
            "all_four_plugins_sha256_verified": True,
            "static_plugin_markers": static,
            "clips": clips,
            "raw_chunk_loss_observed_in_vps_stock_dtsdec":
                any(entry["lost_pcm_frames"] > 0 for x in clips.values()
                    for entry in x["raw_input"].values()),
            "lab_gstreamer_runtime": run(["gst-launch-1.0", "--version"]).splitlines()[0],
            "tested_decoder": "VPS stock dtsdec; NOT LG R278 native ARM decoder",
            "kitchen_installed_binary_sha256_verified": False,
            "kitchen_first_silence_root_cause_verified": False,
        }
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
        print("RESULT=R307_RELEASE_ARTIFACT_AND_INPUT_BOUNDARY_LAB_PASS; LG_UNTESTED")


if __name__ == "__main__":
    main()
