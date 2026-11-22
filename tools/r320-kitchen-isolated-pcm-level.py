#!/usr/bin/env python3
"""R320: verify non-recording PCM amplitude metrics on LG webOS26
using official installed R278 DTS fixtures and a separate GStreamer
pipeline ending in fakesink. Does NOT inspect Lampa's live PCM output.

Security: no speaker sink, no media recording, no service environment
updates, no production GStreamer registry modification; temporary
registry/cache under /tmp; only aggregate bounded level metrics shown.
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

ROOT = Path("/var/lib/webosbrew/aleks-dts-r278")
FIXTURES = {
    "STEREO": ("dts-stereo.mka",
               "7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae", 2),
    "SURROUND_51": ("dts-51.mka",
                    "7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5", 6),
}
LIBS = {
    "libgstaleksdts.so": "5c3b798d4c1109414efc9209276dbf8b23466376f72f5bc71cf4144f3f5a1cbb",
    "libgstaleksdts16dec.so": "dfefb960d49d50ed7629cc4459ffaae8b420509cc9815d8337f6be7faaac18cf",
    "libgstaleksdtscaps.so": "1995a6b6030f6ddb895aeeea4017dcc71db8ebd6caace0107e1c5a33875f0605",
    "libgstaleksdtsr130optin.so": "9b7adb2744a9d7c329669974c15bcfc86ba62daf27efccb95e362c1928d602e0",
}
LEVEL_RE = re.compile(
    r"\(element\): level,.*?rms=\(GValueArray\)<\s*([^>]+?)\s*>,"
    r"\s*peak=\(GValueArray\)<\s*([^>]+?)\s*>"
)


def must_sha(path, expected):
    if not path.is_file() or path.stat().st_size > 1500000:
        raise ValueError("MISSING_OR_OVERSIZE_FIXTURE")
    with path.open("rb") as f:
        h = hashlib.file_digest(f, "sha256").hexdigest()
    if h != expected:
        raise ValueError("SHA256_MISMATCH")


def level_values(output, channels):
    values = []
    for line in output.splitlines():
        m = LEVEL_RE.search(line)
        if not m:
            continue
        try:
            rms = [float(v) for v in m.group(1).split(",")]
            peak = [float(v) for v in m.group(2).split(",")]
        except ValueError:
            raise ValueError("LEVEL_FORMAT")
        if len(rms) != channels or len(peak) != channels:
            raise ValueError("CHANNEL_MISMATCH")
        if not all(math.isfinite(x) and -800 < x <= 12 for x in rms + peak):
            raise ValueError("LEVEL_INVALID")
        values.append(max(rms))
        if len(values) > 512:
            raise ValueError("LEVEL_WINDOW_EXCESS")
    if not values:
        raise ValueError("NO_LEVEL_MESSAGES")
    return values


def main():
    if platform.machine().lower() not in ("aarch64", "armv7l", "armv6l", "arm"):
        raise ValueError("NOT_ARM_TV")
    if len(sys.argv) != 1:
        raise ValueError("UNEXPECTED_ARGS")
    for name, digest in LIBS.items():
        must_sha(ROOT / "plugins" / name, digest)
    print("R320_INSTALLED_RELEASE_LIBS=4/4_SHA256_PASS")
    for name, (file_name, digest, _) in FIXTURES.items():
        must_sha(ROOT / "fixtures" / file_name, digest)
        print("R320_" + name + "_FIXTURE_SHA256=PASS")

    base = "/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0"
    with tempfile.TemporaryDirectory(prefix="aleks-r320-gst-only-",
                                     dir="/tmp") as tmp:
        root = Path(tmp)
        cache = root / "cache"
        cache.mkdir()
        # Explicit isolated env, do not alter the parent or live media process.
        env = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": str(root),
            "XDG_CACHE_HOME": str(cache),
            "LC_ALL": "C",
            "GST_PLUGIN_PATH_1_0": base + ":" + str(ROOT / "plugins"),
            "GST_PLUGIN_SYSTEM_PATH_1_0": base,
            "GST_REGISTRY_1_0": str(root / "gst-test-registry.bin"),
            "GST_REGISTRY_UPDATE": "yes",
            "ALEKS_DTS_R130_ALLOW_AUTOPLUG": "YES",
            "GST_PLUGIN_FEATURE_RANK": "aleksdts16dec:350,decproxy:0",
        }
        for label, (file_name, _digest, channels) in FIXTURES.items():
            cmd = [
                "/usr/bin/gst-launch-1.0", "-m", "-v",
                "filesrc", "location=" + str(ROOT / "fixtures" / file_name),
                "!", "matroskademux", "name=dm",
                "dm.audio_0", "!", "queue", "!", "decodebin",
                "!", "audioconvert", "!",
                "audio/x-raw,format=S16LE,channels=" + str(channels) +
                ",rate=48000",
                "!", "level", "interval=100000000", "post-messages=true",
                "!", "fakesink", "sync=false"
            ]
            try:
                r = subprocess.run(cmd, env=env, capture_output=True,
                                   text=True, errors="replace", timeout=18,
                                   check=False)
            except subprocess.TimeoutExpired:
                raise ValueError("ISOLATED_GST_TIMEOUT_" + label)
            if r.returncode != 0:
                raise ValueError("ISOLATED_GST_EXIT_" + str(r.returncode) +
                                 "_" + label)
            # Only parse safe numeric fields; no raw movie paths in output.
            output = r.stdout + "\n" + r.stderr
            levels = level_values(output, channels)
            maximum = max(levels)
            active = sum(level > -90 for level in levels)
            selected = "AlekSDts16DecBin" in output
            print("R320_" + label + "_CUSTOM_BIN_MAPPED=" +
                  ("yes" if selected else "not_proven"))
            print("R320_" + label + "_LEVEL_WINDOWS=" + str(len(levels)))
            print("R320_" + label + "_ACTIVE_WINDOWS=" + str(active))
            print("R320_" + label + "_MAX_RMS_DBFS=" + "%.2f" % maximum)
            if active == 0 or maximum < -75:
                raise ValueError("UNEXPECTED_ZERO_PCM_" + label)
    print("R320_LAMPA_LIVE_PIPELINE=NOT_OBSERVED")
    print("R320_PRODUCTION_SYSTEM_MODIFIED=NO")
    print("RESULT=R320_WEBOS26_ISOLATED_PCM_LEVEL_PASS")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        print("R320_FAIL=" + str(exc).split(":", 1)[0][:120])
        sys.exit(2)
