#!/usr/bin/env python3
"""R352: strict AC3 passthrough/F32LE 5.1 verifier regression (offline only)."""
from pathlib import Path
import hashlib
import re
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "install-universal.sh"
R278 = ROOT / "downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz"
R278_SHA = "cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1"

PARSE = ("/GstPipeline:pipeline0/GstDecodeBin:decodebin0/GstAc3Parse:ac3parse0.GstPad:src: "
         "caps = audio/x-ac3, framed=(boolean)true, rate=(int)48000, channels=(int)6, alignment=(string)frame")
DECODER = ("/GstPipeline:pipeline0/GstDecodeBin:decodebin0/avdec_ac3:avdec_ac3-0.GstPad:src: "
           "caps = audio/x-raw, format=(string)F32LE, layout=(string)non-interleaved, "
           "rate=(int)48000, channels=(int)6, channel-mask=(bitmask)0x0000000000000c0f")
F32 = ("/GstPipeline:pipeline0/GstFakeSink:fakesink0.GstPad:sink: "
       "caps = audio/x-raw, format=(string)F32LE, layout=(string)non-interleaved, "
       "rate=(int)48000, channels=(int)6, channel-mask=(bitmask)0x0000000000000c0f")
S8 = ("/GstPipeline:pipeline0/GstFakeSink:fakesink0.GstPad:sink: "
      "caps = audio/x-raw, format=(string)S8, layout=(string)interleaved, "
      "rate=(int)48000, channels=(int)1, channel-mask=(bitmask)0x0000000000000000, "
      "mode:passthrough, codec_type=(string)AC3")
EOS = 'Got EOS from element "pipeline0".'

def required(ok, name):
    if not ok:
        raise AssertionError(name)

def shell(args, **kwargs):
    return subprocess.run(args, capture_output=True, timeout=8, **kwargs)

def patch_actual_r278(src):
    blocks = [
        (r"cat > platform.universal <<'PLATFORM'\n(.*?)\nPLATFORM",
         r"awk -v replacement=platform.universal '(.*?)' install.sh > install.patched"),
        (None, r"awk '\n(.*?)\n' install.patched > install.timeout-patched"),
        (r"cat > ac3.compat <<'AC3'\n(.*?)\nAC3",
         r"awk -v replacement=ac3.compat '(.*?)' install.patched > install.ac3-patched"),
    ]
    with tempfile.TemporaryDirectory(prefix="r352-real-r278-") as w:
        folder = Path(w)
        with tarfile.open(R278, "r:gz") as tf:
            pristine = tf.extractfile("install.sh").read()
        (folder / "install.sh").write_bytes(pristine)
        last = pristine
        ac3_snippet = None
        for i, (head, awkpat) in enumerate(blocks):
            if head:
                m = re.search(head, src, re.S)
                required(bool(m), f"MISSING_HEREDOC_{i}")
                filename = ["platform.universal", None, "ac3.compat"][i]
                (folder / filename).write_text(m.group(1) + "\n")
                if i == 2:
                    ac3_snippet = m.group(1)
            awkmatch = re.search(awkpat, src, re.S)
            required(bool(awkmatch), f"MISSING_AWK_{i}")
            prev = "install.sh" if i == 0 else "install.patched"
            (folder / prev).write_bytes(last)
            args = (["awk", "-v", "replacement="+("platform.universal" if i == 0 else "ac3.compat"),
                     awkmatch.group(1), prev] if i != 1
                    else ["awk", awkmatch.group(1), prev])
            res = shell(args, cwd=w)
            required(res.returncode == 0, f"PATCH_AWK_{i}_{res.stderr[:200]}")
            last = res.stdout
            required(shell(["sh", "-n"], input=last).returncode == 0, f"PATCH_SYNTAX_{i}")
        required(last.count(b"check_ac3() {") == 1 and last.count(b"    check_ac3\n") == 1, "AC3_PATCH_COUNT")
        required(b"    check_clip ac3-51 S8 1 " not in last, "OLD_AC3_GATE_STILL_ACTIVE")
        required(last.count(b'    check_clip dts-stereo S16LE 2 ') == 1, "DTS_STEREO_MISSING")
        required(last.count(b'    check_clip dts-51 S16LE 6 ') == 1, "DTS_51_MISSING")
        for guard in (b"verify_pipeline", b"verify_files", b"before_matches",
                      b"rollback", b"replace_config", b"sha256sum"):
            required(guard in last, "SAFETY_MISSING_" + guard.decode())
        required((folder / "install.sh").read_bytes() == pristine, "R278_PRISTINE_CHANGED")
        # Source cardinality: reject missing expected AC3 call and duplicates.
        ac3awk = re.search(blocks[2][1], src, re.S).group(1)
        for damaged in (
            last.replace(b"    check_ac3\n", b"    nothing\n"),
            last + b"\n    check_clip ac3-51 S8 1 0x0000000000000000\n"
                   + b"    check_clip ac3-51 S8 1 0x0000000000000000\n",
        ):
            (folder / "install.patched").write_bytes(damaged)
            bad = shell(["awk", "-v", "replacement=ac3.compat",
                         ac3awk, "install.patched"], cwd=w)
            required(bad.returncode != 0, "R352_UNEXPECTED_SOURCE_ACCEPTED")
        print("R352_REAL_R278_INTEGRITY_SYNTAX_CARDINALITY_PASS")
        return ac3_snippet

def test_logs(snippet):
    baseline = "\n".join((PARSE, DECODER, F32, EOS)) + "\n"
    valid_cases = [
        ("decoded-f32le", baseline, "decoded-F32LE-5.1"),
        ("passthrough-s8", "\n".join((S8, EOS)) + "\n", "(passthrough)"),
    ]
    invalid = [
        ("no-eos", baseline.replace(EOS, ""), None),
        ("wrong-rate", baseline.replace("rate=(int)48000", "rate=(int)44100"), None),
        ("wrong-channels", baseline.replace("channels=(int)6", "channels=(int)2"), None),
        ("wrong-mask", baseline.replace("0x0000000000000c0f", "0x0000000000000003"), None),
        ("interleaved", baseline.replace("non-interleaved", "interleaved"), None),
        ("no-parser", baseline.replace(PARSE, ""), None),
        ("no-ac3-decoder", baseline.replace(DECODER, ""), None),
        ("wrong-decoder", baseline.replace("avdec_ac3", "avdec_dca"), None),
        ("dts-plugin-chosen", baseline+"AlekSDts16DecBin: unexpected\n", None),
        ("unknown-format", baseline.replace("F32LE", "S32LE"), None),
        ("passthrough-wrong-codec", "\n".join((S8.replace("codec_type=(string)AC3", "codec_type=(string)DTS"), EOS))+"\n", None),
        ("passthrough-wrong-channels", "\n".join((S8.replace("channels=(int)1", "channels=(int)6"), EOS))+"\n", None),
    ]
    with tempfile.TemporaryDirectory(prefix="r352-ac3-log-qa-") as w:
        folder = Path(w)
        for name, log, expected in valid_cases + invalid:
            logpath = folder / (name + ".txt")
            logpath.write_text(log)
            # Feed exact stdout as synthetic GStreamer trace, never run real devices.
            prologue = """
set -eu
work="$1"
directory="$1"
AC3_QA_LOG="$2"
AC3_QA_EXIT="$3"
fail() { printf 'ERROR: %s\\n' "$*" >&2; exit 71; }
run_gst() { cat "$AC3_QA_LOG"; return "$AC3_QA_EXIT"; }
"""
            program = prologue + snippet + "\n"
            out = shell(["sh", "-c", program, "r352", w, str(logpath), "0"])
            if expected:
                required(out.returncode == 0 and expected.encode() in out.stdout,
                         f"POSITIVE_{name}: {out.stderr!r}")
            else:
                required(out.returncode != 0 and b"PASS ac3-51" not in out.stdout,
                         f"NEGATIVE_{name}_ACCEPTED")
        fail_log = folder / "pipeline-failure.log"
        fail_log.write_text(baseline)
        prologue = """
set -eu
work="$1"
directory="$1"
AC3_QA_LOG="$2"
AC3_QA_EXIT="$3"
fail() { printf 'ERROR: %s\\n' "$*" >&2; exit 71; }
run_gst() { cat "$AC3_QA_LOG"; return "$AC3_QA_EXIT"; }
"""
        out = shell(["sh", "-c", prologue+snippet+"\n", "r352", w,
                     str(fail_log), "23"])
        required(out.returncode != 0, "FAILED_PIPELINE_WAS_ACCEPTED")
    print("R352_AC3_VALID_2_OF_2_PASS")
    print("R352_AC3_NEGATIVE_13_OF_13_PASS")

def main():
    src = SRC.read_text()
    required(hashlib.sha256(R278.read_bytes()).hexdigest() == R278_SHA,
             "PINNED_R278_SHA_MISMATCH")
    required("RESULT=R352_%s_PASS" in src and "R352 %s failed" in src,
             "R352_OUTCOME_STATUS_MISSING")
    required(shell(["sh", "-n"], input=src.encode()).returncode == 0,
             "WRAPPER_SHELL_BAD")
    test_logs(patch_actual_r278(src))
    print("RESULT=R352_STRICT_AC3_OFFDEVICE_PASS_NO_INSTALL")

if __name__ == "__main__":
    main()