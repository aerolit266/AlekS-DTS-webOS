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
| Other LG ARMv7 TVs with native umediaserver / GStreamer | No model or firmware lock. The installer runs isolated DTS 2.0, DTS 5.1 and AC3 tests before enabling. Native-player playback still needs device-specific verification |
| LG ARM64 or other architectures | Not supported by existing R278 binary plugins; requires a separate build |
| Different media pipeline/ABI, or modified media configuration | Installer must refuse before changing media-service configuration |

Root SSH and an existing Homebrew setup are required. No system libraries or firmware are replaced. A successful isolated GStreamer test does not guarantee correct sound on every built-in player.

Test a DTS Core file in the native player first; your TV may already support it.

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
  printf '%s  %s\n' 'fa674ae01a879f96c10652592c3da987640c34efa2b50a0119133acb7f3ffb3f' "$stage/install-universal.sh" | sha256sum -c -
  sh "$stage/install-universal.sh" install
)
```

**Media configuration compatibility:** the installer detects `umediaserver.env` from the actual `EnvironmentFiles` entry of `umediaserver.service`, instead of assuming the path from a single LG model. A missing directory is created only when that path is declared by the service and its root-owned parent exists. Other service layouts are not modified automatically. To diagnose, download the script and run `sh /tmp/aleks-dts-universal.sh diagnose`.

**Verify without installing:** change the last `install` argument to `verify`. The isolated decoding tests do not modify the media-service configuration. On an untested model, run `verify` first.

After `R278 configured`, fully reboot and test DTS Core, AC3, and Live TV.

**Rollback** from root SSH if playback or the native media service misbehaves:

```sh
sh /var/lib/webosbrew/aleks-dts-r278/install.sh rollback
```

After `Rollback verified`, fully reboot. The original media-service configuration is restored from backup. The installer refuses to overwrite third-party changes to that configuration.

[Universal installer](install-universal.sh) · [Pinned R278 archive](https://github.com/aerolit266/AlekS-DTS-webOS/blob/r278/downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz) · [Archive SHA-256](https://github.com/aerolit266/AlekS-DTS-webOS/blob/r278/downloads/r278/SHA256SUMS) · [Software notices](https://github.com/aerolit266/AlekS-DTS-webOS/blob/r278/downloads/r278/SOFTWARE-NOTICES.txt)

Do not disable ABI/GStreamer checks when an installation refuses. [Open a compatibility report](https://github.com/aerolit266/AlekS-DTS-webOS/issues/new) with model, CPU architecture and GStreamer version so a separate package can be built when needed.


© 2026 AlekS / GameFree24 (@aerolit266). [Documentation terms](LICENSE.md).
