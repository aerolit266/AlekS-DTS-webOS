# R319–R320 — actual decoded DTS PCM amplitude QA, not live Lampa

Date: **2026-11-22**. **Status: real kitchen LG isolated decoder RMS test PASS**. **Cold-silent Lampa root cause remains undetermined.** No production changes.

## R318 established the critical differential

On a single actual LG kitchen session the owner reported first DTS silent after reboot and audible DTS after manually switching to AC3 and back. Two immutable R317 captures three minutes apart both reported exactly the same production codec/route/running PCM6/policy/error fields, except for normal variation in ALSA pointer frame increments. The endpoint metadata and `snd_pcm` hw/app progress provide **no PCM signal amplitude**.

Private, permission-restricted owner-observed R318 snapshots remain on the FI VPS. Their raw content was not published. See [R318 report](R318_REAL_KITCHEN_FIRST_SILENT_TO_AUDIBLE_PAIR_20261122.md).

## Technical facts on the released chain

- Published R278 has four ELF32 ARM GStreamer libraries, and real DTS fixtures.
- `libgstaleksdts.so`: R56 `GstAudioDecoder` using libdcadec.
- `libgstaleksdts16dec.so`: R239 bin constructs `aleksdtsdec`, `audioconvert` and S16LE `capsfilter`.
- `libgstaleksdtsr130optin.so`: first-state parser / event guard around DTS input.
- In actual LG Lampa, R317 observed `ALSA_PCM6=RUNNING`, stereo S16_LE 48000Hz, source ADEC0→MAIN and muted=false at **both silent and audible stages**. This does not demonstrate whether actual PCM data are zero or whether output hardware drops nonzero samples.
- The stock [GStreamer `level` element](https://gstreamer.freedesktop.org/documentation/level/index.html) computes RMS and peak of incoming `audio/x-raw` and posts scalar messages. It can measure decoder output in an **isolated pipeline** without writing audio files. Inserting it into the live Starfish/Lampa path would require an authorized, tested integration; it is NOT possible merely by starting a separate `gst-launch` process.

## R319 — VPS isolated controls and real R278 release

Script [tools/r319-isolated-dts-pcm-amplitude-gate.py](../tools/r319-isolated-dts-pcm-amplitude-gate.py), GitHub commit `413d5bc8275a69cb8a13362205c8f2ec57b69448`, SHA256 `c79bce0631785503f2225b349a9df585fd1045ca316cf28a3fd954cc2c4dde94`.

- The exact published R278 archive SHA256 `cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1` and two DTS fixture SHA256s passed.
- Separate GStreamer 1.24.x x86 pipelines with `gst-launch -m ... level ... fakesink`:
  - 2-channel all-zero synthetic PCM control: **13 windows, 0 active**, max RMS **−700.00 dBFS**.
  - 2-channel sine control: **13 windows, 13 active**, max RMS **−4.95 dBFS**.
  - Real R278 DTS stereo decoded to S16LE: **11/11 active**, max RMS **−24.09 dBFS**.
  - Real R278 DTS 5.1 decoded to S16LE: **11/11 active**, max RMS **−28.82 dBFS**.
- `RESULT=R319_ISOLATED_PCM_AMPLITUDE_GATE_PASS`. Test/archive temporary files were removed. No raw PCM saved, no speaker output, no TV contacted in R319.

## R320 — real kitchen LG isolated decoder test

Script [tools/r320-kitchen-isolated-pcm-level.py](../tools/r320-kitchen-isolated-pcm-level.py), GitHub commit `b9ca388384e08afe4cd47da3a2afffa661d1a3de`, SHA256 `30db05d722e08759a3ab46f3401a26c4d3d28d642c358510b733b69002660b80`.

- VPS static: Python compile PASS, non-ARM guard PASS, isolated registry `GST_REGISTRY_1_0` and `fakesink` preflight PASS.
- Existing authorized GameFree24 VPS MCP V3 → Alex Core → TORMOZ → `aleks-kitchen-root`, **without new tunnel**. On-device downloaded immutable R320 SHA256 verified before running.
- Live R320 run task `82b3417a3bf0a3a978ea2225dc50781e`, COMPLETED exit0. Real installed four plugins **4/4 SHA256 PASS** and actual installed DTS stereo and 5.1 fixtures both SHA256 PASS.
- Isolated program started its **own** GStreamer process with `GST_PLUGIN_PATH_1_0` rooted at known system paths plus R278 plugins, **temporary private registry/cache**, rank override **only in that child's environment** `aleksdts16dec:350,decproxy:0`, `AlekSDts16DecBin` observed in both pipelines; `filesrc → matroskademux → queue → decodebin → audioconvert → S16LE → level → fakesink`.
- **LG stereo: 11/11 active 100ms level windows, maximum RMS −24.08 dBFS.**
- **LG DTS 5.1: 11/11 active, maximum RMS −28.81 dBFS.**
- `RESULT=R320_WEBOS26_ISOLATED_PCM_LEVEL_PASS`, `R320_LAMPA_LIVE_PIPELINE=NOT_OBSERVED`.
- The temporary script was removed from LG; cleanup task `81c3ae535c0b59129a217452c73cdedc` COMPLETED exit0, `R320_TV_TMP_CLEAN_PASS`. Isolated GStreamer registry/cache were automatically removed, no audio service restarted, no file in production install changed.

## What this eliminates, and what it doesn't

The installed R278 software decoder and actual webOS26 GStreamer stack **can decode the two verified DTS fixtures into nonzero PCM**. This rules out a categorical claim that R278 is permanently incapable of generating audible samples on that hardware. It **does not** disprove a transient first-start decode/wrapper/packet bug that occurs only in the Lampa/Starfish pipeline, nor a downstream sink/hardware handoff fault.

A decisive next test needs **scalar non-recording PCM energy telemetry on an actual first-silent Lampa session**, ideally at two checkpoints:

1. Immediately downstream of AlekS R56 decoder / R239 capsfilter (raw S16LE PCM before native output).
2. Immediately upstream of LG's native audio sink, **if a supported hook is proven available**.

If stage 1 is zero and later audible stage is nonzero, investigate compressed DTS input, first CAPS/SEGMENT, framing and decoder start. If stage 1 is nonzero while speakers silent, investigate native `audiooutputd`/ADEC0→MAIN handoff, mixer and route/mute below LS2. If samples are nonzero at the native sink entrance too, the fault is further downstream. These are conditional diagnostic outcomes, not established root causes.

**Gate:** There is no safe live pad/PCM energy readout via the previously collected ALSA `/proc` counters. A live tap would require separate reversible, privacy-preserving opt-in instrumentation with exact ABI verification and rollback; no rootfs, native library, driver, firmware or active service modification is authorized by this R319–R320 test. Keep production R278 unchanged.

**R319/R320 hardware/lab amplitude QA: VERIFIED. Live Lampa PCM amplitude: NOT VERIFIED. Permanent correction: NOT DEPLOYED.**
