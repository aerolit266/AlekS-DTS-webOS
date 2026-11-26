#!/bin/sh
# AlekS DTS R574: read-only compatibility inventory, not an installer.
set -eu
export LC_ALL=C
elf_abi() (
    [ -r "$1" ] || { echo UNREADABLE; exit; }
    bytes=$(od -v -An -tu1 -N52 "$1" 2>/dev/null) || { echo UNREADABLE; exit; }
    set -- $bytes
    [ "$#" -ge 20 ] || { echo UNKNOWN; exit; }
    [ "$1:$2:$3:$4" = 127:69:76:70 ] || { echo NOT_ELF; exit; }
    case "$5:$6:${19}:${20}" in
        1:1:40:0)
            [ "$#" -ge 52 ] || { echo UNKNOWN; exit; }
            case "${37}:${38}:${39}:${40}" in
                0:2:0:5) echo ARM32_EABI5_SOFT ;;
                *) echo ARM32_OTHER_FLAGS ;;
            esac ;;
        2:1:183:0) echo ARM64_LE ;;
        *) echo OTHER_ABI ;;
    esac
)
main() {
    echo 'CHECK=R574_COMPAT_READONLY_V1'
    for cmd in od cmp systemctl grep df awk; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            printf 'MISSING_TOOL=%s\nRESULT=INCOMPLETE\n' "$cmd"
            return 1
        fi
    done
    abi_ok=yes
    for spec in 'UMS:/usr/sbin/umediaserver' 'STARFISH:/usr/sbin/starfish-media-pipeline' 'GST:/usr/bin/gst-inspect-1.0'; do
        name=${spec%%:*}; path=${spec#*:}
        a=$(elf_abi "$path")
        printf '%s_ABI=%s\n' "$name" "$a"
        [ "$a" = ARM32_EABI5_SOFT ] || abi_ok=no
    done
    printf 'ABI_MATCH=%s\n' "$abi_ok"
    printf 'KERNEL_ARCH=%s\n' "$(uname -m)"
    # --version reports the tool version; no pipeline or plugin scan requested.
    if [ -x /usr/bin/gst-inspect-1.0 ]; then
        v=$(/usr/bin/gst-inspect-1.0 --version 2>/dev/null | awk '/^GStreamer [0-9]+\.[0-9]+/{print $2; exit}')
        case "$v" in ''|*[!0-9.]*) v=UNKNOWN;; esac
    else v=UNKNOWN; fi
    printf 'GST_VERSION=%s\n' "$v"
    case "$v" in 1.16.2) echo GST_LAB_BASELINE=MATCH;; *) echo GST_LAB_BASELINE=REVIEW;; esac
    for service in umediaserver.service audiooutputd.service; do
        if systemctl is-active --quiet "$service"; then s=ACTIVE; else s=NOT_ACTIVE_OR_UNKNOWN; fi
        printf '%s=%s\n' "$service" "$s"
    done
    root=/var/lib/webosbrew/aleks-dts-r278
    if [ -f "$root/installed.env" ] && [ ! -L "$root/installed.env" ]; then
        echo R278_RECORD=PRESENT
    else echo R278_RECORD=ABSENT_OR_UNREADABLE; fi
    config=/var/systemd/system/env/umediaserver.env
    if [ -f "$root/installed.env" ] && [ ! -L "$root/installed.env" ] && [ -f "$config" ] && [ ! -L "$config" ]; then
        if cmp -s "$root/installed.env" "$config"; then echo R278_ENV_MATCH=YES; else echo R278_ENV_MATCH=NO_OR_UNREADABLE; fi
    else echo R278_ENV_MATCH=UNKNOWN; fi
    df -Pk /var 2>/dev/null | awk 'NR==2 && $4 ~ /^[0-9]+$/ {print "VAR_FREE_KIB=" $4}'
    echo 'INSTALL_ALLOWED=NO'
    echo 'AUDIBLE_DTS=NOT_TESTED'
    echo 'RESULT=INVENTORY_ONLY'
}
main "$@"
