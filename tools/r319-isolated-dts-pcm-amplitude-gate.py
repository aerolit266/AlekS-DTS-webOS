#!/usr/bin/env python3
"""R319 isolated PCM amplitude gate for official R278 DTS fixtures.

No TV commands, audio output, playback modifications, raw PCM persistence,
raw GStreamer stderr logging, or untrusted archive member extraction.
Uses a transient 350KB public release archive and `gst-launch ! level !
fakesink`. Prints allowlisted scalar dBFS only. Not an LG live pipeline
measurement and not proof of the cold-start silence root cause.
"""
import hashlib
import math
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

URL = ("https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/r278/"
       "downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz")
ARCHIVE_SHA = "cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1"
FIXTURES = {
    "STEREO": ("fixtures/dts-stereo.mka",
               "7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae", 2),
    "SURROUND_51": ("fixtures/dts-51.mka",
                    "7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5", 6),
}
LEVEL_MESSAGE = re.compile(
    r"\(element\): level,.*?rms=\(GValueArray\)<\s*([^>]+?)\s*>,"
    r"\s*peak=\(GValueArray\)<\s*([^>]+?)\s*>"
)


def fail(label):
    raise RuntimeError("R319_" + label)


def require_tool(program):
    exe = shutil.which(program)
    if not exe:
        fail("MISSING_" + program.upper().replace("-", "_"))
    return exe


def run(cmd, timeout=23):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True,
                           errors="replace", timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        fail("CHILD_TIMEOUT")
    if p.returncode:
        # Do not expose raw Gst messages with potential local file paths.
        fail("CHILD_FAILED_EXIT_" + str(p.returncode))
    return p.stdout + "\n" + p.stderr


def parse_level_output(text, minimum_channels):
    windows = 0
    highest_rms = -1000.0
    highest_peak = -1000.0
    any_nonzero = 0
    for line in text.splitlines():
        m = LEVEL_MESSAGE.search(line)
        if not m:
            continue
        try:
            rms = [float(s.strip()) for s in m.group(1).split(",")]
            peaks = [float(s.strip()) for s in m.group(2).split(",")]
        except ValueError:
            fail("LEVEL_FORMAT")
        if len(rms) != minimum_channels or len(peaks) != minimum_channels:
            fail("CHANNEL_MISMATCH")
        if not all(math.isfinite(x) and -800 < x <= 12 for x in rms + peaks):
            fail("LEVEL_INVALID_RANGE")
        windows += 1
        if windows > 512:
            fail("TOO_MANY_WINDOWS")
        max_rms = max(rms)
        highest_rms = max(highest_rms, max_rms)
        highest_peak = max(highest_peak, max(peaks))
        if max_rms > -90:
            any_nonzero += 1
    if not windows:
        fail("NO_LEVEL_MESSAGES")
    return windows, any_nonzero, highest_rms, highest_peak


def validate(kind, cmd, channels, expect_signal):
    text = run(cmd)
    windows, nonzero, rms, peak = parse_level_output(text, channels)
    if expect_signal and not (rms > -75 and nonzero > 0):
        fail("FALSE_SILENCE_" + kind)
    if not expect_signal and not (rms < -100 and nonzero == 0):
        fail("FALSE_AUDIO_" + kind)
    print("R319_" + kind + "_LEVEL_WINDOWS=" + str(windows))
    print("R319_" + kind + "_ACTIVE_WINDOWS=" + str(nonzero))
    print("R319_" + kind + "_MAX_RMS_DBFS=" + "%.2f" % rms)
    print("R319_" + kind + "_MAX_PEAK_DBFS=" + "%.2f" % peak)
    print("R319_" + kind + "_CLASS=" + ("NONZERO_PCM" if expect_signal else "ZERO_PCM"))


def main():
    gst = require_tool("gst-launch-1.0")
    curl = require_tool("curl")
    for decoder in ("dtsdec", "level", "matroskademux", "audioconvert", "fakesink"):
        run([require_tool("gst-inspect-1.0"), decoder], timeout=8)
    for kind in ("silence", "sine"):
        cmd = [gst, "-m", "audiotestsrc", "wave=" + kind, "num-buffers=60",
               "!", "audio/x-raw,format=S16LE,channels=2,rate=48000",
               "!", "level", "interval=100000000", "post-messages=true",
               "!", "fakesink", "sync=false"]
        validate(kind.upper(), cmd, 2, expect_signal=(kind == "sine"))
    with tempfile.TemporaryDirectory(prefix="aleks-r319-dts-level-") as tmp:
        root = Path(tmp)
        archive = root / "r278.tar.gz"
        run([curl, "-fLsS", "--proto", "=https",
             "--connect-timeout", "6", "--max-time", "22",
             URL, "-o", str(archive)], timeout=27)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA:
            fail("RELEASE_ARCHIVE_SHA")
        print("R319_RELEASE_SHA256=PASS")
        with tarfile.open(archive, "r:gz") as tar:
            for kind, (name, digest, channels) in FIXTURES.items():
                member = tar.getmember(name)
                if not member.isfile() or not 0 < member.size < 250000:
                    fail("FIXTURE_MEMBER")
                with tar.extractfile(member) as inp:
                    payload = inp.read(250001)
                if len(payload) != member.size:
                    fail("FIXTURE_LENGTH")
                if hashlib.sha256(payload).hexdigest() != digest:
                    fail("FIXTURE_SHA")
                fixture = root / (kind.lower() + ".mka")
                fixture.write_bytes(payload)
                del payload
                print("R319_" + kind + "_FIXTURE_SHA256=PASS")
                cmd = [gst, "-m",
                       "filesrc", "location=" + str(fixture), "!",
                       "matroskademux", "!", "dtsdec", "!",
                       "audioconvert", "!",
                       "audio/x-raw,format=S16LE,channels=" + str(channels) +
                       ",rate=48000", "!",
                       "level", "interval=100000000", "post-messages=true",
                       "!", "fakesink", "sync=false"]
                validate(kind, cmd, channels, True)
    print("R319_PRODUCTION_TV_MODIFIED=NO")
    print("R319_REAL_TV_PCM_AMPLITUDE=UNMEASURED")
    print("RESULT=R319_ISOLATED_PCM_AMPLITUDE_GATE_PASS")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, KeyError, OSError, tarfile.TarError) as exc:
        print("R319_FAILED=" + str(exc).split(":", 1)[0][:110])
        sys.exit(2)
