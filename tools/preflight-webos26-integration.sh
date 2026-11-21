#!/bin/sh
# AlekS DTS webOS 26 native-media INTEGRATION PREFLIGHT ONLY.
# Read-only. Does NOT install, alter environment files, mount plugins,
# change services, or send commands to the native media service.
set -u
LC_ALL=C; export LC_ALL
printf '%s\n' 'AlekS DTS webOS26 integration preflight (READ ONLY)'
status=0
pass() { printf 'PASS %s\n' "$1"; }
block() { printf 'BLOCKED %s\n' "$1"; status=1; }
note() { printf 'INFO %s\n' "$1"; }
if [ "$(id -u)" != 0 ]; then block "root session required"; fi
if command -v systemctl >/dev/null 2>&1; then
    line=$(systemctl show umediaserver.service -p EnvironmentFiles 2>/dev/null) || line=''
    note "$line"
    case "$line" in
      'EnvironmentFiles=/var/systemd/system/env/umediaserver.env'*)
        pass "media service declares the known environment path" ;;
      *) block "unknown media service environment path" ;;
    esac
    dropins=$(systemctl show umediaserver.service -p DropInPaths 2>/dev/null) || dropins='unavailable'
    if [ "$dropins" = 'DropInPaths=' ]; then pass 'no systemd media drop-ins'; else block "media service overrides present or unavailable"; fi
    if systemctl is-active --quiet umediaserver.service; then pass 'umediaserver active'; else block 'umediaserver not active'; fi
else block 'systemctl missing'; fi
for path in /var /var/lib /var/lib/webosbrew /var/systemd /var/systemd/system /var/systemd/system/env; do
    if [ -L "$path" ]; then
        block "symlink in required directory: $path"
    elif [ -d "$path" ]; then
        owner=$(stat -c %u "$path" 2>/dev/null) || owner=unknown
        if [ "$owner" = 0 ]; then pass "root-owned directory: $path"; else block "directory owner not root: $path"; fi
    elif [ ! -e "$path" ]; then
        case "$path" in
          /var/systemd|/var/systemd/system|/var/systemd/system/env)
            note "systemd env directory missing (may require safe creation by installer): $path" ;;
          *) block "required directory missing: $path" ;;
        esac
    else block "path not a directory: $path"; fi
done
envfile=/var/systemd/system/env/umediaserver.env
if [ -L "$envfile" ]; then
    block 'umediaserver.env is a symlink'
elif [ -f "$envfile" ]; then
    owner=$(stat -c %u "$envfile" 2>/dev/null) || owner=unknown
    [ "$owner" = 0 ] && pass 'root-owned umediaserver.env' || block 'umediaserver.env owner is not root'
    # Do not print its contents; only classify prior plugin configuration.
    if grep -Eq '^[[:space:]]*(GST_PLUGIN_PATH_1_0|GST_REGISTRY_1_0|GST_PLUGIN_SYSTEM_PATH_1_0|ALEKS_DTS_|LD_PRELOAD|LD_LIBRARY_PATH)' "$envfile"; then
        block 'existing media plugin / preload directives in umediaserver.env: preserve them'
    else
        pass 'no conflicting plugin/preload directives detected in umediaserver.env'
    fi
elif [ -e "$envfile" ]; then
    block 'umediaserver.env exists but is not a regular file'
else
    note 'umediaserver.env currently absent'
fi
if [ -e /var/lib/webosbrew/aleks-dts-r278 ] || [ -L /var/lib/webosbrew/aleks-dts-r278 ]; then
    block 'R278 installation path already exists; do not overwrite'
else pass 'R278 installation path free'; fi
for p in /var/lib/webosbrew/init.d/restore_dts /var/lib/webosbrew/dts_restore /home/root/dts_restore; do
    if [ -e "$p" ] || [ -L "$p" ]; then block "possible DTS Restore artifact: $p"; fi
done
# The ELF class and machine are checked without relying on uname -m.
for binary in /usr/sbin/umediaserver /usr/bin/gst-inspect-1.0 /usr/lib/libgstreamer-1.0.so.0; do
    if [ ! -r "$binary" ]; then block "unreadable media binary: $binary"; continue; fi
    class=$(od -An -tu1 -j4 -N2 "$binary" 2>/dev/null | tr -s ' ' | tr -d '\n') || class=''
    machine=$(od -An -tu1 -j18 -N2 "$binary" 2>/dev/null | tr -s ' ' | tr -d '\n') || machine=''
    if [ "$class" = ' 1 1' ] && [ "$machine" = ' 40 0' ]; then
        pass "ELF32 little-endian ARM: $binary"
    else
        block "unexpected ELF ABI: $binary"
    fi
done
if [ -x /usr/bin/gst-inspect-1.0 ]; then
    ver=$(/usr/bin/gst-inspect-1.0 --version 2>/dev/null | head -2)
    note "$ver"
    printf '%s\n' "$ver" | grep -Fq 'GStreamer 1.24.10' && pass 'GStreamer 1.24.10' || block 'unexpected GStreamer version'
fi
# This is ONLY a preflight, not a go-ahead for production installation.
if [ "$status" -eq 0 ]; then
    printf 'RESULT=PREFLIGHT_READY_FOR_BACKUP_AND_STAGED_TEST; NO_INSTALL\n'
else
    printf 'RESULT=PREFLIGHT_BLOCKED; NO_INSTALL\n'
fi
exit 0
