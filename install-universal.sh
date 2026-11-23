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
# R350: inspect the media executable ELF header, not the kernel uname.
# Output is a closed set of statuses; this function is read-only.
elf_media_abi() {
    target=$1
    [ -r "$target" ] || { printf 'UNREADABLE\n'; return; }
    command -v od >/dev/null 2>&1 || { printf 'UNKNOWN_NO_OD\n'; return; }
    bytes=$(od -An -tu1 -N20 "$target" 2>/dev/null) || {
        printf 'UNKNOWN_READ_ERROR\n'; return;
    }
    set -- $bytes
    if [ "$#" -ne 20 ] || [ "$1" != 127 ] || [ "$2" != 69 ] ||
       [ "$3" != 76 ] || [ "$4" != 70 ]; then
        printf 'NOT_ELF\n'; return
    fi
    case "$5:$6:${19}:${20}" in
        1:1:40:0) printf 'ARM32_LE\n' ;;
        2:1:183:0) printf 'ARM64_LE\n' ;;
        *) printf 'UNSUPPORTED_ELF\n' ;;
    esac
}

require_arm32_media() {
    for media_bin in /usr/sbin/umediaserver /usr/sbin/starfish-media-pipeline; do
        [ -x "$media_bin" ] || fail "Native media executable missing: $media_bin. Run diagnose; no install attempted."
        media_abi=$(elf_media_abi "$media_bin")
        [ "$media_abi" = ARM32_LE ] ||
            fail "Incompatible media ABI ($media_abi) at $media_bin; R278 needs 32-bit little-endian ARM MEDIA binaries, independent of kernel uname. Run diagnose; no install attempted."
    done
}

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
        printf '=== MEDIA ELF ABI (read-only) ===\n'
        for media_bin in /usr/sbin/umediaserver /usr/sbin/starfish-media-pipeline /usr/lib/gstreamer-1.0/libgstrtkalsa.so; do
            printf '%s: %s\n' "$media_bin" "$(elf_media_abi "$media_bin")"
        done
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
require_arm32_media
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
    # Recheck both real media binaries in the temporary R278 installer.
    # Kernel aarch64 may run 32-bit Starfish/UMS. Never accept unknown/64-bit ELF.
    command -v od >/dev/null 2>&1 || fail 'ELF header inspector od is missing.'
    for media_bin in /usr/sbin/umediaserver /usr/sbin/starfish-media-pipeline; do
        [ -x "$media_bin" ] || fail "Native media executable missing: $media_bin."
        set -- $(od -An -tu1 -N20 "$media_bin" 2>/dev/null) ||
            fail "Cannot read ELF header: $media_bin."
        [ "$#" -eq 20 ] &&
        [ "$1" = 127 ] && [ "$2" = 69 ] && [ "$3" = 76 ] && [ "$4" = 70 ] &&
        [ "$5" = 1 ] && [ "$6" = 1 ] &&
        [ "${19}" = 40 ] && [ "${20}" = 0 ] ||
            fail "Media executable is not ELF32 little-endian ARM: $media_bin."
    done
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
# R351: stock R278 uses 'timeout -t 20', rejected by BusyBox 1.31.1.
# Both BusyBox and GNU coreutils accept 'timeout 20 COMMAND'.
# Rewrite exactly one pinned archive invocation in the temporary copy.
awk '
    /timeout -t 20 "\$@"/ {
        seen++
        sub(/timeout -t 20/, "timeout 20")
    }
    { print }
    END { if (seen != 1) exit 70 }
' install.patched > install.timeout-patched ||
    fail 'Unexpected R278 timeout syntax; refusing an unverified patch.'
mv install.timeout-patched install.patched
# R352: replace only the pinned R278 AC3 verifier call in temporary install.sh.
# The untouched R278 used AC3 S8 passthrough only; some LG decoders output
# genuine six-channel F32LE. Neither branch may select an AlekS DTS plugin.
cat > ac3.compat <<'AC3'
    check_ac3() {
        out="$work/ac3-51.log"
        run_gst /usr/bin/gst-launch-1.0 -v filesrc "location=$directory/fixtures/ac3-51.mka" \
            '!' matroskademux name=dm dm.audio_0 '!' queue '!' decodebin '!' fakesink sync=false \
            > "$out" 2>&1 || fail "AC3 playback failed. See $out"
        grep -Fq 'Got EOS' "$out" || fail "AC3 EOS missing in $out."
        if grep -Eq 'AlekSDtsR130:|AlekSDts16DecBin' "$out"; then
            fail "DTS plugin incorrectly selected for AC3 in $out."
        fi
        caps=$(grep 'GstFakeSink:.*GstPad:sink: caps = audio/x-raw' "$out" | tail -1)
        [ -n "$caps" ] || fail "AC3 output PCM caps missing in $out."
        printf '%s\n' "$caps" | grep -Fq 'rate=(int)48000' ||
            fail "AC3 sample rate mismatch in $out."
        case "$caps" in
            *'format=(string)S8,'*)
                printf '%s\n' "$caps" |
                    grep -F 'channels=(int)1,' |
                    grep -Fq 'channel-mask=(bitmask)0x0000000000000000' ||
                    fail "AC3 passthrough layout mismatch in $out."
                printf '%s\n' "$caps" |
                    grep -F 'mode:passthrough' |
                    grep -Fq 'codec_type=(string)AC3' ||
                    fail "AC3 passthrough metadata missing in $out."
                printf 'PASS ac3-51 (passthrough)\n'
                ;;
            *'format=(string)F32LE,'*)
                printf '%s\n' "$caps" |
                    grep -F 'layout=(string)non-interleaved' |
                    grep -F 'channels=(int)6,' |
                    grep -Fq 'channel-mask=(bitmask)0x0000000000000c0f' ||
                    fail "AC3 decoded 5.1 PCM layout mismatch in $out."
                grep -E 'GstAc3Parse:.*GstPad:src: caps = audio/x-ac3' "$out" |
                    grep -Fq 'channels=(int)6' ||
                    fail "AC3 parser six-channel evidence missing in $out."
                grep -E '/avdec_ac3:.*GstPad:src: caps = audio/x-raw' "$out" |
                    grep -F 'format=(string)F32LE' |
                    grep -F 'rate=(int)48000' |
                    grep -F 'channels=(int)6' |
                    grep -Fq 'channel-mask=(bitmask)0x0000000000000c0f' ||
                    fail "AC3 decoder six-channel PCM evidence missing in $out."
                printf 'PASS ac3-51 (decoded-F32LE-5.1)\n'
                ;;
            *) fail "Unsupported AC3 output PCM format in $out." ;;
        esac
    }
    check_ac3
AC3
awk -v replacement=ac3.compat '
    /^    check_clip ac3-51 S8 1 0x0000000000000000$/ {
        count++
        if (count != 1) exit 70
        while ((getline line < replacement) > 0) print line
        close(replacement)
        next
    }
    { print }
    END { if (count != 1) exit 70 }
' install.patched > install.ac3-patched ||
    fail 'Unexpected R278 AC3 verifier: refusing an unverified compatibility patch.'
mv install.ac3-patched install.patched
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
if sh ./install.sh "$action"; then
    printf 'RESULT=R352_%s_PASS\n' "$action"
else
    result=$?
    printf 'ERROR: R352 %s failed with exit code %s. Read the verification logs path above, if created.\n' "$action" "$result" >&2
    exit "$result"
fi