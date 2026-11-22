# AlekS DTS for LG webOS

[Русский](README.md) · [Documentation license](LICENSE.md)

> **R278: model-agnostic installer for compatible LG ARMv7 TVs.** No model, firmware-version or SDK allowlist. It checks native media dependencies and DTS/AC3 decoding before changing the media service configuration. [Installation](#installation)

**AlekS DTS R277** adds DTS Core decoding to the native LG webOS media pipeline. Support loads automatically when the TV starts. For the tested DTS 5.1 track, the native audio sink received six-channel PCM S16LE at 48 kHz.

## For other LG owners

Identify the **actual native media process ELF architecture**, GStreamer and `umediaserver` configuration before installation. Some newer TVs use a 64-bit Linux kernel but a 32-bit native media pipeline. Isolated audio tests are mandatory. See the [model compatibility matrix, safe discovery tool and rollback procedure](PUBLIC-COMPATIBILITY.md).

**The kitchen TV installer is a field-test candidate, not a universal release.** It checks the verified model's effective eMMC partition `/dev/mmcblk0p59`; do not run it on other LG models.

## Verified results

| Device or scenario | Result |
| --- | --- |
| LG 65NANO896PC, webOS TV 6.6.0, ARMv7 | R277 loaded after a full TV reboot |
| Built-in media player | The original DTS Core 5.1 clip played to the end. A listening test confirmed audio |
| Lampa | Audio was audible on every track the owner tried, including Russian DTS 5.1 and FLAC 2.0 |
| Regression checks | An AC3 5.1 clip played to the end. DVB-C passed before and after DTS playback |

DTS Core 2.0 and 5.1 also passed isolated tests. DTS-HD MA, DTS:X, DTS passthrough to a receiver, and other LG models require separate verification.

## Compatibility and limitations

| Device or platform | Status |
| --- | --- |
| LG 65NANO896PC · 03.60.96 · webOS TV 6.6.0 · ARMv7 · GStreamer 1.16.2 | DTS Core 5.1 verified on real hardware |
| LG UP75006LF · ARMv7 · R278 | **Installation and DTS playback confirmed by owner:** `R278 configured`, isolated DTS 2.0 / DTS 5.1 / AC3 tests PASS, and owner reports everything working after installation. Separate Live TV regression results and persistence across multiple reboots are not documented |
| Other LG ARMv7 TVs with native umediaserver / GStreamer | No model or firmware lock. The installer runs isolated DTS 2.0, DTS 5.1 and AC3 tests before enabling. Native-player playback still needs device-specific verification |
| LG 43NANO85A6A · webOS 26 · 32-bit ARM media userland on ARM64 kernel · GStreamer 1.24.10 | **Isolated DTS 2.0/5.1 and software AC3 PASS**; native-player playback remains untested; candidate installation and immediate rollback both passed, without reboot. The original R278 installer must not be used; a dedicated frontend is required |
| 64-bit native media process / different CPU ABI | Requires a build matching the actual native media process ABI |
| Different media pipeline/ABI, or modified media configuration | Installer must refuse before changing media-service configuration |

Root SSH and an existing Homebrew setup are required. No system libraries or firmware are replaced. A successful isolated GStreamer test does not guarantee correct sound on every built-in player.

Test a DTS Core file in the native player first; your TV may already support it.

## webOS 26: ARM32 media userland on a 64-bit kernel

**Confirmed on LG 43NANO85A6A, firmware 43.22.74:** `uname -m = aarch64`, while `/usr/sbin/umediaserver` and `/usr/bin/gst-inspect-1.0` have ELF class `1` (32-bit) and little-endian encoding; GStreamer `1.24.10`, runtime `libgstreamer-1.0.so.0.2410.0`. ELF `e_machine = 40 (EM_ARM)` is additionally confirmed for all three components. Both key DTS plugins loaded and DTS 2.0/5.1 decoding succeeded on GStreamer 1.24.10; native `umediaserver` integration is still unverified. **Do not build ARM64 plugins based solely on the kernel architecture**: plugins must match the 32-bit media process ABI and GStreamer 1.24.10.

No `dtsdec`/`avdec_dca` element, matching DTS mounts or DTS Restore files in the tested standard locations were found. This does not prove that a nonstandard DTS Restore or built-in decoder is absent. No media-service or configuration changes were made on the TV; diagnosis used temporary files only.

**Field tests, 2026-11-22:** ELF32 ARM, GStreamer 1.24.10 and archive/fixture SHA256 checks passed; `aleksdtsr130optin` and `aleksdts16dec` loaded; **DTS 2.0 and DTS 5.1 PASS**. Native `GstOMXAC3Dec` produced PCM S16LE/48 kHz and `Got EOS` both with and without AlekS DTS plugins, but the process stalled during teardown and was terminated by timeout (exit 143). This is **not evidence of failed AC3 decoding**. Clean-shutdown AC3 and native-player integration remain unverified. **Update:** later on the same day, installation and immediate rollback both completed successfully; native-player DTS was not tested.

**Do not install R278:** the installer checks `uname -m = armv7l` and rejects the 64-bit kernel. DTS plugins passed isolated checks on GStreamer 1.24.10, but clean-shutdown AC3, `umediaserver` integration, rollback and native-player playback have not been verified. Do not bypass this guard. Backups and further verification are required before changes.

A read-only preflight is available. It changes no files, services or mounts:

```sh
curl -fLsS --proto '=https' --proto-redir '=https' -o /tmp/aleks-dts-probe.sh \
  'https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/main/tools/probe-webos26.sh' &&
printf '%s  %s\n' '2cb5b838ec0a89eed6b0a3003d75cb30e2f200d3a6003bf2aeefa90df8dc0742' /tmp/aleks-dts-probe.sh | sha256sum -c - &&
sh /tmp/aleks-dts-probe.sh
```

Use the output to determine the actual ABI, DTS Restore footprint and umediaserver configuration. Migration then requires a backup, a build for the **actual 32-bit media ABI/GStreamer 1.24.10**, isolated DTS/AC3 tests, and native-player, Live TV and rollback validation. **No webOS 26 installer has been released yet.**

### Safe R278 verification on GStreamer 1.24 (no installation)

The LG 43NANO85A6A can run an **isolated** compatibility test of all four existing ARM32 plugins and three bundled audio fixtures. It verifies SHA256 and ELF32 ARM, uses a temporary GStreamer registry under `/tmp`, and checks DTS 2.0, DTS 5.1 and AC3. It **never** edits `umediaserver.env`, system files, mounts or services.

From TORMOZ PowerShell, using the already configured webOS SDK profile:

```powershell
ares-novacom --device aleks-kitchen-root --run "curl -fLsS https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/d0554defd64bd2831a2bc06e7edc65a1370e7b36/tools/verify-r278-webos26.sh -o /tmp/aleks-dts-verify.sh && echo '6e8dd4f813ca154b31ba96d8113b2c64a34e089dbdca11772858d6e5a7613f81  /tmp/aleks-dts-verify.sh' | sha256sum -c - && sh /tmp/aleks-dts-verify.sh"
```

**Why the URL pins a commit instead of `main`:** On 2026-11-22 GitHub raw CDN served a stale `main` copy with SHA256 `279f8f...`, although the repository already had the corrected file. Commit `d0554def...` was fetched and verified with SHA256 `6e8dd4f8...`. Never run a script whose SHA256 does not match.

A `PASS ISOLATED R278 ON GSTREAMER 1.24 (NO INSTALL)` result demonstrates only separate-process fixture compatibility, **not** native-player functionality. Failures stop without enabling plugins and include a short diagnostic log excerpt.

### AC3 on webOS 26: hardware decoder vs explicit software path

**Confirmed from device logs:** both `native` and `augmented` autoplugged `GstOMXAC3Dec`, produced PCM S16LE/48 kHz (negotiated channels changed 6 → 8), and reached `Got EOS` after about 0.2 s. The process then stalled in teardown and was terminated by the 20 s timeout (`exit=143`). The previous `FAIL_BOTH` label was a **false inference about AC3 decoding**. The `invalid property id 20 for downmix` warning and OMX teardown delay deserve separate diagnosis; no evidence connects them specifically to AlekS DTS.

**R2 passed on the kitchen LG 43NANO85A6A:** `dts-stereo`, `dts-51`, `ac3-software-native`, and `ac3-software-augmented` all PASS. Software `avdec_ac3` produced 48 kHz PCM, reached EOS, and exited cleanly in both modes. Archive and all seven individual fixture/plugin SHA256 checks passed. These are **isolated GStreamer tests**, not native-player DTS verification. It never alters `umediaserver`, mounts, services or persistent configuration.

```powershell
ares-novacom --device aleks-kitchen-root --run "curl -fLsS https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/d050fb7294b4414bc36fe861779eaa1497876ac4/tools/verify-r278-webos26-r2.sh -o /tmp/aleks-dts-r2.sh && echo '1ecd5fbd8698c9c2d15612c6460e325d0c6621041fb1a836c1e1dac8c1b10ea3  /tmp/aleks-dts-r2.sh' | sha256sum -c - && sh /tmp/aleks-dts-r2.sh"
```

Success: `RESULT=PASS_DTS_AND_AC3_SOFTWARE_ISOLATED; NO_INSTALL`. On failure: `RESULT=AC3_REGRESSION_NOT_CLEARED; NO_INSTALL`. Neither result alone authorizes native media installation; hardware OMX and native player require separate verification.

### Native-media integration preparation (read-only)

Before backup and a dedicated webOS 26 installer, inspect the real `umediaserver` `EnvironmentFiles`, writable configuration directory structure, existing plugin configuration, root ownership and any DTS Restore artifacts. This preflight changes no files or services:

```powershell
ares-novacom --device aleks-kitchen-root --run "curl -fLsS https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/1c53eb1ea0f7c69c377a383a2680ecac1c7e4e91/tools/preflight-webos26-integration.sh -o /tmp/aleks-dts-preflight.sh && echo '39804c08eca95a444dc8189def1273db6c4acb5b338f4ab324c4ab7f22edf41d  /tmp/aleks-dts-preflight.sh' | sha256sum -c - && sh /tmp/aleks-dts-preflight.sh"
```

Even `RESULT=PREFLIGHT_READY_FOR_BACKUP_AND_STAGED_TEST; NO_INSTALL` is **not installation approval**. A backup, dedicated installer and rollback, `/var` persistence verification after reboot, and native-player testing are still required. The original R278 installer still rejects the kernel architecture and has an outdated AC3 assertion.

**Confirmed from `/proc/self/mountinfo` (2026-11-22):** `/` is read-only SquashFS; `/var` first has a lower read-only OverlayFS (`lowerdir=/overlay/bsppart/bsp/var:/var`), but a **writable ext4 mount backed by physical eMMC `/dev/mmcblk0p59`** overrides it (mount ID 71, root `/var`). `/var/lib/webosbrew` uses the effective mounted storage; around 561 MB is available. **This is persistent block storage, not RAM**. Persistence of particular files after a full reboot is still to be confirmed because boot maintenance may clean temporary directories. The PREVIEW installer now blocks activation if this effective `/var` mount differs.

**R307 original R278 release audit (2026-11-22, VPS):** verified the public release archive, all four ELF32 ARM plugins, and shipped stereo/5.1 DTS Matroska fixtures by SHA256. Static R239 bin references aleksdtsdec → audioconvert → S16LE capsfilter; the existence of end-to-end compressed-frame assembly is not established. Bundled R278 verifier uses Matroska demux, not raw DTS chunks. VPS stock dtsdec lost PCM on 11/97-byte raw input from these same shipped clips, while Matroska output was complete. [R307 runner](tools/audit-r278-release-packet-boundaries-r307.py) PASS; [report](docs/R307_R278_RELEASE_PACKET_BOUNDARY_AUDIT.md). **The archived release targets the hall TV; exact kitchen installed binaries and silence cause are unverified.**

**R306 genuine DTS packet-boundary differential (2026-11-22; VPS):** FFmpeg generated real original-tone DTS Core stereo and 5.1. On GStreamer 1.24.2, arbitrary raw 11/97-byte chunks into `dtsdec` produced **shorter, variable PCM** despite process exit0. The same DTS losslessly remuxed into Matroska then decoded through `matroskademux ! dtsdec` produced **byte-identical full PCM** for input blocks 11/97/4096 and repeat (72,192 stereo / 73,728 surround frames). Independent `avdec_dca` and FFmpeg produced the same full frame counts. [R306 reproducer](tools/test-real-dts-packet-boundaries-r306.py) PASS; [full evidence](docs/R306_REAL_DTS_PACKET_BOUNDARY_QA.md). **Does not establish the first-silence root cause on kitchen LG R278.**

**R305 actual GStreamer pad-event regression (2026-11-22):** built the unchanged experimental R188 plugin against GStreamer 1.24.2 using SHA256-pinned developer headers extracted into a private temp directory (no package installation). The [R305 C harness](tools/test-r188-real-gstpad-events-r305.c) sends real `STREAM_START`, `FLUSH_STOP`, `EOS`, dynamic CAPS, malformed input and downstream `GST_FLOW_NOT_NEGOTIATED` through connected GstPads. **8/8 native -O2 PASS and 8/8 ASan+UBSan PASS** using the [reproducible runner](tools/run-r188-real-gstpad-events-r305.sh). Initial dynamic-caps failure was a test sink capability-query defect and corrected in QA, not the plugin. **No genuine DTS files, original R122, deployed LG R278, or kitchen audio were tested.** [Triage](docs/WEBOS26_DTS_SILENCE_TRIAGE.md).

**R304 independent synthetic first-frame QA (2026-11-22):** the original R188 C99 frame assembler was tested with an explicitly synthetic R122 header test double, separate from the lost original owner fixtures. On VPS **23/23 ASan+UBSan PASS** and **23/23 optimized C99 PASS**, including split headers, bounded frame assembly, resets, malformed inputs, sink rejection, PTS discontinuities/overflow, 9000-frame rational clock and 400 deterministic fragmentation trials. [Reproducible SHA-pinned R304 runner](tools/run-r188-synthetic-firstframe-r304.sh). **Original R122, genuine DTS, GstPad EOS events, deployed R278 and kitchen audibility NOT TESTED**; legacy R188 original fixture QA remains BLOCKED. [Triage](docs/WEBOS26_DTS_SILENCE_TRIAGE.md).

**R303 SHA-exact historical fixture recovery (2026-11-22):** added [R303](tools/recover-r188-original-pins-r303.py) to locate the three missing original R188 prerequisites in explicitly supplied folders or tar/zip archives using original SHA256 pins only. Python syntax and selftests PASS (traversal, symlinks, idempotency, conflicts). Read-only scan of the old VPS source backup found **0/3 originals**, no extraction or staging performed. Historical R188 ASan/UBSan replay remains **BLOCKED BY MISSING PREREQUISITES**, not a confirmed decoder regression. [Triage](docs/WEBOS26_DTS_SILENCE_TRIAGE.md).

**R302 first-frame and lab QA durability audit (2026-11-22):** historical isolated R184/R186 first-header bridges validated metadata but did not reassemble the encoded DTS frame; experimental R188 is a distinct bounded frame assembler, **not equivalent to deployed kitchen R278**. Replaying R188 ASan/UBSan on VPS is currently **BLOCKED before compilation**: two original pinned source files SHA256 PASS, while three R122/parser/owner-fixture prerequisites under `/tmp` disappeared after a reboot. [R302 read-only checker](tools/audit-r188-replay-prereqs-r302.py) selftest PASS, on VPS 2/5 PASS, 3 MISSING, strict exit2. None of this proves kitchen first-start audio root cause. [Triage](docs/WEBOS26_DTS_SILENCE_TRIAGE.md).

**R301 lifecycle evidence auditor (2026-11-22; offline):** existing R298 ignored the `LIFECYCLE=` records introduced in R299/R300. New [R301 parser](tools/analyze-webos26-dts-lifecycle-r301.py) joins R282 `CASE=` and `LIFECYCLE=` markers, distinguishes EOS/NULL/Freeing evidence and timeout-signal-compatible outcomes without causal overclaims. On VPS 13 assertions PASS and [source-backed integration regression](tools/test-webos26-r282-exit-r298.sh) PASS. Reanalysis of four historical `exit143` cases found **zero recorded lifecycle lines**, so the historical stage of teardown cannot be established. No live TV changes.

**R300 opt-in timeout signal differential (2026-11-22):** verified on VPS: BusyBox `timeout -s USR1` deadline exits **138**, native child SIGTERM exits **143**, GNU deadline exits **124**. Isolated R282 now optionally accepts `R300_TIMEOUT_SIGNAL=USR1` (default remains TERM); the [R300 standalone QA](tools/test-timeout-signal-r300.sh) and [source-backed regression](tools/test-webos26-r282-exit-r298.sh) PASS. **TV was not accessed; production DTS unchanged; exact cause of historical 143 remains unverified.**

**R299 timeout exit ambiguity (2026-11-22):** on VPS, GNU `timeout` deadline exits **124** whereas BusyBox `timeout` expires with **143**, even if a child already printed `Got EOS`. Therefore the four historic R282 exit143 cases are **compatible with** a 12-second BusyBox deadline, but the actual TV timeout implementation/cause remains **unverified**. [R299](tools/test-timeout-exit-r299.sh) offline QA PASS; R282 now records elapsed duration, pipeline NULL/freeing markers and deadline compatibility without claiming causation. No TV system changes.

**R298 DTS lifecycle audit (2026-11-22):** historic R282 `decodebin3` tests emitted EOS and PCM but **all four exited 143 (SIGTERM), not clean exit0**. Corrected [R282](tools/test-webos26-decodebin3-pcm-r282.sh) to reject unclean lifecycles. New [R298 result auditor](tools/audit-webos26-r282-exit-r298.py) passed 14 assertions and rejected all four historic exit143 cases; hermetic [integration QA](tools/test-webos26-r282-exit-r298.sh) accepts EOS+exit0 and rejects EOS+exit143. **All offline; not evidence of kitchen first-start audio root cause.**

**R297 DTS offline regression (2026-11-22):** R295 now rejects `returnValue=false` / missing success markers; R296 now understands actual R289/R294 field formats, rejects API failures, unlinked UMI statuses and incomplete transcripts. Verified with [R297 hermetic QA](tools/test-r295-r296-offline-r297.sh): fake LS2 PASS, R296 15 assertions PASS, actual-shaped two-file comparison PASS, earlier R215 AudioD/Starfish parser 18/18 PASS. DTS Restore Plus documents a similar first-play-after-boot DTS recognition problem on other LG hardware, **not proven to share kitchen's root cause**. New TV probe was blocked; these are **offline-only results**, no production DTS changes.

**R295–R296 (2026-11-22, no TV changes):** official webOS OSE docs confirm `audio/UMI/getStatus` and `audio/getStreamStatus`, and a successful `audiooutput` connection may report `outputMode=null`—not evidence of silence. [R295](tools/inspect-webos26-audio-policy-r295.sh) is a staged read-only policy probe, syntactically and synthetically validated **but NOT run on TV** because a remote call was denied. [R296](tools/compare-webos26-dts-sessions-r296.py) is an offline session-diff tool with Python compile and selftests PASS; acoustic and root-cause claims remain guarded. [Triage](docs/WEBOS26_DTS_SILENCE_TRIAGE.md).

**R294 real kitchen reboot (2026-11-22):** verified via `/proc/uptime`; after reboot AlekS DTS installation/plugin SHA256, registry, uMS environment file and all four live process variables PASS. A non-DTS snapshot reports codec=mpeg, ADEC1→MAIN, ALSA PCM6 closed, no active PulseAudio sink input and no DTS-plugin-holding Starfish process. New [read-only unified R294 snapshot](tools/capture-webos26-audio-session-r294.sh) is tested. **Actual first audible DTS playback following this boot remains untested; original intermittent silence root cause unresolved.**

**R293 native PulseAudio clients (2026-11-22):** clients include audiod PID440, WebAppMgr PID3217, and one exited transient client. Starfish PID20727 carrying AlekS DTS **does not appear as a direct PulseAudio client**. An indirect LG/IPC/DSP route remains possible, but unproven; ALSA hardware pointer movement cannot be attributed solely to DTS. Audible DTS is owner-confirmed. [R293](tools/inspect-webos26-pulse-clients-r293.sh).

**R292 PulseAudio topology clarification (2026-11-22):** active `pcm_output` (S16LE stereo 48 kHz) has one uncorked/unmuted `sink-input #5` owned by **WebAppMgr PID3217**, while AlekS DTS libraries are mapped in **Starfish PID20727**. Native LG audiooutput reports `ADEC0→MAIN`, muted=false, codec=dts. Whether Starfish DTS traverses this PulseAudio input or another DSP path is **not proven**. Correct interpretation of R286–R291: ALSA FIFO movement proves active output, **not DTS samples themselves**. [R292](tools/inspect-webos26-pulse-dts-r292.sh).

**Kitchen R289–R291 healthy DTS reference (2026-11-22):** Starfish loads DTS plugins, hardware ALSA PCM6 RUNNING (S16_LE stereo 48 kHz, both pointers +194560 frames in ~4 s), LG read-only audio APIs return `codec=dts`, `soundOutput=tv_external_speaker`, `volume=23`, `muted=false`, `source=ADEC0`, `sink=MAIN`, `outputMode=null`. ARC controller reports `not_ready`, no ARC audio device, eARC mixer OnOff=0: **no active ARC/eARC route observed**. The first-session silence root cause remains unknown; R289–R291 are comparison probes if it recurs. [Triage](docs/WEBOS26_DTS_SILENCE_TRIAGE.md).

**Kitchen R287–R288 (2026-11-22):** six samples across 65 seconds held the same Starfish PID, all three DTS modules, LG codec=dts, active uMS/audiooutputd and ALSA PCM6 RUNNING; hardware pointer advanced 3,121,152 frames (consistent with 48 kHz) with Starfish RSS +8 KiB. Corrected [R288 read-only thread CPU probe](tools/profile-webos26-dts-cpu-r288.sh) recorded 963 process CPU ticks in ~10 s (CLK_TCK=100), highest individual source/queue threads `souphttpsrc*`, `multiqueueind`, `aqueuesrc`. This is **whole media process CPU**, not DTS decoder-only CPU. No production changes justified; cold start and full regressions remain unverified.

**Kitchen R285–R286 low-level verification (2026-11-22):** three media samples held a stable Starfish PID/RSS (124216 KiB) with all three AlekS `.so` libraries loaded and LG codec=dts. Direct read-only `/proc/asound` measurement confirmed `alsa-sink-MARS` output RUNNING with **S16_LE stereo, 48 kHz**, and advancing hardware PCM frames (~242688 over ~5 seconds). S16LE is accepted by the actual active output chain. See [R286](tools/check-webos26-audio-output-r286.sh). Audible sound is owner-confirmed; FIFO movement alone cannot prove non-silent samples.

**Repeat start (2026-11-22):** DTS was audible immediately after closing and reopening the movie, without an AC3 switch (owner-confirmed). Independent read-only AlekS Core -> TORMOZ -> LG diagnostics confirmed active media services, three mapped DTS libraries, LG audio codec=dts, integrity and environment checks PASS. Original silent session remains unexplained.

**New kitchen LG field result (2026-11-22):** first playback of three *The Matrix* DTS tracks was silent; after switching the player's track to AC3 and back to DTS **all DTS tracks became audible**, with no plugin or service changes. Status **conditional live audio PASS only after AC3→DTS**, silent DTS first start remains unresolved; robustness and root cause unverified. See [DTS silence triage](docs/WEBOS26_DTS_SILENCE_TRIAGE.md).

**Kitchen R281 field test (2026-11-22):** overriding `decproxy=0/300` and AlekS DTS rank `288/350` **did not affect** the isolated `decodebin` pipeline: all three configurations selected AlekS DTS, reached EOS and negotiated six-channel PCM. A rank-only production fix is **unproven and has NOT been applied**. Next test: isolated `decodebin3` and S32LE/stereo negotiation [R282](tools/test-webos26-decodebin3-pcm-r282.sh). Real playback remains silent.

**Negative field test (2026-11-22, kitchen LG, playback of The Matrix):** owner reports **silence on three DTS audio tracks**. Passing isolated DTS decode and `umediaserver` process environment checks **does not prove DTS playback in Lampa or the native player**. Root cause (plugin mapping in the actual media process, decoder selection, PCM output routing) is not yet established. Kitchen DTS playback status is **FAIL** until diagnosed and retested. A [read-only silence probe](tools/diagnose-webos26-dts-silence.sh) was added for use **while playing**.

**Diagnostic during DTS playback:** run the read-only [check-webos26-dts-playback-processes.sh](tools/check-webos26-dts-playback-processes.sh) while LG's native media player plays DTS Core 5.1. It only checks mapped AlekS DTS plugin paths in /proc/*/maps and does not read media titles or control playback. Plugin mapping does not prove audible sound; listening and AC3/AAC/DVB regression are still necessary.

**Verified after reboot (2026-11-22, kitchen LG):** `umediaserver.service` active; installed files and `combined.reg` SHA256 PASS; `umediaserver.env` equals `installed.env`; live `umediaserver` process environment contains the four configured `GST_PLUGIN_PATH_1_0`, `GST_REGISTRY_1_0`, `GST_REGISTRY_UPDATE`, and `ALEKS_DTS_R130_ALLOW_AUTOPLUG` variables. Diagnostic output: **`RESULT=CONFIG_AND_PROCESS_ENV_PASS; NATIVE_AUDIO_NOT_YET_TESTED`**. This verifies the post-reboot configuration, **not audible DTS decoding in the native player**. Actual DTS Core 5.1 listening and AC3/AAC/DVB regression remain to be tested.

**Reactivation after accidental rollback (2026-11-22, kitchen LG):** the owner ran the installed `sh /var/lib/webosbrew/aleks-dts-r278/install.sh install`. All seven fixture/plugin checks, `installed.env`, `combined.reg`, and four plugin SHA256 checks passed; `umediaserver.env` compared byte-for-byte with `installed.env` (`cmp -s`); `ALEKS_DTS_CONFIG_RESTORED` was reported. **On-disk state: DTS has been configured again, but the native `umediaserver` has yet to load it after a full reboot.** Check actual process environment after reboot with the read-only [`check-webos26-dts-runtime.sh`](tools/check-webos26-dts-runtime.sh). Native-player audio remains unverified.

**First R279-candidate install/rollback field test (2026-11-22, LG 43NANO85A6A):** `install CONFIRM-LG-43NANO85A6A` reached `R278 configured`, checked SHA256 for `installed.env`, `combined.reg`, and the four installed plugins, and confirmed the live `umediaserver.env` matched the generated configuration exactly. Final install output: `RESULT=INSTALLED_PENDING_FULL_REBOOT_AND_NATIVE_PLAYER_TEST`. The owner **immediately rolled back** using `sh /var/lib/webosbrew/aleks-dts-r278/install.sh rollback` and received **`Rollback verified. Fully reboot the TV.`**. Thus the media environment configuration was restored; installed binary and recovery artifacts remain. There is **no post-reboot native-player DTS test**. This is not proof of full native DTS support and not a general LG release.

**Do not rerun the R279-candidate install command after rollback:** its target directory now exists, so the safety guard blocks a second staging operation. For a later re-enable, first inspect the on-device state. Read-only status:

```powershell
ares-novacom --device aleks-kitchen-root --run "curl -fLsS https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/acfa9927bf9958f329f10fadb40976d6603c204d/tools/check-webos26-r279-state.sh -o /tmp/aleks-dts-state.sh && echo 'a6ea46d67ba37cd594f28d15ce2f43fe14a40f229aa092ac13744eeca0f64013  /tmp/aleks-dts-state.sh' | sha256sum -c - && sh /tmp/aleks-dts-state.sh"
```

Expected immediately after rollback when the original `umediaserver.env` did not exist: `RESULT=ROLLED_BACK_CONFIGURATION; PLUGINS_RETAINED; REBOOT_NOT_VERIFIED`. Block re-enabling if the actual state differs.

### Kitchen LG dedicated installer (PREVIEW, no media service changes)

For **LG 43NANO85A6A, firmware 43.22.74**, a dedicated frontend adapts the SHA256-pinned R278 archive. It verifies actual media ELF32 ARM, GStreamer 1.24.10, BusyBox timeout compatibility, DTS Core stereo/5.1, software AC3 and current `umediaserver` configuration. Original R278 environment-backup and rollback logic is retained.

**Use `verify` only on unknown models and during initial checks.** The script uses a temporary `/tmp` directory without changing the native media service.

```powershell
ares-novacom --device aleks-kitchen-root --run "curl -fLsS https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/cb18937bee85c422f81bc31e4aab15d9d1fda8db/tools/install-webos26-preview.sh -o /tmp/aleks-dts-webos26-preview.sh && echo '7883bdb5195ce5af13837cb65b9c9a79e6224f7d830a0cb4aa9dccf456789ae0  /tmp/aleks-dts-webos26-preview.sh' | sha256sum -c - && sh /tmp/aleks-dts-webos26-preview.sh verify"
```

Success: `RESULT=VERIFIED_ISOLATED_NO_INSTALL`. **Kitchen LG 43NANO85A6A field verification PASS (2026-11-22):** `PATCH_PASS`, SHA256 of all four plugins and three fixtures, `PASS dts-stereo`, `PASS dts-51`, `PASS ac3-software-augmented`, `RESULT=VERIFIED_ISOLATED_NO_INSTALL`. The candidate `install` and immediate `rollback` later passed on the kitchen TV without reboot or native-player validation. **PREVIEW release with eMMC guard:** commit `cb18937`, SHA256 `7883bdb5...`. VPS `patch-check` passed; an earlier PREVIEW `verify` passed on the kitchen LG. Activation-path eMMC guard has not been run on the kitchen TV. **Changing `umediaserver.env` requires explicit approval.** Rollback, `/var` persistence after reboot and explicit owner authorization to modify `umediaserver.env` remain required. Do not use the old `install-universal.sh` on this TV.

## Installation

Open root SSH on an LG ARMv7 TV and paste the full block. It downloads the pinned R278 archive with SHA-256 validation, replaces **only the fixed model/firmware and system-binary hash gate** in a temporary installer copy, and retains plugin integrity verification, media-pipeline tests, and rollback.

```sh
(
  set -eu
  [ "$(id -u)" = 0 ] || { echo 'Root SSH required.' >&2; exit 1; }
  stage=$(mktemp -d /tmp/aleks-dts-bootstrap.XXXXXX)
  trap 'rm -rf -- "$stage"' EXIT
  curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 60 \
    -o "$stage/install-universal.sh" \
    'https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/main/install-universal.sh'
  printf '%s  %s\n' '9c3ce62eeadcd638968a72bd29b3aefbbe349425c0ef739c455ab50c61de3a48' "$stage/install-universal.sh" | sha256sum -c -
  sh "$stage/install-universal.sh" install
)
```

**Media configuration compatibility:** the installer detects `umediaserver.env` from the actual `EnvironmentFiles` entry of `umediaserver.service`, instead of assuming the path from a single LG model. For a declared `/var/systemd/system/env/umediaserver.env` path, it creates missing `/var/systemd`, `/var/systemd/system` and `/var/systemd/system/env` directories after root ownership and symlink checks; empty directories created by a failed run are cleaned up. Other service layouts are not modified automatically. To diagnose, download the script and run `sh /tmp/aleks-dts-universal.sh diagnose`.

**Verify without installing:** change the last `install` argument to `verify`. The isolated decoding tests do not modify the media-service configuration. On an untested model, run `verify` first.

After `R278 configured`, fully reboot and test DTS Core, AC3, and Live TV. Confirm `/var/systemd/system/env/umediaserver.env` still exists after reboot; persistence of `/var` has not yet been verified on other models.

**Rollback** from root SSH if playback or the native media service misbehaves:

```sh
sh /var/lib/webosbrew/aleks-dts-r278/install.sh rollback
```

After `Rollback verified`, fully reboot. The original media-service configuration is restored from backup. The installer refuses to overwrite third-party changes to that configuration.

[Universal installer](install-universal.sh) · [Pinned R278 archive](https://github.com/aerolit266/AlekS-DTS-webOS/blob/r278/downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz) · [Archive SHA-256](https://github.com/aerolit266/AlekS-DTS-webOS/blob/r278/downloads/r278/SHA256SUMS) · [Software notices](https://github.com/aerolit266/AlekS-DTS-webOS/blob/r278/downloads/r278/SOFTWARE-NOTICES.txt)

Do not disable ABI/GStreamer checks when an installation refuses. [Open a compatibility report](https://github.com/aerolit266/AlekS-DTS-webOS/issues/new) with model, CPU architecture and GStreamer version so a separate package can be built when needed.


© 2026 AlekS / GameFree24 (@aerolit266). [Documentation terms](LICENSE.md).


**R311/R312 (2026-11-22, isolated VPS):** the original bounded R188 framer with a restricted genuine DTS Core BE16 header probe recovered **byte-exact reference PCM** from the original R278 stereo and 5.1 fixtures at 1/11/97/4096-byte raw input blocks (8/8). R312 separately repairs experimental R188's reproducible GStreamer `segment before caps` sticky-event ordering (CAPS → SEGMENT → first frame); zero ordering warnings, 3/3 bad DTS cases rejected, 8/8 GstPad event and 8/8 ASan/UBSan event PASS. [Reproducible R312 QA](tools/run-r312-real-dts-ordered-events.sh), [report](docs/R311_R312_REAL_DTS_FIRST_FRAME_QA.md). **NOT installed on kitchen LG R278; its first-start silent playback cause remains unverified.**
