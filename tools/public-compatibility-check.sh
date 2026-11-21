#!/bin/sh
# AlekS DTS: public read-only hardware/ABI compatibility discovery.
# Never installs, downloads binaries, modifies systemd or scans private data.
set -u
LC_ALL=C; export LC_ALL

pass() { printf 'PASS %s\n' "$1"; }
note() { printf 'INFO %s\n' "$1"; }
warn() { printf 'WARN %s\n' "$1"; }
printf 'AlekS DTS compatibility discovery (READ ONLY)\n'
printf 'kernel_arch='; uname -m || :
printf 'kernel_release='; uname -r || :
printf 'uid='; id -u || :
if [ ! -x /usr/bin/gst-inspect-1.0 ] || [ ! -r /usr/sbin/umediaserver ]; then
  printf 'RESULT=UNSUPPORTED_NO_NATIVE_GSTREAMER\n'
  exit 0
fi
gv=$(/usr/bin/gst-inspect-1.0 --version 2>/dev/null | head -2)
printf '%s\n' "$gv"
for f in /usr/sbin/umediaserver /usr/bin/gst-inspect-1.0 /usr/lib/libgstreamer-1.0.so.0; do
  if [ ! -r "$f" ]; then
    warn "missing ELF $f"
    continue
  fi
  a=$(od -An -tu1 -j4 -N2 "$f" 2>/dev/null | tr -s ' ' | tr -d '\n') || a=''
  m=$(od -An -tu1 -j18 -N2 "$f" 2>/dev/null | tr -s ' ' | tr -d '\n') || m=''
  note "ELF=$f class_and_endian=[$a] machine=[$m]"
done
if command -v systemctl >/dev/null 2>&1; then
  systemctl show umediaserver.service -p LoadState -p ActiveState -p User -p DynamicUser -p EnvironmentFiles -p DropInPaths 2>/dev/null || :
fi
if [ -r /proc/self/mountinfo ]; then
  awk '$5=="/var" {line=$0} END { if(line!="") print "effective_var_mount=" line }' /proc/self/mountinfo
fi
for e in aleksdts16dec aleksdtsr130optin avdec_ac3; do
  if /usr/bin/gst-inspect-1.0 "$e" >/dev/null 2>&1; then pass "element:$e"; else note "missing_element:$e"; fi
done
case "$gv" in
  *'GStreamer 1.16.2'*) printf 'PROFILE=ARMV7_GSTREAMER_1_16_CHECK_ELF_AND_USE_R278_VERIFY\n' ;;
  *'GStreamer 1.24.10'*) printf 'PROFILE=GSTREAMER_1_24_VERIFY_ONLY_UNTIL_DEVICE_APPROVED\n' ;;
  *) printf 'PROFILE=UNTESTED_GSTREAMER_VERSION\n' ;;
esac
printf 'RESULT=DISCOVERY_COMPLETE_NO_INSTALL\n'
