# R321 — OLED77 B1, webOS 6.3.2: installation and HDMI eARC 5.1 report

**Date:** 2026-11-22. **Evidence:** owner-reported forum test only; no SSH access to the third-party television, logs, installed-file hashes, firmware model suffix or receiver details. **Compatibility and 5.1 eARC: NOT VERIFIED.** Do not claim a successful install.

## Field report

A tester reported LG OLED77 B1 / webOS 6.3.2 / root access, terminal PuTTY, and:
1. `/var/systemd/system/env` did not appear after trying the forum command or unplugging the TV; manually created folders remain empty.
2. Dolby Digital 5.1 seems to work.
3. DTS yields sound through HDMI eARC, but receiver displays **PCM Stereo**.

Forum reference supplied by owner: https://webos-forums.ru/post205878.html#p205878

## Confirmed source-level reasons the first installer may not work

1. The **original immutable R278 archive** is `AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz`, SHA256 `cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1`. Its bundled `install.sh` calls `platform()`, which checks **exactly** `modelName=65NANO896PC`, `firmwareVersion=03.60.96`, `sdkVersion=6.6.0` and three fixed system binary SHA256s. This gate **cannot approve an OLED77 B1**. It also requires the parent of `/var/systemd/system/env/umediaserver.env` to exist. Do not defeat the original guard by editing the installed script manually.
2. The first forum post's code block as retrieved on 2026-11-22 displays `sh./install.sh install` (missing space) and `["$(id -u)" = 0]` (missing bracket spaces). Those literal forms are shell syntax/command errors; a failed paste would never create the configuration. This is a **source transcription/formatting observation**, not proof of exactly what the tester ran.
3. The current [universal frontend](../install-universal.sh) (SHA256 `9c3ce62eeadcd638968a72bd29b3aefbbe349425c0ef739c455ab50c61de3a48`) accepts ARMv7 but must pass decoder and systemd checks. It discovers the actual `umediaserver.service` `EnvironmentFiles` rather than guessing the pathname and creates the known absent `/var/systemd/system/env` chain only with root-owner/symlink safety checks. It removes only empty directories created by the failed attempt. **No claim that this frontend has been tested on this B1**.
4. The temporary / permanent `/var` mount and whether a copied `umediaserver.env` survives reboot must be checked on the specific device. Empty manually created directories are not evidence of a successful install.

## DTS decoding vs multichannel HDMI eARC

The original R278 decoder's isolated GStreamer tests produce **six channels of S16LE/48k PCM** for a DTS Core 5.1 fixture, but those tests end in `fakesink`, not the TV's HDMI/eARC output. Conversion to PCM is **by design**; expecting a receiver to show raw `DTS` would require a **separately implemented/validated passthrough** path. The TV can decode six channels upstream yet negotiate or downmix **PCM 2.0** before eARC. The receiver's PCM Stereo display does **not** establish whether R278 was installed, nor whether the decoder's actual in-app output was 5.1. **Do not claim multichannel LPCM over eARC supported until measured.**

Recommended distinct observations (do not modify native audio services to obtain them):
- **Install/activation**: `R278 configured` or another *exact* success marker, current `EnvironmentFiles` path, presence of `installed.env`, `ready`, relevant GStreamer element visibility and live media process environment after a reboot.
- **Decoded source**: in isolated known DTS Core 5.1 reference test, `audio/x-raw, channels=6` is evidence of the decoder only.
- **Receiver eARC output**: on a known 5.1 track (not stereo soundtrack), receiver's native **INPUT** codec/channel status, HDMI eARC (not ARC-only), TV's digital output choice `PCM` vs `Auto` vs `Pass Through`, and eARC support setting.
- **AC3 control**: the same internal app and receiver should show whether AC3 genuinely arrives as 5.1, not merely 5.1 speaker upmix.

## One safe command: read-only compatibility diagnostics (root PuTTY)

This downloads a small script **to /tmp only**. It never changes systemd/firmware/media settings or installs decoder plugins. Pinned commit and SHA256 verified on VPS (22 November 2026).

```sh
curl -fLsS --connect-timeout 10 --max-time 35 \
  'https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/cec9b978e65750a51a12ca21aeaf32adef691581/tools/public-compatibility-check.sh' \
  -o /tmp/aleks-dts-compat-r321.sh &&
printf '%s  %s\n' '70da08090cc9d1c25a9b069c22f072882384234b2e5203d130a7d9b76f664d44' /tmp/aleks-dts-compat-r321.sh | sha256sum -c - &&
sh /tmp/aleks-dts-compat-r321.sh
```

If no Internet on TV, stop; do not bypass the integrity check. Paste the **redacted** output, specifically `kernel_arch`, GStreamer version, `umediaserver` ELF class/machine, `EnvironmentFiles`, `PROFILE` and `RESULT`. Do **not** post `/proc/*/environ`, the **contents** of `umediaserver.env`, passwords, keys, SSH identities, receiver serial numbers or any movie/network URLs.

Additional **read-only** check for original install state (does not open env contents):
```sh
systemctl show umediaserver.service -p EnvironmentFiles -p ActiveState -p DropInPaths
test -f /var/lib/webosbrew/aleks-dts-r278/ready && echo R278_READY=yes || echo R278_READY=no
test -f /var/systemd/system/env/umediaserver.env && echo ENV_FILE=yes || echo ENV_FILE=no
```

**Stop point:** Do not run `install` or create missing folders manually until this output establishes the native media ABI, systemd EnvironmentFiles location, known R278/GStreamer compatibility and conflicts with other DTS Restore configurations. The one-file public command is safe only for **diagnosis**.

## Follow-up / release gates

- Fix the original forum's malformed/outdated command snippet or replace it with a link to [README.md](../README.md) and this diagnostic. Do not paste the original model-bound `install.sh` on other models.
- If the B1 has ARMv7/GStreamer 1.16-class, evaluate the current universal frontend's **verify-only** mode and report its actual output before any installation. That mode runs isolated decoding only; it does not establish HDMI eARC 5.1.
- Never change receiver bitstream mode while a source is unexpectedly producing encoded data without an authorized recovery plan; begin with modest receiver volume. Preserve normal AC3/eARC functionality.
- Native 6-channel PCM to HDMI eARC may require platform-specific mixer/audiooutputd/EDID/ELD handling or a different transport. No such fix is presently verified on B1; **do not copy webOS25/firmware-specific binary patches or kernel modules**.
- Installer error logs, exact version, eARC 2.0/5.1 and cross-app/AC3 controls belong in separate compatibility entries.

**Status: REPORT RECEIVED / INSTALL UNVERIFIED / DTS DECODER 5.1 EARC UNVERIFIED / NO THIRD-PARTY DEVICE MODIFIED.**
