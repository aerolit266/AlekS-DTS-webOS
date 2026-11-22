#!/usr/bin/env python3
"""R306 — actual DTS Core packet-boundary regression (VPS/offline only).

Generate two short original test signals in FFmpeg and encode with its
experimental DTS Core encoder. Check FFprobe packet timestamps, compare
FFmpeg-decoded PCM against GStreamer dtsdec raw-byte and packetized-Matroska
paths at multiple filesrc block sizes. No ALSA, PulseAudio, LG, SSH, internet,
installation, original R122 test files or production media.
"""
import array
import hashlib
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

GSTREAMER_BLOCKS = (11, 97, 4096)
SAMPLE_RATE = 48000
THRESHOLD = 128


def run(args, timeout=28):
    res = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                         check=False)
    if res.returncode:
        error = (res.stderr or res.stdout)[-1800:]
        raise RuntimeError(f"R306_TOOL_FAIL rc={res.returncode} exe={Path(args[0]).name}: {error}")
    return res.stdout


def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for buf in iter(lambda: f.read(1 << 16), b""):
            h.update(buf)
    return h.hexdigest()


def pcm_stats(path, channels):
    raw = path.read_bytes()
    if not raw or len(raw) % (channels * 2):
        raise ValueError("PCM_ZERO_OR_MISALIGNED")
    # The lab host is little-endian x86_64. Convert explicitly if ported.
    vals = array.array("h")
    vals.frombytes(raw)
    if sys.byteorder != "little":
        vals.byteswap()
    frames = len(vals) // channels
    per_channel = []
    for ch in range(channels):
        track = vals[ch::channels]
        peak = max(abs(x) for x in track)
        rms = math.sqrt(sum(x*x for x in track) / frames)
        first = next((i for i, x in enumerate(track) if abs(x) > THRESHOLD), None)
        per_channel.append({
            "peak_s16": peak,
            "rms_s16": round(rms, 3),
            "first_above_128_frame": first,
        })
    return {"frames": frames, "bytes": len(raw), "sha256": sha(path),
            "channels": per_channel}


def make_stream(root, name, channels):
    dts = root / (name + ".dts")
    if channels == 2:
        signal = "sine=frequency=440:sample_rate=48000:duration=1.5"
        bitrate = "768k"
    else:
        signal = (
            "aevalsrc=0.07*sin(2*PI*330*t)|0.07*sin(2*PI*440*t)|"
            "0.07*sin(2*PI*550*t)|0.07*sin(2*PI*110*t)|"
            "0.07*sin(2*PI*660*t)|0.07*sin(2*PI*770*t):"
            "s=48000:d=1.536:channel_layout=5.1(side)"
        )
        bitrate = "1536k"
    run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
         "-f", "lavfi", "-i", signal, "-ac", str(channels),
         "-ar", str(SAMPLE_RATE), "-c:a", "dca", "-strict", "-2",
         "-b:a", bitrate, "-f", "dts", str(dts)])
    raw_info = json.loads(run([
        "ffprobe", "-v", "error", "-show_entries",
        "stream=codec_name,channels,sample_rate:format=size",
        "-of", "json", str(dts)]))
    stream = raw_info["streams"][0]
    if (stream["codec_name"] != "dts" or int(stream["channels"]) != channels
            or int(stream["sample_rate"]) != SAMPLE_RATE):
        raise ValueError("NOT_EXPECTED_REAL_DTS")
    mka = root / (name + ".mka")
    run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
         "-f", "dts", "-i", str(dts), "-map", "0:a:0",
         "-c:a", "copy", "-f", "matroska", str(mka)])
    pkt_info = json.loads(run([
        "ffprobe", "-v", "error", "-select_streams", "a:0",
        "-show_entries", "packet=pts,duration,size", "-of", "json", str(mka)]))
    packets = pkt_info.get("packets", [])
    pts = [int(p["pts"]) for p in packets]
    if (len(packets) < 60 or pts[0] != 0
            or any(a >= b for a, b in zip(pts, pts[1:]))
            or any(int(p["size"]) <= 0 or int(p["duration"]) <= 0 for p in packets)):
        raise ValueError("PACKET_PTS_OR_DURATION_BAD")
    ff_pcm = root / (name + "-ff.raw")
    run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
         "-f", "dts", "-i", str(dts), "-f", "s16le",
         "-c:a", "pcm_s16le", "-ac", str(channels),
         "-ar", str(SAMPLE_RATE), str(ff_pcm)])
    reference = pcm_stats(ff_pcm, channels)
    if reference["frames"] < 60000:
        raise ValueError("FFMPEG_DECODE_TOO_SHORT")
    if any(v["peak_s16"] < 300 or v["first_above_128_frame"] is None
           or v["first_above_128_frame"] > 2048
           for v in reference["channels"]):
        raise ValueError("FFMPEG_REFERENCE_NO_SIGNAL")
    return dts, mka, packets, reference


def gst_decode(root, name, source, channels, blocksize, variant, repeat=0):
    filename = root / f"{name}-{variant}-{blocksize}-r{repeat}.raw"
    args = ["gst-launch-1.0", "-q",
            "filesrc", f"location={source}", f"blocksize={blocksize}", "!"]
    if variant == "packetized":
        args += ["matroskademux", "!"]
    args += ["dtsdec", "!", "audioconvert", "!",
             f"audio/x-raw,format=S16LE,channels={channels},rate={SAMPLE_RATE}",
             "!", "filesink", f"location={filename}"]
    run(args, timeout=30)
    return pcm_stats(filename, channels)


def gst_avdec_packetized(root, name, source, channels):
    filename = root / (name + "-gstreamer-avdec.raw")
    args = ["gst-launch-1.0", "-q", "filesrc",
            f"location={source}", "blocksize=11", "!",
            "matroskademux", "!", "avdec_dca", "!",
            "audioconvert", "!",
            f"audio/x-raw,format=S16LE,channels={channels},rate={SAMPLE_RATE}",
            "!", "filesink", f"location={filename}"]
    run(args, timeout=30)
    return pcm_stats(filename, channels)


def compare_one(name, channels, root):
    dts, mka, packets, ff = make_stream(root, name, channels)
    raw, packetized = {}, {}
    for block in GSTREAMER_BLOCKS:
        raw[block] = gst_decode(root, name, dts, channels, block, "raw")
        packetized[block] = gst_decode(root, name, mka, channels, block, "packetized")
    expected = packetized[4096]
    if expected["frames"] != ff["frames"] or expected["frames"] < 60000:
        raise ValueError(f"{name}_PACKETIZED_LENGTH_DISAGREES_WITH_FFMPEG")
    # Re-segmenting the *container bytes* must not change decoded PCM,
    # not merely its size. Mux copies the original DTS packets unchanged.
    for block in GSTREAMER_BLOCKS:
        item = packetized[block]
        if item["bytes"] != expected["bytes"] or item["sha256"] != expected["sha256"]:
            raise ValueError(f"{name}_PACKETIZED_BLOCK_{block}_PCM_MISMATCH")
    # Raw byte chunking may *lose* frames with dtsdec, which accepts already
    # packetized frames rather than arbitrary partial bytes on this runtime.
    raw_differences = {}
    for block in GSTREAMER_BLOCKS:
        item = raw[block]
        raw_differences[str(block)] = {
            "frames": item["frames"],
            "lost_vs_packetized": expected["frames"] - item["frames"],
            "pcm_sha_matches_packetized": item["sha256"] == expected["sha256"],
        }
    if raw[4096]["sha256"] != expected["sha256"]:
        raise ValueError(f"{name}_BASELINE_RAW4096_NOT_ALIGNED_WITH_PACKETIZED")
    for block in (11, 97):
        again = gst_decode(root, name, dts, channels, block, "raw", repeat=1)
        raw_differences[str(block)]["second_run_frames"] = again["frames"]
        raw_differences[str(block)]["repeat_pcm_sha_same"] = (
            again["sha256"] == raw[block]["sha256"])
    avdec = gst_avdec_packetized(root, name, mka, channels)
    if avdec["frames"] != expected["frames"]:
        raise ValueError(f"{name}_INDEPENDENT_GSTREAMER_AVDEC_FRAME_COUNT_MISMATCH")
    if any(x["peak_s16"] < 100 or x["first_above_128_frame"] is None
           for x in avdec["channels"]):
        raise ValueError(f"{name}_AVDEC_NO_SIGNAL")

    # Verify comparable per-channel signal without assuming exact PCM
    # identity across FFmpeg and libdca/GStreamer.
    for ch in range(channels):
        a = ff["channels"][ch]
        b = expected["channels"][ch]
        if (a["rms_s16"] <= 0 or b["rms_s16"] <= 0
                or abs(a["rms_s16"] - b["rms_s16"]) / a["rms_s16"] > 0.08
                or abs(a["first_above_128_frame"] - b["first_above_128_frame"]) > 32):
            raise ValueError(f"{name}_CHANNEL_{ch}_SIGNAL_MISMATCH")
    repeated = gst_decode(root, name, mka, channels, 11, "packetized", repeat=1)
    if repeated["sha256"] != expected["sha256"]:
        raise ValueError(f"{name}_REOPEN_NOT_DETERMINISTIC")
    return {
        "codec": "DTS Core encoded by local FFmpeg dca experimental",
        "channels": channels, "rate": SAMPLE_RATE,
        "encoded_bytes": dts.stat().st_size,
        "encoded_sha256": sha(dts),
        "matroska_packets": len(packets),
        "matroska_first_packet_size": int(packets[0]["size"]),
        "ffmpeg_pcm_frames": ff["frames"],
        "gstreamer_packetized_frames": expected["frames"],
        "packetized_sha256": expected["sha256"],
        "packetized_all_3_blocks_identical": True,
        "repeat_first_start_11_block_identical": True,
        "gstreamer_avdec_dca_packetized_frames": avdec["frames"],
        "gstreamer_avdec_dca_sha256": avdec["sha256"],
        "raw_bytestream": raw_differences,
        "packetized_signal": expected["channels"],
        "ffmpeg_signal": ff["channels"],
    }


def main():
    for tool in ("ffmpeg", "ffprobe", "gst-launch-1.0"):
        if not shutil.which(tool):
            raise SystemExit(f"R306_BLOCKED_MISSING_TOOL={tool}")
    with tempfile.TemporaryDirectory(prefix="aleks-r306-real-dts-") as temp:
        root = Path(temp)
        result = {
            "schema": "aleks.dts.r306.raw-vs-packetized.v1",
            "environment": "isolated host, no audio output devices",
            "runtime": {
                "ffmpeg": run(["ffmpeg", "-version"]).splitlines()[0],
                "gstreamer": run(["gst-launch-1.0", "--version"]).splitlines()[0],
            },
            "streams": {
                "stereo": compare_one("stereo", 2, root),
                "surround": compare_one("surround", 6, root),
            },
            "actual_dts_bitstreams_used": True,
            "actual_dts_to_pcm_decoding_tested": True,
            "real_lg_tested": False,
            "kitchen_r278_production_decoding_tested": False,
            "first_silent_session_root_cause_proven": False,
        }
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        print("RESULT=R306_REAL_DTS_PACKET_BOUNDARY_QA_PASS; "
              "LIVE_LG_R278_UNTESTED")
    # All encoded/PCM buffers are temporary and cleaned before exit.


if __name__ == "__main__":
    main()
