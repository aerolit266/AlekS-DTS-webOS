# R323 — native kitchen LG R278: Matroska versus raw DTS source failure

Date: 2026-11-22. **STATUS: VERIFIED on real kitchen LG in isolated GStreamer; Lampa first-start causality is NOT VERIFIED.** No production change.

## Context

Owner confirmed the real `cold DTS silent -> AC3 -> DTS audible` fault in R318. In both real owner-confirmed states, the normal LS2, ALSA and native audio counters were essentially identical. R320 independently proved real installed R278 plugins can decode a public DTS test fixture into nonzero PCM using GStreamer `matroskademux`. This R323 test isolates the source packaging / first packet handling hypothesis.

## Exact input and hardware

- LG kitchen webOS 26, `uname -m=aarch64` kernel but decoder/media ELF32 ARM and GStreamer 1.24.10.
- Verified current four original installed R278 plugins against pinned hashes, 4/4. Verified original DTS stereo Matroska fixture SHA256 `7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae`.
- Exact **executed** source: [R323 probe pinned to tested revision](https://github.com/aerolit266/AlekS-DTS-webOS/blob/45a955e0e0f78bd5bc70c872cf7fe33f6e3b4c7e/tools/r323-native-dts-raw-fragmentation-probe.py), commit `45a955e0e0f78bd5bc70c872cf7fe33f6e3b4c7e`, SHA256 `04cc10240502363e07ef92678feae30b82df1823b0a1d55c68b1a1ef97228133`. Python syntax and x86 fail-closed architecture test PASS. [Mainline probe](../tools/r323-native-dts-raw-fragmentation-probe.py) may contain newer **untested** follow-ups.
- Existing authorized GameFree24 VPS MCP V3 -> Alex Core tasks -> TORMOZ -> device `aleks-kitchen-root`; no new bridge.
- On-device GitHub source hash independently verified. Native test task `4f709d9ab8a5779481d719671da4c896` COMPLETED exit0, final `RESULT=R323_NATIVE_RAW_DTS_FRAGMENTATION_DIFFERENTIAL_COMPLETE`. Prior initial-stage tasks `48b359e7f7c567f43be778a9686bf262` and frame-boundary task `b1f93a31d52913d00de9969ae2e29942` also completed exit0.
- Completely separate `gst-launch` child: private ephemeral `/tmp` GStreamer registry, child-only rank override `aleksdts16dec:350,decproxy:0`, no speaker output, only `level ! fakesink`. No live app, services, system mount or device audio controls modified.
- For raw source, `matroskademux` first extracted **only the public fixture's 96,256 bytes of encoded DTS** to a temporary file. The file contains **94 frame-start 0x7FFE8001 syncs at all 1024-byte boundaries**. The raw file was automatically deleted after the test. **No decoded PCM was stored**.

## Actual isolated native outcomes

| Source | Exit | Nonzero PCM windows | Decoder discovered | Error class |
|---|---:|---:|---|---|
| Original DTS Matroska, packets from matroskademux | **0** | **11/11** | AlekSDts16DecBin yes | none |
| Raw DTS filesrc blocksize=11 | 1 | 0 | yes | internal data stream error / reason error |
| Raw DTS filesrc blocksize=97 | 1 | 0 | yes | internal data stream error / reason error |
| Raw DTS filesrc blocksize=512 | 1 | 0 | yes | internal data stream error / reason error |
| Raw DTS filesrc blocksize=1024 (**one entire verified Core frame**) | 1 | 0 | yes | internal data stream error / reason error |
| Raw DTS filesrc blocksize=2048 | 1 | 0 | yes | internal data stream error / reason error |
| Raw DTS filesrc blocksize=4096 | 1 | 0 | yes | internal data stream error / reason error |
| Raw 1024 + `audio/x-dts,channels=2,rate=48000` | 1 | 0 | yes | internal data stream error / reason error |
| Raw 1024 + channels/rate + `framed=true` | 1 | 0 | yes | internal data stream error / reason error |

Matroska PCM: maximum RMS `-24.08 dBFS`, 11 consecutive active 100ms windows. Every raw-source case returned exit1 and no PCM. All diagnostics are allowlisted scalars; no private media, filenames/URLs from system logs or audio data recorded.

**Caution 1:** The presence of `AlekSDts16DecBin` in `gst-launch -v` proves discovery/construction in the test, but cannot prove correct parsing/dispatch of actual raw DTS data.

**Caution 2:** Raw DTS fails *even when buffers align exactly with all verified 1024-byte frame boundaries*. Thus **fragmentation alone is insufficient** to explain the specific raw-source failure. Merely adding channels, rate and `framed=true` also fails. One or more remaining differences between `matroskademux` and raw `filesrc` may include stream initial events (`STREAM_START`, `CAPS`, `SEGMENT`), timing/PTS and downstream codec framing/negotiation. The generic internal stream error does not identify the failing function.

**Caution 3:** We have not observed actual Lampa/Starfish DTS GstBuffers during the owner's first-silent state. Lampa may already deliver correctly packetized DTS Core. We **must not attribute** the real R318 first-silent defect to the isolated raw-source failure or deploy R312 blindly.

## Next engineering test and release gate

Build a stand-alone GStreamer 1.24-compatible native pad-probe harness with explicit known `STREAM_START -> CAPS -> SEGMENT(TIME) -> frames` vs byte-segment / wrong event ordering, retaining a private registry and `fakesink`, to narrow down initial-event and segment-format handling. The R312 experimental framer has already corrected a CAPS/SEGMENT ordering issue on VPS but was **not built/tested on kitchen 1.24.10**. ARM target compile needs a pinned compatible SDK/sysroot; no writable firmware or active service modification permitted. Only after this isolated parity test could a reversible, specifically authorized live first-start telemetry experiment be considered.

No production R278, `umediaserver.env`, TV service, kernel, rootfs, firmware, sound settings, Lampa config or receiver routing changed.

**R323 isolated raw-source failure: VERIFIED. R318 real cold DTS silence root cause: NOT VERIFIED. Permanent fix: NOT DEPLOYED.**

## Later unexecuted extension (do NOT mix with verified native result)

A later source revision at commit `36be5f2a2316d81fb4de50eacf108a28855cac3e`, SHA256 `6a2c2ddc7fc5cf98210a3df6587c6956e9244ecc1ce547b1ab87ed9b5fddad5b`, added three **new** raw-DTS cases using the stock `identity` element with `datarate`, `single-segment`, and both together, intended to distinguish timestamps/segment semantics from frame fragmentation. Python compilation PASS, and the temporary script SHA256 was verified on LG (task `9b50178f2940fe4cb5aaa03fb8a1af24`, exit0). **The attempt to launch the extended test was blocked by the remote execution safety system. No new identity test was performed. No alternate channel was used to bypass this block.** The temporary source was cleaned from TV through the established route; cleanup task `cb5eb4d6c068d76393bbaa2ee04a1f93`, exit0, marker `R323_TV_TMP_CLEAN_PASS`. The effective native test evidence remains the exact `45a955e` run detailed above.

**Interpretation unchanged:** The 1024-byte correctly aligned raw frames failed even with channel/rate/framed caps; whether this is caused by missing time PTS, SEGMENT/CAPS state, or another native integration issue remains **UNVERIFIED**. The actual owner's silent Lampa stream was **never sampled** in R323.
