#!/bin/sh
# AlekS DTS R279 / webOS26: READ-ONLY post-install / post-rollback status.
# Does not disclose the contents of environment files or process environments.
set -u
LC_ALL=C; export LC_ALL
home=/var/lib/webosbrew/aleks-dts-r278
config=/var/systemd/system/env/umediaserver.env
printf '=== AlekS DTS webOS26 installation state (READ ONLY) ===\n'
if command -v systemctl >/dev/null 2>&1; then
    systemctl show umediaserver.service -p LoadState -p ActiveState -p MainPID -p EnvironmentFiles --no-pager 2>&1 || :
fi
if [ -L "$home" ] || [ -L "$config" ]; then
    printf 'RESULT=BLOCKED_UNEXPECTED_SYMLINK; NO_CHANGE\n'
    exit 0
fi
if [ ! -d "$home" ]; then
    if [ -e "$config" ]; then
        printf 'RESULT=NO_ALEKS_INSTALL_EXISTING_MEDIA_ENV; NO_CHANGE\n'
    else
        printf 'RESULT=NOT_INSTALLED_MEDIA_ENV_ABSENT; NO_CHANGE\n'
    fi
    exit 0
fi
if [ ! -f "$home/ready" ] || [ ! -f "$home/installed.sha256" ] ||
   [ ! -f "$home/installed.env" ]; then
    printf 'RESULT=INCOMPLETE_STAGED_INSTALL; MANUAL_REVIEW_NEEDED; NO_CHANGE\n'
    exit 0
fi
if ! (cd "$home" && sha256sum -c installed.sha256); then
    printf 'RESULT=INTEGRITY_FAILURE; MANUAL_REVIEW_NEEDED; NO_CHANGE\n'
    exit 0
fi
printf 'PASS installed artifact SHA256\n'
if [ -f "$home/original.absent" ] && [ ! -e "$config" ]; then
    printf 'PASS original media env was absent and is absent now\n'
    printf 'RESULT=ROLLED_BACK_CONFIGURATION; PLUGINS_RETAINED; REBOOT_NOT_VERIFIED\n'
elif [ -f "$config" ] && cmp -s "$home/installed.env" "$config"; then
    printf 'PASS media env matches installed AlekS config\n'
    printf 'RESULT=CONFIGURED_ON_DISK; SERVICE_LOAD_AND_PLAYER_NOT_VERIFIED\n'
elif [ -f "$home/original.env" ] && [ -f "$config" ] &&
     cmp -s "$home/original.env" "$config"; then
    printf 'PASS media env matches original backup\n'
    printf 'RESULT=ROLLED_BACK_CONFIGURATION; PLUGINS_RETAINED; REBOOT_NOT_VERIFIED\n'
else
    printf 'RESULT=MEDIA_ENV_DIFFERS_FROM_BOTH_BACKUPS; MANUAL_REVIEW_NEEDED; NO_CHANGE\n'
fi
exit 0
