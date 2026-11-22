# R311–R312: real DTS Core frame recovery and ordered GStreamer events

Date: 2026-11-22. Status: ISOLATED VPS LAB VERIFIED. Kitchen LG webOS26: NOT TESTED and NOT MODIFIED.

## Why this matters

The owner reproduced kitchen DTS after reboot: first DTS selected but no sound, AC3 selected and audible, then DTS selected again and audible. That is a genuine user-observed behavior, but neither input packet boundaries nor first PCM/sink state were captured while silent.

R306/R307 confirmed that VPS stock GStreamer dtsdec loses part of decoded PCM if given raw DTS as arbitrary 11/97-byte input buffers. The same encoded bytes passed through Matroska demux produce complete PCM. That observation does not prove identical behavior on the kitchen LG.

R311/R312 answer a narrower and useful engineering question: can the already-developed R188 bounded frame assembler eliminate this lab loss and deliver correct first-stream events without re-encoding DTS? YES, on isolated GStreamer 1.24.2 VPS tests.

## Precise source provenance

- [Unmodified original R188 C99 frame assembler](../tools/r311-original-r188-dts-framer.h) SHA256: 8fcf17dd9d9890d26542f093a87f91e760e8ea8999619e17b4e56485b04bfa97.
- [Unmodified original R188 GStreamer wrapper](../tools/r311-original-r188-gst-framer.c) SHA256: 773aea865d8b49c36b7cf72b8baf56db5615670b80776622b1e5e23ca0146a52. This original wrapper is retained for comparisons.
- [R311 real BE16 header probe](../tools/r311-real-dts-be16-probe.h) commit 7be05af8b2520b99d30ec559431720ae130dd0a8 SHA256 57d9d1df5b1ffe0d3fce8ad7ae584a7d95a6cb81f265ab658199a332866b9ed1. Limited subset of normal DTS Core BE16, NOT the original missing full R122. Channel-mode/sample-rate tables and low-frequency effects bit positions were independently checked against LGPL libdcadec sources in the exact R278 relink archive SHA256 2723b1cd09b50df367161e5acff6d1d622c76856592c907d79ef606380c98ccf. This does not imply full DTS/DTS-HD conformance.
- [R312 derived GStreamer wrapper](../tools/r312-r188-framer-ordered-events.c) commit d38ea00d351a99e55d69ebd9d6f1d683564dd41b SHA256 9dfe39eddda78844d4234603530e6b76d64cc5d0806283d1be012f1811d19a30. Retains the original bounded C99 assembler while correcting GStreamer event ordering and guarding ns timestamp overflow.

## Confirmed defect in the R188 experimental wrapper

First R311 genuine-DTS tests achieved byte-perfect PCM, but the original R188 wrapper emitted:

    Sticky event misordering, got 'segment' before 'caps'

This appeared at the framer src pad and dtsdec sink. The raw filesrc supplied SEGMENT before the first full DTS header was available, while R188 forwarded SEGMENT immediately and emitted CAPS only when the first decoded header had been assembled.

R312 defers the incoming SEGMENT until output CAPS are known and sends events in the correct order:

    STREAM_START -> CAPS -> SEGMENT -> first complete encoded DTS frame

Owned pending-segment memory is cleared on STREAM_START and FLUSH_STOP, and on GObject finalization; downstream event rejection is surfaced. The original R188 wrapper was not modified. This is a proven bug and fix in the ISOLATED R188 code, not proof of an event bug in the deployed kitchen R278/R130.

## Real release DTS fixture outputs

Used two original SHA-pinned DTS clips in the published R278 hall-TV release, losslessly extracted as elementary DTS. No movie stream copied or DTS transcoding performed. Output was written to a temporary file (no speaker).

Pipeline: filesrc(blocksize=N) -> aleksdtsr188framer (R312) -> dtsdec -> audioconvert -> S16LE 48kHz PCM file.

| Input clip | block 1 | block 11 | block 97 | block 4096 | Matroska gold |
| --- | ---: | ---: | ---: | ---: | ---: |
| R278 DTS stereo | 48,128 frames | 48,128 | 48,128 | 48,128 | 48,128 |
| R278 DTS 5.1 | 48,128 frames | 48,128 | 48,128 | 48,128 | 48,128 |

Every R312 output was BYTE-IDENTICAL with its Matroska PCM reference, not just the same length, and no sticky misordering warning was emitted.

- Stereo: 192,512 PCM bytes, SHA256 19a367f440beedaed0ffdb3e18403c9ed14124f289e354983036b51b347c0773.
- 5.1: 577,536 PCM bytes, SHA256 d7d992363b866249f7e18790beda1f9e2e5f202d9a7536f5a9e1606c605f28e6.

Before inserting a full-frame parser, raw arbitrary 11/97-byte chunks into the stock VPS dtsdec lost PCM; R312 eliminates those losses on the tested original R278 fixture bytes.

## Negative and GStreamer regression

Three separate real DTS invalid-input cases FAIL CLOSED as expected: invalid first sync, truncated frame at EOS, and good first frame followed by invalid next sync.

Eight native real-GstPad event cases PASS via the existing R305 harness (R304 synthetically generated DTS-like header specifically for event unit tests, NOT used for real PCM tests): fragmented first frame and EOS, FLUSH_STOP clearing incomplete header, STREAM_START clearing incomplete frame, incomplete EOS rejection, replay after EOS, changed channel/rate CAPS, invalid sync error recovery, downstream GST_FLOW_NOT_NEGOTIATED propagation/recovery.

Eight of eight same event tests PASS with ASan and UBSan enabled and halt-on-error. ASan leak detection disabled due to GStreamer/GLib process-global allocations. This does not claim a leak-free production runtime.

The R188 C99 assembler and the restricted real-header probe also cross-compiled to ELF32 ARM EABI5 with arm-linux-gnueabi-gcc -march=armv7-a -mfloat-abi=softfp. Standalone object SHA256 891daf96f268cfdfae34224131e2e7fa0b359f5c1f8e7bc9385e463aa9d65c24. THIS IS ARM COMPILE ONLY: the full GStreamer plugin was not cross-linked for kitchen webOS26 GStreamer 1.24.10 because an exact target developer sysroot was not found on the VPS.

## Reproducible full QA

[tools/run-r312-real-dts-ordered-events.sh](../tools/run-r312-real-dts-ordered-events.sh) final commit 7091cbe752822e7f1e6b13a5c5c8b7fc74e5de50 SHA256 82afab34a27cb169be4a09a78f260279a16a7fcb77e23571c9488b1d45e24a59:

- Downloads and verifies six SHA256-pinned upstream sources/archive/isolated SDK header packages, plus R278 fixtures and pinned R304/R305 event QA sources.
- Compiles and loads the R312 derived plugin only from a temporary directory with GST_RANK_NONE; no system package installation, no TV media playback.
- Requires 8/8 genuine DTS byte-exact PCM tests, zero sticky-order warnings, 3/3 real DTS negative rejection cases, 8/8 GstPad event regression and 8/8 ASan+UBSan event regression.
- Automatically deletes its generated DTS, PCM, GStreamer registry, plugin binaries and developer headers.

This final immutable GitHub commit was independently downloaded and executed on the FI VPS, with result:

    R312_REAL_GSTPAD_EVENT_8_OF_8_PASS
    R312_ASAN_UBSAN_GSTPAD_EVENT_8_OF_8_PASS
    RESULT=R312_REAL_DTS_8_OF_8_PCM_3_OF_3_FAIL_CLOSED_EVENTS_8_OF_8_ASAN_8_OF_8_PASS

## Kitchen release gate: critical distinction

The actual kitchen installed plugin is R278 composed of R130/R239/R56 stages. R188/R312 is experimental and is not its present runtime. R312 passing on VPS stock GStreamer 1.24.2 does not prove the cause of the initial silence on LG, that the LG receives fragmented raw DTS frames, or that the LG's R130 sends SEGMENT before CAPS.

Before any installation: obtain authorized read-only first-silent versus audible R310 snapshots, determine the real R278 input GstBuffer framing and first PCM/native sink events, secure the exact webOS26 ARM GStreamer 1.24.10 sysroot, make a reversible isolated build, run full native first-cold-start, track-switch, seek, stereo, 5.1, AC3 and A/V sync regression. Do not enable a second parser or change system decoder rank based only on this lab result.

No LG, TORMOZ, OpenWrt or VPS production service changed in R311/R312.
