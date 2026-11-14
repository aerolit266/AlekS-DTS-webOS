# AlekS DTS for LG webOS

[Русский](README.md) · [Documentation license](LICENSE.md)

> **R278 is available** for LG 65NANO896PC running firmware 03.60.96. [Installation command](#installation)

**AlekS DTS R277** adds DTS Core decoding to the native LG webOS media pipeline. Support loads automatically when the TV starts. For the tested DTS 5.1 track, the native audio sink received six-channel PCM S16LE at 48 kHz.

## Verified results

| Device or scenario | Result |
| --- | --- |
| LG 65NANO896PC, webOS TV 6.6.0, ARMv7 | R277 loaded after a full TV reboot |
| Built-in media player | The original DTS Core 5.1 clip played to the end. A listening test confirmed audio |
| Lampa | Audio was audible on every track the owner tried, including Russian DTS 5.1 and FLAC 2.0 |
| Regression checks | An AC3 5.1 clip played to the end. DVB-C passed before and after DTS playback |

DTS Core 2.0 and 5.1 also passed isolated tests. DTS-HD MA, DTS:X, DTS passthrough to a receiver, and other LG models require separate verification.

## R277 compatibility

| Model or platform | Status |
| --- | --- |
| LG 65NANO896PC · firmware 03.60.96 · webOS TV 6.6.0 · ARMv7 · GStreamer 1.16.2 | Verified on a rooted TV with R56 already installed |
| Other LG TVs on webOS TV 6.x and ARMv7 | Candidates for testing. Verify the exact model, firmware, GStreamer ABI, native media player and Live TV |
| webOS TV 5.x and webOS TV 22–26 | R277 has not been verified on these releases. ARM64 needs its own build and native playback tests |

Before installing, open a local MKV with a known DTS Core track in the built-in player. If you already hear audio, you do not need this installation for that track. The webOS version alone does not establish DTS support or R277 compatibility. [LG webOS TV specifications](https://webostv.developer.lge.com/develop/specifications)

## Installation

Set up root SSH and Homebrew on **LG 65NANO896PC running firmware 03.60.96 and webOS TV 6.6.0**. Open an SSH session on the TV and paste the full block. When you see `R278 configured`, fully reboot the TV.

```sh
(
  set -eu
  [ "$(id -u)" = 0 ] || { echo 'Root SSH is required.' >&2; exit 1; }
  [ "$(uname -m)" = armv7l ] || { echo 'This release requires ARMv7.' >&2; exit 1; }
  stage=$(mktemp -d /tmp/aleks-dts-download.XXXXXX)
  trap 'rm -rf -- "$stage"' EXIT
  cd "$stage"
  curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 120 \
    -o release.tar.gz 'https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/main/downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz'
  printf '%s  %s\n' 'cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1' release.tar.gz | sha256sum -c -
  tar -xmzf release.tar.gz
  sh ./install.sh install
)
```

To roll back, run `sh /var/lib/webosbrew/aleks-dts-r278/install.sh rollback` and fully reboot the TV.

[Installer archive](downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz) · [SHA‑256](downloads/r278/SHA256SUMS) · [Software notices](downloads/r278/SOFTWARE-NOTICES.txt) · [libdcadec and relinking kit](downloads/r278/R278-R56-LGPL-RELINK.tar.gz)

The original installer was tested with a clean media-server configuration. The stripped plugins in the public package passed isolated DTS 2.0, DTS 5.1 and AC3 tests on the same LG. For another model or firmware, open a [compatibility request](https://github.com/aerolit266/AlekS-DTS-webOS/issues/new).


© 2026 AlekS / GameFree24 (@aerolit266). [Documentation terms](LICENSE.md).
