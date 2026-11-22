#!/usr/bin/env python3
"""R326: bounded non-recording PCM *level* measurement at PulseAudio output.

READ ONLY: opens only LG's pcm_output.monitor (a sink monitor, NOT microphone),
streams raw s16le/2ch/48k to a bounded in-memory counter, exports RMS/peak
and ZERO/nonzero aggregate ONLY. Audio bytes never enter stdout, disk, logs,
network, or saved files. Audio output settings/services are never changed.

This measures post-PulseAudio MIX, not AlekS decoder or speakers. Other app
sounds may be included; observation label is supplied by OWNER.
  python3 r326-pulse-monitor-energy.py measure unclassified|silent|audible
  python3 r326-pulse-monitor-energy.py selftest
"""
import array
import json
import math
import os
import platform
import re
import select
import subprocess
import sys
import time

MONITOR = "pcm_output.monitor"
SAMPLE_RATE = 48000
CHANNELS = 2
MAX_DURATION_SEC = 0.80
HARD_DEADLINE_SEC = 4.0
MAX_BYTES = SAMPLE_RATE * CHANNELS * 2
KNOWN_LABELS = ("unclassified", "silent", "audible")
EXPECTED_SOURCE = re.compile(
    r"^\d+\tpcm_output\.monitor\tmodule-alsa-sink\.c\ts16le 2ch 48000Hz\t[A-Z]+$"
)


def error(name):
    print("RESULT=R326_MONITOR_" + name)
    sys.exit(2)


def source_valid():
    try:
        p = subprocess.run(["pactl", "list", "short", "sources"],
                           check=False, capture_output=True, text=True,
                           errors="replace", timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return False
    if p.returncode or len(p.stdout) > 16000:
        return False
    matches = sum(EXPECTED_SOURCE.fullmatch(line.strip()) is not None
                  for line in p.stdout.splitlines())
    return matches == 1


def accumulator(chunks):
    total = nonzero = max_peak = 0
    square = 0
    for chunk in chunks:
        if len(chunk) > 8192 or len(chunk) % 4:
            raise ValueError("INVALID_SAMPLE_BLOCK")
        values = array.array("h")
        values.frombytes(chunk)
        for value in values:
            total += 1
            square += value * value
            if value:
                nonzero += 1
            if abs(value) > max_peak:
                max_peak = abs(value)
    if not total:
        return {"sample_count": 0, "classification": "NO_PCM_DATA"}
    mean_square = square / total
    rms = math.sqrt(mean_square)
    rms_db = None if rms == 0 else round(20 * math.log10(rms / 32768), 2)
    peak_db = None if max_peak == 0 else round(20 * math.log10(max_peak / 32768), 2)
    if nonzero == 0:
        status = "DIGITAL_ZERO"
    elif rms_db is not None and rms_db < -90:
        status = "VERY_LOW_LEVEL_NONZERO"
    else:
        status = "NONZERO_PCM"
    return {
        "sample_count": total, "frames": total // CHANNELS,
        "nonzero_sample_count": nonzero,
        "rms_dbfs": rms_db, "peak_dbfs": peak_db,
        "classification": status,
    }


def sample():
    if not source_valid():
        error("NO_PINNED_OUTPUT_SOURCE")
    cmd = ["parec", "--device=" + MONITOR, "--raw",
           "--format=s16le", "--channels=2", "--rate=48000",
           "--latency-msec=100"]
    try:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL,
                             stdin=subprocess.DEVNULL)
    except OSError:
        error("PAREC_UNAVAILABLE")
    fd = p.stdout.fileno()
    stream_started = time.monotonic()
    chunks = []
    size = 0
    try:
        while time.monotonic() - stream_started < HARD_DEADLINE_SEC:
            elapsed = time.monotonic() - stream_started
            if elapsed >= MAX_DURATION_SEC or size >= MAX_BYTES:
                break
            ready, _, _ = select.select([fd], [], [], min(0.25, MAX_DURATION_SEC-elapsed))
            if not ready:
                continue
            chunk = os.read(fd, min(8192, MAX_BYTES - size))
            if not chunk:
                break
            if len(chunk) % 4:
                error("MISALIGNED_PCM")
            chunks.append(chunk)
            size += len(chunk)
    finally:
        p.terminate()
        try:
            p.wait(timeout=2)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait(timeout=2)
        if p.stdout is not None:
            p.stdout.close()
    result = accumulator(chunks)
    if result["sample_count"] == 0:
        error("NO_PCM_SAMPLES")
    result["sample_rate"] = SAMPLE_RATE
    result["channels"] = CHANNELS
    result["source"] = "PULSE_AUDIO_OUTPUT_MONITOR_NOT_MIC"
    result["audio_files_created"] = 0
    result["raw_pcm_exported"] = False
    result["scope"] = "POST_PULSEAUDIO_MIX_PRE_ALSA_HARDWARE"
    return result


def selftest():
    assert sys.byteorder == "little"
    zeros = bytes(8192)
    r = accumulator([zeros])
    assert r["classification"] == "DIGITAL_ZERO"
    assert r["sample_count"] == 4096
    tone = array.array("h", [0, 8192, 0, -8192] * 200).tobytes()
    r = accumulator([tone])
    assert r["classification"] == "NONZERO_PCM"
    assert r["nonzero_sample_count"] == 400
    assert -18 < r["rms_dbfs"] < -17
    assert EXPECTED_SOURCE.fullmatch(
        "1\tpcm_output.monitor\tmodule-alsa-sink.c\ts16le 2ch 48000Hz\tIDLE")
    assert not EXPECTED_SOURCE.fullmatch(
        "2\tprecord\tmodule-null-source.c\ts16le 2ch 48000Hz\tIDLE")
    print("RESULT=R326_MONITOR_SELFTEST_PASS")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "selftest":
        selftest()
        return
    if len(sys.argv) != 3 or sys.argv[1] != "measure" or sys.argv[2] not in KNOWN_LABELS:
        error("BAD_ARGUMENTS")
    if platform.machine().lower() != "aarch64" or sys.byteorder != "little":
        error("NOT_EXPECTED_LG")
    result = sample()
    result["owner_observation"] = sys.argv[2]
    result["owner_observation_verified_by_microphone"] = False
    print("R326_MONITOR_METRICS=" + json.dumps(result,sort_keys=True,separators=(",",":")))
    print("RESULT=R326_MONITOR_AGGREGATE_ONLY_PASS")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        # No raw audio or app metadata in error.
        print("RESULT=R326_MONITOR_LAB_EXCEPTION_" + type(exc).__name__)
        sys.exit(2)
