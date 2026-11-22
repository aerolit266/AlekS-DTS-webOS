# R307 — published R278 binary audit and DTS packet boundaries

**Date:** 2026-11-22. **Result:** OFFLINE PASS on Finnish VPS. Kitchen LG not contacted.

## SHA256-verified release

The public archive AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz, from the GitHub r278 tag, is 348,539 bytes. SHA256:

    cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1

All four bundled plugins matched the public R278 verification manifest, and all four were confirmed to be **ELF32 little-endian ARM EABI5**:

| File | SHA256 |
| --- | --- |
| libgstaleksdts.so | 5c3b798d4c1109414efc9209276dbf8b23466376f72f5bc71cf4144f3f5a1cbb |
| libgstaleksdts16dec.so | dfefb960d49d50ed7629cc4459ffaae8b420509cc9815d8337f6be7faaac18cf |
| libgstaleksdtscaps.so | 1995a6b6030f6ddb895aeeea4017dcc71db8ebd6caace0107e1c5a33875f0605 |
| libgstaleksdtsr130optin.so | 9b7adb2744a9d7c329669974c15bcfc86ba62daf27efccb95e362c1928d602e0 |

Also verified the separate LGPL relink archive SHA256 2723b1cd09b50df367161e5acff6d1d622c76856592c907d79ef606380c98ccf. It contains the R56 adapter object and the libdcadec source tree.

**Crucial limitation:** this is explicitly the public release for the **hall** LG 65NANO896PC, not a fresh readout of the installed kitchen television. Prior kitchen records showed R278-labelled components, but their currently installed and loaded binary SHA256 hashes were NOT checked in R307.

## Source-independent static plugin facts (not a running-pipeline trace)

- R239 libgstaleksdts16dec.so is a GStreamer *bin* referencing factory elements aleksdtsdec, audioconvert and capsfilter with S16LE output caps. It imports gst_element_factory_make and gst_element_link_many. No distinct compressed-frame assembler was established from its imported symbol set. That does NOT prove none exists elsewhere in the decoder chain.
- R56 libgstaleksdts.so uses GstAudioDecoder and libdcadec routines dcadec_context_parse and gst_audio_decoder_finish_frame. Its dynamic imports do not reveal the size or completeness of actual incoming GstBuffers.
- R130 opt-in parser has first-caps/flush-guard metadata and imports gst_pad_push plus GQueue functions. Whether it assembles complete compressed DTS frames rather than buffering metadata or initial events remains unverified.
- The R56 caps bridge describes its function as mapping unknown A_DTS caps to audio/x-dts without modifying compressed bytes.

This supports investigating **encoded packet boundaries**. It is not evidence enough to patch any production component.

## Coverage gap in the published R278 test

The published [R278 isolated verification script](../tools/verify-r278-webos26.sh) runs its bundled DTS stereo and DTS 5.1 test clips through:

    filesrc -> matroskademux -> queue -> decodebin -> fakesink

This tests properly demultiplexed DTS packets and cannot exclude behavior differences when arbitrary raw DTS bytes are directly delivered to a decoder.

Both original release DTS Matroska clips were SHA256 verified:

| Clip | SHA256 | Codec |
| --- | --- | --- |
| dts-stereo.mka | 7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae | DTS, 2ch, 48000 Hz |
| dts-51.mka | 7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5 | DTS, 6ch, 48000 Hz |

Control AC3 sample hash ab82bf91f6b61fc5a3cdf11ccd1e3bf3b4d91e2cc12089a88 was also verified, but is outside this DTS comparison.

## Lab test with the actual R278 release fixtures

**VPS stock GStreamer 1.24.2 dtsdec** (x86_64, not the native ARM AlekS R278 decoder). The same encoded DTS frames were taken from these release clips, losslessly extracted with FFmpeg -c:a copy, and decoded through two pathways:

    PACKETIZED: filesrc(blocksize=N) -> matroskademux -> dtsdec -> audioconvert -> PCM file
    RAW:        filesrc(blocksize=N) -> dtsdec -> audioconvert -> PCM file

| Release clip | Complete PCM via Matroska | Raw 11-byte blocks | Raw 97-byte blocks | Raw 4096-byte blocks |
| --- | ---: | ---: | ---: | ---: |
| Stereo | **48,128 frames** | 40,960 | 47,616 | 48,128 |
| 5.1 | **48,128 frames** | 44,032 | 47,104 | 48,128 |

For both streams, the Matroska path produced identical PCM at 11, 97, and 4096-byte input blocks.

- Stereo: 192,512 PCM bytes, SHA256 19a367f440beedaed0ffdb3e18403c9ed14124f289e354983036b51b347c0773
- 5.1: 577,536 PCM bytes, SHA256 d7d992363b866249f7e18790beda1f9e2e5f202d9a7536f5a9e1606c605f28e6

Raw bytestream losses can vary between independent runs (see R306). These figures represent the verified **final R307 run**, not a universal lost-frame count.

## Automated reproducibility

New [R307 automated release audit](../tools/audit-r278-release-packet-boundaries-r307.py) downloads only the 348 KB SHA-pinned archive, verifies four ARM plugins and both DTS fixtures, checks ELF class/architecture and static markers, confirms DTS metadata by FFprobe, then runs the 12 stock GStreamer test cases with packetized and raw input. All samples and output files are contained in a temporary directory removed after execution.

Runner final commit: 61c554535e8c77d318345ea768c15ec836673cc3

Runner SHA256: c07feac0f23be23d3a42fc16caf8c36304e39b271c6eb571dce3567deb53faa8

Final verified log:

    R307_FINAL_PINNED_RELEASE_QA_PASS

## Status, scope and next on-device gate

**Confirmed:** the published R278 package's bundled tests are packetized via Matroska. The VPS stock software decoder loses PCM for arbitrary fine-grained raw DTS blocks but produces complete PCM with Matroska packets.

**Not confirmed:** whether the kitchen TV runs these exact R278 binaries, whether Starfish sends fragmented raw buffers rather than properly framed DTS packets to the native decoder, and whether any of this caused the owner's intermittent initially silent movie playback.

Before a production change, first safely verify the actual kitchen installed plugin SHA256 hashes and collect authorized read-only evidence of demuxer, parser, decoder GstBuffer boundaries and initial PCM/sink state in a silent and audible session. Do not blindly introduce experimental R188, alter parser ranks, restart services or change system firmware.

No LG/TORMOZ connection, production updates, media playback interference or package installs occurred in R307.
