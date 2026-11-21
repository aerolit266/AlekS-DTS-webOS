#!/bin/sh
# AlekS DTS webOS26 - post-reboot native umediaserver runtime audit.
# Read-only: no service restart, no file changes, no process environment dump.
set -u
LC_ALL=C; export LC_ALL
home=/var/lib/webosbrew/aleks-dts-r278
envfile=/var/systemd/system/env/umediaserver.env
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failed=1; }
warn() { printf 'UNVERIFIED %s\n' "$1"; }
failed=0
printf '=== ALEKS DTS WEBOS26 POST REBOOT STATUS (READ ONLY) ===\n'

if [ ! -f "$home/ready" ] || [ ! -f "$home/installed.sha256" ] ||
   [ ! -f "$home/installed.env" ]; then
    fail 'missing installation/recovery markers'
elif ( cd "$home" && sha256sum -c installed.sha256 >/dev/null 2>&1 ); then
    pass 'installed.env, registry and plugins SHA256'
else
    fail 'installed files SHA256 mismatch'
fi
if [ -L "$envfile" ]; then
    fail 'symlink instead of media environment file'
elif [ -f "$envfile" ] && [ -f "$home/installed.env" ] &&
     cmp -s "$home/installed.env" "$envfile"; then
    pass 'umediaserver.env equals installed.env'
else
    fail 'media environment does not match installed AlekS configuration'
fi
if ! command -v systemctl >/dev/null 2>&1; then
    fail 'systemctl unavailable'
else
    state=$(systemctl is-active umediaserver.service 2>/dev/null || :)
    if [ "$state" = active ]; then pass 'umediaserver.service active'; else fail "umediaserver.service state=$state"; fi
    rawpid=$(systemctl show umediaserver.service -p MainPID 2>/dev/null || :)
    pid=$(printf '%s\n' "$rawpid" | sed -n 's/^MainPID=//p')
    case "$pid" in ''|0|*[!0-9]*) fail "invalid umediaserver MainPID=$pid";;
      *)
        if [ -r "/proc/$pid/environ" ]; then
            # Do not reveal process environment values or unrelated secrets.
            # Only test exact known configuration values.
            envlines=$(tr '\000' '\n' <"/proc/$pid/environ")
            for entry in \
              "GST_PLUGIN_PATH_1_0=/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0:$home/plugins" \
              "GST_REGISTRY_1_0=$home/combined.reg" \
              'GST_REGISTRY_UPDATE=no' \
              'ALEKS_DTS_R130_ALLOW_AUTOPLUG=YES'; do
                key=$(printf '%s\n' "$entry" | cut -d= -f1)
                if printf '%s\n' "$envlines" | grep -Fxq "$entry"; then
                    pass "process env $key"
                else
                    fail "process env $key missing/mismatch"
                fi
            done
        else
            warn 'cannot read media process environment; no claim of live plugin injection'
        fi
        ;;
    esac
fi
if [ "$failed" -eq 0 ]; then
    printf 'RESULT=CONFIG_AND_PROCESS_ENV_PASS; NATIVE_AUDIO_NOT_YET_TESTED\n'
else
    printf 'RESULT=POST_REBOOT_CHECK_FAILED; DO_NOT_CLAIM_DTS_PLAYBACK\n'
fi
exit 0
