#!/bin/sh
# R331: independent on-LG LD_PRELOAD interposer ABI/PCM QA.
# Only a new gst-launch child with PUBLIC DTS fixtures and fakesink.
# No hook or restart of active Starfish and no decoded PCM files.
set -eu
umask 077
LC_ALL=C
export LC_ALL
lab=/tmp/aleks-r331-interposer-qa-20261122
fixtures=/tmp/aleks-r331-interposer-fixtures-20261122
original=/var/lib/webosbrew/aleks-dts-r278
sha=c692b256d91484f5cf9becce381544854098335b5ea92ce00afbe7ab9b7236e2
test "$(id -u)" -eq 0
test -d "$lab" && test ! -L "$lab"
test "$(stat -c %a "$lab")" = 700
base64 -d "$lab/hook.b64" >"$lab/libaleksr331hook.so"
printf '%s  %s\n' "$sha" "$lab/libaleksr331hook.so" | sha256sum -c - >/dev/null
chmod 0700 "$lab/libaleksr331hook.so"
test ! -e "$fixtures"
mkdir -m 0700 "$fixtures"
cleanup() { rm -rf -- "$fixtures"; }
trap cleanup EXIT
trap 'exit 2' HUP INT TERM
cp "$original/fixtures/dts-stereo.mka" "$fixtures/stereo.mka"
cp "$original/fixtures/dts-51.mka" "$fixtures/surround.mka"
printf '%s  %s\n' \
7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae "$fixtures/stereo.mka" \
7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5 "$fixtures/surround.mka" |
sha256sum -c - >/dev/null
echo R331_LG_PUBLIC_DTS_FIXTURE_HASHES_PASS
export GST_PLUGIN_PATH_1_0="$original/plugins:/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0"
export GST_REGISTRY_1_0="$lab/qa-registry.bin"
export GST_REGISTRY_UPDATE=yes
export GST_PLUGIN_FEATURE_RANK=aleksdts16dec:350,decproxy:0
oldpreload=$(printenv LD_PRELOAD 2>/dev/null || :)
for track in stereo surround; do
  ch=2
  if [ "$track" = surround ]; then ch=6; fi
  before=$(find "$lab" -maxdepth 1 -name 'r331-*.json' | wc -l)
  if timeout 30 env \
       LD_PRELOAD="$oldpreload $lab/libaleksr331hook.so" \
       ALEKS_R331_ENABLE=YES ALEKS_R331_ISOLATED_QA=YES \
       ALEKS_R331_QA_DIR="$lab" \
       gst-launch-1.0 -q \
       filesrc "location=$fixtures/$track.mka" \
       '!' matroskademux name=dm dm.audio_0 \
       '!' queue '!' decodebin '!' audioconvert \
       '!' "audio/x-raw,format=S16LE,channels=$ch,rate=48000" \
       '!' identity sleep-time=42000 \
       '!' fakesink sync=false \
       >"$lab/$track.stdout" 2>"$lab/$track.stderr"; then :; else
    echo "R331_LD_QA_GST_FAILURE_$track"
    exit 2
  fi
  python3 - "$lab" "$track" "$before" <<'PY'
from pathlib import Path
import sys,json
folder=Path(sys.argv[1]); label=sys.argv[2]; before=int(sys.argv[3])
files=sorted(folder.glob('r331-*.json'),key=lambda p:p.stat().st_mtime_ns)
assert len(files)>before,(len(files),before)
records=[json.loads(p.read_text()) for p in files]
best=max(records,key=lambda r:(r.get('pcm_nonzero',0),r.get('be16_sync',0)))
assert best['schema']=='aleks-dts-r331-interpose-v1'
assert best['raw_pcm_exported'] is False and best['audio_files_created']==0
assert best['pipeline_mutated'] is False
assert best['input_buffers']>0 and best['be16_sync']>0
assert best['pcm_buffers']>0 and best['pcm_sampled']>0
assert best['pcm_nonzero']>0 and best['pcm_rate']==48000
assert best['pcm_channels']==(2 if label=='stereo' else 6)
assert best['bad_maps']==0 and best['event_bytes']==0
print('R331_LD_QA_TRACK='+label)
print('R331_LD_QA_INPUT='+str(best['input_buffers']))
print('R331_LD_QA_BE16='+str(best['be16_sync']))
print('R331_LD_QA_PCM_BUFFERS='+str(best['pcm_buffers']))
print('R331_LD_QA_PCM_NONZERO='+str(best['pcm_nonzero']))
print('R331_LD_QA_RMS_DBFS='+str(best['pcm_rms_dbfs']))
print('R331_LD_QA_EVENTS='+','.join(str(best['event_'+k]) for k in ('start','caps','time','bytes')))
print('RESULT=R331_LD_'+label.upper()+'_ISOLATED_PASS')
PY
done
echo R331_MEDIA_SERVICE_RESTARTED=NO
echo R331_RAW_PCM_STORED=NO
echo RESULT=R331_LG_LD_INTERPOSER_ISOLATED_2_OF_2_PASS
