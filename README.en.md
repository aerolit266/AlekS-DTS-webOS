# AlekS DTS for LG webOS

[Русский](README.md) · [Documentation license](LICENSE.md)

> **R278: model-agnostic installer for compatible LG ARMv7 TVs.** No model, firmware-version or SDK allowlist. It checks native media dependencies and DTS/AC3 decoding before changing the media service configuration. [Installation](#installation)

**AlekS DTS R277** adds DTS Core decoding to the native LG webOS media pipeline. Support loads automatically when the TV starts. For the tested DTS 5.1 track, the native audio sink received six-channel PCM S16LE at 48 kHz.

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
| LG 43NANO85A6A · webOS 26 · 32-bit ARM media userland on ARM64 kernel · GStreamer 1.24.10 | **Isolated DTS 2.0/5.1 and software AC3 PASS**; native-player playback and installation remain untested. The original R278 installer must not be used; a dedicated frontend is required |\n| 64-bit native media process / different CPU ABI | Requires a build matching the actual native media process ABI |
| Different media pipeline/ABI, or modified media configuration | Installer must refuse before changing media-service configuration |

Root SSH and an existing Homebrew setup are required. No system libraries or firmware are replaced. A successful isolated GStreamer test does not guarantee correct sound on every built-in player.

Test a DTS Core file in the native player first; your TV may already support it.

## webOS 26: ARM32 media userland on a 64-bit kernel

**Confirmed on LG 43NANO85A6A, firmware 43.22.74:** `uname -m = aarch64`, while `/usr/sbin/umediaserver` and `/usr/bin/gst-inspect-1.0` have ELF class `1` (32-bit) and little-endian encoding; GStreamer `1.24.10`, runtime `libgstreamer-1.0.so.0.2410.0`. ELF `e_machine = 40 (EM_ARM)` is additionally confirmed for all three components. ABI calling convention, library and dynamic-loader compatibility with the R278 plugins are still unverified. **Do not build ARM64 plugins based solely on the kernel architecture**: plugins must match the 32-bit media process ABI and GStreamer 1.24.10.

No `dtsdec`/`avdec_dca` element, matching DTS mounts or DTS Restore files in the tested standard locations were found. This does not prove that a nonstandard DTS Restore or built-in decoder is absent. No TV modifications were made.

**Field tests, 2026-11-22:** ELF32 ARM, GStreamer 1.24.10 and archive/fixture SHA256 checks passed; `aleksdtsr130optin` and `aleksdts16dec` loaded; **DTS 2.0 and DTS 5.1 PASS**. Native `GstOMXAC3Dec` produced PCM S16LE/48 kHz and `Got EOS` both with and without AlekS DTS plugins, but the process stalled during teardown and was terminated by timeout (exit 143). This is **not evidence of failed AC3 decoding**. Clean-shutdown AC3 and native-player integration remain unverified. **Nothing was installed.**

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

### Kitchen LG dedicated installer (PREVIEW, no media service changes)

For **LG 43NANO85A6A, firmware 43.22.74**, a dedicated frontend adapts the SHA256-pinned R278 archive. It verifies actual media ELF32 ARM, GStreamer 1.24.10, BusyBox timeout compatibility, DTS Core stereo/5.1, software AC3 and current `umediaserver` configuration. Original R278 environment-backup and rollback logic is retained.

**Run `verify` mode only at this stage.** The script uses a temporary `/tmp` directory without changing the native media service.

```powershell
ares-novacom --device aleks-kitchen-root --run "curl -fLsS https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/0c9e34e7c54d3230fda1816ff4bba42c6edbcbe3/tools/install-webos26-preview.sh -o /tmp/aleks-dts-webos26-preview.sh && echo 'bb1401495a1d6950cb7b2026b9ff3a9dc9c7ca166b1f213e67d03aaa45f60b8d  /tmp/aleks-dts-webos26-preview.sh' | sha256sum -c - && sh /tmp/aleks-dts-webos26-preview.sh verify"
```

Success: `RESULT=VERIFIED_ISOLATED_NO_INSTALL`. **Kitchen LG 43NANO85A6A field verification PASS (2026-11-22):** `PATCH_PASS`, SHA256 of all four plugins and three fixtures, `PASS dts-stereo`, `PASS dts-51`, `PASS ac3-software-augmented`, `RESULT=VERIFIED_ISOLATED_NO_INSTALL`. Actual `install` and rollback have not been tested on the kitchen TV. Rollback, `/var` persistence after reboot and explicit owner authorization to modify `umediaserver.env` remain required. Do not use the old `install-universal.sh` on this TV.

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
