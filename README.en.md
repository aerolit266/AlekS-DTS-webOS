# AlekS DTS for LG webOS

DTS Core support for compatible LG televisions. Check your model and firmware before installation.

## Compatibility

| LG TV | webOS | Firmware | Result |
| --- | --- | --- | --- |
| **65NANO766QA** | 22 / 7.5.7-23 | 04.54.30 | **DTS 5.1 works** after reboot; audio-track switching and seeking work |
| **65NANO896PC** | 6.6 | 03.60.96 (R278 profile) | **DTS Core 5.1 works** |
| 43NANO85A6A | 26 | 43.22.74 | **Partial:** first DTS playback may be silent; switching AC3 → DTS restores sound |
| UP75006LF | — | — | DTS playback reported by owner; extended tests unavailable |

[Compatibility table](PUBLIC-COMPATIBILITY.md). Results are device-specific, not a guarantee for every LG TV.

## Check and install

Root SSH is required. Install only on televisions you own or are authorized to administer. Run diagnosis and verification first. Stop on errors.

```sh
cd /tmp
curl -fLsS 'https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/59a725f96323ba3e32dd9ca5e20c3ad64c75dee9/install-universal.sh' -o aleks-dts.sh
printf '%s  %s\n' '8b370958cf55b84ae3f33c28cd42a6d87759b6540649e0cfe661f233cec723d8' aleks-dts.sh | sha256sum -c -
sh aleks-dts.sh diagnose
sh aleks-dts.sh verify
```

**Only after successful `verify`:**

```sh
sh /tmp/aleks-dts.sh install
```

After `RESULT=R352_install_PASS`, fully reboot the television and check DTS/AC3 in your player.

Read-only installed status check:

```sh
sh /tmp/aleks-dts.sh status
```

Rollback if necessary (followed by a full reboot):

```sh
sh /var/lib/webosbrew/aleks-dts-r278/install.sh rollback
```

`status` checks installed files and configuration, **not audible audio**. Do not install on unverified models without prior checks.

## Downloads and licenses

- [R278 package](downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz), [SHA256](downloads/r278/SHA256SUMS).
- [Software notices](downloads/r278/SOFTWARE-NOTICES.txt), [LGPL source and relinkable materials](downloads/r278/R278-R56-LGPL-RELINK.tar.gz).
- [Documentation license](LICENSE.md).

© 2026 AlekS / GameFree24.