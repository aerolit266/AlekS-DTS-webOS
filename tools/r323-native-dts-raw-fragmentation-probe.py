#!/usr/bin/env python3
"""R323: read-only native LG DTS Core fragmented-stream differential lab.

Tests only the publicly released R278 stereo fixture in a separate private
GStreamer child with fakesink. NO live app hooking, no audio output, no media
service restart or configuration changes, no private media or PCM storage.
The Matroska fixture is safely demuxed to a transient /tmp encoded DTS blob.
Run independent decoded-amplitude probes at source block sizes 11,97,4096.
An isolated failure does not establish actual Lampa cold-boot root cause.
"""
import hashlib
import math
import os
import pathlib
import platform
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path("/var/lib/webosbrew/aleks-dts-r278")
FIXTURE = ROOT / "fixtures/dts-stereo.mka"
EXPECTED_FIXTURE = "7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae"
LIBS = {
    "libgstaleksdts.so": "5c3b798d4c1109414efc9209276dbf8b23466376f72f5bc71cf4144f3f5a1cbb",
    "libgstaleksdts16dec.so": "dfefb960d49d50ed7629cc4459ffaae8b420509cc9815d8337f6be7faaac18cf",
    "libgstaleksdtscaps.so": "1995a6b6030f6ddb895aeeea4017dcc71db8ebd6caace0107e1c5a33875f0605",
    "libgstaleksdtsr130optin.so": "9b7adb2744a9d7c329669974c15bcfc86ba62daf27efccb95e362c1928d602e0",
}
RE_RMS = re.compile(r"\(element\): level,.*?rms=\(GValueArray\)<\s*([^>]+?)\s*>")
GST = "/usr/bin/gst-launch-1.0"


def sha_check(path, expected):
    if not path.is_file() or path.stat().st_size > 2_000_000:
        raise ValueError("INPUT_MISSING_OR_OVERSIZE")
    with path.open("rb") as f:
        got = hashlib.file_digest(f, "sha256").hexdigest()
    if got != expected:
        raise ValueError("INPUT_SHA_MISMATCH")


def run(cmd, env, secs=15):
    try:
        p = subprocess.run(cmd, env=env, capture_output=True, text=True,
                           errors="replace", timeout=secs, check=False)
    except subprocess.TimeoutExpired:
        return -124, "", ""
    return p.returncode, p.stdout, p.stderr


def test_decoder(name, source_args, env):
    cmd = ([GST, "-m", "-v"] + source_args +
           ["!", "queue", "!", "decodebin", "!", "audioconvert",
            "!", "audio/x-raw,format=S16LE,channels=2,rate=48000",
            "!", "level", "interval=100000000", "post-messages=true",
            "!", "fakesink", "sync=false"])
    code, output, err = run(cmd, env, secs=18)
    output += "\n" + err
    levels = []
    for line in output.splitlines():
        m = RE_RMS.search(line)
        if not m:
            continue
        fields = [v.strip() for v in m.group(1).split(",")]
        if len(fields) != 2:
            raise ValueError("UNEXPECTED_LEVEL_CHANNELS_" + name)
        vals = [float(v) for v in fields]
        if not all(math.isfinite(v) and -800 < v <= 12 for v in vals):
            raise ValueError("BAD_LEVEL_NUMBER_" + name)
        levels.append(max(vals))
    if len(levels) > 512:
        raise ValueError("TOO_MANY_LEVEL_WINDOWS")
    active = sum(v > -90 for v in levels)
    detected_decoder = "AlekSDts16DecBin" in output
    print("R323_" + name + "_EXIT=" + str(code))
    print("R323_" + name + "_PCM_WINDOWS=" + str(len(levels)))
    print("R323_" + name + "_ACTIVE_WINDOWS=" + str(active))
    print("R323_" + name + "_CUSTOM_DECODER=" +
          ("yes" if detected_decoder else "not_seen"))
    if levels:
        print("R323_" + name + "_MAX_RMS_DBFS=" + "%.2f" % max(levels))
    # No raw logs/filenames or PCM: only allowlisted scalars.
    return code, len(levels), active, detected_decoder


def main():
    if len(sys.argv) != 1:
        raise ValueError("UNEXPECTED_ARGS")
    if platform.machine().lower() not in ("armv7l", "aarch64"):
        raise ValueError("UNEXPECTED_CPU")
    for name, digest in LIBS.items():
        sha_check(ROOT / "plugins" / name, digest)
    sha_check(FIXTURE, EXPECTED_FIXTURE)
    print("R323_PINNED_R278_INPUTS=PASS_5")
    with tempfile.TemporaryDirectory(prefix="aleks-r323-first-dts-", dir="/tmp") as tmp:
        root = pathlib.Path(tmp)
        (root / "cache").mkdir()
        env = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": str(root),
            "LC_ALL": "C",
            "XDG_CACHE_HOME": str(root / "cache"),
            "GST_PLUGIN_PATH_1_0":
                "/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0:" +
                str(ROOT / "plugins"),
            "GST_PLUGIN_SYSTEM_PATH_1_0":
                "/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0",
            "GST_REGISTRY_1_0": str(root / "registry.bin"),
            "GST_REGISTRY_UPDATE": "yes",
            "ALEKS_DTS_R130_ALLOW_AUTOPLUG": "YES",
            "GST_PLUGIN_FEATURE_RANK": "aleksdts16dec:350,decproxy:0",
        }
        packet_source = ["filesrc", "location=" + str(FIXTURE),
                         "!", "matroskademux", "name=dm", "dm.audio_0"]
        good = test_decoder("MATROSKA", packet_source, env)
        if not (good[0] == 0 and good[2] > 0 and good[3]):
            raise ValueError("PACKETIZED_NATIVE_BASELINE_FAILED")
        raw = root / "public_fixture.dts"
        dump = ([GST, "-q"] + packet_source +
                ["!", "queue", "!", "filesink", "location=" + str(raw)])
        code, _stdout, _err = run(dump, env, secs=16)
        if code or not raw.is_file() or not 1000 < raw.stat().st_size < 200000:
            raise ValueError("DEMUX_RAW_PREP_FAILED")
        print("R323_ENCODED_DTS_BYTES=" + str(raw.stat().st_size))
        print("R323_NOTE=RAW_TESTS_ARE_ISOLATED_DIFFERENTIAL_NOT_LAMPA")
        for block in (11, 97, 4096):
            src = ["filesrc", "blocksize=" + str(block),
                   "location=" + str(raw), "!", "audio/x-dts"]
            test_decoder("RAW_" + str(block), src, env)
    print("R323_PRODUCTION_SERVICE_MODIFIED=NO")
    print("R323_LIVE_LAMPA_PCM=UNOBSERVED")
    print("RESULT=R323_NATIVE_RAW_DTS_FRAGMENTATION_DIFFERENTIAL_COMPLETE")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, subprocess.SubprocessError) as e:
        print("R323_FAILURE=" + str(e).split("\n")[0][:100])
        sys.exit(2)
