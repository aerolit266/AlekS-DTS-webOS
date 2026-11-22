#!/bin/sh
# R331: isolated on-LG validation of aggregate-only GStreamer DTS tracer.
# Uses original checksum-pinned public R278 encoded fixtures with fakesink.
# Does not attach to Starfish, restart service, touch audio or export PCM.
set -eu
umask 077
LC_ALL=C
export LC_ALL
lab=/tmp/aleks-r331-tracer-qa-20261122
fixture=/tmp/aleks-r331-fixtures-20261122
source=/var/lib/webosbrew/aleks-dts-r278
expected=bc833620c49d19b6f58e68106abce2d2efce412125f35f09afa36062d4e39924
test "$(id -u)" -eq 0 || { echo R331_QA_NOT_ROOT; exit 2; }
test -d "$lab" && test ! -L "$lab" || { echo R331_QA_BAD_STAGE; exit 2; }
test "$(stat -c %a "$lab")" = 700 || { echo R331_QA_WRONG_MODE; exit 2; }
base64 -d "$lab/tracer.b64" >"$lab/libgstaleksr331live.so"
printf '%s  %s\n' "$expected" "$lab/libgstaleksr331live.so" | sha256sum -c - >/dev/null
chmod 0700 "$lab/libgstaleksr331live.so"
test ! -e "$fixture" && test ! -L "$fixture"
mkdir -m 0700 "$fixture"
cleanup() { rm -rf -- "$fixture"; }
trap cleanup EXIT
trap 'exit 2' HUP INT TERM
cp "$source/fixtures/dts-stereo.mka" "$fixture/stereo.mka"
cp "$source/fixtures/dts-51.mka" "$fixture/surround.mka"
printf '%s  %s\n' \
7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae "$fixture/stereo.mka" \
7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5 "$fixture/surround.mka" |
 sha256sum -c - >/dev/null
export GST_PLUGIN_PATH_1_0="$source/plugins:/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0:$lab"
export GST_REGISTRY_1_0="$lab/registry.bin"
export GST_REGISTRY_UPDATE=yes
export GST_PLUGIN_FEATURE_RANK=aleksdts16dec:350,decproxy:0
export GST_TRACERS=aleksr331live
export ALEKS_R331_ENABLE=YES
export ALEKS_R331_ISOLATED_QA=YES
export ALEKS_R331_QA_DIR="$lab"
gst-inspect-1.0 aleksr331live >"$lab/inspect.log" 2>&1 || {
 echo R331_QA_TRACER_FACTORY_NOT_FOUND; exit 2;
}
echo R331_NATIVE_TRACER_FACTORY_PASS
for track in stereo surround; do
  before=$(find "$lab" -maxdepth 1 -name 'r331-*.json' | wc -l)
  expected_ch=2
  if [ "$track" = surround ]; then expected_ch=6; fi
  if timeout 30 gst-launch-1.0 -q \
       filesrc "location=$fixture/$track.mka" \
       '!' matroskademux name=dm dm.audio_0 \
       '!' queue '!' decodebin '!' audioconvert \
       '!' "audio/x-raw,format=S16LE,channels=$expected_ch,rate=48000" \
       '!' identity sleep-time=42000 '!' fakesink sync=false \
       >"$lab/$track.stdout" 2>"$lab/$track.stderr"; then :; else
    echo "R331_QA_$track"_GST_EXIT_NOT_ZERO
    exit 2
  fi
  python3 - "$lab" "$track" "$before" <<'PY'
import json
from pathlib import Path
import sys
root=Path(sys.argv[1]);label=sys.argv[2];before=int(sys.argv[3])
files=sorted(root.glob('r331-*.json'),key=lambda p:p.stat().st_mtime_ns)
assert len(files)==before+1, (len(files),before)
d=json.loads(files[-1].read_text())
assert d['schema']=='aleks-dts-r331-scalar-v1'
assert d['raw_pcm_exported'] is False and d['audio_files_created']==0
assert d['tracer_loaded'] and not d['pipeline_modified']
assert d['dts_decoder_seen'] and d['pcm_seen']
assert d['input_buffers']>0 and d['be16_sync']>0
assert d['pcm_buffers']>0 and d['pcm_sampled']>0
assert d['pcm_nonzero']>0 and d['pcm_rms_dbfs']>-200
assert d['pcm_channels']==(2 if label=='stereo' else 6)
assert d['pcm_rate']==48000 and d['map_failures']==0
assert d['event_bytes']==0
print('R331_QA_TRACK='+label)
print('R331_QA_INPUT_BUFFERS='+str(d['input_buffers']))
print('R331_QA_BE16_FRAMES='+str(d['be16_sync']))
print('R331_QA_PCM_NONZERO='+str(d['pcm_nonzero']))
print('R331_QA_RMS_DBFS='+str(d['pcm_rms_dbfs']))
print('R331_QA_EVENTS='+','.join(str(d['event_'+k]) for k in ('start','caps','time','bytes')))
print('RESULT=R331_QA_'+label.upper()+'_PASS')
PY
done
echo R331_QA_MEDIA_RESTARTED=NO
echo R331_QA_AUDIO_FILES_CREATED=0
echo RESULT=R331_PHYSICAL_LG_ISOLATED_TRACER_2_OF_2_PASS
