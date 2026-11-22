#!/usr/bin/env python3
"""R325 kitchen LG / GStreamer 1.24: isolated DTS Core framer QA.

PREVIEW ONLY. Loads the R312 framer from a verified temporary /tmp copy
in a NEW child GStreamer registry, alongside installed unmodified R278
decoder. Uses public pinned DTS stereo/5.1 fixtures and level ! fakesink.
No speaker output, PCM files, private media, systemd changes, installation
or plugin updates. The script *does not* test Lampa's live cold-start path.
"""
import hashlib
import math
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile

TV_STAGE = Path("/tmp/aleks-r325-lab-20261122")
ROOT = Path("/var/lib/webosbrew/aleks-dts-r278")
EXPECTED_PLUGIN = "0fc2959e92fd4f93f810a74a5b87c3c3a1401b7b3b37d0c26885ee771d1d9d44"
PLUGINS = {
    "libgstaleksdts.so": "5c3b798d4c1109414efc9209276dbf8b23466376f72f5bc71cf4144f3f5a1cbb",
    "libgstaleksdts16dec.so": "dfefb960d49d50ed7629cc4459ffaae8b420509cc9815d8337f6be7faaac18cf",
    "libgstaleksdtscaps.so": "1995a6b6030f6ddb895aeeea4017dcc71db8ebd6caace0107e1c5a33875f0605",
    "libgstaleksdtsr130optin.so": "9b7adb2744a9d7c329669974c15bcfc86ba62daf27efccb95e362c1928d602e0",
}
FIXTURES = {
    "STEREO": (
        "dts-stereo.mka", 2, 1024,
        "7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae",
        "282d15e11221524f6af40f4202ec6d2a3813d2a12a49de904e7cdfc0c4ce9bda",
    ),
    "SURROUND_51": (
        "dts-51.mka", 6, 2048,
        "7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5",
        "8897677d593a5710b62f90919fe0e9888a31621bf55b166e2294a2f36f4fb013",
    ),
}
LEVEL_RE = re.compile(r"\(element\): level,.*?rms=\(GValueArray\)<\s*([^>]+?)\s*>")
SYSTEM_PATH = "/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0"
WARNINGS = (
    "Sticky event misordering", "Got data flow before segment",
    "not-negotiated", "GStreamer-CRITICAL", "GStreamer-WARNING",
    "Internal data stream error", "reason error",
)


def checked_sha(path, digest, max_bytes):
    if not path.is_file() or not 0 < path.stat().st_size < max_bytes:
        raise ValueError("INPUT_MISSING_OR_INVALID")
    with path.open("rb") as stream:
        value = hashlib.file_digest(stream, "sha256").hexdigest()
    if value != digest:
        raise ValueError("SHA256_MISMATCH")


def call(cmd, env, seconds=18):
    try:
        out = subprocess.run(cmd, env=env, capture_output=True,
                             text=True, errors="replace", timeout=seconds,
                             check=False)
    except subprocess.TimeoutExpired:
        raise ValueError("GST_TIMEOUT")
    return out.returncode, out.stdout + "\n" + out.stderr


def levels(label, cmd, channels, env, need_framer):
    status, log = call(cmd, env)
    windows = []
    for line in log.splitlines():
        match = LEVEL_RE.search(line)
        if not match:
            continue
        entries = [float(v.strip()) for v in match.group(1).split(",")]
        if len(entries) != channels or not all(
            math.isfinite(v) and -800 < v <= 12 for v in entries
        ):
            raise ValueError("BAD_GST_LEVEL_CHANNELS")
        windows.append(max(entries))
        if len(windows) > 512:
            raise ValueError("TOO_MANY_LEVEL_WINDOWS")
    active = sum(v > -90 for v in windows)
    tags = [w for w in WARNINGS if w.lower() in log.lower()]
    native = "AlekSDts16DecBin" in log
    framer = "aleksdtsr188framer" in log
    print("R325_" + label + "_EXIT=" + str(status))
    print("R325_" + label + "_LEVEL_WINDOWS=" + str(len(windows)))
    print("R325_" + label + "_NONZERO_WINDOWS=" + str(active))
    if windows:
        print("R325_" + label + "_MAX_RMS_DBFS=" + "%.2f" % max(windows))
    print("R325_" + label + "_R278_DECODER_USED=" + str(native).lower())
    print("R325_" + label + "_FRAMER_USED=" + str(framer).lower())
    print("R325_" + label + "_WARNING_COUNT=" + str(len(tags)))
    if status or not windows or active != len(windows) or tags or not native:
        raise ValueError("DECODE_OR_EVENT_CHECK_FAILED_" + label)
    if need_framer and not framer:
        raise ValueError("CUSTOM_FRAMER_NOT_USED_" + label)
    return len(windows), max(windows)


def dts_raw(encoded_mka, frame_bytes, expected_raw):
    data = encoded_mka
    marker = bytes.fromhex("7ffe8001")
    positions = []
    at = 0
    while True:
        index = data.find(marker, at)
        if index == -1:
            break
        positions.append(index)
        at = index + 4
    if len(positions) != 94 or any(i + frame_bytes > len(data)
                                   for i in positions):
        raise ValueError("PUBLIC_FIXTURE_DTS_FRAME_COUNT")
    raw = b"".join(data[i:i + frame_bytes] for i in positions)
    if hashlib.sha256(raw).hexdigest() != expected_raw:
        raise ValueError("PUBLIC_FIXTURE_RAW_SHA256")
    return raw


def main():
    if len(sys.argv) != 1:
        raise ValueError("UNEXPECTED_ARGUMENTS")
    if platform.machine() != "aarch64":
        raise ValueError("NOT_KITCHEN_LG_ARCH")
    plugin = TV_STAGE / "libgstaleksdtsr188framer.so"
    checked_sha(plugin, EXPECTED_PLUGIN, 128_000)
    for name, sha in PLUGINS.items():
        checked_sha(ROOT / "plugins" / name, sha, 2_000_000)
    for _track, (name, _channels, _frame, sha, _raw) in FIXTURES.items():
        checked_sha(ROOT / "fixtures" / name, sha, 500_000)
    print("R325_VERIFIED_STAGED_PLUGIN_AND_R278_LIBS=5_OF_5")
    print("R325_PUBLIC_FIXTURES_SHA256=2_OF_2")
    with tempfile.TemporaryDirectory(prefix="aleks-r325-gst-preview-", dir="/tmp") as tmp:
        root = Path(tmp)
        (root / "cache").mkdir()
        env = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": str(root),
            "LC_ALL": "C",
            "XDG_CACHE_HOME": str(root / "cache"),
            "GST_PLUGIN_SYSTEM_PATH_1_0": SYSTEM_PATH,
            "GST_PLUGIN_PATH_1_0":
                str(TV_STAGE) + ":" + str(ROOT / "plugins") + ":" + SYSTEM_PATH,
            "GST_REGISTRY_1_0": str(root / "registry.bin"),
            "GST_REGISTRY_UPDATE": "yes",
            "GST_DEBUG_NO_COLOR": "1",
            "ALEKS_DTS_R130_ALLOW_AUTOPLUG": "YES",
            "GST_PLUGIN_FEATURE_RANK": "aleksdts16dec:350,decproxy:0",
        }
        gst = "/usr/bin/gst-launch-1.0"
        status, inspect = call(["/usr/bin/gst-inspect-1.0",
                                "aleksdtsr188framer"], env, seconds=10)
        if status or "Rank                     none (0)" not in inspect:
            raise ValueError("CUSTOM_FRAMER_REGISTRATION")
        print("R325_R312_FRAMER_RANK_NONE=PASS")
        cases = 0
        for label, (filename, channels, frame_bytes, _sha, raw_sha) in FIXTURES.items():
            mka = ROOT / "fixtures" / filename
            raw = dts_raw(mka.read_bytes(), frame_bytes, raw_sha)
            filename_raw = root / (label.lower() + ".dts")
            filename_raw.write_bytes(raw)
            common = [
                "!", "audioconvert", "!",
                "audio/x-raw,format=S16LE,channels=" + str(channels) + ",rate=48000",
                "!", "level", "interval=100000000", "post-messages=true",
                "!", "fakesink", "sync=false"
            ]
            base = [gst, "-m", "-v", "filesrc", "location=" + str(mka),
                    "!", "matroskademux", "name=dm", "dm.audio_0", "!",
                    "queue", "!", "decodebin"] + common
            reference = levels(label + "_REFERENCE", base, channels, env, False)
            for block in (1, 11, 97, 4096):
                chain = [
                    gst, "-m", "-v", "filesrc",
                    "location=" + str(filename_raw), "blocksize=" + str(block),
                    "!", "audio/x-dts", "!", "aleksdtsr188framer",
                    "!", "queue", "!", "decodebin"
                ] + common
                result = levels(label + "_BLOCK_" + str(block), chain,
                                channels, env, True)
                if abs(result[1] - reference[1]) >= 0.10:
                    raise ValueError("PCM_AMPLITUDE_REFERENCE_MISMATCH")
                cases += 1
        print("R325_FRAMER_GST124_CASES_PASS=" + str(cases) + "_OF_8")
    print("R325_LAMPA_COLD_START=NOT_OBSERVED")
    print("R325_R278_SERVICES_OR_LIBRARIES_CHANGED=NO")
    print("RESULT=R325_REAL_LG_ISOLATED_FRAMER_QA_PASS")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, TypeError, subprocess.SubprocessError) as exc:
        print("RESULT=R325_REAL_LG_ISOLATED_FRAMER_QA_FAIL")
        print("ERROR_CLASS=" + str(exc).split("\n", 1)[0][:140])
        sys.exit(2)
