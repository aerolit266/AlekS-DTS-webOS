#!/bin/sh
# R331 runtime-only, bounded diagnostic of LG UMediaServer Starfish children.
# Owner has authorized one temporary media-service restart. This file must
# remain within /run for independent systemd-run watchdog rollback.
# The original R278 install and env are NEVER edited.
set -eu
umask 077
export LC_ALL=C

ROOT=/run/aleks-r331
BASE=/var/systemd/system/env/umediaserver.env
INSTALLED=/var/lib/webosbrew/aleks-dts-r278/installed.env
STAGE=/tmp/aleks-r331-interposer-qa-20261122/libaleksr331hook.so
HOOK=$ROOT/libaleksr331hook.so
DROP_DIR=/run/systemd/system/umediaserver.service.d
DROP=$DROP_DIR/99-aleks-r331.conf
MARK='# AlekS R331 runtime-only observer 20261122'
EXPECTED_ENV=654530c165e1f8229b9326c020ec5654da3e8b47e0425182d011c210c3e45497
EXPECTED_HOOK=deb1adb853e4d7546ce0fc7a8b446a849b7b3a47fbcdb5dcf870b16ce1cd8057

die() { echo "RESULT=R331_ABORT_$1";exit 2; }
verify_sha() {
  printf '%s  %s\n' "$1" "$2" | sha256sum -c - >/dev/null || die SHA
}
verify_base() {
  verify_sha "$EXPECTED_ENV" "$BASE"
  verify_sha "$EXPECTED_ENV" "$INSTALLED"
  cmp -s "$BASE" "$INSTALLED" || die BASE_ENV_NOT_EQUAL
}
verify_plugins() {
  verify_sha 5c3b798d4c1109414efc9209276dbf8b23466376f72f5bc71cf4144f3f5a1cbb /var/lib/webosbrew/aleks-dts-r278/plugins/libgstaleksdts.so
  verify_sha dfefb960d49d50ed7629cc4459ffaae8b420509cc9815d8337f6be7faaac18cf /var/lib/webosbrew/aleks-dts-r278/plugins/libgstaleksdts16dec.so
  verify_sha 1995a6b6030f6ddb895aeeea4017dcc71db8ebd6caace0107e1c5a33875f0605 /var/lib/webosbrew/aleks-dts-r278/plugins/libgstaleksdtscaps.so
  verify_sha 9b7adb2744a9d7c329669974c15bcfc86ba62daf27efccb95e362c1928d602e0 /var/lib/webosbrew/aleks-dts-r278/plugins/libgstaleksdtsr130optin.so
}
read_original_preload() {
  pid=$(systemctl show umediaserver.service -p MainPID --value)
  case "$pid" in ''|*[!0-9]*) die INVALID_SERVICE_PID ;; esac
  [ "$pid" -gt 1 ] || die INVALID_SERVICE_PID
  python3 - "$pid" <<'PY'
import sys
from pathlib import Path
data=(Path('/proc')/sys.argv[1]/'environ').read_bytes().split(b'\x00')
matches=[s.split(b'=',1)[1].strip() for s in data if s.startswith(b'LD_PRELOAD=')]
assert len(matches)==1 and matches[0]==b'libsystrim.so.3'
print('R331_ORIGINAL_PRELOAD_IDENTICAL=YES')
PY
}
preflight() {
  [ "$(id -u)" = 0 ] || die NOT_ROOT
  command -v systemd-run >/dev/null || die NO_TIMER
  command -v timeout >/dev/null || die NO_TIMEOUT
  verify_base
  verify_plugins
  [ "$(systemctl is-active umediaserver.service)" = active ] || die MEDIA_INACTIVE
  [ -z "$(systemctl show umediaserver.service -p DropInPaths --value)" ] || die EXISTING_OTHER_DROPIN
  [ ! -e "$DROP" ] || die ALREADY_INSTALLED
  [ ! -e "$ROOT" ] || die R331_ALREADY_STAGED
  verify_sha "$EXPECTED_HOOK" "$STAGE"
  read_original_preload
  echo RESULT=R331_PREFLIGHT_PASS
}
stage() {
  preflight
  mkdir -m 0700 "$ROOT"
  mkdir -m 0700 "$ROOT/metrics"
  cp -p "$BASE" "$ROOT/baseline-umediaserver.env"
  chmod 0600 "$ROOT/baseline-umediaserver.env"
  verify_sha "$EXPECTED_ENV" "$ROOT/baseline-umediaserver.env"
  cp "$STAGE" "$HOOK"
  chmod 0700 "$HOOK"
  verify_sha "$EXPECTED_HOOK" "$HOOK"
  cp "$0" "$ROOT/controller.sh"
  chmod 0700 "$ROOT/controller.sh"
  cat >"$ROOT/observer.env" <<'ENV'
LD_PRELOAD="libsystrim.so.3 /run/aleks-r331/libaleksr331hook.so"
ALEKS_R331_ENABLE=YES
ENV
  chmod 0600 "$ROOT/observer.env"
  echo R331_STAGED_CONFIG_IN_TMPFS=YES
  echo RESULT=R331_RUNTIME_STAGE_PASS
}
arm() {
  [ "$(id -u)" = 0 ] || die NOT_ROOT
  verify_base
  verify_plugins
  [ -d "$ROOT/metrics" ] || die MISSING_STAGE
  verify_sha "$EXPECTED_HOOK" "$HOOK"
  [ -f "$ROOT/controller.sh" ] || die MISSING_ROLLBACK_SCRIPT
  [ ! -e "$DROP" ] || die DROPIN_ALREADY_INSTALLED
  [ -z "$(systemctl show umediaserver.service -p DropInPaths --value)" ] || die OTHER_DROPINS
  mkdir -p "$DROP_DIR"
  printf '%s\n' "$MARK" '[Service]' 'EnvironmentFile=-/run/aleks-r331/observer.env' >"$DROP"
  chmod 0600 "$DROP"
  if ! systemctl daemon-reload;then
    rm -f "$DROP"
    systemctl daemon-reload || :
    die RELOAD_FAILED
  fi
  files=$(systemctl show umediaserver.service -p EnvironmentFiles --value)
  case "$files" in
    *'/var/systemd/system/env/umediaserver.env'*) : ;;
    *) rm -f "$DROP";systemctl daemon-reload || :;die ORIGINAL_ENV_NOT_REGISTERED ;;
  esac
  case "$files" in
    *'/run/aleks-r331/observer.env'*) : ;;
    *) rm -f "$DROP";systemctl daemon-reload || :;die OVERLAY_ENV_NOT_REGISTERED ;;
  esac
  # The watchdog is owned by systemd PID1, independent of the SSH/MCP session.
  if ! systemd-run --unit=aleks-r331-rollback --on-active=100s /bin/sh "$ROOT/controller.sh" rollback; then
    rm -f "$DROP";systemctl daemon-reload || :;die WATCHDOG_NOT_CREATED
  fi
  [ "$(systemctl is-active aleks-r331-rollback.timer)" = active ] ||
    { rm -f "$DROP";systemctl daemon-reload || :;die WATCHDOG_NOT_ACTIVE; }
  echo R331_WATCHDOG_BEFORE_RESTART=VERIFIED
  if ! timeout 26 systemctl restart umediaserver.service;then
    /bin/sh "$ROOT/controller.sh" rollback || :
    die FIRST_RESTART_FAILED
  fi
  [ "$(systemctl is-active umediaserver.service)" = active ] ||
    { /bin/sh "$ROOT/controller.sh" rollback || :;die MEDIA_NOT_ACTIVE; }
  pid=$(systemctl show umediaserver.service -p MainPID --value)
  if python3 - "$pid" <<'PY'
from pathlib import Path
import sys
env=(Path('/proc')/sys.argv[1]/'environ').read_bytes().split(b'\x00')
assert b'ALEKS_R331_ENABLE=YES' in env
preloads=[x.split(b'=',1)[1] for x in env if x.startswith(b'LD_PRELOAD=')]
assert len(preloads)==1
assert b'libsystrim.so.3' in preloads[0]
assert b'/run/aleks-r331/libaleksr331hook.so' in preloads[0]
print('R331_UMEDIASERVER_PRELOAD_ACTIVE=YES')
PY
  then
    echo RESULT=R331_LIVE_WINDOW_ARMED_AUTO_ROLLBACK
  else
    /bin/sh "$ROOT/controller.sh" rollback || :
    die PRELOAD_NOT_APPLIED_AND_ROLLBACK_ATTEMPTED
  fi
}
rollback() {
  [ "$(id -u)" = 0 ] || die ROLLBACK_NOT_ROOT
  if [ -e "$DROP" ];then
    grep -Fxq "$MARK" "$DROP" || die FOREIGN_DROPIN_REFUSE_TO_REMOVE
    rm -f "$DROP"
    rmdir "$DROP_DIR" 2>/dev/null || :
    systemctl daemon-reload || die ROLLBACK_RELOAD_FAILED
    if timeout 30 systemctl restart umediaserver.service;then
      echo R331_MEDIA_RESTART_RESTORED=YES
    else
      echo R331_MEDIA_RESTART_RESTORED=NO
      timeout 15 systemctl start umediaserver.service || :
    fi
  else
    echo R331_RUNTIME_DROPIN_ALREADY_ABSENT=YES
  fi
  verify_base
  verify_plugins
  [ "$(systemctl is-active umediaserver.service)" = active ] ||
    die ROLLBACK_MEDIA_NOT_ACTIVE
  if [ -d "$ROOT" ];then
    echo 'R331_ROLLBACK_STATUS=COMPLETE' >"$ROOT/rollback-status"
    chmod 0600 "$ROOT/rollback-status"
  fi
  echo RESULT=R331_RUNTIME_ROLLBACK_PASS
}
status() {
  if [ -e "$DROP" ];then echo R331_OVERRIDE=ACTIVE
  else echo R331_OVERRIDE=ABSENT; fi
  echo R331_MEDIA_SERVICE=$(systemctl is-active umediaserver.service 2>/dev/null || :)
  echo R331_AUDIO_SERVICE=$(systemctl is-active audiooutputd.service 2>/dev/null || :)
  echo R331_TIMER=$(systemctl is-active aleks-r331-rollback.timer 2>/dev/null || :)
  if [ -d "$ROOT/metrics" ];then
    echo R331_METRIC_COUNT=$(find "$ROOT/metrics" -maxdepth 1 -name 'r331-*.json' | wc -l)
  else echo R331_METRIC_COUNT=0; fi
  echo RESULT=R331_STATUS_PASS
}
[ "$#" -eq 1 ] || die USAGE
case "$1" in
 preflight) preflight ;;
 stage) stage ;;
 arm) arm ;;
 rollback) rollback ;;
 status) status ;;
 *) die USAGE ;;
esac
