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

## R286: actual ALSA playback FIFO in RUNNING state — 2026-11-22

Additional **read-only hardware-level measurement via the existing AlekS Core → TORMOZ → kitchen LG** route after owner-confirmed working DTS:

- `/proc/asound/pcm` reports Realtek MARS PCM playback devices. `card0/pcm6p/sub0/status` **RUNNING**, other pcm0-5/7 initially closed.
- This live playback stream is owned by PID **1220**, `alsa-sink-MARS`, not the process directly loading AlekS `.so`. Its `hw_params` are `RW_INTERLEAVED`, **S16_LE**, **2 channels**, **48000 Hz**, period_size330, buffer_size1322.
- Two direct snapshots about 5 seconds apart: `hw_ptr` 29974272 → 30215168 (**+240896 frames**), `appl_ptr` 29975594 → 30215978 (**+240384 frames**), and ALSA remained RUNNING. This establishes active PCM FIFO consumption at approximately the expected 48 kHz, rather than merely registered GStreamer plugins.
- A reproducible read-only diagnostic was created as [tools/check-webos26-audio-output-r286.sh](../tools/check-webos26-audio-output-r286.sh), GitHub commit `33cd831ca21146eed098576e49d4e022ccd53b6d`, SHA256 `5c4bfe62bfddcddb98b4dcd734b48b35fb83bf9ba7dc22dbf54dde9bc80bc4e3`. VPS syntax PASS; TV SHA256 PASS. Device output: the same PCM6 RUNNING, owner alsa-sink-MARS, S16_LE 2ch 48kHz, pointer 32739072→32981760 (+242688), estimated ~48.2k frames/sec over 5.03s; the query again reported `codec=dts`.
- **Important correction**: kitchen LG's actual running ALSA output **accepts S16_LE**, contrary to treating an S16→S32 mismatch as a primary proven cause. Do **not** force an S32LE-only converter in production based on webOS25 examples. This observed two-channel ALSA output is a downstream playback format and does not itself prove the source DTS track or internal decoding was 2.0. Other DSP/proprietary audio stages may exist.
- Advancing hardware FIFO pointers **do not prove nonzero samples or audible speech**. Audible DTS remains reported by the owner, while remote evidence independently verifies an active PCM output contemporaneous with LG reporting `codec=dts`.

**Next real defect capture:** if a first-start DTS silence recurs, run R286 **while silent** before AC3 switching. Compare state of the PCM6 output, owner PID, pointer movement, codec and starfish mapped plugins with this known-good snapshot. If PCM remains RUNNING and pointers advance even in silence, inspect sample contents/muting/routing under separate authorized, isolated controls; otherwise focus on output resource grant/creation. Do not force AC3 toggles, restart native services or patch firmware without root cause.

## R287 extended live DTS/ALSA stability monitoring (2026-11-22)

Read-only script [tools/monitor-webos26-dts-output-r287.sh](../tools/monitor-webos26-dts-output-r287.sh), commit `bd514100379d24e24b75059b1043cf9b4d465604`, SHA256 `245da729a3e1d5db723803cbc6de342415934448d744201b1d2157648414afea`; VPS `sh -n` PASS and no service mutation/recording, target download SHA256 PASS, executed using existing VPS→AlekS Core→TORMOZ→LG route.

6 samples at 2026-11-21 22:27:58, 22:28:11, 22:28:25, 22:28:37, 22:28:50, 22:29:03 UTC, observed window **65 s**. Note script uses 10-s sleeps between queries but actual sample times are ~12–14 s due to collection overhead.

| Signal | Sample 1 | Sample 6 | Result |
| --- | --- | --- | --- |
| Starfish PID | 20727 | 20727 | No PID change (0/5 intervals) |
| AlekS DTS modules mapped | 3/3 | 3/3 | 3/3 in 6/6 samples |
| Starfish RSS | 118024 KiB | 118032 KiB | +8 KiB across window |
| Starfish threads | 72 | 72 | No change |
| Starfish CPU ticks | 97124 | 101650 | +4526; thread-level attribution not yet captured |
| uMS/audiooutputd | active/active | active/active | 6/6 |
| LG audio reported codec | dts | dts | 6/6 |
| ALSA PCM6 playback state | RUNNING | RUNNING | 6/6 |
| ALSA hardware pointer | 66776320 | 69897472 | **+3121152 frames**; 5/5 positive intervals |

ALSA hardware pointer average advancement ≈ **48.0k frames/s** over the elapsed 65 seconds, compatible with the previously measured stereo S16_LE 48-kHz ALSA sink. This does NOT prove nonzero samples, synchronization with video, absence of underruns, or successful audio output after a full TV power cycle. Source DTS decode, the ALSA sink and LG audio service are active *contemporaneously*, while audible sound was owner-confirmed previously.

**Verdict:** PASSED bounded 65-second process/service/plugin/ALSA-continuity checks, no short-window memory growth beyond 8 KiB, no service restart. Initial silent first-open remains unexplained; do not claim root-cause fix, apply rank changes or publish universal webOS26 compatibility.

## R288 passive per-thread CPU baseline under working DTS (2026-11-22)

Script: [tools/profile-webos26-dts-cpu-r288.sh](../tools/profile-webos26-dts-cpu-r288.sh), final commit `756c3c7ee64a2be3d705959256b47b64995aecbb`, SHA256 `b230a2759b0540390d87704e220c8bdb1bf93162a171418a600a43a68ef41a58`. VPS `sh -n` and synthetic AWK two-snapshot deltas PASS; exact file hash verified on kitchen TV; executed using existing AlekS Core, no service or playback changes.

Two earlier diagnostic executions were **invalid** and are **not** TV CPU results: the first mixed numeric sort and `join`'s lexicographic requirement; the second discovered **GNU `join` is missing** on LG's busybox shell. The script was corrected to a plain POSIX AWK associative-array merge and enforces nonempty thread intersection. Do not interpret those earlier `TOTAL_TICKS=0` values as zero load.

**Valid 10-second result:** Starfish PID20727, 72 threads stable, `CLK_TCK=100`, total **963 CPU ticks** aggregated across all media-process threads (roughly **0.96 logical CPU core** over ~10s, not DTS-specific).

| TID | Thread name (truncated kernel comm) | Δ CPU ticks, 10s |
| --- | --- | ---: |
| 20735 | souphttpsrc0sr | 258 |
| 20753 | multiqueueind | 153 |
| 20793 | aqueuesrc | 65 |
| 20733 | souphttpsrc | 64 |
| 20805 | OMX_VideoInput | 47 |
| 20840 | aqueuesrc | 40 |
| 20806 | OMX_VideoOutput | 30 |
| 20767, 20768, 20769 | multiqueueind | 19, 19, 18 |

**Interpretation:** currently the largest *individual* measured CPU consumers are HTTP source and queue threads, with some OMX video threads. This suggests measuring media source/buffering before attributing playback CPU consumption to DTS decoder. These are thread labels, not definitive code-stack hotspots; no independent pure-DTS decoding cost or AC3 control measurement was performed. This is a working-session baseline only. No production optimization, rank change or LG audio configuration change applied.

## R289–R291: working-session DTS vs audio output/mute and ARC/eARC — 2026-11-22

All commands were executed **on the kitchen LG** through the existing GameFree24 VPS MCP V3 → AlekS Core → TORMOZ SDK route, root read-only, no film interruption. Each shell script was SHA256 verified on TV and syntax checked on VPS.

| Probe | Source SHA256 | Evidence |
| --- | --- | --- |
| [R289](../tools/check-webos26-dts-first-start-r289.sh), commit `85823d0` | `ff5f09877bd08318fbb7cfd3d5d5c9d64ee504cc77fb3cb63368a1956a1be941` | New working-session reference fingerprint |
| [R290](../tools/check-webos26-audio-mute-route-r290.sh), commit `a764ecb` | `b39132e9a5e9353a14009ba12ff6937b53dc08a07da8c953cd8f91bcd82e568b` | Read-only LS2 output selection, volume, mute and internal source/sink |
| [R291](../tools/check-webos26-earc-route-r291.sh), commit `6489ba5` | `5780fb753e138291597b12aa30ab9d57ffd3035d9df0ecc71830271b1a7fdd07` | ARC state and ALSA eARC mixer read-only |

**R289 working-session fingerprint:** UTC 2026-11-21 22:37:05, `umediaserver` and `audiooutputd` active, Starfish PID20727 mapped three AlekS DTS plugins; `libgstaleksdtscaps.so` not mapped, which is not by itself a problem; 72 threads, RSS124684 KiB. ALSA card0 pcm6p RUNNING via `alsa-sink-MARS`, output S16_LE 2ch 48000 Hz, `hw_ptr` and `appl_ptr` each advanced by **194560 frames over ~4 seconds**, LG Luna codec `dts`. This is the **positive reference** for a future silent first-open, not an acoustic sample or demonstration that the first-start defect was repaired.

**R290 audio LS2:** LG codec `dts`, getSoundOutput `tv_external_speaker`, master volume23, audiooutput source `ADEC0`, sink `MAIN`, `muted=false`, `outputMode="null"`; audiooutput device volume query confirms muted=false and volume23 with soundOutput `tv_external_speaker`. **Do not interpret `outputMode=null` alone as no sound**: the owner previously confirmed audible DTS and direct ALSA PCM6 was RUNNING in this session. OSE audiooutput service semantics may not map one-to-one to LG's proprietary media/DSP output.

**R291 ARC/eARC:** ARC controller replied `arcActivation=not_ready`, `audioDeviceType=none`, `earcATMOS=false`, while getSoundOutput still `tv_external_speaker`. `amixer cget name='Sndout EARC OnOff'` gave `values=0`; `Sndout EARC Outputtype` gave `values=2,1,0,0,1` (vendor-specific, do not decode without verified mapping). Thus **there is no observed active ARC/eARC receiver route in the working session**; avoid blaming initial DTS silence on an HDMI ARC handshake without evidence. A selectable `tv_external_speaker` label is not proof of active ARC.

**Remaining uncertainty / next regression gate:** First silent session may involve initialization timing, player stream selection, resource grant, sink routing or a per-session race. The current healthy audio route **cannot uniquely identify the old fault**. If first-open DTS silence recurs, collect R289+R290+R291 *before* AC3→DTS switching; compare codec recognition, plugin residency, ALSA HW pointer advancement, mute/volume/output and ARC state to this baseline. If identical, these probes still do not measure whether PCM data contain actual nonzero audio; a separately authorized audio-content/meter test or more precise media-pipeline instrumentation would be needed. Cold power cycle, native LG player, seeking, long-play sync and regression are still unverified.

**Status:** live DTS route/stability checked; no production change, no auto-AC3 toggle, no unverified codec-rank or S32LE patch installed.

## R292: actual PulseAudio sink-input ownership vs DTS Starfish (2026-11-22)

**Important provenance correction** to R286–R291: live ALSA `pcm_output` running at S16LE stereo 48 kHz with advancing `hw_ptr` is a **real audio output**, but **alone does not prove that those samples are Starfish-decoded DTS**. A PulseAudio sink input may originate from web application audio independently of the native LG media pipeline. The owner has heard DTS, but no instrumented direct decoder→sink lineage is yet proven.

The R292 source [tools/inspect-webos26-pulse-dts-r292.sh](../tools/inspect-webos26-pulse-dts-r292.sh), final commit `f5d54b5516404ac2a7113af5c13ee4491f3ac3b9`, SHA256 `29b2e9324ff7e2425bbcf1b24ea147e0f4fdc4c7f2c26f3a3c53d591c40367d3`, passed VPS `sh -n`, synthetic short-sink parser test and on-TV SHA256, and was executed via the existing AlekS Core→TORMOZ→LG read-only route.

Measured under working video session:

| Layer | Observed process or signal | Evidence |
| --- | --- | --- |
| DTS GStreamer | Starfish PID20727 | `libgstaleksdts16dec.so` mapped; no proof decoder element instance is currently active |
| PulseAudio app stream | sink-input #5; `application.process.id=3217` | `/proc/3217/comm=WebAppMgr`, **different from Starfish PID20727**; input sink=1, 2ch S16LE 48000Hz, `Corked=no`, `Mute=no` |
| PulseAudio hardware sink | `pcm_output` (sink #1) | module-alsa-sink.c, RUNNING S16LE 2ch 48000Hz |
| Latency (at R292 capture) | buffer=64000µs, sink=23364µs | momentary reported latency, not measured A/V sync |
| LG native audio service | codec=dts, source=ADEC0→sink=MAIN, muted=false, outputMode=null | read-only Luna getAudioInputProperty and audiooutput getStatus |

The first R292 run incorrectly parsed `pactl list short sinks` due to the sample spec spanning **three whitespace tokens** (`s16le 2ch 48000Hz`). The corrected script prints `FORMAT=s16le 2ch 48000Hz STATE=RUNNING`, verified on actual LG.

**Do not infer** either that (a) Starfish DTS necessarily flows through the WebAppMgr PulseAudio sink input, or that (b) it bypasses PulseAudio. Both could occur via IPC, shared buffers or separate proprietary DSP paths; current evidence only identifies independent process owners. Similarly `outputMode=null` is observed in a working session and cannot be used as a sole failure marker.

**Root cause status:** first-open silence remains unexplained. A proper A/B failure capture would compare live Starfish decoder instance, native sink ownership, muting, and PCM sample flow before/after AC3 switching. Until reproduced, do not patch rank, DTS parser/decoder, S16/S32 converter, system services or first-track behavior speculatively. Acoustically verified output still derives from the owner's report, not the `pactl`/ALSA tests.

## R293: PulseAudio native client enumeration (2026-11-22)

Created [tools/inspect-webos26-pulse-clients-r293.sh](../tools/inspect-webos26-pulse-clients-r293.sh), GitHub commit `b6f2342d976e3faf93708f05c0ffc70f46708818`, SHA256 `7de436893ce9ab71cc972c08767b36f1ea784653900f938d077a800fa6ecce85`; source passed VPS `sh -n` and target SHA256. Executed read-only on kitchen LG via existing AlekS Core route.

PulseAudio clients exposed via native socket `/var/run/pulse/native`:

| Client | PID | Current process |
| --- | ---: | --- |
| #0 | 440 | `audiod` |
| #5 | 3217 | `WebAppMgr` |
| #18 | 32743 | Process already exited by time of `/proc` lookup; likely transient, unverified |

**DTS plugin holder is a different process, Starfish PID 20727.** No PulseAudio client with PID20727 appeared in this `pactl list clients` snapshot. The only active `sink-input #5` also belongs to `WebAppMgr` PID3217 (R292). Thus **do not claim** a direct `starfish-media → PulseAudio` client connection or that ALSA PCM6 FIFO advancement exclusively measures decoded DTS samples. Data support process ownership and simultaneous live codec/output activity only. An indirect bridge through `audiod`, `audiooutputd`, WebAppMgr, IPC or DSP is possible but unverified.

**R292 corrected source on LG** shows `pcm_output` sink #1 `module-alsa-sink.c`, `FORMAT=s16le 2ch 48000Hz`, `STATE=RUNNING` and its single active uncorked/unmuted input owned by WebAppMgr; read-only native LG audio service continues to report `source=ADEC0`, `sink=MAIN`, `muted=false`, `codec=dts`. No player interaction or system changes.

**Next scientific gate:** only a captured failed first-start session, and comparison to this working topology, can justify an initialization change. A fully resolved data provenance would require target-specific native GStreamer audio sink tracing and/or safely instrumented IPC/PCM data path, not assumed from mapping, PIDs or hardware pointer movement. For now live DTS audible success is **owner-reported**, and all instrumented checks are non-acoustic.

## R294 — independently verified kitchen LG reboot, installation survives and idle-vs-DTS reference (2026-11-22)

Confirmed from the actual TV over GameFree24 VPS MCP V3 → AlekS Core task queue → TORMOZ SDK → existing `aleks-kitchen-root` access. At UTC `2026-11-22T04:35:28Z`, `/proc/uptime` was `484.30` seconds; approximate current boot epoch `04:27:24Z`. This is a **genuine TV boot since the previous active DTS observations**, not merely a media-process restart. `/tmp/aleks-dts-r289.sh` and `/tmp/aleks-dts-r292.sh` were missing, consistent with temporary filesystem reset, but uptime is the primary proof.

The pinned read-only [tools/check-webos26-dts-runtime.sh](../tools/check-webos26-dts-runtime.sh) SHA256 `530c20a60df5c3af68144d5f9c2dde3d2b154b42dc64d8141fff0128f499318d` was downloaded fresh and verified ON TV. **PASS** installed.env/registry/plugin bundle SHA256, exact match `/var/systemd/system/env/umediaserver.env` to installed.env, `umediaserver.service=active` and all four values in the actual live uMS environment: `GST_PLUGIN_PATH_1_0`, `GST_REGISTRY_1_0`, `GST_REGISTRY_UPDATE`, `ALEKS_DTS_R130_ALLOW_AUTOPLUG`. Output `CONFIG_AND_PROCESS_ENV_PASS; NATIVE_AUDIO_NOT_YET_TESTED`. **This proves persistent installation and service environment after reboot, not that cold-first DTS has been heard.**

R290 and R293 were run again after cold boot, with verified file SHA256, to establish an **idle/broadcast reference**: `codec=mpeg`, `source=ADEC1`, `sink=MAIN`, `muted=false`, `outputMode=null`, `soundOutput=tv_external_speaker`, volume23, `ALSA_PCM6=closed`, `pactl` active sink inputs 0. PulseAudio client `audiod` PID440 present; no direct active DTS Starfish client.

Added unified read-only [tools/capture-webos26-audio-session-r294.sh](../tools/capture-webos26-audio-session-r294.sh), commit `826995766d571d1b3fdfc5634aba7bf68392cda3`, SHA256 `b90f4d27358264b85105be31bdb135b48e21c8f770509d35fc8dcf4a4355fb39`. VPS shell syntax PASS and no service/audio mutation commands, on-device SHA256 PASS and execution PASS. Real output at UTC `04:37:39Z` with uptime615s: services active, **STARFISH_PROCESSES=1**, **DTS_PLUGIN_HOLDERS=0**, PULSE_INPUT_COUNT=0, ALSA_PCM6=closed, codec=mpeg, native route ADEC1→MAIN, soundOutput tv_external_speaker. Classification `NO_DTS_PLUGIN_HOLDER_OBSERVED` is expected for this **non-DTS** session.

| Signal | Working DTS session earlier (R289/R292) | New boot with no DTS playback (R294) |
| --- | --- | --- |
| Process with three AlekS DTS plugins mapped | Starfish PID20727 | None, one non-DTS Starfish process exists |
| LG audio codec | dts | mpeg |
| LG native source→sink | ADEC0→MAIN | ADEC1→MAIN |
| PulseAudio active sink inputs | one WebAppMgr-owned input | zero |
| ALSA PCM6 playback | RUNNING with increasing pointers | closed |
| Selected sound output | tv_external_speaker | tv_external_speaker |
| uMS/AOD services | active | active |

**Interpretation:** This provides a real *non-DTS vs DTS* differential and a reference signature to detect whether a media player actually constructed the DTS path after a fresh boot. It does **NOT** prove that the historical silent first-start lacked this path: no snapshot was taken during the historical silence with these new probes. Codec=mpeg in the absence of PCM6 shows audio input property alone can describe a selected broadcast/input codec even if nothing is being rendered by PCM6.

**Do not run a warm-up test in the native system before the next first-start user test:** that would destroy the opportunity to observe any cold-first initialization race. Do not start/stop the user's playback, system services, adjust PCM format, decoder ranks or firmware just to force a condition. If the owner opens a DTS movie, collect R294 with the exact SHA-pinned script *while the new session is present* and compare above. If the owner reports silence, capture before switching to AC3; later compare after switching. No background process or TV watchdog installed.

**Status:** COLD BOOT DETECTED; DTS CONFIG AFTER REBOOT VERIFIED PASS; FIRST REAL DTS PLAYBACK AFTER THIS BOOT NOT VERIFIED; FIRST-SILENCE ROOT CAUSE UNKNOWN. All TV actions were non-destructive and read-only except staging the bounded diagnostic scripts under `/tmp`.

## R295/R296 2026-11-22: native audio policy API research and offline first-start comparator

### Current access limitation

An attempted read-only LG R294 snapshot through the previously working AlekS Core → TORMOZ → `ares-novacom` route was **blocked before execution by the platform's security controls**. Do **not** label that attempt PASS or route around the denial via an alternative bridge. No new measurement of the TV was collected in this phase, and the most recent verified on-TV evidence remains the post-reboot R294 idle snapshot. All actions below were GitHub/VPS **offline only**.

### New evidence from official webOS OSE API documentation

- [com.webos.service.audiooutput](https://www.webosose.org/docs/reference/ls2-api/com-webos-service-audiooutput/) describes a stateless HAL-facing audiooutput service and gives a **successful getStatus response with `outputMode:"null"`**. This field alone cannot establish audio silence. Official docs warn that application developers must not control audiooutput directly; we use **read-only** getStatus only.
- [com.webos.service.audio](https://www.webosose.org/docs/reference/ls2-api/com-webos-service-audio/) documents `UMI/getStatus` (audio resource connections, `audio.query`) and `getStreamStatus` (stream policy/active/mute status, API level12). These methods describe OSE; **consumer LG service signatures and permissions may differ** and have not been verified on the kitchen TV.
- [com.webos.service.avoutput](https://www.webosose.org/docs/reference/ls2-api/com-webos-service-avoutput/) documents `ADEC` / `MAIN` source/sink terminology; relevant historical interfaces are deprecated/retired and were not invoked.

### New read-only R295, staged only

[tools/inspect-webos26-audio-policy-r295.sh](../tools/inspect-webos26-audio-policy-r295.sh), commit `3d71e50687b83a1e28a80ee0bafc5c3f04943e69`, SHA256 `655fef7e918edae9b73c84b433c6a5ab2ad3c4bada4319c258147236f767fe98`. Only queries `audio/UMI/getStatus`, `audio/getStreamStatus` with `subscribe:false`, `audiooutput/audio/getStatus`, `audio/tv/getAudioInputProperty` using bounded `luna-send`. Prints only allowlisted scalar fields and counts, no full payload, session IDs, title, URLs, or media paths. Its flattened fields **do not preserve array-object linkage**: do not claim a source, mute flag and streamType all belong to one connection. VPS `sh -n` PASS; a synthetic JSON matching known field formats is parsed correctly. **ON-TV TEST NOT PERFORMED** due to the access restriction noted above.

### R296 offline differential comparator, verified

[tools/compare-webos26-dts-sessions-r296.py](../tools/compare-webos26-dts-sessions-r296.py), commit `8e74e5eed7a99f1f06395100e98a851b0f7f1cf0`, SHA256 `c455a48606e4486e3583a13673055148dd18c4b6197344ca16fce197d05e8223`. Python stdlib only, reads two user-supplied R294/R295 transcripts from local files and emits only known fields and differences. Separate hearing labels `--heard-before` / `--heard-after` default `unknown`; always reports `root_cause_verified=false`. Tests on VPS: `py_compile` PASS, `--selftest` PASS with 5 synthetic assertions (silent/working/idle and inference guard). No TV access, source audio or remote command in comparator.

Usage example (offline, after independently collecting paired samples): `python3 tools/compare-webos26-dts-sessions-r296.py before.txt after.txt --heard-before no --heard-after yes`. Absent/null fields remain unknown, not assumed FAIL.

### Data-backed working hypothesis — not root-cause proof

During prior owner-reported **silent** playback (R280/R283), three AlekS DTS shared libraries were mapped and LG API said `codec=dts`. During owner-reported **audible** playback (R289/R292), both remained true, while PCM, PulseAudio and ADEC route metadata were finally measured. Therefore **codec detection and .so mapping alone do not distinguish the two states**. A future concurrent silent→audible comparison must capture resource connections, native sink state, muted flags and timeline of audio creation. Existing historical traces do not determine whether the silent session had a missing ADEC grant, incorrectly initialized sink, empty samples, or another player race.

**Production and safety status:** no firmware, service, SSH, decoder priority, ALSA, PulseAudio or video playback changes. R295 is STAGED/NOT ON-TV VERIFIED; R296 OFFLINE PASS; first DTS startup after the last LG boot remains NOT VERIFIED.

## R297 (2026-11-22): offline regression gate and upstream first-play analogue

### What was corrected in R295/R296

- [R295](../tools/inspect-webos26-audio-policy-r295.sh), updated commit `51dd71d4dd9abbb6c9c8694b9c71476de5470c11`, SHA256 `9be7dd53179d38869e25f255cf6020bcc46bb27a9cfcf167ab96c1e8747764d6`: API-level `returnValue:false` now reports `QUERY_STATUS=API_RETURN_FALSE` with allowlisted errorCode only. A reply lacking `returnValue:true` reports `NO_SUCCESS_MARKER`. Only actual successful responses emit audio fields. Therefore the previous R295's generic `RESPONDED` is no longer confused with successful audio state; records from different array elements still deliberately lack linkage.
- [R296](../tools/compare-webos26-dts-sessions-r296.py), updated commit `1def1061bf7a2cea896eff7c83d6cc0e9048024b`, SHA256 `68d3282f98b6dd4e7d5d17d31700163abae1fac1ea8913764fdcebb2c3638735`: recognizes R289's real `LG_AUDIO_"codec":"dts"` line, R294's `DTS_PLUGIN_HOLDERS=0` and distinct output states, requires an accepted terminal `RESULT` marker, rejects failed API replies, and refuses to attribute flattened UMI stream states to a single DTS source. If the 'before' sample is idle/MPEG, the comparator explicitly refuses to call it a 'silent DTS first-start'. `root_cause_verified` is **always false** pending independent causal proof. Selftest 15 AST-counted assertions PASS, and two-file CLI real-shaped fixture comparison PASS on VPS.

### Durable repeatable QA

Added [tools/test-r295-r296-offline-r297.sh](../tools/test-r295-r296-offline-r297.sh), commit `6de056a1cdd4f2e2122350555e3e32dd14810c4a`, SHA256 `d1220b7f329f0a3d2e49ed6053a0dc07ef54359f340025ff37404afaef8c2542`. POSIX shell + Python3; uses its **own mock `luna-send`** at the front of PATH to simulate `returnValue:false`, missing success and valid responses, ensures rejected API data do not leak into output, then runs R296's selftest and end-to-end idle-vs-working comparison. Checked on FI VPS with downloaded SHA256-verified R295/R296 files: **R297_OFFLINE_QA_PASS** (no connection to LG, no real audio API call). Existing historical R215 AudioD/Starfish parser regression reran **18/18 PASS**; that is an offline test of the **other LG lab session**, not a kitchen playback result.

### Independent upstream first-play precedent (research only)

`josippapez/dts_restore_plus` [upstream README troubleshooting](https://github.com/josippapez/dts_restore_plus#troubleshooting) documents that on some older LG webOS models DTS/audio detection may fail on the first play after boot and work after **closing and replaying** the video. This matches the *form* of the kitchen owner's intermittent initial silence followed by success after AC3→DTS and a full player relaunch. **It is not proof that the native failure mode is the same**, nor that a plugin priority increase or a forced AC3 track switch would correct it. Its compatibility targets differ from kitchen webOS26.

Historical separate hall-TV lab work R213/R215 measured an ~8.0-second **Starfish playback lifecycle** excess for DTS5.1 vs AC3 and AudioD `pcm/channel=-1` vs `ac3/channel=6` in tests on **another LG**, with standalone decoded EOS normal. This is a possible component to include in future investigation, not verified on kitchen; application PLAY→PAUSE timing is not Gst EOS timing, and `channel=-1` cannot independently establish silence.

### Current release gate

Kitchen after last known reboot: persisted installation/configuration PASS, idle `codec=mpeg`, ALSA PCM6 closed. Owner previously confirmed **audible DTS** in earlier session after track switch and on player reopen. A subsequent diagnostic call to kitchen was blocked by platform safety controls; no attempts to use an alternative route. **R295 and R297 were not run on the TV**. Missing cold-first acoustic evidence and native decoder→sink lineage remain the release blockers. Do not install speculative workarounds or publish a generalized webOS26 DTS fix.

## R298 (2026-11-22): correct R282 lifecycle false PASS; EOS is not a clean process exit

**Re-audit of the real R282 field output supplied by the owner:** All four `decodebin3` cases (`db3_stock`, `db3_lg`, `db3_aleks`, `db3_aleks_pcm2`) found the AlekS DTS decoder, emitted `Got EOS`, negotiated the expected PCM caps (6-channel for three modes, S32LE stereo for PCM2), showed no selected negotiation errors, but every `gst-launch` command returned `exit=143` under a `timeout 12` wrapper. Exit143 conventionally denotes termination by SIGTERM (128+15); **`Got EOS` is a GStreamer bus message, not proof the process exited cleanly**. The exact SIGTERM source and whether GStreamer teardown stalled are **not established**. In particular, do not claim that `exit143` proves a decoder bug or explains the intermittent audible first-run silence.

### Source QA corrections

- Patched [tools/test-webos26-decodebin3-pcm-r282.sh](../tools/test-webos26-decodebin3-pcm-r282.sh), commit `af6c13091e23956e1e8ea93f9fff9d6e14339d3f`, SHA256 `3966f8b7d10a4d2b9d41b356cecb15b67ec4a5703d061094f6640c7b0d23a66f`. Each mode now needs `exit=0`, DTS element, EOS, expected PCM caps and no negotiation markers for a **clean PASS**. Each nonzero exit gets a non-PASS verdict, with `exit=143` explicitly flagged as SIGTERM, `124` as timeout (vendor timeout behavior might differ). The overall R282 diagnostic now returns **nonzero** and `RESULT=...INCOMPLETE` unless all four modes cleanly pass. This is an update to a QA script in GitHub only; NOT installed as an audio-decoder modification.
- Added [tools/audit-webos26-r282-exit-r298.py](../tools/audit-webos26-r282-exit-r298.py), final commit `68950d0728a5c577780a04b44e361beefa7599b6`, SHA256 `85a2209294ab4f9869bb9413cafc44fe679589f5a0906e922aff079a623021af`: offline analyzer for historic/future R282 console output, requiring four distinct known modes and exit0 for a clean verdict. On FI VPS Python syntax PASS, **14 assertions PASS**, and **legacy observed four cases** `SIGTERM_EXIT_143_NOT_CLEAN` 4/4, overall `all_clean=false`, `--strict` exit2. `root_cause_proven=false`, `native_audio_tested=false`.
- Added [tools/test-webos26-r282-exit-r298.sh](../tools/test-webos26-r282-exit-r298.sh), final commit `6199e7dbd2c2a06d78232fc5759243eb75091cec`, SHA256 `9d69d7b236a59f98bc1b37e6a4a4af448abbf7b5e03662bda23a9e7390a357e9`. It creates an **isolated temporary copy** of the actual R282 script with fake fixture and `gst-launch`/`gst-inspect` executables. The clean simulated case emits EOS/PCM and exits0 for 4/4 **PASS**; simulated EOS/PCM with exit143 for 4/4 is **REJECTED** by the R282 strict gate. On FI VPS `sh -n` and full integration **R298_OFFLINE_R282_STRICT_LIFECYCLE_QA_PASS**; all mocks are local, no TV or physical audio device contacted. Initial harness failed because its placeholder SHA had been truncated; corrected to the exact 64-hex R282 fixture reference and then passed.

### Boundaries and follow-up

- Current R282 historical result is **decoded PCM/EOS detected, process lifecycle INCOMPLETE**, not a clean end-to-end pipeline pass. Previous R281 `decodebin` runs `exit=0` remain valid isolated decode tests. A real GStreamer EOS→shutdown trace on kitchen is **not available**; do not conflate native Starfish first-start silence with synthetic tests or the historical R282 process signal.
- New on-TV calls remained blocked by platform safety controls; we did not retry through alternative routes, touch systemd, change codec ranks/PCM, load or restart a media stream. To establish actual teardown defect, a separately authorized non-disruptive on-device trace would have to show timing of EOS, NULL transition and process wait/exit; nothing collected here justifies patching production.

**Status R298:** diagnostic scripts and offline regression **PASS**; historic R282 **NOT CLEAN**; cause of LG first-start silence **UNVERIFIED**.

## R299 (2026-11-22): BusyBox-vs-GNU timeout provenance; improve R282 shutdown evidence

**New independently reproduced result ON FINNISH VPS ONLY:** With a one-second deadline and a mock child printing `Got EOS` immediately before running longer than the deadline, GNU coreutils 9.4 `timeout` returned **124**, while BusyBox 1.36.1 `timeout` returned **143**, and BOTH logs contained the EOS marker. BusyBox `timeout 2 sh -c 'exit 143'` also returned 143 without deadline expiry; BusyBox with child exit0 returned0. Thus **the same numeric 143 is ambiguous**: it can be the BusyBox timeout wrapper expiring, an explicit child status 143, or signal-style exit reporting. EOS says the pipeline got an EOS event, **not** that its teardown had completed or that the DTS decoder caused an error.

**Critical scope limitation:** The kitchen LG webOS26 `timeout` executable/version has **NOT** been independently identified in this phase because further device calls were blocked earlier. The measured BusyBox behavior makes the historical R282 `exit=143` *compatible with its 12-second wrapper expiring*, but does NOT establish that this happened on kitchen LG. Likewise it does not establish an internal GStreamer deadlock or link to the owner's initial DTS silence.

- Added reproducible [tools/test-timeout-exit-r299.sh](../tools/test-timeout-exit-r299.sh), commit `2fc7df746c54b5804736a4674d9323427fa57fe2`, SHA256 `9e05132d49dde4c1d2c45946b1b907ce3027de767527b45c39abc81fb0bc8688`. On FI VPS `sh -n` PASS, **R299_OFFLINE_TIMEOUT_SEMANTICS_PASS**; prints GNU timeout expired exit124, BusyBox expired exit143, BusyBox child explicit143=143, child clean0, EOS present in both timeout cases.
- Enhanced read-only isolated [tools/test-webos26-decodebin3-pcm-r282.sh](../tools/test-webos26-decodebin3-pcm-r282.sh), commit `0576709bfb0f2f7f783f78de6069899715c11997`, SHA256 `af8f6256bba2aadee99f8c8ceee78543d31c9ba9d2859176af4cc4ea945106bd`. Each test now records `LIFECYCLE=... elapsed_wall_s=... timeout_limit_s=12 null_transition_seen=... pipeline_free_seen=... deadline_compatible=...` based on bounded stdout and timestamps. `deadline_compatible` means only exit143 near the 12-second limit, **NOT a causal classification**. Existing strict exit0+EOS+PCM conditions preserved; no script executed on kitchen TV.
- Enhanced [tools/test-webos26-r282-exit-r298.sh](../tools/test-webos26-r282-exit-r298.sh), commit `0f0355ab08f4af54471c3951d2585e67cc2d58c1`, SHA256 `aab434044b45f5b12fbcff0d1da1c09045636ea9d3ef4b5c2b411036f4d1a63d`. Hermetic real-source mock now checks clean EOS+exit0 also prints NULL/freeing markers 4/4, whereas synthetic EOS+exit143 is rejected with no freeing marker and `deadline_compatible=no` (mock exits immediately, not via deadline). On FI VPS `sh -n` and full **R298_OFFLINE_R282_STRICT_LIFECYCLE_QA_PASS**.

**Next discriminating test if TV read-only diagnostics are independently authorized:** identify LG's actual `timeout` executable behavior first, then examine per-case measured elapsed time and the `Setting pipeline to NULL` / `Freeing pipeline` milestones in its own bounded R282 logs. A full original 12-second wait without exit0 should be classified INCOMPLETE; the presence/absence of cleanup strings is suggestive only, not a guarantee of successful system resource teardown. No GStreamer pipeline was started on the TV in R299.

**R299 status:** Tool and QA improvements OFFLINE VERIFIED; *whether R282 exit143 represents a timeout or an actual GStreamer shutdown defect* remains NOT VERIFIED; original intermittent kitchen DTS silence root cause still UNKNOWN.

## R300 (2026-11-22): opt-in distinct timeout signal to disambiguate BusyBox deadline vs SIGTERM (offline)

**Observation on FI VPS, not the LG:** BusyBox 1.36.1 `timeout 1` with the default signal TERM returns **143** when the deadline expires, even when the child has printed `Got EOS`. With `timeout -s USR1 1`, the same deliberate deadline returns **138** (128 + SIGUSR1), whereas a child which self-terminates under SIGTERM inside the USR1 wrapper still produces **143**. GNU coreutils timeout with USR1 expiration returned **124**; a clean child returns **0**. This provides a **more discriminating optional signal mode** for future isolated QA but never absolute proof of causation from a lone numeric code.

- Added [tools/test-timeout-signal-r300.sh](../tools/test-timeout-signal-r300.sh), commit `72031f357f98c3b18ec555a54f60b45c7415ddf5`, SHA256 `d50f4b4ac698ba815d6acd7f7076520bcd38f6cfe59f8540e7dbc8bf8c7bee6b`. FI VPS `sh -n` PASS, actual five synthetic timeout/exit conditions PASS, terminal `R300_OFFLINE_TIMEOUT_SIGNAL_DIFFERENTIAL_PASS`. No on-TV commands or DTS media streams.
- Updated [tools/test-webos26-decodebin3-pcm-r282.sh](../tools/test-webos26-decodebin3-pcm-r282.sh), commit `ec8b669a50d4b54e30969f4cc1aa81cd6f338425`, SHA256 `cfe0d9a54341c8fc51acea900548810c18a697049da27548f68fc9baa4d82681`. **Default remains TERM**. Only when explicitly invoking `R300_TIMEOUT_SIGNAL=USR1` does the isolated QA wrapper send SIGUSR1 at 12 seconds. Both modes log the configured signal and record deadline compatibility from the exit code and measured elapsed time: BusyBox TERM→143, BusyBox USR1→138, GNU timeout→124. These are compatibility checks, **not** direct proof of why the child exited. Unknown signal modes fail immediately with exit2. Strict quality gate still requires clean exit0, EOS, decoder, PCM caps and no negotiation error.
- Expanded [tools/test-webos26-r282-exit-r298.sh](../tools/test-webos26-r282-exit-r298.sh), final commit `596898c1704e9a9d9d5afe9a09661c0fce253159`, SHA256 `bc67b2f4cd9b5a68cb7bfbee14891a0afa5876e6c695c40ec0331e441c12865a`. Hermetic source-backed mock on FI VPS: baseline EOS+exit0 PASS, EOS+exit143 NOT PASS, USR1 opt-in + child exit143 NOT PASS with explicit distinction, USR1 opt-in + exit0 PASS, synthetic USR1 code138 NOT PASS, invalid mode exits2. All checks and shell syntax PASS; summary `R298_OFFLINE_R282_STRICT_LIFECYCLE_QA_PASS; REAL_LG_NOT_TESTED`. A test-harness editing error temporarily produced malformed shell quoting; restored the pre-change verified script, applied a safe replacement and reran all checks successfully. This was a GitHub QA file only, not a production artifact.

**Important limitations:** Switching to USR1 changes the *test wrapper* signal and must be deliberately opt-in; it is **NOT** a runtime workaround for the user's player or Starfish media service. Current TV command execution was previously blocked by safety controls; R300 did not access TV or reconfigure SSH. We still do not know which timeout utility LG ran for the historical four `exit=143` cases, nor whether an EOS→NULL transition stalled; and none of this proves a cause of intermittent DTS silence. No rootfs, DTS plugin rank, service, decoder or user playback change.

**Status:** R300 OFFLINE PASS, LIVE LG untested, historically silent first DTS start unresolved.

## R301 (2026-11-22): parse the missing R282 LIFECYCLE data, offline evidence gate

**Concrete defect identified in prior QA:** the R282 shell reporter was enhanced at R299/R300 to emit one `LIFECYCLE=<mode> ...` line per case with elapsed time, timeout signal, observed GStreamer NULL/free milestones and deadline compatibility. The existing R298 Python auditor **only parsed `CASE=` lines**, so it could not use or validate any of these new milestones. This was an analysis gap, not a demonstrated production DTS decoder failure.

Added [tools/analyze-webos26-dts-lifecycle-r301.py](../tools/analyze-webos26-dts-lifecycle-r301.py), commit `8eff8fc3fa726e2ee0529d42a549b0455b78d2b5`, SHA256 `5ef06ba359376f225ca03d79830a6896af2babc9856ed97d06f576238bd7d669`, Python standard library only. It explicitly requires R298 alongside it; parses both `CASE` and `LIFECYCLE` entries by mode, rejects duplicates/partial lifecycle, handles the terminal RESULT marker, and does not treat an incomplete run as PASS. States include `EOS_NULL_FREE_RECORDED`, `EOS_NULL_NO_FREE_MARKER`, `EOS_NO_NULL_MARKER`, `NO_LIFECYCLE_EVIDENCE`, plus `BUSYBOX_TIMEOUT_OR_OTHER_TERM_COMPATIBLE`, `BUSYBOX_USR1_DEADLINE_COMPATIBLE`, `TERM_EXIT_WHILE_WRAPPER_CONFIGURED_FOR_USR1`, etc. **They are evidence descriptions, not verified crash causes.** It always sets `real_lg_tested=false`, `acoustic_output_tested=false`, `decoder_root_cause_proven=false`.

Expanded [tools/test-webos26-r282-exit-r298.sh](../tools/test-webos26-r282-exit-r298.sh), commit `0d7bf18577d5aefe32e551e0f942e5d32870e7dc`, SHA256 `d403d6bbbd23f19162c42ce0cfdcfd8d2675b61bc1e8185e9d5704c29c8162fe`. The hermetic VPS harness now runs the actual R282 source in an isolated mock environment and feeds its **actual console output** into R301 for three integration controls: EOS+exit0+NULL+freeing yields a strictly clean complete timeline, EOS+exit143 without NULL/free is rejected, and USR1 synthetic exit138 is rejected. Additional R300 earlier scenarios retained.

**On VPS, independently verified:** R301 parser `--selftest` PASS with **13 assertions**, legacy R298 parser 14 assertions PASS, `sh -n` for both underlying R282 and test harness PASS, source-backed R298/R300/R301 integration PASS including `R301_SOURCE_BACKED_CLEAN_TIMELINE_PASS`, `R301_SOURCE_BACKED_SIGTERM_TIMELINE_REJECTED_PASS` and `R301_SOURCE_BACKED_USR1_NOT_CLEAN_PASS`. Actual prior four R282 field `CASE` lines (source-shaped, no LIFECYCLE because that earlier script did not emit it) were rechecked: exit143 4/4, **seen_lifecycles=0**, `NO_LIFECYCLE_EVIDENCE` 4/4, `r301_complete_qa=false`, `--strict` exit2. This proves the historical log cannot pinpoint EOS→NULL/freeing, **not** that the decoder shutdown is broken.

**Interpretation guardrails:** A logged `Freeing pipeline` marker does not by itself prove internal resources were freed; lack of the marker does not prove a deadlock (process may have been killed by timeout). GNU vs BusyBox timeout exit statuses differ and real kitchen TV timeout implementation has **not** been established. No first-start silent/audible paired telemetry is available. None of the new QA tests accessed the kitchen LG or changed production code, audio, services, SSH or firmware. Prior platform denial was respected.

**Next release gate (once direct TV diagnostics are allowed and owner initiates DTS playback):** first determine on LG which timeout is used, then capture bounded R282 timeline on a **separate isolated fixture**, never while interrupting the owner's film. If silence recurs, collect R294/R295 at the moment of silence before track switches and compare with the working output; root cause remains unverified.

## R302 (2026-11-22): inspect first-frame metadata bridge and recover lab QA reproducibility

**Scope:** source-level audit of old **experimental, not currently deployed** lab components `r184_gstaleksdtsstable.c`, `r186_gstaleksdtsbounded.c`, `r188_dts_framer.h`, `r188_gst_framer.c` on Finnish VPS. Kitchen LG's active R278 `libgstaleksdts16dec.so` and associated plugins are different; the R184/R186/R188 findings are NOT causal evidence for the kitchen silent first play.

### First-frame path, existing source behavior

- R184 metadata bridge probes only the **first input buffer** using `r122_dts_probe_be16`. On insufficient/invalid bytes, it sets `attempted=TRUE` and returns `GST_FLOW_OK`, leaving stream metadata unresolved until a new stream/flush boundary. No buffering/reassembly of encoded payload.
- R186 improved metadata probe: retains at most an 11-byte header prefix and checks up to **8 incoming buffers**, clearing/reinitializing state on `GST_EVENT_STREAM_START` and `GST_EVENT_FLUSH_STOP`. Its source explicitly warns that this **does not repair a split encoded DTS frame**: the `GstBaseTransform` still forwards original input buffers in-place; it can validate metadata without constructing frame-aligned downstream packets.
- R188 lab framer contains a bounded encoded-frame assembler (maximum 16 KiB per complete frame, max 1 MiB per feed) which buffers fragments and emits whole frames. Its lab plugin is `GST_RANK_NONE`; it is **not** the deployed kitchen decoder. Its event handler resets on `STREAM_START` and `FLUSH_STOP` and checks incomplete EOS. Existing R188 experiments/test history are not a substitute for on-device cold first-start A/B proof.

**Research hypothesis, not an identified production bug:** if a real first DTS packet is fragmented and the active decoder chain lacks a suitable parser, downstream could see incomplete frame payload despite correct channel/rate metadata. Current LG observations do not show first-packet bytes, decoder element instances or sink ownership during *silent* session, and R278 internals are not demonstrated to match R186. Do not install a hypothetical framing fix or modify plugin ranks on this basis.

### Concrete R188 QA infrastructure failure after VPS reboot

Running existing `/opt/gamefree24-vps-mcp/src/r188_asan_ubsan_qa.py` on 2026-11-22 produced `R188_SANITIZER_TEST_FAILED_INVALID_SOURCE_PIN` **before GCC/ASan/UBSan launched**. The script hardcodes five SHA256-pinned dependencies. Verified **two persistent sources present and hash-exact**, while the other **three files below `/tmp` are missing** after a VPS reboot; this is NOT a DTS codec test failure:

| ID | Pinned file | Observation |
| --- | --- | --- |
| R188 C header | `/opt/gamefree24-vps-mcp/src/r188_dts_framer.h` | SHA256 PASS |
| R188 clock QA C | `/opt/gamefree24-vps-mcp/src/r188_clock_qa.c` | SHA256 PASS |
| R122 parser header | `/tmp/aleks-r120-armel-qa/r122_dts_core_probe.h` | MISSING |
| DTS 5.1 QA fixture | `/tmp/aleks-r171-sdk/qa/dts51-audioonly.mkv` | MISSING |
| DTS 2.0 QA fixture | `/tmp/aleks-r171-sdk/qa/dts20-audioonly.mkv` | MISSING |

Added [tools/audit-r188-replay-prereqs-r302.py](../tools/audit-r188-replay-prereqs-r302.py), commit `bf35123e69a777904eb722eb963fb530c8f1c637`, SHA256 `c6fe6c15e13892d2d709f57409483c4f3e47a121a0aa4ed41ea49ef4f0542c1d`. Stdlib-only, read-only checker verifies all five **original pins**, rejects symlinks and treats missing/mismatch/read errors separately. VPS `--selftest` **PASS** (missing, hash mismatch, symlink and result-guard cases). Real host `checked=5, sha256_pass=2, missing=3, mismatch=0`, classification `R188_QA_BLOCKED_BY_PREREQUISITES_NOT_A_DECODER_FAILURE`; `--strict` explicitly exits **2**, not a false PASS. No large media files copied or recreated. VPS root filesystem was 94% full with ~6.1 GiB free at capture, another reason not to duplicate large fixtures casually.

**Recovery gate:** restore the original R122 header and the two owner-created pinned fixtures from their authoritative backup with identical SHA256 into persistent nonvolatile staging (not /tmp), then adapt isolated test harness to accept verified paths. Do **not** fabricate replacements and call the old 27/27/ASan/UBSan R188 QA passing; replacing fixtures or changing pins creates a NEW test lineage that must be named separately. Current R188 sanitizer test status = **BLOCKED**, not failed decoding.

**Status:** R302 original-source audit and prerequisite checker ON VPS verified; original R188 ASan QA BLOCKED by missing dependencies; kitchen LG NOT TOUCHED and first-start DTS silence root cause still NOT VERIFIED.

## R303 (2026-11-22): original R188 dependency recovery without altered SHA pins

**Goal:** recover exact historical R122 header and two R171 owner-created DTS audio fixtures required by the original R188 ASan/UBSan laboratory QA after the Finnish VPS reboot. **No source file or fixture was fabricated, re-pinned, or inserted into the production system.**

### Read-only source and archive discovery

- Confirmed VPS hostname `mediarus.com`; `df -h /` still shows **94%** in use, approximately **6.1 GiB free**. Conserved disk capacity and avoided copying media or unpacking archives.
- Searched only relevant explicit project/staging directories on VPS, a compact prior-source backup `/opt/gamefree24-vps-mcp/private-maintenance/old-source-backups-before-20261025-compact-20261101.tar.gz`, and relevant GitHub repository paths/commits (AlekS-DTS-webOS and AlekS-LG-65NANO896PC). **No SHA-matching original R122 header or R171 DTS 5.1/2.0 files were found** in those checked places. This is a scoped search, not evidence the files are nowhere else.
- The archive can be opened, but the recovery scan found **0/3 matching originals** (`archives_opened=1`, `replay_ready=false`, exit2). Dry-run only; **no archive extraction or staging on VPS**.

### Repeatable, fail-closed recovery helper

Added [tools/recover-r188-original-pins-r303.py](../tools/recover-r188-original-pins-r303.py), final commit `05631e256ad5f5fb46a72368feea218a98946f25`, SHA256 `61bc17cb59ec79807a37bd00e153d09b38a47db0113f08a9b39ff3b79f2fd7dc`. It checks exactly the three expected historical SHA256 hashes and **accepts only explicit local source directories/files or tar/zip archives**; no systemwide search, network or TV connection. Archive member paths are not trusted or used for output; symlink, traversal and oversized entries are rejected, with a member count cap. Dry-run by default. Optional `--stage-dir` saves **only matched** files with exclusive-create, post-write verification, no overwrite of mismatched existing files, and rejects symlinks in staging parents. Does not touch any production paths.

VPS validation: Python compile PASS; `--selftest` PASS for exact-hash source, original-like synthetic **test-only** fixtures, nested tar, ZIP member, malicious traversal, symlink archive entry, symlink staging ancestor, idempotent staging and existing-file hash conflict. Mock bytes are clearly **not** the original R171 fixtures. Applied on the real old compact backup **read-only**, match count 0, strict exit2 as expected.

**Status:** R303 tool OFFLINE PASS. Actual R188 full sanitizer replay **BLOCKED: three original SHA-pinned prerequisites remain missing**. This does not prove an audio decoder defect or identify the kitchen LG first-start silence; kitchen TV and production R278 were not accessed or modified. If authoritative originals reappear, verify all hashes with R302/R303 and stage persistently before rerunning the exact old R188 QA. A new synthetic regression must have a distinct test identity and cannot be represented as the prior original 27/27 run.

## R304 (2026-11-22): independent synthetic first-frame / DTS-like fragmentation C99 regression

**Purpose and provenance:** A new, clearly separated synthetic QA lineage for the **original R188 bounded BE16 frame assembler core**, not restoration of the old R188 owner-fixture ASan/UBSan run and not a test of the kitchen R278 decoder or LG hardware. The R122 dependency originally pinned by R188 remains absent. The following tests use a deliberately **non-compliant partial R122 test double** solely to exercise frame boundary logic with synthetic DTS-like headers. The generated frame body is arbitrary bytes and **cannot be played or decoded as DTS audio**.

### Sources, pins and sandbox isolation

- Original unmodified VPS `/opt/gamefree24-vps-mcp/src/r188_dts_framer.h`: SHA256 `8fcf17dd9d9890d26542f093a87f91e760e8ea8999619e17b4e56485b04bfa97`. C99 frame assembler: retains max 16384 bytes, rejects feed >1 MiB, validates BE16 sync/header via R122 API, accumulates complete frames and rational microsecond PTS, fail-closes on invalid data or sink rejection.
- [R304 synthetic R122 test double](../tools/r304-synthetic-r122-test-double.h), commit `aaf24680c3985d5235edbd6c814d598c1d8fafb6`, SHA256 `977f09779d5a3801aca383c876da0d6fe173acfc21823e55f4e9bed3967796fd`: only the R188-required `aleks_r122_read_bits` / `aleks_r122_dts_probe_be16` surface, 11-byte BE16-like bitfields and deliberately restricted synthetic channel/rate codes. **Not original R122, not an actual DTS Core parser.**
- [R304 C99 synthetic frame regression](../tools/test-r188-synthetic-firstframe-r304.c), commit `04431fd9b96a724612f7ca10be9e48170d561ba6`, SHA256 `8b6214e4365df94cb863bec33d1b6537aad15280a621c84d424c12b12e01c39b`: 23 named PASS groups. Checks 1/2/3/7/11/97/1023-byte fragmentation, whole multi-frame input, first header split at 1..10 bytes, byte-for-byte frame callback, stereo 48k and synthetic six-channel 44.1k metadata, reset of partial frame as a **C-level analogue** to FLUSH/STREAM_START, malformed sync/frame length/unsupported synthetic rate fail-closed, sink rejection, NULL/oversized inputs, unspecified PTS, PTS overflow, rate change/PTS discontinuity, rational clock over 9000 frames and 400 deterministic fragmentation trials.
- [R304 repeatable runner](../tools/run-r188-synthetic-firstframe-r304.sh), commit `d9bd27d33f0e5153f12b4d633607a2050dee7a63`, SHA256 `6edcb7a8526ed49d0137be16dd0f2560ce49e57d6a06141cc046e6306a9bb272`: checks all three file hashes; copies the actual R188 header plus the synthetic QA sources **only into a bounded temporary directory under /tmp** and deletes it after execution. Builds with GCC 13.3 `-O1 -fsanitize=address,undefined -fno-omit-frame-pointer` and separately `-O2` native C99; no production files modified, no audio devices/network/TV calls.

### Verified result

On Finnish VPS mediarus.com: initial independent C99 ASan/UBSan compile/run PASS all 23 groups; subsequently retrieved all three SHA-pinned files and reran [the reproducible R304 runner](../tools/run-r188-synthetic-firstframe-r304.sh). `sh -n` PASS, all source hashes PASS, `R304_ASAN_UBSAN_23_OF_23_PASS`, `R304_OPTIMIZED_C99_23_OF_23_PASS`, final **`RESULT=R304_SYNTHETIC_OFFLINE_QA_PASS; ORIGINAL_R122_AND_REAL_DTS_UNTESTED`**. No ASan/UBSan findings within this synthetic coverage.

**EOS limitation:** The pure C99 R188 core does not itself receive GStreamer EOS events. R304 confirms a truncated end-of-input leaves `framer.have > 0`, which the separate GStreamer wrapper is designed to reject at EOS; **it does not execute or verify the actual GstPad EOS / STREAM_START / FLUSH_STOP event handlers**. VPS has `gst-launch-1.0` but lacks `gstreamer-1.0` development headers (`pkg-config gstreamer-1.0` MISSING), so a GStreamer plugin integration build was not attempted; do not install packages onto the VPS just for this production-adjacent QA without appropriate planning.

**Boundary:** The original R188 sanitizer QA that requires the absent original R122 header + two owner DTS fixtures is **still BLOCKED**. R304 does not make that old original validation PASS. It does not verify genuine DTS bitstream acceptance, any decoder, PCM samples, acoustic sound, or first-start silence on the kitchen LG. R278 production files and uMS/Starfish services were not changed. Separate lab QA PASS only.

## R305 (2026-11-22): real GStreamer GstPad event regression on original lab R188, ISOLATED

**Purpose:** Extend R304 pure C99 synthetic first-frame checks to the **actual original R188 GStreamer wrapper** and real GStreamer pad-event dispatch: `STREAM_START`, `FLUSH_START`, `FLUSH_STOP`, `EOS`, `CAPS`, `GST_FLOW_NOT_NEGOTIATED`. All eight cases run on the Finnish VPS against **GStreamer 1.24.2**. This does NOT use genuine DTS media, the original missing R122 parser, or the kitchen's production R278 plugin. No LG, TORMOZ, service, firmware, audio sink or proprietary media accessed.

### Isolated SDK provisioning; no system package installation

- VPS runtime had `/usr/bin/gst-launch-1.0` and GStreamer 1.24.2/GLib runtime libraries, but lacked dev headers and `.pc` files. Downloaded **only two matching Ubuntu Noble developer `.deb` packages** over HTTPS to a private `/tmp` directory and extracted with `dpkg-deb -x`; no `apt install`, no system include/library changes, no service restarts.
- GStreamer 1.24.2 developer package SHA256 `616dab4dbd89fb66dda41e5195c5890ddce0b1c9d467d649cf3f7773d46165a8`; GLib 2.80.0 developer package SHA256 `6d1d88d68192256603c0de05d084b8ef06ed9b16753215ec2c1ef9ef5fa15014`.
- The original experimental C code `/opt/gamefree24-vps-mcp/src/r188_gst_framer.c` SHA256 `773aea865d8b49c36b7cf72b8baf56db5615670b80776622b1e5e23ca0146a52`; its companion `r188_dts_framer.h` SHA256 `8fcf17dd9d9890d26542f093a87f91e760e8ea8999619e17b4e56485b04bfa97`, both **unmodified**.
- Isolated GStreamer plugin builds from those original C sources linked against the already installed runtime `.so.0` files. Only `r122_dts_core_probe.h` in the private build directory was the **explicitly synthetic and non-DTS-conformant R304 test double**, SHA256 `977f09779d5a3801aca383c876da0d6fe173acfc21823e55f4e9bed3967796fd`.

### Genuine event test harness and defect in its first iteration

- Added [tools/test-r188-real-gstpad-events-r305.c](../tools/test-r188-real-gstpad-events-r305.c), final commit `f81b2d08f8cd7b469005353de994b137b84c8429`, SHA256 `935c03e126514559df70642079c859e94abf6f3548d634f1fbe89b7a5af3c0bf`. It builds actual `GstPad` upstream and downstream peers, instantiates the GStreamer-registered R188 plugin, pushes real `GstEvent` messages and `GstBuffer` payloads through the `GstPad` chain function, checks byte-for-byte output and downstream caps metadata. The downstream is a **test capture pad**, never a speaker/audio sink.
- First iteration: five cases PASS, added direct format change 2ch/48k→6ch/44.1k returned `GST_FLOW_NOT_NEGOTIATED`. GStreamer `GST_DEBUG` traced this to our **bare test sink pad lacking an appropriate CAPS/ACCEPT_CAPS query**, whose default query advertised `EMPTY` or only the old negotiated format. Adding an explicitly flexible `downstream_query()` that accepts `audio/x-dts` corrected the lab harness. Repeated direct format change then PASS, without changing original R188 C code or installing a speculative production patch.

**Eight source-backed real-GStreamer scenarios, verified:**

| # | Event/condition | Result |
| --- | --- | --- |
| 1 | Actual `STREAM_START`, fragmented first frame (single-byte chunks), downstream full frame, `EOS` | PASS |
| 2 | `FLUSH_START`/`FLUSH_STOP` removes partially buffered 13-byte frame then fresh stream | PASS |
| 3 | New `STREAM_START` resets prior incomplete 37-byte frame | PASS |
| 4 | Incomplete 71-byte frame at `EOS` is rejected; no downstream frame/EOS forwarded | PASS |
| 5 | After completed `EOS`, FLUSH and new STREAM_START permit replay in same element | PASS |
| 6 | Dynamic CAPS change from synthetic stereo 48k to 6-channel 44.1k forwarded and accepted | PASS |
| 7 | Invalid sync produces `GST_FLOW_ERROR`; FLUSH and new stream recover cleanly | PASS |
| 8 | Downstream deliberate `GST_FLOW_NOT_NEGOTIATED` propagates; subsequent FLUSH/restart recovers | PASS |

### Reproducible release QA

- Added [tools/run-r188-real-gstpad-events-r305.sh](../tools/run-r188-real-gstpad-events-r305.sh), commit `d231df20173ef486b3c3c9f1a28d0e7e074e340e`, SHA256 `dd49323556efc24b978bdd1ed7e7019b710e3760a3a8cdd93e7b2f06c8651424`. It independently fetches and verifies BOTH developer package pins and all FOUR source/test pins, extracts under `mktemp`/`tmp` with `trap` cleanup, compiles **native optimized -O2** and **ASan+UBSan -O1** versions, uses separate private GStreamer registry files, then requires exactly eight PASS markers and terminal `RESULT=R305_GSTPAD_EVENTS_8_OF_8_PASS` from each run.
- **VERIFIED ON VPS by running that exact downloaded immutable-commit script:** `sh -n PASS`; 6/6 SHA256 pins PASS; `R305_SDK_AND_SOURCE_PIN_PASS`, `R305_GSTREAMER_NATIVE_O2_8_OF_8_PASS`, `R305_GSTREAMER_ASAN_UBSAN_8_OF_8_PASS`, final `RESULT=R305_REAL_GSTPAD_EVENT_QA_PASS; SYNTHETIC_HEADER_NO_REAL_DTS_NO_LG`.
- GStreamer plugin-scan `GST_REGISTRY_FORK=no` is scoped to the sandbox test process to ensure AddressSanitizer is initialized in the same sanitized process as the plugin; it does **not** change system GStreamer. ASan/UBSan error detection enabled; leak detection disabled because GLib/GStreamer process-global caches make leak checks unsuitable for this harness. Therefore no claim of full system leak-free status.

**Interpretation and boundaries:** R188's real GstPad event handlers appear functional in these synthetic scenarios on GStreamer 1.24.2, so no R188 code changes were warranted. However this is an x86_64 userspace lab; kitchen LG webOS26 has a different media environment and uses **R278**, not the experimental R188 plugin. The original R188 owner-fixture QA remains BLOCKED due to the missing SHA-pinned original R122 and two DTS media fixtures. DTS decode/PCM sound and first-boot silent-vs-audible comparison on LG remain **NOT VERIFIED**. No change to installed DTS rank, decoder, production UMS, TV, firmware, or SSH.

## R306 (2026-11-22): real DTS Core raw-chunk loss vs correctly packetized frames (FI VPS ONLY)

**This is the first R30x test with genuine encoded DTS Core inputs, not synthetic DTS-looking headers.** On FI VPS FFmpeg's experimental DCA encoder generated a 2ch/48 kHz 440 Hz signal (144384 encoded bytes) and original multitone 5.1(side)/48 kHz (294912 bytes). FFprobe confirmed both real DTS. Two independent decoders in GStreamer, `dtsdec` and `avdec_dca`, plus FFmpeg decoded temporary PCM to disk; no speaker, LG, or movie content.

### Key demonstrated differential

With raw DTS supplied directly as arbitrary `filesrc` chunks into `dtsdec` (no packet framer installed on this VPS), PCM volume was **shorter and could vary between independent process launches**, despite exit status 0:

| Test | 11-byte raw blocks (first / repeat) | 97-byte raw blocks (first / repeat) | 4096-byte raw blocks |
| --- | ---: | ---: | ---: |
| Stereo, PCM frames | 61952 / 61440 | 70656 / 70656 | **72192** |
| 5.1, PCM frames | 64512 / 69632 | 72704 / 72704 | **73728** |

**Same encoded DTS frames, losslessly remuxed into Matroska, fed through `matroskademux ! dtsdec`:** all block sizes 11/97/4096 and a repeated 11-byte run produced **byte-identical PCM** at the full counts **72192 stereo and 73728 surround**. GStreamer `matroskademux ! avdec_dca` separately reproduced both full frame counts; FFmpeg's independent decoder also gave those exact frame counts. Matroska packet counts were 141 stereo and 144 5.1. The full packetized decoder audio was nonzero on all channels, per-channel RMS matched the FFmpeg reference within 8%, and the first substantial decoded sample fell around frames 513–514 (LFE ~386). These ordinary short initial codec samples do not explain a user-observed prolonged silent session.

**Interpretation:** in this **software lab**, arbitrary raw bytestream chunk boundaries at the compressed decoder input can result in missing PCM, whereas a proper upstream packet boundary-preserving demuxer removes that loss for the same DTS data. `dtsparse` was absent from this VPS; `matroskademux` supplied framed audio packets. This does **not prove** that the kitchen LG's native Starfish path or installed R278 receives improperly framed encoded data, nor that fragmented packet loss caused its initial silence. It does identify a concrete and now independently reproducible **candidate failure mechanism to check read-only on real LG** before patching any source.

### Repeatable code and verification

- Added [R306 end-to-end real DTS packet-boundary tester](../tools/test-real-dts-packet-boundaries-r306.py), final GitHub commit `92a9f1a8b170474f878d509179df5f9197a7fbc5`, SHA256 `129faf0b276df085e4e5e6f43fd99d64495e616d3be69538619d09c5def2ae24`. Stdlib Python creates the original tones and DTS frames using FFmpeg, verifies FFprobe codec+packet PTS/duration, compares three raw read sizes to three Matroska read sizes, checks actual PCM length, per-channel signal, independent FFmpeg/GStreamer decode, second GStreamer decoder and replay identity; prints all raw lost frames and rerun variability. Files kept only in a temporary directory.
- Verified by independently downloading GitHub commit to FI VPS and running it: **`RESULT=R306_REAL_DTS_PACKET_BOUNDARY_QA_PASS; LIVE_LG_R278_UNTESTED`**. FFmpeg 6.1.1-3ubuntu5+esm15; GStreamer 1.24.2. Script SHA and numeric outputs verified. See [standalone R306 report](R306_REAL_DTS_PACKET_BOUNDARY_QA.md) for SHA256 of packetized PCM, frame counts and exact reproduction commands.
- **No firmware/TV or production plugin changes, no new packages, no hardware audio output**. The old R188 owner-fixture QA remains blocked by missing original R122 and two DTS samples; R306 is a separately labeled, real-encoded-DTS lab lineage.

**Next evidence needed:** On kitchen LG, safely record first DTS sample/PCM production and **how the media/demuxer passes packet/frame boundaries to installed R278** in a silent versus audible session, plus audio output allocation state, only through authorized read-only diagnostics without interrupting the user's playback. Do not blindly insert the experimental R188 framer, switch tracks, change plugin ranks or restart LG services based on the VPS result.
