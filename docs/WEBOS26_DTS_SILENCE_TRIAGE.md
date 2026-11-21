# webOS 26 / LG 43NANO85A6A — DTS silence triage (2026-11-22)

## Observed facts

- Hardware: kitchen LG 43NANO85A6A, firmware 43.22.74, `uname -m=aarch64`; media userspace ELF32 little-endian ARM (EABI5 soft-float), GStreamer 1.24.10.
- R278 four plugins and 3 fixtures sha256 PASS; isolated DTS stereo + 5.1 decode and software AC3 all PASS.
- R279 candidate install PASS, accidental rollback PASS, subsequent re-activation from `/var/lib/webosbrew/aleks-dts-r278/install.sh install` PASS.
- After TV reboot, installed artifacts SHA256 PASS, `umediaserver.service` active, `umediaserver.env` byte-for-byte matches `installed.env`, and live process has `GST_PLUGIN_PATH_1_0`, `GST_REGISTRY_1_0`, `GST_REGISTRY_UPDATE=no`, `ALEKS_DTS_R130_ALLOW_AUTOPLUG=YES`.
- **User field test: movie “The Matrix”, 3 DTS soundtracks tested: all silent. STATUS: DTS PLAYBACK FAIL**. Actual application/native player mode and detailed pipeline not yet identified.

## Important limit

Passing plugin decode in a standalone `gst-launch` pipeline and checking `umediaserver` environment **does not prove** that the actual playback pipeline loaded the plugin, negotiated DTS caps, emitted PCM acceptable to LG's sink, or delivered audible audio. Do not release this webOS26 build publicly as working.

## Source-backed hypotheses, not proven for this TV

1. Playback runs in `starfish-media-pipeline`, `audiooutputd` or another process with an environment different from `umediaserver`, and the AlekS plugins are not loaded.
2. MKV demuxer may emit `audio/x-unknown, codec-id=A_DTS`, not `audio/x-dts`, preventing autoplug. In [dts_restore_plus webOS25 README](https://github.com/josippapez/dts_restore_plus/blob/main/webos25/README.md), this behavior is documented on C5/G5; it **must be verified on the kitchen set**, not assumed.
3. PCM caps and audio sink mismatch can silently drop frames. Same external research identifies S32LE integer PCM as supported target for its webOS25 native sink. Confirm exact kitchen sink capabilities and current AlekS output caps first.
4. Lampa's playback route may differ from the built-in LG Media Player; compare the same DTS test clip in both environments before attributing failure to one service.

## Next read-only test while the movie is playing

Download and SHA256-verify [tools/diagnose-webos26-dts-silence.sh](../tools/diagnose-webos26-dts-silence.sh). It reports active media process identities, count of AlekS `.so` mappings, whether process environments include configured plugin path/opt-in, individual GST element discoverability, stock Matroska plugin SHA256 fingerprints and journal error markers. It does not restart, change, or reconfigure any media service. Do not share application environment values or user file paths.

Interpretation:

- `ALEKS_SO_MAPPINGS=0` during active playback: possible different-process routing / no autoplug, not by itself proof of root cause.
- `.so` mapping >0 but silence: inspect demuxed DTS caps, PCM produced, actual output sink and routing.
- `PLUGIN_REGISTRY_MISSING`: investigate GStreamer registry/environment in isolation, no production changes.

## Modification gate

Before experimenting with `libgstmatroska.so`, `audiooutputd`, media service environment or bind mounts: identify exact firmware binary SHA256, test with temporary external pipeline, preserve original configuration and fully verified rollback. Do **not** install webOS25 third-party binaries on webOS26 without ABI, firmware and hardware verification. LG root/system modifications require separate safety review.

## Live media-process evidence (user field output, UTC 2026-11-21 21:39:13)

- `umediaserver` PID 1214 was active but mapped **0 AlekS DTS libraries**; its environment included the configured plugin path and opt-in.
- `starfish-media-` PID 10846 mapped **3 of the 4** AlekS libraries; the second `starfish-media-` PID 10848 mapped 0; **both** had plugin path and autoplug opt-in environment. This disproves the simplistic hypothesis that AlekS does not reach any actual media subprocess. Exactly **which three** libraries are mapped remains to be identified, and loaded libraries do not establish decoder selection or PCM audio delivery.
- `audiooutputd`, `audiod`, `pulseaudio` mapped 0 AlekS libraries, which is expected if decoding happens upstream.
- `gst-inspect` showed `aleksdts16dec` and `aleksdtsr130optin` **available in the installed registry**; factory presence is not proof the live pipeline chose them.
- Stock `libgstmatroska.so` SHA256 `0061c0d9f00c5e065c3c883f5cb19f7065edc983d7d83e62756ea944c3665fe9`; stock `libgstisomp4.so` SHA256 `c8dc19c8a9136e6ddfd7d5e8b7c2e66f449bdfe747a5a3521bb97b65039179cf`. **Do not bind-mount replacements without separate compatibility proof**.
- `journalctl` returned zero keyword matches in the queried 15-minute window. This **does not mean** the pipeline has no error: relevant messages may be under another process/unit or logging disabled.
- R278 isolated test explicitly expects **`S16LE`** for DTS 2.0/5.1. DTS Restore Plus webOS25 documents a platform-specific LG sink requiring integer **`S32LE`**. This is a **plausible PCM-output mismatch**, but no evidence yet that kitchen webOS26's actual `audiosink` has the same constraint.

Next non-invasive test: [`diagnose-webos26-dts-path-r280.sh`](../tools/diagnose-webos26-dts-path-r280.sh) (run **during playback**, read-only) prints per-library mappings for each `starfish-media-` process, GStreamer element ranks/caps and stock decoder policy clues. After determining whether `libgstaleksdts16dec.so` is actually loaded, distinguish **decoder selection** from **S16LE→S32LE/output routing** before changing any code. Native player and Lampa may take different paths.

