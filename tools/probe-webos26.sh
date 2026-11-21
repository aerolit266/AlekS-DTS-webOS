#!/bin/sh
# AlekS-DTS webOS preflight, read-only. No changes to mounts, systemd or files.
# Copyright 2026 AlekS / GameFree24
set -u
LC_ALL=C
export LC_ALL
SYSTEMD_PAGER=cat
PAGER=cat
export SYSTEMD_PAGER PAGER

section() { printf '\n=== %s ===\n' "$1"; }
exists() {
    for p do
        if [ -e "$p" ] || [ -L "$p" ]; then
            ls -ld "$p" 2>&1
        else
            printf 'MISSING %s\n' "$p"
        fi
    done
}
section 'IDENTITY'
printf 'architecture: '; uname -m 2>&1
printf 'kernel: '; uname -r 2>&1
printf 'uid: '; id -u 2>&1
if command -v getconf >/dev/null 2>&1; then
    printf 'libc: '; getconf GNU_LIBC_VERSION 2>&1 || :
fi
section 'GSTREAMER'
if command -v gst-inspect-1.0 >/dev/null 2>&1; then
    gst-inspect-1.0 --version 2>&1 | head -5
    for elem in avdec_dca aleksdts aleksdtscaps aleksdtsr130optin aleksdts16dec; do
        printf '\nplugin %s\n' "$elem"
        gst-inspect-1.0 "$elem" 2>&1 | grep -E '^(  (Rank|Filename|Version|Long-name|Name)|No such element|Plugin Details|Factory Details|Could not load)' | head -12 || :
    done
else
    printf 'gst-inspect-1.0 not available\n'
fi
section 'UMEDIASERVER UNIT (NO ENV CONTENTS)'
if command -v systemctl >/dev/null 2>&1; then
    systemctl --no-pager show umediaserver.service -p LoadState -p ActiveState -p FragmentPath -p DropInPaths -p EnvironmentFiles 2>&1 | head -12 || :
else
    printf 'systemctl not available\n'
fi
section 'DTS RESTORE / ALEKS DTS LOCATIONS'
exists \
    /var/lib/webosbrew/init.d/restore_dts \
    /var/lib/webosbrew/aleks-dts-r278 \
    /var/lib/webosbrew/aleks-dts-r56 \
    /home/root/dts_restore-2.0 \
    /mnt/lg/user/dts_restore-2.0 \
    /var/systemd/system/env/umediaserver.env
section 'PLUGIN DIRECTORIES'
exists /usr/lib/gstreamer-1.0 /mnt/lg/res/lglib/gstreamer-1.0
section 'ACTIVE DTS-RELATED MOUNTS (PATHS ONLY)'
if command -v mount >/dev/null 2>&1; then
    mount | grep -Ei 'libgst(matroska|libav|isomp4)|restore_dts' | head -15 || :
fi
section 'DONE'
printf 'Read-only probe complete; no changes made.\n'