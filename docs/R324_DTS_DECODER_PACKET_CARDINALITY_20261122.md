# R324 — R278 DTS decoder input contract: incomplete and multi-frame buffers

Date: **2026-11-22**. Scope: **source-level decoder investigation and reproducible off-TV lab on the exact released LGPL `libdcadec` sources**. Real Lampa first-start root cause **NOT VERIFIED**. Production R278 **NOT MODIFIED**.

## Why we investigated this

[R318](R318_REAL_KITCHEN_FIRST_SILENT_TO_AUDIBLE_PAIR_20261122.md): owner confirmed first DTS after a TV restart was silent. Switching DTS→AC3→DTS restored sound. The actual silent and audible R317 scalar captures had the same DTS codec, media service, ALSA running state, active unmutted audio routes and almost identical hw/app pointer increments. Neither captured PCM signal amplitudes.

[R323](R323_REAL_LG_DTS_RAW_VS_MATROSKA_DIFFERENTIAL_20261122.md): on the physical kitchen LG, a *separate* native GStreamer process could decode a verified Matroska DTS fixture, but raw DTS fed to the same custom decoder failed even at aligned complete-frame buffer sizes and with explicit channels/rate/framed caps. The source of that failure is not fully determined.

### Static inspection of original shipped R56 decoder

The **unmodified R278 LGPL relink source archive**, SHA256 `2723b1cd09b50df367161e5acff6d1d622c76856592c907d79ef606380c98ccf`, contains `gstaleksdtsdec.o`, SHA256 `ad705f63a479753ac28836417c211e937edb525a44678da29f5e56037076f613`.

Actual ARM EABI disassembly of `handle_frame` (starting at object offset 0x184) shows:

- `gst_buffer_map` of the incoming buffer.
- `g_malloc0(in_size + 8)` and `__memcpy_chk` of the **entire incoming buffer**.
- Exactly one `dcadec_context_parse(ctx, copied_bytes, input_size)` call for that buffer.
- One `dcadec_context_filter`, output PCM conversion and `gst_audio_decoder_finish_frame` (on success).
- A negative `dcadec_context_parse` or filter result branches to `GST_FLOW_ERROR` (`-5`) without an incremental-frame accumulation/retry in this handler.
- No `gst_adapter` or `GstAudioDecoderClass.parse` implementation from R56's referenced imports and registered vfunc set; wrapper R239 constructs `aleksdtsdec → audioconvert → capsfilter(S16LE)`, but does **not** add a DTS frame parser. These are scoped to the inspected released objects, not a claim about all upstream media elements. `matroskademux` may already supply one frame per buffer in normal playback.

GStreamer [`GstAudioDecoder`](https://gstreamer.freedesktop.org/documentation/audio/gstaudiodecoder.html) supplies input frames to subclass `handle_frame` and permits optional `parse` handling for accumulated input. A per-frame decoder is therefore dependent on correctly framed upstream data if it does not implement its own assembly.

## Executable regression

- [C harness](../tools/r324-libdcadec-packet-cardinality.c): calls *the exact released* `dcadec_context_create/parse/filter` API, in fresh or persistent contexts, using bounded, aligned, SHA-checked public fixture input; no PCM bytes stored.
- [Reproducible runner](../tools/run-r324-libdcadec-packet-cardinality.sh): locally validates the immutable original release archive SHA256 `cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1` and LGPL relink archive SHA256. Builds libdcadec **in a private temporary directory** from source (no `make install`), uses only the two original DTS Matroska fixtures (SHA256 validated), extracts the known 94 intact BE16 frames via Python standard library, and verifies that extracted DTS bytes exactly match independent `ffmpeg -c copy` reference SHA256 digests. Compiles/statically links the C test harness and runs stereo and 5.1 separately.
- Original encoded stereo reference: 94 frames × 1024 bytes = 96,256 bytes; SHA256 `282d15e11221524f6af40f4202ec6d2a3813d2a12a49de904e7cdfc0c4ce9bda`.
- Original encoded DTS 5.1 reference: 94 frames × 2048 bytes = 192,512 bytes; SHA256 `8897677d593a5710b62f90919fe0e9888a31621bf55b166e2294a2f36f4fb013`.

### Observed results (VPS, freshly rebuilt from pinned release)

| Byte length submitted to one `dcadec_context_parse` | DTS stereo (1024 B frame) | DTS 5.1 (2048 B frame) |
|---|---|---|
| 11, 97, 512 bytes | Reject — incomplete | Reject — incomplete |
| 1024 bytes | Accept, **512 samples/channel** | Reject — incomplete |
| 2048 bytes | Accept, **512 samples/channel** (one of 2 frames) | Accept, **512 samples/channel** |
| 4096 bytes | Accept, **512 samples/channel** (one of 4 frames) | Accept, **512 samples/channel** (one of 2 frames) |
| First-byte-corrupted full frame | Reject | Reject |
| **All 94 frames sequentially, one parse/filter per frame** | **94/94 PASS, 48,128 samples/channel** | **94/94 PASS, 48,128 samples/channel** |

Both runs ended with `RESULT=R324_LIBDCADEC_CARDINALITY_PASS` and `R324_LAB_ISOLATED_ONLY=PASS`. The returned `512` samples/channel is **per decoder call**, not per entire 2–4-frame buffer. This exposes the precise **potential packet aggregation loss** in the R56 caller if upstream supplies multiple frames per input buffer. The incomplete-frame rejection exposes a separate potential loss if upstream delivers only part of a frame and no pre-parser assembles it.

**This does not establish that Lampa delivered either malformed packet shape in the actual R318 silent session.** On the kitchen TV, R323 raw 1024/2048 also failed as a GStreamer stream before decoded PCM; the standalone libdcadec API accepts a full frame. This difference implicates some GStreamer input setup/metadata/event/transport condition, not necessarily a broken decoder algorithm. No blocked native timestamp experiment was retried.

## CI integration and resolved dependency issue

- Integrated R324 runner into [GitHub Actions public integrity workflow](../.github/workflows/dts-public-integrity.yml).
- First Actions attempt on commit `4d804e930a8e41cc90598774a92691a424492c6c` **FAILED** because the GitHub runner lacks the `ffmpeg` executable. The source/release checksum audit step itself passed.
- Corrected runner to use the verified public test fixture's BE16 frame boundaries and compare recovered raw DTS against the independent FFmpeg reference SHA256. The release fixture SHA256 and recovered raw SHA256 both gate correctness. **No external dependency/install/network download remains in the runner** apart from files already checked out.
- Subsequent GitHub Actions commits from `0ebab6898babff7e4fb401cb8127dcc6c245a635` onward completed **SUCCESS**.
- Latest completed stereo+surround QA on commit `7650aa2bc3ec74c12650327ea850a637a4909abf`, via [GitHub Actions run 45022820512](https://github.com/aerolit266/AlekS-DTS-webOS/actions/runs/45022820512): **completed/success**. On FI VPS a clean shallow clone of the same commit also yielded all stereo and 5.1 cardinality cases PASS, plus R322 release/source/README integrity PASS.
- Temporary build/source media automatically removed in the reproducible runner; standalone research temp cleanup performed separately. No binary/plugin/env/service on LG was changed.

## Candidate correction design — not yet shipped

To make the DTS Core path independent of upstream buffer shape, use a dedicated bounded, low-overhead DTS Core framer **before** R56. The existing [R312 experimental full-frame assembler](../tools/r312-r188-framer-ordered-events.c) has *off-device* 8/8 tests on real DTS fixture fragmentation and correct CAPS-before-SEGMENT events. Before hardware use on webOS26, ensure the candidate:

1. Accumulates partial DTS Core frames with a hard 16-KiB frame limit, proper BE16 header bounds and no unbounded resync.
2. Emits each complete frame **individually**, even when one upstream GstBuffer contains multiple DTS frames; preserves input timestamps and interpolates subsequent frame durations without drift.
3. Maintains strict `STREAM_START → CAPS → SEGMENT → first data` ordering, correctly handles `DISCONT`, `FLUSH_STOP`, `EOS`, track changes and channel/caps renegotiation.
4. Fails closed on unsupported DTS-HD frame extensions instead of silently corrupting data, keeps original DTS Core-only scope, and has no disk recording or audible-output side effects in tests.
5. Is cross-built against a verified **webOS26 media ELF32 ARM/GStreamer 1.24.10** target ABI and tested in isolated GStreamer with `fakesink` **before** any controlled installation.
6. Requires backup, versioned opt-in, explicit permission, an immediate rollback path and real first-cold-start listening regression. The current original R278 installation is not replaced by this research.

**R324 INPUT CARDINALITY RISK: VERIFIED OFF-DEVICE. Actual cold-silent Lampa root cause: NOT VERIFIED. R278 production: UNCHANGED.**
