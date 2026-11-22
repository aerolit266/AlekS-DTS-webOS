# R326 — real kitchen LG PulseAudio sink/ALSA provenance and non-recording PCM monitor

**Date:** 2026-11-22. **Actual hardware probe: VERIFIED.** **Initial DTS cold-silent root cause: NOT VERIFIED.** **Production R278: UNCHANGED.**

## Why the R318 ALSA cursor comparisons were non-discriminating

The owner has previously **confirmed** an actual Lampa cold first-DTS silence and an audible state after AC3→DTS on the same kitchen LG; see [R318](R318_REAL_KITCHEN_FIRST_SILENT_TO_AUDIBLE_PAIR_20261122.md). R318 reported identical ALSA PCM6 RUNNING/48kHz/cursor movement, one unmuted ADEC0→MAIN route, and 2 active streams in both stages, but **no sample amplitude was measured**. Do not mistake those counters for valid decoded DTS sound.

The **new read-only physical R326 check** identified that `/proc/asound/card0/pcm6p/sub0/status` `owner_pid=1246` belonged to task `alsa-sink-MARS`, with `Tgid=545` whose process name is **`pulseaudio`**, not `starfish-media-` or the AlekS DTS decoder. Exact PIDs are transient and are included only to explain the verified ownership. The final ALSA write cursor is advanced by the **PulseAudio sink thread** and can advance when mixed samples are digital zeros. Hence ALSA cursor movement is a **device pacing** check, not evidence of decoded PCM energy.

An additional `amixer -c 0 scontrols` read-only attempt returned `Operation not permitted`; no privilege, permissions, device node or kernel setting was changed to bypass this restriction.

## New read-only PulseAudio state telemetry (physical LG)

The existing `pactl 15.0.0` works via the authorized GameFree24 VPS MCP V3 → AlekS Core → TORMOZ → `aleks-kitchen-root` route.

At the time of the **unclassified** capture (owner had NOT confirmed either audible or silent DTS playback during this session), PulseAudio reported:

- One sink-input `#1`, pointing to active sink `#1`.
- The input was `s16le 2ch 48000Hz`, `Corked: no`, `Mute: no`, input volume **100%** on both channels.
- The corresponding `pcm_output` sink was `RUNNING`, `s16le 2ch 48000Hz`, `Mute: no` and sink volume **100%**.
- Two Starfish media processes were present; one mapped `libgstaleksdts16dec.so`. The `umediaserver`, `pulseaudio` and `audiooutputd` processes were present.
- PCM6 remained `RUNNING` and 48kHz S16LE stereo. In a 350 ms sampling interval, hardware cursor advanced around **17,000 frames**. The ALSA PCM6 owner was PulseAudio's `alsa-sink-MARS` thread.
- PulseAudio buffer and sink latency counters are collected as **transient measurements**, not as correctness criteria by themselves.

This evidence is **not a real first-DTS silent capture**, so it does not establish whether the PulseAudio sink-input is muted/corked or at 0% volume when the actual defect happens.

Tool: [tools/r326-passive-pulseaudio-alsa-snapshot.py](../tools/r326-passive-pulseaudio-alsa-snapshot.py), immutable tested revision `38038fb3f2237fbcfb4fcfd3c6b56057f71a4d00`, SHA256 `8cf1b47502a8586b127ec2f5d20a7a8eccd66c948b86217cfcb42a83399dee1c`. It prints only known PulseAudio state/volume/sample format/latency and ALSA process/PCM counters, without media names, URL, environment values, raw logs, or audio data.

## First real physical PCM amplitude measurement without audio recording

The standard `pactl list short sources` verified that the **physical audio sink** has a read-only monitor source `pcm_output.monitor`, provided by `module-alsa-sink.c`, format **S16LE/2ch/48000Hz**. This is **NOT a microphone**.

Created [tools/r326-pulse-monitor-energy.py](../tools/r326-pulse-monitor-energy.py), immutable tested revision `80c3c21236c84b75dc50475701dfb8fa8e88bcbf`, SHA256 `cd0c5a2688a888580624c4e4a064a2d6a76e9f60764065c0af38a7b5502d84a5`.

It establishes a short-lived, explicitly named output monitor client via `parec`, reads bounded S16LE bytes into RAM only, computes **aggregate RMS, peak, nonzero sample count**, immediately discards bytes, and outputs no audio content. It does not create audio files, send samples over SSH/network, start a microphone, modify volume, playback, mixer, settings, service or firmware. One capture is bounded to 0.8 s / at most 192,000 bytes / absolute 4-second read deadline and tears down its client. Note: the monitor covers the **entire post-PulseAudio mix**, which can include other application sounds, and is **before ALSA hardware**; it does not show actual per-DTS decoder output.

Physical LG test: SHA256 on LG PASS, `selftest` PASS, `RESULT=R326_MONITOR_AGGREGATE_ONLY_PASS`.

- First **unclassified** read: **70,060** PCM samples in 35,030 frames; **0 nonzero samples**; classification **DIGITAL_ZERO**.
- Second **unclassified** read in a bounded `before → PCM monitor → after` comparison: **72,108** samples in 36,054 frames; **0 nonzero samples**, classification **DIGITAL_ZERO**.
- In the same second comparison, both before and after `pactl` snapshots continued to show sink-input `#1` unmuted, uncorked, at **100%** stereo volume, sink `RUNNING` at 48 kHz. PCM6 remained `RUNNING`, and the ALSA cursor continued advancing around 17,000 frames/350 ms. The service and two Starfish processes were unchanged by the measurement.

**Technical conclusion:** it is empirically possible on this specific LG for the PulseAudio/ALSA sink to be RUNNING with an uncorked, unmuted 100%-volume sink-input and moving ALSA counters **while the mixed output is entirely zero**. This explains why the *kinds* of scalar measurements in R318 could not prove acoustic DTS. However, **the zero samples measured here were not owner-labeled as first-DTS silence or as playing a movie**; they could simply represent an idle or otherwise silent input. **No DTS defect was confirmed or fixed by this observation.**

A private allowlisted baseline record of one `before → monitor → after` trio is stored on the FI VPS under `/opt/gamefree24-vps-mcp/private/dts-r326-20261122/unclassified-pa-monitor-1315Z.json`, file permission 0600 in a 0700 folder, SHA256 `e8882a28a6f4f5861ce421a68ee03a40f9d0a12118476a3f4173e2a830c8ab5b`. No audio bytes or user media identifiers were stored.

## Reproducibility and fail-closed tests

- `r326-passive-pulseaudio-alsa-snapshot.py selftest`: known fields from synthetic PulseAudio output are parsed, unknown private media metadata are dropped; x86 trying to collect an ARM-only sample rejects; synthetic silent/audible comparison same-boot PASS and differing-boot comparison correctly refuses to compare. Synthetic labels were **never saved as genuine owner observations**.
- `r326-pulse-monitor-energy.py selftest`: 4096 synthetic zero samples correctly produce DIGITAL_ZERO; nonzero S16LE test produces expected RMS/peak, and the specific `pcm_output.monitor` source is allowed while a microphone is not. Non-ARM capture rejects.
- Public [GitHub Actions CI](../.github/workflows/dts-public-integrity.yml) now runs these **offline** R326 selftests alongside R322 hash/README integrity checks and R324 DTS packet cardinality. This tests code math and serialization; hardware-only `parec`/PulseAudio tests were done separately on the kitchen LG.

## What is required to determine the *real* DTS failure

The key available **non-invasive** same-TV comparison is now:

1. After a TV restart, the owner starts Lampa and selects DTS. **Only if it is genuinely silent**, label that stage `silent` based on owner listening; remotely run both pinned R326 probes once, saving only aggregate JSON. Do not switch tracks before the first snapshot.
2. The owner manually switches to AC3 and back to DTS, confirms audible sound and labels that stage `audible`. Remotely rerun both probes under the same boot and within 30 minutes.
3. Compare PulseAudio sink-input cork/mute/volume/format/sink identity and the post-PulseAudio-monitor RMS:
   - **Silent output PCM digital zero, recovered output PCM nonzero** with otherwise same sink/input: problem occurs at or before PulseAudio mix (decoder/Starfish delivery/resource/cork/mix); not evidence alone of which element was at fault.
   - Silent PCM nonzero while speakers inaudible: investigate **after** the monitor (ALSA/native hardware routing/speaker).
   - Silent stream corked, muted or volume 0 and recovered unmuted: investigate audio policy/handoff at PulseAudio.
   - Both signals zero: verify the film really played during each owner-labeled stage and whether the source is routed into `pcm_output`; the monitor may not be a trustworthy discriminator for that path.
4. First actual `STREAM_START`, `CAPS`, `SEGMENT` events inside native Starfish and actual *pre-PulseAudio* decoder PCM cannot be read from `/proc` or `pactl`. Those measurements require **separately authorized reversible pad instrumentation**. R325's isolated byte-to-time framer cannot be asserted to fix live Lampa until that input is known.

**Safety:** no TV reboot, restart, track switch, production plugin/registry/service/firmware/mixer/rootfs modification, permanent monitor process, microphone use, raw audio recording or playback control performed.

**R326 PulseAudio input metadata & PCM output monitor: VERIFIED on physical TV. Real cold-DTS silent-vs-audible PCM pair: NOT YET CAPTURED. Permanent production DTS fix: NOT DEPLOYED.**
