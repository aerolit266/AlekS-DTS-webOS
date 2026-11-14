# AlekS DTS for LG webOS

[Русский](README.md) · [Documentation license](LICENSE.md)

> **Installation status.** R277 works on the test LG 65NANO896PC. Self-service installation from GitHub is not available yet. [Details](#installation)

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

**R277 cannot currently be installed from this repository.** This repository provides documentation. The installer archive and installation command have yet to be published.

To check whether your TV is a candidate, open a [compatibility request](https://github.com/aerolit266/AlekS-DTS-webOS/issues/new) and include:

- the exact LG model;
- the firmware and webOS versions shown in the TV information screen;
- whether the built-in player produces sound from an MKV with DTS Core audio.

The R278 installer candidate targets a TV with root access already configured. Isolated DTS and rollback checks passed on the LG 65NANO896PC. A first normal boot following installation on a clean media-server configuration remains to be verified. The download link and exact install and rollback commands will appear here when the package is ready to distribute.

© 2026 AlekS / GameFree24 (@aerolit266). [Documentation terms](LICENSE.md).
