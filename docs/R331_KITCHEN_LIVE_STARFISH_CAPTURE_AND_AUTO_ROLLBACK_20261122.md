# R331 — kitchen LG webOS 26: bounded Starfish probe and verified automatic rollback

**Date:** 2026-11-22. **Status:** live instrumentation/automatic rollback **PASS**; DTS cold-silence root cause **NOT MEASURED**.

## Why R331 exists

The owner previously reproduced *first DTS after TV restart is silent; AC3 then DTS makes sound audible*. R329 proved nonzero PCM in a separate native R278 decoding pipeline; R330 proved isolated DTS→software AC3→DTS consistency. Neither demonstrated what happens inside **real Lampa/Starfish during the silent interval**.

R331 authorizes one time-limited, reversible measurement using only input DTS buffer counters, GStreamer event counters and post-decoder-adjacent sampled PCM energy. No movie data, decoded samples, URLs, titles or timestamps are exported.

## Real LG preflight

- Existing authorized path: GameFree24 VPS MCP V3 → AlekS Core → TORMOZ → `aleks-kitchen-root`. `umediaserver` and `audiooutputd` active.
- Two original `starfish-media-` processes were observed as `umediaserver` children. One had R278 libraries mapped; GStreamer and DTS environment variable *names* inherited.
- Existing `/var/systemd/system/env/umediaserver.env` exactly matched `/var/lib/webosbrew/aleks-dts-r278/installed.env`; SHA256 `654530c165e1f8229b9326c020ec5654da3e8b47e0425182d011c210c3e45497`.
- The four installed R278 plugin hashes were checked as unchanged before, during and after work.
- Existing OEM `LD_PRELOAD` contains **libsystrim.so.3**. The staging tool captures and preserves its *exact current value* rather than replacing it.
- The system had no existing `umediaserver` drop-ins. Temporary data is restricted to the RAM-backed `/run` and `/tmp`.

## Engineering and isolated checks

- [Read-only Starfish topology probe](../tools/r331-readonly-starfish-topology.py): limited process ancestry, active GStreamer module presence and allowlisted environment *key names*, not values.
- [Read-only service environment preflight](../tools/r331-readonly-service-env.py): current service and installed environment checksum, original preload library basename only.
- [R331 GStreamer tracing experiment](../tools/r331-bounded-live-dts-tracer.c): on VPS, an isolated DTS file produced input-frame and PCM metrics. **LG vendor GStreamer reported zero active tracers** for both standard `latency` and `log`, as well as our plugin, despite successful factory discovery. Vendor exported `gst_tracing_register_hook` has been observed as a two-byte stub in the archived ARM library. The normal GStreamer tracer route was **not installed in live Starfish**.
- [R331 fallback `LD_PRELOAD` interposer](../tools/r331-bounded-dts-interposer.c): ELF32 ARMv7 soft-float, no direct `DT_NEEDED` on GStreamer, only `libc`, `libm` and ELF loader; inactive unless the process is a Starfish child (or explicitly flagged isolated QA). Interposes only exported `gst_pad_push` and `gst_pad_push_event` and forwards all calls unchanged. Samples at most 1024 decoded PCM values per buffer and stores only aggregate RMS/peak/counts. Correlates converter measurements with recent DTS input, and prevents double-counting duplicated converter pads. Automatically stops after 180 seconds even if service rollback fails. No ptrace, gdb, audio output or ALSA modification.
- ARM module SHA256 `deb1adb853e4d7546ce0fc7a8b446a849b7b3a47fbcdb5dcf870b16ce1cd8057`. [Isolated LG QA script](../tools/r331-verify-interposer-lg.sh) verified **2/2 PASS** with the unchanged installed R278 decoder and public DTS fixtures. Stereo: 94/94 BE16 DTS inputs, 94 sampled PCM buffers, 95,414 nonzero sampled PCM; surround: 94/94, 94 buffers, 95,367 nonzero sampled PCM. The `audioconvert` output is marked an **indirect** PCM measurement, not precise sampling of every output sample at the decoder pad.
- On VPS, unrelated processes were denied instrumentation. A test compiled with a 4-second window stopped automatically at the deadline.

## Reversible field exercise on actual Starfish

The owner had explicitly authorized R331 service-level instrumentation. [R331 runtime controller](../tools/r331-runtime-window-lg.sh) uses exact checksums of the source module, original environment and all R278 plugins. It copies a baseline environment into `/run/aleks-r331` with mode 0600 and creates a **temporary** systemd `EnvironmentFile` drop-in under `/run/systemd/system`; it never edits `/etc`, `/var/systemd`, the DTS plugins or firmware.

A standalone systemd timer was successfully tested on LG using an 8-second benign file-creation task. Before any media service restart, the controller scheduled a **100-second independent systemd-run rollback timer**. It then restarted only `umediaserver`. Both that service and `audiooutputd` remained active, the parent acquired the temporary preload and the background Starfish process created the private aggregate JSON metric.

**Observed live capture:** 102 seconds elapsed, `input_buffers=0`, `be16_sync=0`, `pcm_nonzero=0`. This is **not a measured silent DTS failure**: no DTS stream passed through the active instrument during the capture. No conclusion about the failing first-DTS path can be drawn from these zero counters. The user's actual cold-boot DTS/AC3/DTS scenario was **not triggered in this window**.

**Verified independent automatic rollback:** systemd `aleks-r331-rollback.service` returned `Result=success`, `ExecMainStatus=0`. Afterwards `umediaserver=active`, `audiooutputd=active`, timer inactive, `DropInPaths=` empty, only the original `EnvironmentFiles=/var/systemd/system/env/umediaserver.env` registered. Base environment and installed R278 env SHA256 both remained `654530c165e1f8229b9326c020ec5654da3e8b47e0425182d011c210c3e45497`. No running process mapped the temporary hook after rollback. Temporary on-device diagnostics and `/run/aleks-r331` were removed with verification.

A private aggregate-only manifest of the completed cycle (no user media) was saved on the FI VPS at `/opt/gamefree24-vps-mcp/private/dts-r331-20261122/LIVE-ROLLBACK-MANIFEST.json`, SHA256 `c289403f2d1748ee1cd3067f4fd4888f7ba25f3b00ddd18018d1d7cbcf31a405` (0700 directory, 0600 file). Exact remote task results: armed `4fede4d58a6fed1744752a68ad8f2a55`; final rollback `a8e256f3178ac15ece1938d5071e0cdb`; temporary LG cleanup `8d47b06550082c28257b24adf6803ad0`.

## Remaining work

**Cold DTS silence is NOT fixed or explained.** A future diagnostic window must coincide with the *real* owner-confirmed silent first DTS in Lampa, followed by the AC3→DTS recovery, while collecting pre- and post-switch counters. Do not prolong the temporary preload indefinitely, treat lack of DTS frames as decoding failure, or change the production R278 based only on this negative capture.

**R331 status: physically verified isolated instrumentation and fully verified runtime rollback, but no valid cold-silence field sample.**
