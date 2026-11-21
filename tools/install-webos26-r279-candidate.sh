#!/bin/sh
# AlekS DTS R278 kitchen LG / webOS 26 - candidate installer R279 integration.
# Verified target: 43NANO85A6A, 32-bit EM_ARM userland, GStreamer 1.24.10.
# Does not patch firmware/system libraries. No restart or live TV change on verify.
set -eu
umask 077
LC_ALL=C
export LC_ALL

archive_url=https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/r278/downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz
archive_sha=cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1
preflight_url=https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/1c53eb1ea0f7c69c377a383a2680ecac1c7e4e91/tools/preflight-webos26-integration.sh
preflight_sha=39804c08eca95a444dc8189def1273db6c4acb5b338f4ab324c4ab7f22edf41d
root=/var/lib/webosbrew/aleks-dts-r278
envfile=/var/systemd/system/env/umediaserver.env
fail() { printf 'BLOCKED: %s\n' "$*" >&2; exit 1; }

case "$*" in
  patch-check) action=patch-check ;;
  verify) action=verify ;;
  status) action=status ;;
  'install CONFIRM-LG-43NANO85A6A') action=install ;;
  rollback) action=rollback ;;
  *) fail 'Usage: sh install-webos26-r279-candidate.sh patch-check | verify | status | install CONFIRM-LG-43NANO85A6A | rollback' ;;
esac

if [ "$action" = status ]; then
  printf 'STATUS: umediaserver state and R278 installed files (contents not disclosed)\n'
  systemctl is-active umediaserver.service 2>&1 || :
  systemctl show umediaserver.service -p MainPID -p User -p DynamicUser -p EnvironmentFiles 2>&1 || :
  if [ -f "$root/ready" ] && [ -f "$root/installed.sha256" ]; then
    (cd "$root" && sha256sum -c installed.sha256) || fail 'Installed R278 integrity check failed'
    if [ -f "$root/installed.env" ] && [ -f "$envfile" ] && cmp -s "$root/installed.env" "$envfile"; then
      printf 'RESULT=INSTALLED_CONFIGURATION_MATCH\n'
    else
      printf 'RESULT=INSTALLED_FILES_BUT_ENV_NOT_ACTIVE\n'
    fi
  else
    printf 'RESULT=NOT_INSTALLED_OR_INCOMPLETE\n'
  fi
  exit 0
fi

if [ "$action" = rollback ]; then
  [ "$(id -u)" = 0 ] || fail 'root required'
  [ -f "$root/install.sh" ] && [ ! -L "$root/install.sh" ] || fail 'Installed rollback script not found'
  exec sh "$root/install.sh" rollback
fi

for tool in curl sha256sum tar mktemp awk grep sed sh od tr stat; do
  command -v "$tool" >/dev/null 2>&1 || fail "Required tool missing: $tool"
done
stage=$(mktemp -d /tmp/aleks-dts-webos26.XXXXXX) || fail 'Cannot create staging directory'
created_env_dirs=''
cleanup() {
  rm -rf -- "$stage"
  if [ -n "$created_env_dirs" ] && [ ! -e "$envfile" ] && [ ! -L "$envfile" ]; then
    # Reverse order, rmdir never removes nonempty folders.
    for d in $created_env_dirs; do rmdir "$d" 2>/dev/null || :; done
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 120 \
    -o "$stage/release.tar.gz" "$archive_url" || fail 'R278 download failed'
printf '%s  %s\n' "$archive_sha" "$stage/release.tar.gz" | sha256sum -c - ||
    fail 'R278 archive SHA256 mismatch'
tar -xmzf "$stage/release.tar.gz" -C "$stage" || fail 'R278 extraction failed'
[ -f "$stage/install.sh" ] && [ ! -L "$stage/install.sh" ] ||
    fail 'Original install.sh missing or symlink'
grep -Fq "fail 'Unsupported model or firmware.'" "$stage/install.sh" ||
    fail 'Pinned R278 installer changed unexpectedly'
grep -Fq 'hash 46a353723ec66894596d9ce0822c3f2273422731ad0426fc6ff16beb349162bc /usr/sbin/umediaserver' "$stage/install.sh" ||
    fail 'Unexpected installer platform gate'
grep -Fq 'timeout -t 20' "$stage/install.sh" || fail 'Unexpected timeout syntax'
grep -Fq 'check_clip ac3-51 S8 1 0x0000000000000000' "$stage/install.sh" ||
    fail 'Unexpected R278 AC3 check'
grep -Fq 'config=/var/systemd/system/env/umediaserver.env' "$stage/install.sh" ||
    fail 'Unexpected media configuration destination'

# Replace ONLY the original model/firmware/hash gate with the tested ELF userland gate.
cat > "$stage/platform.new" <<'PLATFORM'
platform() {
    [ "$(id -u)" = 0 ] || fail 'Root required'
    [ -x /usr/sbin/umediaserver ] || fail 'umediaserver missing'
    [ -x /usr/sbin/starfish-media-pipeline ] || fail 'starfish-media-pipeline missing'
    [ -x /usr/bin/gst-inspect-1.0 ] || fail 'gst-inspect missing'
    [ -x /usr/bin/gst-launch-1.0 ] || fail 'gst-launch missing'
    for elf in /usr/sbin/umediaserver /usr/bin/gst-inspect-1.0 /usr/lib/libgstreamer-1.0.so.0; do
        [ -r "$elf" ] || fail "Missing media ELF: $elf"
        class=$(od -An -tu1 -j4 -N2 "$elf" | tr -s ' ' | tr -d '\n')
        machine=$(od -An -tu1 -j18 -N2 "$elf" | tr -s ' ' | tr -d '\n')
        [ "$class" = ' 1 1' ] && [ "$machine" = ' 40 0' ] ||
            fail "Requires ELF32 little-endian EM_ARM: $elf"
    done
    /usr/bin/gst-inspect-1.0 --version | grep -Fq 'GStreamer 1.24.10' ||
        fail 'This preview requires GStreamer 1.24.10'
    [ -e /usr/lib/libgstreamer-1.0.so.0.2410.0 ] ||
        fail 'Expected GStreamer library missing'
}
PLATFORM

awk -v replacement="$stage/platform.new" '
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
' "$stage/install.sh" > "$stage/installer.step1" ||
    fail 'Failed to replace pinned platform gate'

# Original R278 assumes BusyBox accepts timeout -t and AC3 uses an old
# passthrough S8 format. Kitchen TV uses BusyBox timeout 20 and avdec_ac3.
sed -e 's/timeout -t 20 /timeout 20 /' \
    -e 's/check_clip ac3-51 S8 1 0x0000000000000000/check_ac3_software/' \
    "$stage/installer.step1" > "$stage/installer.step2" ||
    fail 'Unable to adapt BusyBox timeout / AC3 check'

# Add isolated software AC3 regression function before before_matches().
cat > "$stage/ac3.new" <<'AC3'
check_ac3_software() {
    out=$work/ac3-software.log
    if ! run_gst /usr/bin/gst-launch-1.0 -v \
      filesrc "location=$directory/fixtures/ac3-51.mka" \
      '!' matroskademux name=dm dm.audio_0 '!' queue '!' ac3parse '!' avdec_ac3 \
      '!' fakesink sync=false > "$out" 2>&1; then
      tail -n 30 "$out" >&2
      fail "AC3 software pipeline did not exit cleanly"
    fi
    grep -Fq 'Got EOS' "$out" || fail 'AC3 software EOS missing'
    grep 'GstFakeSink:.*GstPad:sink: caps = audio/x-raw' "$out" |
      grep -Fq 'rate=(int)48000' || fail 'AC3 PCM 48 kHz missing'
    if grep -Eq 'AlekSDtsR130:|AlekSDts16DecBin' "$out"; then
      fail 'AC3 routed through AlekS DTS element'
    fi
    printf 'PASS ac3-software-augmented\n'
}
AC3
awk -v extra="$stage/ac3.new" '
    /^before_matches\(\) \{$/ {
        seen++
        if (seen != 1) exit 70
        while ((getline line < extra) > 0) print line
        close(extra)
        print ""
    }
    { print }
    END { if (seen != 1) exit 70 }
' "$stage/installer.step2" > "$stage/installer.step3" ||
    fail 'Unable to add AC3 software regression test'

# Explicit system plugin path: reproduces the successful isolated R2 harness.
awk '
  /GST_REGISTRY_1_0="\$work\/combined.reg" GST_REGISTRY_UPDATE=yes/ {
      print $0
      print "            GST_PLUGIN_SYSTEM_PATH_1_0=\"$base\" \\"
      changed++
      next
  }
  {print}
  END {if (changed != 1) exit 70}
' "$stage/installer.step3" > "$stage/install.patched" ||
    fail 'Unable to pin GStreamer system plugin paths'

if grep -Fq 'Unsupported model or firmware.' "$stage/install.patched" ||
   grep -Fq 'timeout -t 20' "$stage/install.patched" ||
   grep -Fq 'check_clip ac3-51 S8 1' "$stage/install.patched"; then
   fail 'Original device-specific gate or invalid AC3 check remains'
fi
sh -n "$stage/install.patched" || fail 'Patched R278 installer syntax invalid'
mv "$stage/install.patched" "$stage/install.sh"
chmod 0700 "$stage/install.sh"
printf 'PATCH_PASS: R278 plugin hashes and rollback logic retained; 32-bit ARM/GStreamer 1.24 and software AC3 adapted\n'
if [ "$action" = patch-check ]; then
    printf 'RESULT=PATCH_ONLY_PASS; NO_DEVICE_CHANGE\n'
    exit 0
fi
[ "$(id -u)" = 0 ] || fail 'Root required'
[ -d /var/lib/webosbrew ] && [ ! -L /var/lib/webosbrew ] ||
    fail 'Homebrew path missing or symlink'
[ "$(stat -c %u /var/lib/webosbrew)" = 0 ] ||
    fail 'Homebrew path not root-owned'
[ -f "$stage/install.sh" ] || fail 'Internal installer missing'

# Read-only preflight must pass immediately before verification or activation.
curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 60 \
    -o "$stage/preflight.sh" "$preflight_url" || fail 'Preflight download failure'
printf '%s  %s\n' "$preflight_sha" "$stage/preflight.sh" | sha256sum -c - ||
    fail 'Preflight SHA256 mismatch'
sh "$stage/preflight.sh" > "$stage/preflight.log" ||
    fail 'Preflight execution failed'
cat "$stage/preflight.log"
grep -Fxq 'RESULT=PREFLIGHT_READY_FOR_BACKUP_AND_STAGED_TEST; NO_INSTALL' "$stage/preflight.log" ||
    fail 'Preflight did not pass'
# Verify all plugin checksums and DTS2.0/DTS5.1/AC3 software before touching config.
sh "$stage/install.sh" verify || fail 'R278 adapted verification failed'
printf 'PASS: DTS2.0 DTS5.1 and isolated AC3 software on kitchen GStreamer\n'
if [ "$action" = verify ]; then
    printf 'RESULT=VERIFIED_ISOLATED_NO_INSTALL\n'
    exit 0
fi

# INSTALL: only after explicit model-named opt-in. Keep the Homebrew + original
# installer backup/rollback logic; no /usr changes and no restart in this script.
[ "$action" = install ] || fail 'Unexpected action'
# Confirm runtime identity: when the service runs as an unprivileged user,
# the existing R278 plugin staging mode (0700) will not be readable.
service_user=$(systemctl show umediaserver.service -p User) || fail 'Cannot identify media service owner'
case "$service_user" in User=|User=root) ;; *) fail "Unsupported service user: $service_user" ;; esac
dyn_user=$(systemctl show umediaserver.service -p DynamicUser) || fail 'Cannot inspect DynamicUser'
case "$dyn_user" in DynamicUser=no|DynamicUser=) ;; *) fail "Dynamic media service user: $dyn_user" ;; esac
service_pid=$(systemctl show umediaserver.service -p MainPID) || fail 'Cannot inspect service PID'
service_pid=${service_pid#MainPID=}
case "$service_pid" in ''|0|*[!0-9]*) fail 'Invalid MainPID for media service' ;; esac
[ -r "/proc/$service_pid/status" ] || fail 'Cannot inspect media service process UID'
service_uid=$(awk '/^Uid:/ {print $2}' "/proc/$service_pid/status")
[ "$service_uid" = 0 ] || fail "Non-root umediaserver main process UID: $service_uid"
printf 'PASS: umediaserver runs as root; R278 0700 plugins accessible\n'
# Test required BusyBox applet features in the temporary staging directory.
command -v sync >/dev/null 2>&1 || fail 'sync unavailable'
sync -f "$stage/release.tar.gz" >/dev/null 2>&1 || fail 'sync -f unsupported by this device'
command -v flock >/dev/null 2>&1 || fail 'flock unavailable'
( exec 8>"$stage/lock-test"; flock -x 8 ) || fail 'flock -x unsupported by this device'
printf 'PASS: required sync -f and flock -x supported\n'
# Kitchen webOS 26 uses two /var mount layers: read-only overlay under a
# writable ext4 bind mount from eMMC /dev/mmcblk0p59. Check the *effective*
# mount, not df(1)'s reported filesystem or the lower overlay layer.
# This guard does not prove persistence across firmware maintenance/reboots.
[ -r /proc/self/mountinfo ] || fail 'Cannot inspect effective /var mount'
var_mount=$(awk '$5 == "/var" { line=$0 } END { print line }' /proc/self/mountinfo)
case "$var_mount" in
  *" - ext4 /dev/mmcblk0p59 rw,"*) ;;
  *) fail 'Effective /var is not the expected writable eMMC ext4 mount; refuse activation' ;;
esac
printf 'PASS: /var effective mount is writable ext4 on /dev/mmcblk0p59\n'
[ ! -e "$root" ] && [ ! -L "$root" ] ||
    fail "Existing installation directory: $root"
[ ! -e "$envfile" ] && [ ! -L "$envfile" ] ||
    fail 'Existing media environment file requires manual audit, not overwrite'
line=$(systemctl show umediaserver.service -p EnvironmentFiles) ||
    fail 'Cannot inspect media service'
case "$line" in
  "EnvironmentFiles=$envfile"*) ;;
  *) fail 'Media service environment path changed' ;;
esac
[ "$(systemctl show umediaserver.service -p DropInPaths)" = DropInPaths= ] ||
    fail 'Service has custom drop-ins'
systemctl is-active --quiet umediaserver.service ||
    fail 'Media service is not active'
for d in /var /var/systemd /var/systemd/system /var/systemd/system/env; do
    [ ! -L "$d" ] || fail "Symlink in environment path: $d"
    if [ -d "$d" ]; then
        [ "$(stat -c %u "$d")" = 0 ] || fail "Not root-owned: $d"
    elif [ -e "$d" ]; then
        fail "Unexpected non-directory: $d"
    else
        [ "$d" != /var ] || fail 'Missing /var'
        mkdir -m 0755 "$d" || fail "Cannot create $d"
        created_env_dirs="$d $created_env_dirs"
    fi
done
if ! sh "$stage/install.sh" install; then
    printf 'INSTALL_FAILED: inspect recovery files before reboot.\n' >&2
    printf 'RECOVERY: sh %s/install.sh rollback (if present)\n' "$root" >&2
    fail 'Adapted R278 install failed; no success claimed'
fi
[ -f "$root/ready" ] && [ -f "$root/installed.sha256" ] && [ -f "$root/installed.env" ] ||
    fail 'Installation recovery markers missing'
( cd "$root" && sha256sum -c installed.sha256 ) || fail 'Installed plugin/registry/env SHA256 failed'
[ -f "$envfile" ] && [ ! -L "$envfile" ] && cmp -s "$root/installed.env" "$envfile" ||
    fail 'Installed umediaserver.env did not match generated configuration'
printf 'PASS: installed artifacts and exact environment configuration verified\n'
printf 'RESULT=INSTALLED_PENDING_FULL_REBOOT_AND_NATIVE_PLAYER_TEST\n'
printf 'ROLLBACK: sh %s/install.sh rollback; then full reboot\n' "$root"
