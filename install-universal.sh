#!/bin/sh
# AlekS DTS webOS - model/firmware independent installation front-end for R278.
# Copyright 2026 AlekS / GameFree24 (@aerolit266)
# Does not replace platform binaries. Tests plugins in isolation before enabling.
set -eu
umask 077
export LC_ALL=C

url='https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/r278/downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz'
sha='cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1'
installed='/var/lib/webosbrew/aleks-dts-r278/install.sh'

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$#" -eq 1 ] || fail 'Usage: sh install-universal.sh diagnose | verify | install | rollback'
case "$1" in
    rollback)
        [ "$(id -u)" = 0 ] || fail 'Root SSH is required.'
        [ -f "$installed" ] && [ ! -L "$installed" ] || fail 'Installed rollback script not found.'
        exec sh "$installed" rollback
        ;;
    install|verify) action=$1 ;;
    diagnose)
        printf '=== DEVICE ===\n'
        uname -m
        printf '=== MEDIA SERVICE ===\n'
        systemctl show umediaserver.service -p LoadState -p ActiveState -p FragmentPath -p DropInPaths -p EnvironmentFiles 2>&1 || :
        printf '=== CONFIGURATION DIRECTORIES ===\n'
        for d in /var/systemd/system /var/systemd/system/env /etc/systemd/system /var/lib/webosbrew; do
            if [ -e "$d" ] || [ -L "$d" ]; then ls -ld "$d"; else printf 'MISSING %s\n' "$d"; fi
        done
        exit 0
        ;;
    *) fail 'Usage: sh install-universal.sh diagnose | verify | install | rollback' ;;
esac

[ "$(id -u)" = 0 ] || fail 'Root SSH is required.'
[ "$(uname -m)" = armv7l ] || fail 'The existing R278 binary plugins are ARMv7-only. This TV requires a separately compiled package.'
for tool in curl sha256sum tar awk grep mktemp sh; do
    command -v "$tool" >/dev/null 2>&1 || fail "Missing tool: $tool"
done

stage=$(mktemp -d /tmp/aleks-dts-universal.XXXXXX) || fail 'Cannot create temporary directory.'
cleanup() {
    rm -rf -- "$stage"
    if [ -n "${created_env_dirs:-}" ] && [ ! -e "${config_path:-}" ]; then
        # Reverse creation order. Never force-remove a nonempty directory.
        for d in $created_env_dirs; do
            rmdir "$d" 2>/dev/null || :
        done
    fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
cd "$stage"

curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 120 \
    -o release.tar.gz "$url" || fail 'Cannot download pinned R278 archive.'
printf '%s  %s\n' "$sha" release.tar.gz | sha256sum -c - || fail 'Archive integrity check failed.'
tar -xmzf release.tar.gz || fail 'Cannot unpack archive.'
[ -f install.sh ] && [ ! -L install.sh ] || fail 'Installer missing from archive.'
grep -Fq "fail 'Unsupported model or firmware.'" install.sh || fail 'Unexpected R278 installer: refusing an unverified patch.'
grep -Fq 'hash 46a353723ec66894596d9ce0822c3f2273422731ad0426fc6ff16beb349162bc /usr/sbin/umediaserver' install.sh ||
    fail 'Unexpected firmware compatibility checks: refusing an unverified patch.'

# Derive the native service's declared environment path rather than assuming
# a folder borrowed from one TV model. No service modification or new drop-in.
config_path=''
created_env_dirs=''
if [ "$action" = install ]; then
    command -v systemctl >/dev/null 2>&1 || fail 'systemctl is missing.'
    env_line=$(systemctl show umediaserver.service -p EnvironmentFiles) ||
        fail 'Cannot inspect umediaserver.service environment files.'
    case "$env_line" in EnvironmentFiles=*) ;; *)
        fail 'Unknown service environment format; run diagnose and report its output.' ;;
    esac
    env_paths=${env_line#EnvironmentFiles=}
    for entry in $env_paths; do
        case "$entry" in
            /*/umediaserver.env|-/*/umediaserver.env)
                candidate=${entry#-}
                case "$candidate" in
                    *[!A-Za-z0-9._/-]*) fail 'Unsafe environment-file path in service.' ;;
                esac
                case "$candidate" in
                    /var/*|/etc/systemd/*) ;;
                    *) fail 'Unsupported environment-file location; run diagnose.' ;;
                esac
                if [ -n "$config_path" ] && [ "$config_path" != "$candidate" ]; then
                    fail 'Ambiguous service environment files; run diagnose.'
                fi
                config_path=$candidate
                ;;
        esac
    done
    [ -n "$config_path" ] ||
        fail 'umediaserver.service does not declare an umediaserver.env file. Run diagnose; a different integration method is required.'
    dir=${config_path%/*}
    # The exact chain below is referenced by umediaserver.service on LG webOS.
    # /var is writable; never create arbitrary directories under /etc or /usr.
    if [ "$dir" = /var/systemd/system/env ]; then
        for d in /var /var/systemd /var/systemd/system /var/systemd/system/env; do
            [ ! -L "$d" ] || fail "Symbolic link in media configuration path: $d"
            if [ -d "$d" ]; then
                [ "$(stat -c %u "$d")" = 0 ] || fail "Non-root directory owner: $d"
            elif [ -e "$d" ]; then
                fail "Not a directory in media configuration path: $d"
            else
                [ "$d" != /var ] || fail 'Root /var directory is missing.'
                mkdir -m 0755 "$d" || fail "Cannot create media config directory: $d"
                created_env_dirs="$d $created_env_dirs"
                printf 'Created media environment directory: %s\n' "$d"
                [ "$(stat -c %u "$d")" = 0 ] || fail "Incorrect owner for created directory: $d"
            fi
        done
    else
        # No automatic creation for unknown service paths.
        [ -d "$dir" ] && [ ! -L "$dir" ] ||
            fail 'Unknown media configuration directory. Run diagnose.'
        [ "$(stat -c %u "$dir")" = 0 ] ||
            fail 'Environment directory must be owned by root.'
    fi
    if [ -e "$config_path" ] || [ -L "$config_path" ]; then
        [ -f "$config_path" ] && [ ! -L "$config_path" ] ||
            fail 'Unsafe pre-existing media environment file.'
    fi
    printf 'Verified media environment path: %s\n' "$config_path"
fi

# Replace only the original platform() gate. All integrity checks for shipped
# plugins, protected systemd configuration and recovery logic remain unchanged.
cat > platform.universal <<'PLATFORM'
platform() {
    [ "$(id -u)" = 0 ] || fail 'Root is required.'
    [ "$(uname -m)" = armv7l ] || fail 'R278 contains ARMv7-only plugins.'
    [ -x /usr/sbin/umediaserver ] || fail 'Native umediaserver is not available.'
    [ -x /usr/sbin/starfish-media-pipeline ] || fail 'Native media pipeline is not available.'
    [ -x /usr/bin/gst-inspect-1.0 ] || fail 'GStreamer inspector is missing.'
    [ -x /usr/bin/gst-launch-1.0 ] || fail 'GStreamer launcher is missing.'
}
PLATFORM

awk -v replacement=platform.universal '
    /^platform\(\) \{$/ {
        seen++
        if (seen != 1) exit 70
        while ((getline line < replacement) > 0) print line
        close(replacement)
        skip=1
        next
    }
    skip && /^}$/ { skip=0; next }
    skip { next }
    { print }
    END { if (seen != 1 || skip) exit 70 }
' install.sh > install.patched || fail 'Cannot patch platform check safely.'
sh -n install.patched || fail 'Patched installer has a shell syntax error.'
if grep -Fq 'Unsupported model or firmware.' install.patched ||
   grep -Fq '46a353723ec66894596d9ce0822c3f2273422731ad0426fc6ff16beb349162bc' install.patched; then
    fail 'Fixed-firmware checks remain after patch.'
fi
# The R278 archive hardcodes one media-service environment path. Replace
# that exact assignment with the path declared by THIS TV's systemd unit.
if [ "$action" = install ]; then
    awk -v discovered="$config_path" '
        /^config=\/var\/systemd\/system\/env\/umediaserver.env$/ {
            count++; print "config=" discovered; next
        }
        { print }
        END { if (count != 1) exit 70 }
    ' install.patched > install.portable ||
        fail 'Could not replace the old fixed media configuration path.'
    mv install.portable install.patched
fi
sh -n install.patched || fail 'Portable installer has a shell syntax error.'
mv install.patched install.sh
chmod 0700 install.sh
printf 'AlekS DTS R278 universal: model/firmware gate removed.\n'
printf 'Hardware ABI and DTS/AC3 tests remain mandatory.\n'
sh ./install.sh "$action"
