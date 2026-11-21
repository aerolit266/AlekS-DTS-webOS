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
| 64-bit Linux kernel + 32-bit ARM media userland (e.g. LG 43NANO85A6A, webOS 26) | Never infer plugin ABI from `uname -m`: inspect ELF class and e_machine for umediaserver and GStreamer. R278 targeting GStreamer 1.16.2 is **untested** against GStreamer 1.24.10 and is rejected by the current installer |\n| 64-bit native media process / different CPU ABI | Requires a build matching the actual native media process ABI |
| Different media pipeline/ABI, or modified media configuration | Installer must refuse before changing media-service configuration |

Root SSH and an existing Homebrew setup are required. No system libraries or firmware are replaced. A successful isolated GStreamer test does not guarantee correct sound on every built-in player.

Test a DTS Core file in the native player first; your TV may already support it.

## webOS 26: ARM32 media userland on a 64-bit kernel

**Confirmed on LG 43NANO85A6A, firmware 43.22.74:** `uname -m = aarch64`, while `/usr/sbin/umediaserver` and `/usr/bin/gst-inspect-1.0` have ELF class `1` (32-bit) and little-endian encoding; GStreamer `1.24.10`, runtime `libgstreamer-1.0.so.0.2410.0`. ELF `e_machine = 40 (EM_ARM)` is additionally confirmed for all three components. ABI calling convention, library and dynamic-loader compatibility with the R278 plugins are still unverified. **Do not build ARM64 plugins based solely on the kernel architecture**: plugins must match the 32-bit media process ABI and GStreamer 1.24.10.

No `dtsdec`/`avdec_dca` element, matching DTS mounts or DTS Restore files in the tested standard locations were found. This does not prove that a nonstandard DTS Restore or built-in decoder is absent. No TV modifications were made.

**Field test, 2026-11-22:** ELF32 ARM checks (`umediaserver`, `gst-inspect`, GStreamer), GStreamer 1.24.10 and SHA256 checks for the archive, all four plugins and all three fixtures passed. The original test failed **before loading any plugin** because BusyBox 1.36.1 rejected the unsupported `timeout -t 20` option. **Fixed:** portable `timeout 20`; rerun on physical TV required. DTS/AC3 decoding and native-player playback remain **untested**; **no install** performed.

**Do not install R278:** its installer checks `uname -m = armv7l` and rejects a 64-bit kernel, while R278 plugin compatibility with GStreamer 1.24.10 is unverified. Do not disable gates. Backups, isolated tests, native-player and rollback validation are required before replacing any existing DTS solution.

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
