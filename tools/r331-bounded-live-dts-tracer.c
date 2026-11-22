/*
 * R331 bounded live DTS GStreamer tracer for LG webOS 26.
 *
 * Does not change elements, pad flows, policy, ALSA or decoder state.
 * Counts decoder-bound DTS buffers/events and bounded post-decoder PCM
 * amplitude samples. Audio bytes, filenames, timestamps of user media,
 * paths, caps fields, stream IDs, URLs and titles never leave memory.
 *
 * Activation: GST_TRACERS=aleksr331live ALEKS_R331_ENABLE=YES
 * Only starfish-media-* OR explicitly isolated GST QA is permitted.
 * Emits private aggregate-only JSON every 2s under /run/aleks-r331/metrics
 * (or temporary /tmp/aleks-r331-qa-... ONLY for QA).
 * Self-disables after 180 seconds even without rollback. Runtime files
 * reside in /run and disappear on reboot. No file I/O in pad hooks.
 *
 * IMPORTANT: tracing raw media codec buffer contents is prohibited; the
 * tracer only samples decoded raw audio amplitude in process memory and
 * emits aggregate scalar values. No audio recording, external sockets
 * or process attachment.
 *
 * SPDX-License-Identifier: MIT
 */
#define _POSIX_C_SOURCE 200809L
#include <gst/gst.h>
#include <gst/gsttracer.h>
#include <math.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>

#ifndef PACKAGE
#define PACKAGE "aleks-dts"
#endif
#ifndef R331_WINDOW_US
#define R331_WINDOW_US (180LL * 1000000LL)
#endif
#define R331_PCM_SAMPLE_BUDGET_PER_BUFFER 1024U
#define R331_MAX_TOTAL_SAMPLES 14000000ULL

typedef struct {
  GstTracer parent;
  GMutex lock;
  gint enabled;
  gint64 start_us;
  guint64 input_buffers, input_be16_sync, missing_pts;
  guint64 event_start, event_caps, event_time, event_bytes;
  guint64 pcm_buffers, pcm_samples, pcm_nonzero;
  guint64 accepted_pcm_format_s16, accepted_pcm_format_s32, accepted_pcm_format_f32;
  guint64 pcm_clipped, map_failures, ignored_buffers;
  guint64 energy_samples;
  gdouble energy_sq, pcm_peak;
  gint pcm_channels, pcm_rate;
  gboolean seen_decoder, seen_pcm, in_fakesink_qa;
  char dest[192];
} AlekSR331Tracer;

typedef struct { GstTracerClass parent_class; } AlekSR331TracerClass;
G_DEFINE_TYPE(AlekSR331Tracer, aleks_r331_tracer, GST_TYPE_TRACER)

static gboolean active(AlekSR331Tracer *s) {
  if (!g_atomic_int_get(&s->enabled)) return FALSE;
  if ((g_get_monotonic_time() - s->start_us) > R331_WINDOW_US) {
    g_atomic_int_set(&s->enabled, 0);
    return FALSE;
  }
  return TRUE;
}

static gboolean wrapper_pad(GstPad *pad, gboolean *is_sink) {
  if (!pad) return FALSE;
  GstElement *owner = gst_pad_get_parent_element(pad);
  if (!owner) return FALSE;
  const gchar *cls = G_OBJECT_TYPE_NAME(owner);
  GstElementFactory *factory = gst_element_get_factory(owner);
  const char *feature = factory ? gst_plugin_feature_get_name(GST_PLUGIN_FEATURE(factory)) : NULL;
  gboolean match = (cls && g_str_has_prefix(cls, "AlekSDts16Dec")) ||
                   (feature && g_strcmp0(feature, "aleksdts16dec") == 0);
  if (!match && g_strcmp0(g_getenv("ALEKS_R331_ISOLATED_QA"), "YES") == 0)
    match = feature && g_strcmp0(feature, "dtsdec") == 0;
  if (match && is_sink) *is_sink = GST_PAD_DIRECTION(pad) == GST_PAD_SINK;
  gst_object_unref(owner);
  return match;
}

static void encoded_hook(GObject *obj, GstClockTime ts, GstPad *pad, GstBuffer *buffer) {
  (void)ts;
  AlekSR331Tracer *s = (AlekSR331Tracer *)obj;
  if (!active(s)) return;
  gboolean sink = FALSE;
  if (!wrapper_pad(pad, &sink) || !sink || !buffer) return;
  guint64 bytes = gst_buffer_get_size(buffer);
  if (bytes == 0 || bytes > 262144) return;
  gboolean pts_missing = !GST_BUFFER_PTS_IS_VALID(buffer);
  gboolean sync = FALSE;
  GstMapInfo map;
  if (gst_buffer_map(buffer, &map, GST_MAP_READ)) {
    if (map.size >= 4 && map.data[0] == 0x7f && map.data[1] == 0xfe &&
        map.data[2] == 0x80 && map.data[3] == 0x01) sync = TRUE;
    gst_buffer_unmap(buffer, &map);
  } else {
    g_mutex_lock(&s->lock);
    s->map_failures++;
    g_mutex_unlock(&s->lock);
    return;
  }
  g_mutex_lock(&s->lock);
  s->seen_decoder = TRUE;
  s->input_buffers++;
  s->input_be16_sync += sync;
  s->missing_pts += pts_missing;
  g_mutex_unlock(&s->lock);
}

static void event_hook(GObject *obj, GstClockTime ts, GstPad *pad, GstEvent *event) {
  (void)ts;
  AlekSR331Tracer *s = (AlekSR331Tracer *)obj;
  if (!active(s) || !event) return;
  gboolean sink = FALSE;
  if (!wrapper_pad(pad, &sink)) return;
  g_mutex_lock(&s->lock);
  switch (GST_EVENT_TYPE(event)) {
    case GST_EVENT_STREAM_START: s->event_start++; break;
    case GST_EVENT_CAPS: s->event_caps++; break;
    case GST_EVENT_SEGMENT: {
      const GstSegment *segment = NULL;
      gst_event_parse_segment(event, &segment);
      if (segment && segment->format == GST_FORMAT_TIME) s->event_time++;
      else s->event_bytes++;
      break;
    }
    default: break;
  }
  g_mutex_unlock(&s->lock);
}

static void pcm_hook(GObject *obj, GstClockTime ts, GstPad *pad, GstBuffer *buffer) {
  (void)ts;
  AlekSR331Tracer *s = (AlekSR331Tracer *)obj;
  if (!active(s)) return;
  gboolean sink = TRUE;
  if (!wrapper_pad(pad, &sink) || sink || !buffer) return;
  GstCaps *caps = gst_pad_get_current_caps(pad);
  if (!caps || gst_caps_get_size(caps) != 1) {
    if (caps) gst_caps_unref(caps);
    return;
  }
  const GstStructure *st = gst_caps_get_structure(caps, 0);
  if (g_strcmp0(gst_structure_get_name(st), "audio/x-raw")) {
    gst_caps_unref(caps);
    return;
  }
  const gchar *fmt = gst_structure_get_string(st, "format");
  const gchar *layout = gst_structure_get_string(st, "layout");
  int rate=0,channels=0;
  gst_structure_get_int(st, "channels", &channels);
  gst_structure_get_int(st, "rate", &rate);
  gint kind = 0;
  if (g_strcmp0(fmt, "S16LE") == 0) kind=1;
  if (g_strcmp0(fmt, "S32LE") == 0) kind=2;
  if (g_strcmp0(fmt, "F32LE") == 0) kind=3;
  if (kind==0 || rate<8000 || rate>192000 || channels<1 || channels>8 ||
      (layout && g_strcmp0(layout, "interleaved") != 0)) {
    gst_caps_unref(caps);
    return;
  }
  gst_caps_unref(caps);
  GstMapInfo m;
  if (!gst_buffer_map(buffer, &m, GST_MAP_READ)) {
    g_mutex_lock(&s->lock);s->map_failures++;g_mutex_unlock(&s->lock);
    return;
  }
  guint step=kind==1?2:4;
  if ((m.size%step) || m.size>262144) {
    g_mutex_lock(&s->lock);s->ignored_buffers++;g_mutex_unlock(&s->lock);
    gst_buffer_unmap(buffer,&m);
    return;
  }
  guint sample_count=(guint)(m.size/step);
  guint limit=MIN(sample_count, R331_PCM_SAMPLE_BUDGET_PER_BUFFER);
  guint64 nz=0, clipped=0;
  double squared=0, peak=0;
  for(guint i=0;i<limit;i++) {
    const guint8 *p=m.data+(size_t)i*step;
    gdouble a=0;
    if (kind==1) {
      gint16 v=(gint16)((guint16)p[0] | ((guint16)p[1]<<8));
      a=(gdouble)v/32768.0;
    } else if(kind==2) {
      gint32 v=(gint32)((guint32)p[0]|((guint32)p[1]<<8)|
                        ((guint32)p[2]<<16)|((guint32)p[3]<<24));
      a=(gdouble)v/2147483648.0;
    } else {
      float v;
      memcpy(&v,p,4);
      if(!isfinite(v)) continue;
      a=(gdouble)v;
    }
    if(a!=0) nz++;
    if(fabs(a)>peak) peak=fabs(a);
    if(fabs(a)>1.0) clipped++;
    squared+=a*a;
  }
  gst_buffer_unmap(buffer,&m);
  g_mutex_lock(&s->lock);
  if(s->pcm_samples<R331_MAX_TOTAL_SAMPLES) {
    s->seen_pcm=TRUE;
    s->pcm_buffers++;
    s->pcm_samples+=limit;
    s->pcm_nonzero+=nz;
    s->pcm_clipped+=clipped;
    s->energy_sq+=squared;
    s->energy_samples+=limit;
    if(peak>s->pcm_peak) s->pcm_peak=peak;
    s->accepted_pcm_format_s16+=kind==1;
    s->accepted_pcm_format_s32+=kind==2;
    s->accepted_pcm_format_f32+=kind==3;
    s->pcm_channels=channels;
    s->pcm_rate=rate;
  }
  g_mutex_unlock(&s->lock);
}

static void export_snapshot(AlekSR331Tracer *s, guint duration_seconds) {
  char data[1200];
  g_mutex_lock(&s->lock);
  gdouble dbfs = s->energy_samples && s->energy_sq > 0 ?
     10*log10(s->energy_sq/s->energy_samples) : -999.0;
  gdouble peak = s->pcm_peak>0 ? 20*log10(s->pcm_peak) : -999.0;
  int n=snprintf(data,sizeof(data),
   "{\"schema\":\"aleks-dts-r331-scalar-v1\",\"elapsed_s\":%u,"
   "\"input_buffers\":%" G_GUINT64_FORMAT ",\"be16_sync\":%" G_GUINT64_FORMAT ","
   "\"missing_pts\":%" G_GUINT64_FORMAT ",\"event_start\":%" G_GUINT64_FORMAT ","
   "\"event_caps\":%" G_GUINT64_FORMAT ",\"event_time\":%" G_GUINT64_FORMAT ","
   "\"event_bytes\":%" G_GUINT64_FORMAT ",\"pcm_buffers\":%" G_GUINT64_FORMAT ","
   "\"pcm_sampled\":%" G_GUINT64_FORMAT ",\"pcm_nonzero\":%" G_GUINT64_FORMAT ","
   "\"pcm_rms_dbfs\":%.2f,\"pcm_peak_dbfs\":%.2f,"
   "\"pcm_clipped\":%" G_GUINT64_FORMAT ",\"pcm_channels\":%d,\"pcm_rate\":%d,"
   "\"format_s16_buffers\":%" G_GUINT64_FORMAT ","
   "\"format_s32_buffers\":%" G_GUINT64_FORMAT ","
   "\"format_f32_buffers\":%" G_GUINT64_FORMAT ","
   "\"map_failures\":%" G_GUINT64_FORMAT ",\"ignored_buffers\":%" G_GUINT64_FORMAT ","
   "\"dts_decoder_seen\":%s,\"pcm_seen\":%s,"
   "\"raw_pcm_exported\":false,\"process_attached\":false,"
   "\"audio_files_created\":0,\"pipeline_modified\":false,\"tracer_loaded\":true}\n",
   duration_seconds,s->input_buffers,s->input_be16_sync,s->missing_pts,
   s->event_start,s->event_caps,s->event_time,s->event_bytes,
   s->pcm_buffers,s->pcm_samples,s->pcm_nonzero,dbfs,peak,
   s->pcm_clipped,s->pcm_channels,s->pcm_rate,
   s->accepted_pcm_format_s16,s->accepted_pcm_format_s32,
   s->accepted_pcm_format_f32,s->map_failures,s->ignored_buffers,
   s->seen_decoder?"true":"false",s->seen_pcm?"true":"false");
  g_mutex_unlock(&s->lock);
  if(n<=0 || n>=(gint)sizeof(data)) return;
  char tmp[240];
  snprintf(tmp,sizeof(tmp),"%s.tmp",s->dest);
  int fd=open(tmp,O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC|O_NOFOLLOW,0600);
  if(fd<0) return;
  ssize_t wrote=write(fd,data,n);
  (void)close(fd);
  if(wrote != n) {unlink(tmp);return;}
  if(rename(tmp,s->dest)) unlink(tmp);
}

static gpointer exporter(gpointer item) {
  AlekSR331Tracer *s=item;
  guint tick=0;
  for(tick=0;tick<=180;tick+=2) {
    g_usleep(2000000);
    if(g_get_monotonic_time()-s->start_us>=R331_WINDOW_US)
      g_atomic_int_set(&s->enabled,0);
    export_snapshot(s,tick+2);
    if(!g_atomic_int_get(&s->enabled)) break;
  }
  g_atomic_int_set(&s->enabled,0);
  export_snapshot(s,tick+2);
  g_object_unref(s);
  return NULL;
}

static void aleks_r331_tracer_init(AlekSR331Tracer *s) {
  const gchar *gate=g_getenv("ALEKS_R331_ENABLE");
  if(g_strcmp0(gate,"YES")) return;
  const gchar *mode=g_getenv("ALEKS_R331_ISOLATED_QA");
  gboolean qa=mode && g_strcmp0(mode,"YES")==0;
  char comm[64]={0};
  FILE *f=fopen("/proc/self/comm","r");
  if(f) { if (!fgets(comm,sizeof(comm),f)) comm[0]=0; fclose(f); }
  if(!g_str_has_prefix(comm,"starfish-media-") && !qa) return;
  const gchar *destdir=qa?g_getenv("ALEKS_R331_QA_DIR"):"/run/aleks-r331/metrics";
  if(!destdir) return;
  if(qa && (!g_str_has_prefix(destdir,"/tmp/aleks-r331-") ||
            strstr(destdir,"..") || strlen(destdir)>125)) return;
  if(!qa && g_strcmp0(destdir,"/run/aleks-r331/metrics")) return;
  struct stat st;
  if(stat(destdir,&st) || !S_ISDIR(st.st_mode) || (st.st_mode & 0077)) return;
  g_snprintf(s->dest,sizeof(s->dest),"%s/r331-%ld.json",destdir,(long)getpid());
  g_mutex_init(&s->lock);
  s->start_us=g_get_monotonic_time();
  g_atomic_int_set(&s->enabled,1);
  s->in_fakesink_qa=qa;
  gst_tracing_register_hook(GST_TRACER(s),"pad-chain-pre",G_CALLBACK(encoded_hook));
  gst_tracing_register_hook(GST_TRACER(s),"pad-push-pre",G_CALLBACK(pcm_hook));
  gst_tracing_register_hook(GST_TRACER(s),"pad-push-event-pre",G_CALLBACK(event_hook));
  g_object_ref(s);
  GThread *thread=g_thread_new("aleks-r331-dts",exporter,s);
  g_thread_unref(thread);
}

static void aleks_r331_tracer_class_init(AlekSR331TracerClass *klass) {
  (void)klass;
}

static gboolean plugin_init(GstPlugin *plugin) {
  return gst_tracer_register(plugin,"aleksr331live",aleks_r331_tracer_get_type());
}
GST_PLUGIN_DEFINE(GST_VERSION_MAJOR,GST_VERSION_MINOR,aleksr331live,
    "Bounded redacted in-process DTS frame/PCM tracer for R331 diagnosis",
    plugin_init,"0.1.0-r331","LGPL","AlekS DTS","https://github.com/aerolit266/AlekS-DTS-webOS")
