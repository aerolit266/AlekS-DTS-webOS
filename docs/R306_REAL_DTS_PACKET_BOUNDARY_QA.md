# R306 — Real DTS Core packet-boundary regression (2026-11-22)

**Status: OFFLINE VERIFIED, LG NOT TESTED.** Reproducer: [test-real-dts-packet-boundaries-r306.py](../tools/test-real-dts-packet-boundaries-r306.py), GitHub commit 92a9f1a8b170474f878d509179df5f9197a7fbc5, SHA256 129faf0b276df085e4e5e6f43fd99d64495e616d3be69538619d09c5def2ae24.

## What was actually tested

On Finnish VPS mediarus.com, FFmpeg 6.1.1-3ubuntu5+esm15 generated two short **real DTS Core** streams from original tone signals, using its experimental dca encoder. FFprobe verified codec=dts, sample rate 48000 Hz and 2/6 channels. No movie/audio tracks were copied. GStreamer 1.24.2 with dtsdec, avdec_dca and matroskademux decoded the generated data to **temporary PCM files**, with no audio speaker output.

| Source | Stereo | 5.1(side) |
| --- | ---: | ---: |
| Encoded raw DTS bytes | 144384 | 294912 |
| Losslessly remuxed Matroska DTS packet count | 141 | 144 |
| FFmpeg decoded PCM frames | 72192 | 73728 |
| GStreamer dtsdec with Matroska PCM frames | 72192 | 73728 |
| GStreamer avdec_dca with Matroska PCM frames | 72192 | 73728 |
| First substantial PCM sample on typical channels | frame 513-514 | frame 513-514 |
| 5.1 LFE first substantial PCM sample | n/a | frame 386 |

FFmpeg PCM and GStreamer PCM were independently decoded; exact inter-decoder PCM bytes need not match. Comparisons required matching frame counts, nonzero per-channel audio samples, comparable RMS within 8%, and comparable first-signal timing.

## Raw DTS byte chunks: decoder can lose samples

With pipeline:

    filesrc blocksize=N ! dtsdec ! audioconvert ! audio/x-raw,... ! filesink

Changing the **source read block size alone** reduced the resulting PCM length and sometimes changed the PCM content, even though GStreamer exited with code 0. Examples from the verified release script:

| Stream | Raw block 11, first / second run | Raw block 97, first / second run | Raw block 4096 |
| --- | --- | --- | --- |
| Stereo | 61952 / 61440 frames | 70656 / 70656 | 72192 frames |
| 5.1 | 64512 / 69632 | 72704 / 72704 | 73728 |

Other manual repeated runs also produced different deficits for 11- and 97-byte chunks. **The amount of loss is not deterministic**, but incomplete PCM output is reproducible in this software environment. An earlier attempt to insert a nonfixed audio/x-dts capsfilter before dtsdec caused a separate caps-negotiation failure; the functioning raw pipeline above omitted that filter.

## The same DTS, correctly packetized: full output at every source block size

Identical encoded DTS frames were copied without re-encoding to Matroska audio-only files, then decoded through:

    filesrc blocksize=N ! matroskademux ! dtsdec ! audioconvert ! audio/x-raw,... ! filesink

At input blocks 11, 97 and 4096 bytes, **all decoded PCM outputs were complete and byte-identical within each stream**. Repeating the 11-byte block test with a fresh decode process also produced the identical SHA256.

| Stream | Matroska block 11 | 97 | 4096 |
| --- | ---: | ---: | ---: |
| Stereo | 72192 frames | 72192 | 72192 |
| 5.1 | 73728 frames | 73728 | 73728 |

Decoded PCM SHA256s for every Matroska block size:
- Stereo: 27ee5b511b02bab7d7e0d8ea07649187e604ddff592d5af59fb9312b87ae7ffc
- 5.1: 6e1df37b806348469fbccec818474153c0c79ee65e72568efa9beb88aadf9c9d

Separately, packetized GStreamer avdec_dca returned the same full frame counts. GStreamer dtsparse was NOT installed in this VPS environment. The results are consistent with dtsdec needing properly delineated compressed input frames; raw arbitrary byte splits are not a valid substitute for proper packetization.

## Exact repeatable procedure

Run the [R306 Python 3 test](../tools/test-real-dts-packet-boundaries-r306.py) on an isolated Linux test host equipped with FFmpeg dca experimental encoder, ffprobe, gst-launch-1.0 and the named GStreamer elements. It checks genuine codec identity, monotonic timestamped Matroska packets, independent FFmpeg/GStreamer PCM, per-channel signal, packetized SHA256 across block sizes and replay, and reports raw-input deficits independently. All media and PCM are generated into a temporary directory and cleaned after testing.

Verified on VPS using the immutable code commit and SHA256 above:

    RESULT=R306_REAL_DTS_PACKET_BOUNDARY_QA_PASS; LIVE_LG_R278_UNTESTED

## Limitations and follow-up

This is a **software-only laboratory finding**. The kitchen LG's Starfish pipeline, actual installed R278 decoder/renderer, input DTS packetization and first silent playback have NOT been measured by this test. It would be an overclaim to say that the user's intermittent original DTS silence was caused by the observed VPS issue.

Before modifying R278, verify on the actual kitchen TV **read-only** that partially framed DTS buffers are reaching the decoder, and compare buffer framing/packet flags, initial PCM production and LG native sink allocation during silent and audible sessions. Do not install the experimental R188 framer, change ranks, restart audio services or force audio-track toggles on the basis of this offline correlation alone.

No production firmware, LG, TORMOZ, SSH bridge, active media or system package installation was changed in R306. No physical speakers were tested.
