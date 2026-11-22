#!/bin/sh
# R337 independent LG native GStreamer ABI/PCM test.
# Only original public R278 encoded DTS Matroska fixtures and fakesink.
# Never connects hardware speaker, native Realtek sink, Lampa, or Starfish.
# SPDX-License-Identifier: MIT
set -eu
umask 077
export LC_ALL=C
lab=/tmp/aleks-r337-sink-qa-20261122
original=/var/lib/webosbrew/aleks-dts-r278
observer=$lab/libaleksr337sink.so
expected=2e460188129b3cf946a10b66f21c2dcc6adb1994d35ab8faf9b3d0576d94f595
fail() { echo "RESULT=R337_LG_QA_ABORT_$1";exit 2; }

test "$(id -u)" -eq 0 || fail NONROOT
test -d "$lab" && test ! -L "$lab" || fail WRONG_STAGE
test "$(stat -c %a "$lab")" = 700 || fail INSECURE_DIRECTORY
printf '%s  %s\n' "$expected" "$observer" | sha256sum -c - >/dev/null ||
  fail BINARY_HASH
printf '%s  %s\n' \
7b49fee09f78add1fb27afd404dc7ec229f4950e5803c081e1068b6d245587ae "$original/fixtures/dts-stereo.mka" \
7f9ed29c1ea9e6493d1977590a8506e432897f2eabd29ef2d7fc1ef48a4af6b5 "$original/fixtures/dts-51.mka" |
  sha256sum -c - >/dev/null || fail FIXTURE_HASH
test "$(systemctl is-active umediaserver.service)" = active ||
  fail MEDIA_SERVICE_INACTIVE
test "$(systemctl is-active audiooutputd.service)" = active ||
  fail AUDIO_SERVICE_INACTIVE
test -z "$(systemctl show umediaserver.service -p DropInPaths --value)" ||
  fail UNEXPECTED_MEDIA_DROPIN
chmod 0700 "$observer"
mkdir -m 0700 "$lab/qa-stereo" "$lab/qa-surround"
export GST_PLUGIN_PATH_1_0="$original/plugins:/usr/lib/gstreamer-1.0:/mnt/lg/res/lglib/gstreamer-1.0"
export GST_REGISTRY_1_0="$lab/registry.bin"
export GST_PLUGIN_FEATURE_RANK=aleksdts16dec:350,decproxy:0
export GST_REGISTRY_UPDATE=yes
gst-inspect-1.0 aleksdts16dec >"$lab/native-factory.txt" 2>&1 ||
  fail NATIVE_DECODER_UNAVAILABLE
echo R337_NATIVE_R278_DECODER_FACTORY_PASS
oldpreload=$(printenv LD_PRELOAD 2>/dev/null || :)
for track in stereo surround; do
  channels=2
  fixture="$original/fixtures/dts-stereo.mka"
  if [ "$track" = surround ];then
    channels=6
    fixture="$original/fixtures/dts-51.mka"
  fi
  dir="$lab/qa-$track"
  if ! timeout 23 env \
     LD_PRELOAD="$oldpreload $observer" \
     ALEKS_R337_ENABLE=YES \
     ALEKS_R337_ISOLATED_QA=YES \
     ALEKS_R337_QA_DIR="$dir" \
     gst-launch-1.0 -q \
        filesrc "location=$fixture" \
        '!' matroskademux name=dm dm.audio_0 \
        '!' queue '!' decodebin '!' audioconvert \
        '!' "audio/x-raw,format=S16LE,channels=$channels,rate=48000" \
        '!' fakesink sync=false \
        >"$dir/stdout" 2>"$dir/stderr";then
    echo "RESULT=R337_GST_CHILD_FAILED_$track"
    exit 2
  fi
  python3 - "$dir" "$track" "$channels" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1]);label=sys.argv[2];channels=int(sys.argv[3])
files=list(root.glob('r337-*.json'))
assert len(files)==1,("METRIC_FILE_COUNT",len(files))
data=json.loads(files[0].read_text())
sink=data['renderer_qa_fakesink']
assert data['schema']=='aleks-dts-r337-interpose-v1'
assert sink['pcm_buffers']==94 and sink['buffers']==94,sink
assert sink['pcm_samples']==94*1024
assert sink['pcm_nonzero']>0 and sink['rms_dbfs']>-90
assert sink['channels']==channels and sink['rate']==48000
assert sink['dts_buffers']==sink['ac3_buffers']==0
assert sink['bad_maps']==0 and sink['segment_other']==0
assert data['renderer_rtkalsasink']['buffers']==0
assert data['renderer_rasink']['buffers']==0
assert data['raw_pcm_exported'] is False
assert data['raw_media_exported'] is False
assert data['audio_files_created']==0
assert data['pipeline_mutated'] is False
assert data['external_process_attached'] is False
print('R337_NATIVE_TRACK='+label)
print('R337_NATIVE_PCM_BUFFERS='+str(sink['pcm_buffers']))
print('R337_NATIVE_PCM_NONZERO='+str(sink['pcm_nonzero']))
print('R337_NATIVE_RMS_DBFS='+str(sink['rms_dbfs']))
print('R337_NATIVE_CHANNELS='+str(sink['channels']))
print('R337_NATIVE_BE16_DTS_INPUT='+str(data['be16_sync']))
print('R337_NATIVE_STREAM_START='+str(sink['stream_start']))
print('R337_NATIVE_CAPS_EVENTS='+str(sink['caps_events']))
print('RESULT=R337_LG_'+label.upper()+'_ISOLATED_SINK_PROBE_PASS')
PY
done
test "$(systemctl is-active umediaserver.service)" = active ||
  fail MEDIA_SERVICE_AFTER
test "$(systemctl is-active audiooutputd.service)" = active ||
  fail AUDIO_SERVICE_AFTER
echo R337_AUDIO_SPEAKER_USED=NO
echo R337_MEDIA_SERVICES_RESTARTED=NO
echo R337_AUDIO_SAMPLES_RECORDED=NO
echo RESULT=R337_LG_ISOLATED_REAL_R278_SINK_2_OF_2_PASS
