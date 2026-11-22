#!/bin/sh
# R338 runtime-only, bounded diagnostic of LG UMediaServer Starfish children.
# Owner explicitly authorized one temporary media restart for R338. This file must
# remain within /run for independent systemd-run watchdog rollback.
# The original R278 install and env are NEVER edited.
set -eu
umask 077
export LC_ALL=C

ROOT=/run/aleks-r338
BASE=/var/systemd/system/env/umediaserver.env
INSTALLED=/var/lib/webosbrew/aleks-dts-r278/installed.env
STAGE=/tmp/aleks-r338-stage-20261123/libaleksr338hook.so
HOOK=$ROOT/libaleksr338hook.so
DROP_DIR=/run/systemd/system/umediaserver.service.d
DROP=$DROP_DIR/99-aleks-r338.conf
MARK='# AlekS R338 runtime-only observer 20261123'
EXPECTED_ENV=654530c165e1f8229b9326c020ec5654da3e8b47e0425182d011c210c3e45497
EXPECTED_HOOK=45ba5af2e437b94d43c2902fd7471dc852ae8fa285ff01502a16197bbf799dd1

die() { echo "RESULT=R338_ABORT_$1";exit 2; }
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
assert len(matches)==1
value=matches[0]
assert value and len(value)<200 and b' ' not in value and b'"' not in value
assert Path(value.decode('ascii')).name=='libsystrim.so.3'
print('R338_ORIGINAL_PRELOAD_LIBRARY_PRESERVED=YES')
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
  [ ! -e "$ROOT" ] || die R338_ALREADY_STAGED
  [ "$(systemctl is-active aleks-r338b-rollback.timer 2>/dev/null || :)" != active ] || die TIMER_ALREADY_ARMED
  [ "$(systemctl is-active aleks-r331-rollback.timer 2>/dev/null || :)" != active ] || die PRIOR_TIMER_ACTIVE
  [ "$(systemctl is-active aleks-r338-rollback.timer 2>/dev/null || :)" != active ] || die PRIOR_R338_TIMER_ACTIVE
  verify_sha "$EXPECTED_HOOK" "$STAGE"
  read_original_preload
  echo RESULT=R338_PREFLIGHT_PASS
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
  # Capture the exact existing systemd preload value (not only basename).
  # Reject unexpected paths, extra libraries or shell/metacharacters.
  pid=$(systemctl show umediaserver.service -p MainPID --value)
  python3 - "$pid" "$ROOT/observer.env" <<'PY'
from pathlib import Path
import sys,re,os
items=(Path('/proc')/sys.argv[1]/'environ').read_bytes().split(b'\x00')
matches=[v.split(b'=',1)[1].decode('ascii') for v in items if v.startswith(b'LD_PRELOAD=')]
assert len(matches)==1
preload=matches[0].strip()
assert re.fullmatch(r'[A-Za-z0-9_./+\-]{1,199}',preload)
assert Path(preload).name=='libsystrim.so.3'
data='LD_PRELOAD="'+preload+' /run/aleks-r338/libaleksr338hook.so"\nALEKS_R338_ENABLE=YES\n'
with open(sys.argv[2],'x',encoding='ascii') as out:out.write(data)
os.chmod(sys.argv[2],0o600)
print('R338_EXISTING_PRELOAD_EXACT_VALUE_PRESERVED=YES')
PY
  echo R338_STAGED_CONFIG_IN_TMPFS=YES
  echo RESULT=R338_RUNTIME_STAGE_PASS
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
  printf '%s\n' "$MARK" '[Service]' 'EnvironmentFile=-/run/aleks-r338/observer.env' >"$DROP"
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
    *'/run/aleks-r338/observer.env'*) : ;;
    *) rm -f "$DROP";systemctl daemon-reload || :;die OVERLAY_ENV_NOT_REGISTERED ;;
  esac
  # The watchdog is owned by systemd PID1, independent of the SSH/MCP session.
  if ! systemd-run --unit=aleks-r338b-rollback --on-active=140s /bin/sh "$ROOT/controller.sh" rollback; then
    rm -f "$DROP";systemctl daemon-reload || :;die WATCHDOG_NOT_CREATED
  fi
  [ "$(systemctl is-active aleks-r338b-rollback.timer)" = active ] ||
    { rm -f "$DROP";systemctl daemon-reload || :;die WATCHDOG_NOT_ACTIVE; }
  echo R338_WATCHDOG_BEFORE_RESTART=VERIFIED
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
assert b'ALEKS_R338_ENABLE=YES' in env
preloads=[x.split(b'=',1)[1] for x in env if x.startswith(b'LD_PRELOAD=')]
assert len(preloads)==1
assert b'libsystrim.so.3' in preloads[0]
assert b'/run/aleks-r338/libaleksr338hook.so' in preloads[0]
print('R338_UMEDIASERVER_PRELOAD_ACTIVE=YES')
PY
  then
    echo RESULT=R338_LIVE_WINDOW_ARMED_AUTO_ROLLBACK
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
      echo R338_MEDIA_RESTART_RESTORED=YES
    else
      echo R338_MEDIA_RESTART_RESTORED=NO
      timeout 15 systemctl start umediaserver.service || :
    fi
  else
    echo R338_RUNTIME_DROPIN_ALREADY_ABSENT=YES
  fi
  verify_base
  verify_plugins
  [ "$(systemctl is-active umediaserver.service)" = active ] ||
    die ROLLBACK_MEDIA_NOT_ACTIVE
  if [ -d "$ROOT" ];then
    echo 'R338_ROLLBACK_STATUS=COMPLETE' >"$ROOT/rollback-status"
    chmod 0600 "$ROOT/rollback-status"
  fi
  echo RESULT=R338_RUNTIME_ROLLBACK_PASS
}
status() {
  if [ -e "$DROP" ];then echo R338_OVERRIDE=ACTIVE
  else echo R338_OVERRIDE=ABSENT; fi
  echo R338_MEDIA_SERVICE=$(systemctl is-active umediaserver.service 2>/dev/null || :)
  echo R338_AUDIO_SERVICE=$(systemctl is-active audiooutputd.service 2>/dev/null || :)
  echo R338_TIMER=$(systemctl is-active aleks-r338b-rollback.timer 2>/dev/null || :)
  if [ -d "$ROOT/metrics" ];then
    echo R338_METRIC_COUNT=$(find "$ROOT/metrics" -maxdepth 1 -name 'r338-*.json' | wc -l)
  else echo R338_METRIC_COUNT=0; fi
  echo RESULT=R338_STATUS_PASS
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
