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


## R280 real playback decoder rank evidence (user field output, 2026-11-22)

- `starfish-media-` PID 10846 maps **libgstaleksdts.so, libgstaleksdtsr130optin.so and libgstaleksdts16dec.so**, while `libgstaleksdtscaps.so` is **not mapped**. A second `starfish-media-` PID 10848 maps none. Mapping `libgstaleksdts16dec.so` proves its library loaded, **not that an element instance is in the active audio chain**.
- Stock GStreamer libraries mapped in PID10846: `libgstaudioconvert.so`, `libgstaudioparsers.so`, `libgstaudioresample.so`, `libgstdecproxy.so`, `libgstfakedec.so`, `libgstomx.so`, `libgsttsinkbin.so`; stock modules' mere mapping does not prove they processed the DTS stream.
- GStreamer factory ranks from isolated `gst-inspect`: `aleksdtsr130optin=322`, `aleksdts16dec=288`, `aleksdtscaps=256`; decoder offers `audio/x-dts → audio/x-raw S16LE [1..8 channels]`; parser accepts `audio/x-unknown, codec-id=A_DTS` and `audio/x-dts`.
- `decproxy` reported **factory rank NONE (0)** in `gst-inspect`, but LG `/etc/gst/gstcool.conf` declares `decproxy=300`. These are **different rank sources** and may affect native pipeline selection; **effective runtime precedence remains unverified**.
- No `adecswitch` or `audiosink` factory was discovered under those exact names. This alone does not prove there is no hardware sink or native output.
- **Leading hypothesis**: after `aleksdtsr130optin` parses DTS (rank 322), stock LG `decproxy` (policy 300) is preferred over `aleksdts16dec` (288), causing a fake audio decoder / no PCM. Actual routing needs confirmation.
- **Separate hypothesis**: PCM negotiating to native sink may fail. Important distinction: **S16LE is integer PCM**, so webOS25 documentation saying integer-only does *not* by itself establish that S16LE is unsupported. Test actual kitchen sink caps before proposing S32LE conversion.

### R281 falsifiable isolated experiment

Created [tools/test-webos26-decoder-ranks-r281.sh](../tools/test-webos26-decoder-ranks-r281.sh). It verifies bundled files SHA256, runs GStreamer only with a **temporary registry**, never modifies media service or stock libraries, and tests DTS 5.1 through `decodebin ! fakesink` (no speakers) under three per-process `GST_PLUGIN_FEATURE_RANK` policies:

1. `decproxy:0,aleksdts16dec:288` (control).
2. `decproxy:300,aleksdts16dec:288` (simulate stock policy).
3. `decproxy:300,aleksdts16dec:350` (candidate rank repair).

Logs report exit, `AlekSDts16DecBin` instantiation, EOS, and 6-channel PCM negotiation only. GStreamer 1.24 supports documented `GST_PLUGIN_FEATURE_RANK` overrides (since 1.18): https://gstreamer.freedesktop.org/documentation/gstreamer/running.html .

**Decision gate:** only if (2) reproduces the failed decoder selection and (3) restores 6-channel PCM may a reversible native service environment override be considered. Still require a real audio sink / Lampa sound test and AC3/DVB regression; never infer production success from `fakesink`.

**Status:** R281 script GitHub commit `def783e5`; VPS shell syntax PASS, SHA256 `b75fe27330827db37a17c143796313347e72a8f8aa37c582bef0255d551a84d2`; NOT YET TESTED ON KITCHEN.

## R281 real field result — 2026-11-22

User executed R281 on the kitchen LG. **All installed R278 integrity checks passed.** GStreamer 1.24.10 confirmed, `/etc/gst/gstcool.conf` contains `decproxy=300`. Temporary per-process rank overrides were confirmed effective: `aleksdts16dec=288,decproxy=0`, `aleksdts16dec=288,decproxy=300`, `aleksdts16dec=350,decproxy=300`.

For all three **ordinary `decodebin ! fakesink`** cases: **exit 0, AlekSDts16DecBin instantiated, EOS yes, PCM six-channel yes**. Therefore **rank 300 vs 288 does NOT reproduce silent audio in this isolated decodebin test**, and a rank-only production fix is **not justified**.

This test does not model LG's complete native media-resource negotiation. It also does not cover `decodebin3`, `decproxy` resource-grant events, real output sinks, or actual feature/movie DTS track specifics. Never claim that it disproves every possible native rank conflict.

### Next experiment R282 (staged, read-only for production)

Created [`tools/test-webos26-decodebin3-pcm-r282.sh`](../tools/test-webos26-decodebin3-pcm-r282.sh), commit `993083a`, tested shell syntax on VPS, SHA256 `447ffe1802cb7cdf945a705b0c72ed7ac52629c0c93b11bb72a1a235e2d1d6b0`. Its `gst-launch` tests use **`decodebin3`**, not `decodebin`, under 288/0, 288/300 and 350/300 rank configurations. A fourth test adds `audioconvert ! audio/x-raw,format=S32LE,channels=2` and `fakesink`, while querying discovered sink factory caps. It touches only an isolated /tmp registry/fixture and **never sends sound to physical outputs**. It is **NOT YET RUN ON LG**.

Decision points: if `decodebin3` differs by rank then investigate resource handling; if all decodebin3 tests work, rank changes are lower priority, investigate real player stream caps and hardware/native sound sink. Successful S32LE/stereo negotiation with `fakesink` is **not proof** that the physical sink accepts or reproduces it.

**Safety:** no replacement or mutation of stock `libgstmatroska.so`, `libgsttsinkbin.so`, `/etc/gst/gstcool.conf`, `umediaserver.env` or LG system partitions; no reboot or service restart. DTS playback still **FAIL** until real audio test passes.

## R282 field result: decodebin3 and S32LE conversion (2026-11-22)

Owner executed `tools/test-webos26-decodebin3-pcm-r282.sh` on LG 43NANO85A6A. R278 installed SHA256 and fixture PASS, `decodebin`, `decodebin3`, `audioconvert` available.

| Case | Effective ranks (AlekS/decproxy) | Custom DTS bin instantiated | EOS | Sink PCM caps | Exit |
| --- | --- | --- | --- | --- | --- |
| db3_stock | 288 / 0 | yes | yes | 6 channels, S16LE | **143** |
| db3_lg | 288 / 300 | yes | yes | 6 channels, S16LE | **143** |
| db3_aleks | 350 / 300 | yes | yes | 6 channels, S16LE | **143** |
| db3_aleks_pcm2 | 350 / 300 | yes | yes | 2 channels, S32LE | **143** |

All four `decodebin3 ! fakesink` test cases reached EOS and reported no negotiation error, **but exited 143 after the 12-second timeout**. This is **not clean teardown**; it is potentially the known native OMX/decproxy shutdown stall. `exit 143` is `128 + SIGTERM(15)`; no evidence this signal arose *before* EOS. A clean-exit PASS must not be claimed. `tsinkbin` and `alsasink` factory available; ALSA advertises both S16LE and S32LE plus other formats, but these templates **do not describe the actual LG playback sink/resource path**.

**Decision:** R281+R282 do not justify changing ranks: all isolated pipelines decode under rank 288/300. S32LE stereo conversion is technically feasible but real-audio efficacy remains untested. Prioritize actual uMS/Starfish audio resource acquisition, decoder instance, `audiooutputd` routing, playback track/caps and native sink; avoid production changes while diagnosis is incomplete.

## R283 read-only hardware audio-route probe — staged

The R282 field result isolates codec decoding from the real LG audio output. In webOS25's documented audio path, `decproxy` may require an `acquired-resource` grant from `umediaserver`; a `fakeadec` placeholder can cause silence after track switching. This is a **research-supported hypothesis** from a different LG model, not proof for 43NANO85A6A; see https://github.com/josippapez/dts_restore_plus/blob/main/webos25/README.md.

Created [tools/diagnose-webos26-native-audio-route-r283.sh](../tools/diagnose-webos26-native-audio-route-r283.sh), GitHub `8ef36cf`, SHA256 `037b7394c68f78db3a465c02b37d42ec88a477f16aae83fafdc3aa3c408b20a4`, VPS shell syntax PASS. Run **while a native video pipeline is actively playing a selected DTS track**. It reports only plugin mappings, a SHA256 and keyword counts for LG's codec capability config, narrowly allowlisted fields from LG's documented read-only `getAudioInputProperty` API (if supported), and counts of recent `fakeadec`, `acquired-resource`, negotiation and resource errors in system journal. It does not alter TV sound or decode a synthetic signal and avoids disclosing the movie title or full LS payload.

Interpretation: `CAPABILITY_REFERENCE_dts=0` may flag a missing uMS DTS resource declaration but is only a substring count, not definitive capability assessment. The LS audio-input-property API may describe the selected input instead of the app's audio stream. Zero journal counts may reflect absent logging. No production changes until decoded PCM and actual LG output path are linked by evidence.

QA of R283 shell script performed on **VPS only**; fake/absent TV resources there are expected and **not kitchen test results**.

## R283 field result — codec detected; sound still silent (2026-11-22)

User ran R283 on actual kitchen LG during DTS playback. `starfish-media-` PID10846 continues to map the three AlekS libraries (decoder, R130 parser, base); second process PID10848 maps none. The native LG resource config `/etc/umediaserver/device_codec_capability_config.json` SHA256 is `053190bf35dc1ce59124b098c5a38683d86a1c33e35c4bddbfdc22334860336c`; case-insensitive substring counts `dts=3,pcm=2,ac3=2,eac3=1`. **Counts indicate codec-related references, not a proven active decoder resource allocation.**

`luna-send` succeeded against `com.webos.service.audio/tv/getAudioInputProperty` with `returnValue=true, codec="dts"`. Thus LG's audio service **recognizes an incoming DTS codec**, but does **not** prove decoded PCM frames reach the actual native audio renderer. Selected journal markers `fakeadec`, `acquired-resource`, `no-resource`, `not-negotiated`, `error`, `failed-to-link`, `no-audio` all matched 0 in the recent bounded system journal check. **Zero log matches do not prove absence of resource failures or silence.**

## Next instrument R284 — native renderer logs, no production changes

Based on the existing read-only renderer diagnostics in `josippapez/dts_restore_plus/webos25/restore/report-tv.sh`, test LG's `/var/log/legacy-log` markers `lgao_push_first_event`, `Caps is first or updated`, `Connect ES Renderer`, `Set pcm`, and `Restart renderer`. These are closer to the native PCM sink path than GStreamer factory inspection alone. Script: [tools/diagnose-webos26-native-sink-r284.sh](../tools/diagnose-webos26-native-sink-r284.sh), commit `8f51108`, SHA256 `29d917f7109e16a5f6162ddc7a2e0d9d39e145f4ea4e1c81d9219890fd62ec7f`.

Script only reports a bounded tail's marker counts, codec/PCM keywords, available DSP decoder **names** and allowlisted Luna fields. No raw movie paths, URLs, user app payloads, raw logs, media control, restart, service or firmware modifications. Run with DTS in the same player and compare to a known-good AC3/AAC track. Native renderer event counts are from the **last 3000 log lines, not an exact time window**; differences are suggestive, not absolute root-cause proof.

VPS verified `sh -n` and checksum; **R284 not yet run on kitchen LG**.

## 2026-11-22: DTS audio begins working after AC3 → DTS track switch (owner report)

**IMPORTANT NEW FIELD RESULT:** The owner first had no audible sound on **three DTS tracks** of *The Matrix*. Without changing our installed plugins or media service configuration, the owner switched the in-player audio track to **AC3**, then back to DTS. **All DTS tracks immediately became audible**. This is the first owner-confirmed live DTS sound on the kitchen LG with the existing AlekS installation. It is **not** proof of clean DTS first-start, reliable multiple cold starts, or successful passthrough of every stream.

**Reasoning (not proven root cause):** The initial DTS-only path may skip or misorder initialization of LG's native output renderer/resource grant or fail to construct a working PCM path. AC3 causes the native Dolby audio branch to initialize/reconfigure the resource/sink; subsequent DTS then has a valid or rebuilt audio route. A related `acquired-resource`/`fakeadec` and decodebin3 track-switch lifecycle issue was documented in `josippapez/dts_restore_plus` webOS25 README on different LG hardware; it is only an analogy, not direct proof here. The R283 Luna codec `dts` and 3 mapped AlekS .so modules proved detection/library loading before audible audio, **not** usable output.

**Next focused regressions:** (1) fully close media playback, restart same DTS track as *first* track without AC3; (2) compare with AC3-first then DTS; (3) switch DTS→DTS, pause/seek and test native player vs Lampa; (4) use read-only R284 renderer-log probe in both silent and audible conditions, preferably after a clean restart of player, and compare. Capture logs while conditions differ, not only after success. Do not change rank, GStreamer libraries or LG firmware based on this result. Don't add artificial AC3 switching as a hidden workaround until cause/side effects are verified.

**Revised status:** `DTS_DECODING_AND_LIVE_SOUND=CONDITIONAL_PASS_AFTER_AC3_SWITCH`, `DIRECT_DTS_FIRST_START=FAIL_OBSERVED`, `ROOT_CAUSE=UNVERIFIED`. Public webOS26 compatibility remains **experimental**, not universal DTS restore.

## 2026-11-22: repeat launch starts DTS with sound (owner report)

Owner fully reopened the player/movie after the earlier AC3→DTS recovery and confirmed **DTS played immediately on the next start**, without another AC3 switch. Therefore the earlier silent first-run behavior is **intermittent or session-dependent**, **not** a reliably reproducible failure on every new DTS launch. Do **not** hard-code an automatic AC3→DTS flip or change decoder ranks.

Supported operational summary: isolated DTS decode, source integrity and live plugin mappings PASS; `luna://com.webos.service.audio/tv/getAudioInputProperty` returns codec=dts; owner reports **audible DTS after AC3 switching and after a full player relaunch**. Acoustic output is only user-observed, not independently measured by the remote diagnostic connector. Cold TV boot, multi-playback regression, seamless DTS track switching, seeking, AC3/DVB and long-play stability are still not proven. The native sink/decoder lifecycle remains a hypothesis, not a demonstrated root cause.

Active route to kitchen LG was independently reestablished through `GameFree24 VPS MCP V3 → Alex Core task_queue → TORMOZ` executing the existing `ares-novacom.cmd` from `C:\Users\aerol\AppData\Roaming\npm` with its owner CLI profile environment (without SSH reconfiguration). A live read-only `id -u` returned `0`, `uname -m` returned `aarch64`, and `systemctl is-active umediaserver.service` returned `active`. The AlekS Core Windows service runs under SYSTEM, so its default PATH does not include this SDK. SSH reverse port 22022 is listening but new authentications were denied; using the already-functional Core avoids resetting bridges. No system modification made.

## Independent read-only verification after successful player relaunch — 2026-11-22

GameFree24 VPS MCP V3 -> AlekS Core task_queue -> TORMOZ Windows SYSTEM -> existing webOS SDK user profile -> aleks-kitchen-root successfully executed read-only checks. TV replied root UID0, aarch64, active umediaserver. No SSH, system media service or firmware changes.

During owner-confirmed audible DTS session, new starfish-media PID20727 mapped libgstaleksdts.so, libgstaleksdtsr130optin.so, libgstaleksdts16dec.so; PID20737 mapped none. umediaserver and audiooutputd services active. LG audio read-only Luna getAudioInputProperty returned codec=dts and returnValue=true. Codec capabilities SHA256 053190bf35dc1ce59124b098c5a38683d86a1c33e35c4bddbfdc22334860336c unchanged.

R284 renderer log probes found no selected events in last 3000 legacy-log lines, DSP proc directory unavailable: does NOT disprove audible playback. User confirmed sound after completely closing and reopening movie without any AC3 switch. Independently reran hash-pinned runtime script, PASS installed.env/registry/plugins integrity, env matches, umediaserver active, all live GST_PLUGIN_PATH_1_0/GST_REGISTRY_1_0/GST_REGISTRY_UPDATE/ALEKS_DTS_R130_ALLOW_AUTOPLUG settings. Sound is owner-observed, not a connector acoustic measurement.

STATUS: REPEAT DTS START LIVE AUDIO OWNER-PASS; CONFIG AND LIVE MEDIA PIPELINE VERIFIED; FIRST SILENT SESSION INTERMITTENT/UNKNOWN; FULL TV POWER-CYCLE AND MULTI-FILE REGRESSIONS NOT VERIFIED.

## R285 field stability monitor (2026-11-22, read-only)

New script: [tools/monitor-webos26-dts-runtime-r285.sh](../tools/monitor-webos26-dts-runtime-r285.sh), commit `d2ed98a00390dc8cd0543f33c3dcf620d95801bc`, SHA256 `86db4976c18525ad3131209616bf189e01a7036a5fe5dd2aee2e38c78bc60526`. Shell syntax and absence of destructive commands checked on VPS. Executed **directly on kitchen TV via existing AlekS Core route**; SHA256 verified on target.

| Sample | uMS PID/RSS KiB | Starfish active PID/RSS KiB/threads/CPU ticks | Other starfish PID/RSS KiB | audiooutputd PID | Luna codec |
| --- | --- | --- | --- | --- | --- |
| 1 | 1214 / 3384 | 20727 / 124216 / 72 / 35744 | 20737 / 7020 | 439 | dts |
| 2 | 1214 / 3384 | 20727 / 124216 / 72 / 36656 | 20737 / 7020 | 439 | dts |
| 3 | 1214 / 3384 | 20727 / 124216 / 72 / 37627 | 20737 / 7020 | 439 | dts |

All three AlekS DTS plugins (`libgstaleksdts.so`, `libgstaleksdtsr130optin.so`, `libgstaleksdts16dec.so`) remained mapped in active Starfish PID 20727 in all 3 samples. umediaserver and audiooutputd services remained active, no PID changes. Starfish RSS and threads remained unchanged, its CPU ticks grew (process actively executing), but without precise times/scheduler statistics we cannot attribute CPU load to DTS decoding alone. No service changes or player interactions; 3 samples separated by ~5 seconds each, **not a full long-play stability test**.

**Status:** R285 stability probe PASS for process persistence, library residency and no short-window RSS growth. Actual acoustic output remains owner-confirmed, not an independently observed audio sample. Cold-boot DTS-first path and long-play seek/track regression NOT YET VERIFIED.
