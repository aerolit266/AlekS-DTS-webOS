# AlekS DTS R342 — source/ELF boundary and cold-audio evidence gate
Date: 2026-11-23 | Status: OFF-DEVICE forensic audit / NO-GO for deployment

## Verified input identity
- Official public R278 archive `downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz`
- SHA256 `cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1`.
- ARMv7 EABI5 ELF shared libraries:
  - `plugins/libgstaleksdts16dec.so`: SHA256 `dfefb960d49d50ed7629cc4459ffaae8b420509cc9815d8337f6be7faaac18cf` (matches previously verified installed physical kitchen TV R278).
  - `plugins/libgstaleksdts.so`: SHA256 `5c3b798d4c1109414efc9209276dbf8b23466376f72f5bc71cf4144f3f5a1cbb`.
- Role inspection based on `readelf -Ws` undefined imported functions and `strings` on the authentic release objects. Import absence is evidence of no direct dynamic import of those APIs; not proof of every possible indirect behavior.

## Exact R278 role separation, materially important for R341

`libgstaleksdts16dec.so` is a GStreamer bin wrapper (binary self-description: `AlekSDts16DecBin`, `aleks_dts16_dec_bin_init`; provenance string R239). Literal factory names found: `aleksdtsdec`, `audioconvert`, `capsfilter`. Output caps specify `audio/x-raw,format=S16LE`; it creates ghost pads and calls `gst_bin_add_many`, `gst_element_link_many` and `gst_element_factory_make`. It is **not** an independent DTS core decoder. It has **no direct imported GstEvent push/ref or proprietary OMX/decproxy resource-grant APIs**. This last observation does NOT prove what parent pipeline does.

`libgstaleksdts.so` is the real DTS software audio decoder using `gst_audio_decoder_set_output_format`, `gst_audio_decoder_allocate_output_buffer`, `gst_audio_decoder_finish_frame` and PCM info/channel layout APIs. Prior isolated actual LG R337 measured 94 decoded DTS frames, S16LE 2/6ch 48 kHz through a *fakesink*, with nonzero PCM RMS. These are actual isolated fixture results, NOT a live Starfish path result.

`libgstaleksdtscaps.so` is the input caps transform/mapping stage (`gst_base_transform`).

`GstOMXAc3DecBin`, the resource-bearing decoder in R339 native logs, is not implemented by the three R278 software plugins. Any R341 hardware grant-replay hook must live at a legitimate **uMS/decproxy hardware-child** integration point, not in the software decoder; the R341 detached GstPad simulation cannot establish such an integration hook.

## Owner-labelled real playback comparison (R334/R339, independent boot windows)

Owner labels:
- Cold first DTS in Lampa: silent.
- After AC3 → DTS: audible, without restart of UMS/Starfish/audiooutputd.

Both cold and recovered windows show real resource acquisitions, OMX AC3 decoder initialization and stream/caps activity. R334 cold contained 4 resource grants and 6 OMX AC3 initialization log lines; recovered contained 1 grant and 3 initialization log lines. These are log *counts*, not counts of successfully decoding DTS sessions.

R339 more precise cold: DTS audio/x-dts CAPS first appeared at 17:33:58.7523Z, grant 17:33:59.3210Z (~568.7ms later); second DTS CAPS 17:34:01.5037Z, grant 17:34:02.0776Z (~573.9ms later). Recovery: grant 17:44:00.691663Z, OMX AC3 init 17:44:00.703081Z, switch success 17:44:00.705286Z, followed by generic stream-start/caps, but **no fresh native DTS caps** logged in the same second. Therefore comparing early `audio/x-dts` CAPS with *generic* post-recovery CAPS does not prove same event traversed the same pad.

PulseAudio `pcm_output` reported RUNNING, S16LE, stereo, 48 kHz, one active sink-input routed to sink1 in both owner-labelled cold and recovered R334 snapshots. Same UMS and Starfish PIDs; route presence does **not** prove nonzero audio samples, hardware frames, unmuted output or healthy PCM sink.

**Missing decisive measurements, all UNVERIFIED:**
- Actual DTS decoder output PCM buffers/energy in owner-labelled cold-silent Starfish instance.
- Actual renderer/Realtek sink input PCM buffers/energy in that same live pipeline.
- Physical mute/UMI policies bound to the specific audio stream in both samples.
- Exact reason audio first becomes audible after AC3 → DTS.

## Decision and next physical proof

1. Do NOT replace R278, change ranks, inject arbitrary acquired-resource, modify OMX/UMS, trigger automatic AC3-toggle, or merge R341.
2. Keep existing R278 and the previously working manual recovery unchanged.
3. When explicitly permitted live read-only instrumentation is available, compare **same identified pipeline** in owner-labelled silent vs recovered states with bounded decoder-edge PCM samples, sink-edge PCM/clock and original-grant ACKs. No raw media bytes or audio samples stored. Use staged opt-in / reversible instrumentation, no implicit system restart.
4. If PCM nonzero at decoder but no buffers at sink, target decproxy post-caps child/link/segment. If PCM at sink but physically silent, target AudioD/Pulse/Realtek policy. If no PCM at decoder, target R278 decode initialization and actual selected child.
5. Previous attempt to execute a fresh read-only TV device command through the existing PC SDK was **blocked by tool safety**. No alternate TV access method attempted after this denial; device observation is presently blocked. TORMOZ hostname check alone passed; it does not imply current TV access.
6. R341 lab CI 20/20 and ASan/UBSan remain valid **only for artificial GStreamer pads**, not real decproxy or sound. Keep PR1 DRAFT/NO-GO.

## Files retained and changes
- Release ELF inspected OFF-DEVICE only; no firmware or TV modifications.
- Project record: `/opt/gamefree24-vps-mcp/src/aleks-dts-r342-audit/R342_FORENSIC_REPORT.md`.
- No proprietary code or personal audio/media contents copied into public repository. No actual DTS audio repair claimed.