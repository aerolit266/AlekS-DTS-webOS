# R325 — kitchen LG GStreamer 1.24 DTS Core framer: full native preview QA

**Date:** 2026-11-22. **Outcome:** experimental DTS Core BE16 framer with zero-origin BYTE→TIME segment normalization **PASS on physical kitchen LG**. **Production R278 unchanged.** This is a fix for the isolated R323 raw-source test, **NOT verified as a fix for the owner's Lampa first-DTS-after-reboot silence**.

## Why R325 exists

- Owner-confirmed [R318](R318_REAL_KITCHEN_FIRST_SILENT_TO_AUDIBLE_PAIR_20261122.md): on real LG kitchen, first DTS playback after a full reboot was silent. Switching to AC3 then back to DTS restored audible DTS. Audio route, mute, active streams and moving ALSA PCM6 cursors looked equivalent in the two captured states. **No live PCM amplitude or initial GStreamer event trace was taken from Lampa.**
- [R323](R323_REAL_LG_DTS_RAW_VS_MATROSKA_DIFFERENTIAL_20261122.md): real kitchen GStreamer pipeline with official R278 DTS Core Matroska fixture worked (11/11 PCM windows), while a raw `filesrc → decodebin` failed, even for correctly aligned DTS Core packet lengths and with extra caps. Generic stream errors alone did not show the cause.
- [R324](R324_DTS_DECODER_PACKET_CARDINALITY_20261122.md): shipped R56 handler invokes `dcadec_context_parse/filter` once per GstBuffer. Original decoder cannot decode partial frames or more than the first frame of a multi-frame input buffer in a single call. Reassembler required **if upstream packets are arbitrary chunks**, but this alone is not enough to explain R323 raw-source failures.

## Build provenance and source

The original [R312 framer source](../tools/r312-r188-framer-ordered-events.c) (SHA256 `9dfe39eddda78844d4234603530e6b76d64cc5d0806283d1be012f1811d19a30`) already assembles DTS Core complete frames and delays the first source SEGMENT until source CAPS. It previously passed off-TV tests on GStreamer 1.24.2.

The [R325 experiment](../tools/r325-r188-framer-time-segment-lab.c) (commit `ca9ca57fad31623230f33b6c9fc85d6685ba7312`, SHA256 `e5b615a6e17bb829df035800229dcf3c07a12a1c45066b91a8eeb4e197ae02ce`) adds exactly one bounded behavior to the R312 source:

- If initial upstream segment has `format=GST_FORMAT_BYTES`, `start=0`, `position=0`, `rate=1.0`, `applied_rate=1.0`, create a new **zero-origin `GST_FORMAT_TIME` segment** and forward it **after** actual output DTS CAPS, **before** the first complete DTS frame.
- Nonzero initial byte seeks and non-1.0 rates are **rejected**, not silently mapped to invented PTS. Already-TIME initial segments are forwarded.
- Encoded bytes, DTS frame length, downstream R278 libraries and PCM samples are otherwise unchanged.
- **Limitation:** subsequent SEEK / `FLUSH_STOP` / BYTE segment renegotiation, track changes and DTS-HD/extension handling are not yet hardware-validated for production use.

### ARM32 build and reproducibility

[tools/build-r325-armel-framer-lab.sh](../tools/build-r325-armel-framer-lab.sh) (commit `cea3811caa17ef0617bdc13f8f8f9162a038a29e`) is a fail-closed lab builder. It:

- Checks 3 immutable repo source/header SHA256 values before compiling; no latest/master floating inputs.
- Retrieves the ARMhf **GStreamer 1.24.2 development headers** from pinned Ubuntu package SHA256 `2813892aa616ead7d499100122fa034872b38ba998dde50fa2f89250f0477f1e`, and ARMEL **GLib 2.74.6 development headers** from Debian SHA256 `1175a6e446f8ea74975ecf709e29a675710a5108becbf28e7c623db971232a8d`. Everything extracts under a private temporary build dir using `dpkg-deb -x`; no `apt install`, system SDK or rootfs change.
- Uses `arm-linux-gnueabi-gcc -march=armv7-a -mfloat-abi=soft` and an explicitly supplied local **ARM EABI-compatible reference shared library directory** for strict `--no-undefined` linking. On VPS the reference directory was the audited historical OEM `/opt/lg-webos-epk/rootfs87-candidate/usr/lib` (legacy GStreamer1.16 sonames). This proves symbols and basic ABI; it does **not** make the reference libraries identical to the kitchen GStreamer 1.24.10 runtime.
- Exports a GStreamer plugin with **rank none (0)** and `gst_plugin_aleksdtsr188framer_get_desc`, never modifying GStreamer ranks for production. Output constrained to a private `/tmp/aleks-r325-*` directory with no overwrite.
- **Two independent full runs** (fresh source checkout and separate `mktemp` SDK directories), produced **byte-identical ELF**:
  - size **19,480 bytes**;
  - SHA256 **`c230709fcebe8175c254557a7c30858fe71219894a018aeac54cdd07ea6157f8`**;
  - ELF32, ARMv7, EABI5, soft-float; SONAME dependencies `libgstreamer-1.0.so.0`, `libgobject-2.0.so.0`, `libglib-2.0.so.0`, `libc.so.6`, ARM `ld-linux.so.3`.
- The manual initial ARM proof built using GLib 2.80 headers failed to link against the older reference GLib because `g_once_init_enter_pointer` was missing. Using pinned ARMEL GLib2.74 headers removed the incompatibility. No unverified hard-float binaries were installed or tested.

## Exact A/B test on real kitchen LG

Authorized existing GameFree24 VPS MCP V3 → Alex Core task queue → TORMOZ → `aleks-kitchen-root` route. No new SSH services/tunnels. Kitchen GStreamer **1.24.10**. The files were staged under private `/tmp/aleks-r325-*` only, decoded on-device from SHA-pinned base64, verified SHA256 before separate `gst-inspect-1.0` and Python `gst-launch` QA. No production library, service, `umediaserver.env`, systemd unit or firmware modified.

- **Original R312 ARM plugin** SHA256 `0fc2959e92fd4f93f810a74a5b87c3c3a1401b7b3b37d0c26885ee771d1d9d44`, 18,892 B, loaded and registered on actual TV with **rank none**. Official R278 Matroska baseline: **PASS, 11/11 nonzero PCM windows, RMS −24.08 dBFS**. Raw DTS stereo blocksize=1: **FAIL, 0 PCM windows, internal data stream error**. Exact script [r325-kitchen-isolated-framer-qa.py](../tools/r325-kitchen-isolated-framer-qa.py) initially ran source SHA `35454629ee5667a13f1032bb1090e89042e62653291bfcb868866413edb007f1`. No false PASS claimed.
- **R325 manually compiled TIME-segment candidate** SHA256 `e90242c3559e7d5586f8d64995a2b81dd0299cd67c38fb46f09af1caae5e8863`, 19,480 B, registered on physical TV. **8/8 real positive cases PASS** for blocks of 1,11,97,4096 bytes × DTS Stereo and 5.1, 11/11 nonzero PCM windows for each; max RMS exactly matched reference per track, **0 GStreamer warning tags**.
- **Final deterministic build** SHA256 `c230709fcebe8175c254557a7c30858fe71219894a018aeac54cdd07ea6157f8`, same 19,480 B and same source behavior but a canonical compiler-embedded source filename. Staged and SHA verified on TV. Final QA script commit `373bbee23758865db993b8010e879891da2d7c4c` SHA256 `ece5c343fef4b3de8de491d73a86eebc7efadb4f5b8f783835bb96317380b74a`. QA task `e040eb2adbc8e9df925589a72c47257d`, **COMPLETED exit0, explicit `RESULT=R325_REAL_LG_ISOLATED_FRAMER_QA_PASS`**.
- Final native QA verified **5/5 plugin SHA256 (4 shipped R278 + 1 lab R325)** and **2/2 published DTS fixture hashes**. Child-only GStreamer `GST_PLUGIN_PATH_1_0`, `GST_REGISTRY_1_0`, no global rank, no service environment changes, `level ! fakesink`, no speaker audio, no PCM recording or private movie data.

### Final physical test outcomes (deterministic R325 build)

| Real kitchen LG GStreamer 1.24.10 test | DTS Stereo 2.0 | DTS Core 5.1 |
|---|---|---|
| Matroska baseline with installed R278 | PASS, 11/11 active, −24.08 dBFS | PASS, 11/11 active, −28.81 dBFS |
| RAW block 1 byte → R325 → installed R278 | PASS, 11/11, −24.08 | PASS, 11/11, −28.81 |
| RAW block 11 bytes | PASS, 11/11, −24.08 | PASS, 11/11, −28.81 |
| RAW block 97 bytes | PASS, 11/11, −24.08 | PASS, 11/11, −28.81 |
| RAW block 4096 bytes | PASS, 11/11, −24.08 | PASS, 11/11, −28.81 |
| GStreamer warnings | 0 | 0 |
| Mutated first BE16 sync word | Fail closed PASS | Fail closed PASS |
| Truncated final frame at EOS | Fail closed PASS | Fail closed PASS |

**All 8/8 positive and all 4/4 negative native tests passed** with the exact reproducible binary. Source files and encoded public fixture temp files were never written to production areas. The test did not produce sound through the TV (sink was always `fakesink`).

## What the evidence supports

**Confirmed for isolated R323:** changing the initial BYTE segment to a TIME segment while retaining the existing bounded R312 frame assembly **causes a previously failing raw-source DTS pipeline to decode correctly on the physical kitchen LG**, including arbitrary fragmentation and multi-frame buffers. This strongly identifies byte/time segment mismatch as the source of the **isolated raw GStreamer test failure**, while also covering packet boundaries.

**Not confirmed for actual owner's Lampa first-DTS-silent defect:** The real first-start Lampa/Starfish pipeline's upstream segment format, first DTS timestamps, frame boundaries and PCM energy were **not observed**. It may already receive TIME segments or correctly framed packets. We cannot claim the user-facing initial silence is fixed from this isolated success.

**Production gate:** the experimental plugin remains **rank none** and is not integrated into Lampa/Starfish, installed into the system plugin directory, enabled in `umediaserver.env`, or reboot-tested. Before an explicit opt-in deployment, require (1) real cold-silent native event/PCM telemetry with privacy-safe scalar logging, (2) seek/flush/reconnect and AC3/5.1 regressions, (3) backup and atomic rollback, (4) approved user-visible install with no firmware/rootfs replacement.

**R325 isolated native QA: VERIFIED; reproducible ARM build: VERIFIED; user-facing first-DTS fix: NOT VERIFIED / NOT DEPLOYED.**
