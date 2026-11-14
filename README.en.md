# AlekS DTS for LG webOS

[Русский](README.md) · [Documentation license](LICENSE.md)

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

**A public installer is not available yet.** The steps below apply if you already have a compatible R277 package. Software distribution must follow the component licenses, including the LGPL. This repository's license covers the documentation text. [Check compatibility through GitHub Issues](https://github.com/aerolit266/AlekS-DTS-webOS/issues/new)

1. **Check your device.** The verified configuration is LG 65NANO896PC with webOS TV 6.6.0 on ARMv7. The test TV already had root access and the R56 decoder. Installation from a factory configuration has not been verified.
2. **Prepare for rollback.** Keep a copy of the current media-server configuration outside the TV. Confirm that you can access the TV for recovery after a reboot. If you use cable TV, check sound and picture on a free-to-air DVB-C channel first.
3. **Stage the package using its instructions.** Verify the supplied checksums. Run the isolated DTS Core and AC3 control checks first. On the verified model, the plugins reside in a persistent Homebrew directory, and the GStreamer registry is generated on the TV using its local paths. If the model, files, or test results differ from the package instructions, stop before activation.
4. **Activate R277.** Apply the media-server configuration prepared for your unit and fully reboot the TV. This installation requires no firmware image.
5. **Verify playback.** Open a local file with a known DTS Core track in the built-in player and check sound through the end of the clip. Then test AC3 and return to the same free-to-air cable channel. If you use Lampa, select a DTS track there and check sound.

### Rollback

If sound disappears in the player or on cable TV after activation, restore the saved configuration with the package's rollback command and fully reboot the TV. Recheck the cable channel and the built-in player. On the tested LG, restarting the media server alone could leave cable TV silent until a full reboot.

© 2026 AlekS / GameFree24 (@aerolit266). [Documentation terms](LICENSE.md).
