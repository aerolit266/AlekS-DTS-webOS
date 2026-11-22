/*
 * R338 fallback: bounded, process-gated, low-dependency GStreamer
 * LD_PRELOAD observer for vendor builds with GST_TRACERS disabled.
 *
 * Symbol interposition only on gst_pad_push and gst_pad_push_event.
 * No replacement of codec/system libraries and no mutation of buffers,
 * pad state, routing, service controls or audio output.
 * All GStreamer APIs are resolved lazily at runtime: this SO has NO
 * libgstreamer/libglib/libgobject DT_NEEDED in umediaserver parent.
 *
 * Only Starfish child or ALEKS_R338_ISOLATED_QA=YES is active.
 * Exports counts and normalized PCM energy only; never decoded/encoded
 * user data, streams, media identifiers, URLs, timestamps or secrets.
 * Maximum active 180 seconds, private JSON on /run tmpfs, no hooks
 * block on file writes; worker writes once every 2s.
 *
 * The owner must authorize even temporary production use separately;
 * first test exclusively with public DTS R278 fixtures and fakesink.
 * SPDX-License-Identifier: MIT
 */
#define _GNU_SOURCE
#include <gst/gst.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#ifndef R338_WINDOW_SECS
#define R338_WINDOW_SECS 180
#endif
#define MAX_PCM_PER_BUFFER 1024U
#define MAX_PCM_TOTAL 14000000U

typedef GstFlowReturn (*PadPush)(GstPad*,GstBuffer*);
typedef gboolean (*PadPushEvent)(GstPad*,GstEvent*);
typedef GstPad* (*PadGetPeer)(GstPad*);
typedef GstElement* (*PadGetParent)(GstPad*);
typedef GstElementFactory* (*ElementFactory)(GstElement*);
typedef void (*ObjUnref)(gpointer);
typedef GstCaps* (*PadGetCaps)(GstPad*);
typedef guint (*CapsSize)(const GstCaps*);
typedef const GstStructure* (*CapsStructure)(const GstCaps*,guint);
typedef const gchar* (*StructureName)(const GstStructure*);
typedef const gchar* (*StructureString)(const GstStructure*,const gchar*);
typedef gboolean (*StructureInt)(const GstStructure*,const gchar*,gint*);
typedef void (*MiniUnref)(GstMiniObject*);
typedef gboolean (*BufferMap)(GstBuffer*,GstMapInfo*,GstMapFlags);
typedef void (*BufferUnmap)(GstBuffer*,GstMapInfo*);
typedef void (*EventSegment)(GstEvent*,const GstSegment**);

static struct {
  PadPush push;
  PadPushEvent push_event;
  PadGetPeer get_peer;
  PadGetParent get_parent;
  ElementFactory get_factory;
  ObjUnref object_unref;
  PadGetCaps current_caps;
  CapsSize caps_size;
  CapsStructure caps_structure;
  StructureName structure_name;
  StructureString structure_string;
  StructureInt structure_int;
  MiniUnref mini_unref;
  BufferMap buffer_map;
  BufferUnmap buffer_unmap;
  EventSegment parse_segment;
  int available;
} a;
static pthread_once_t resolve_once=PTHREAD_ONCE_INIT;
static pthread_mutex_t mu=PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t io_mu=PTHREAD_MUTEX_INITIALIZER;
static atomic_int enabled=ATOMIC_VAR_INIT(0);
static atomic_ulong last_dts_sec=ATOMIC_VAR_INIT(0);
static atomic_uintptr_t selected_converter_pad=ATOMIC_VAR_INIT((uintptr_t)0);
static atomic_ulong selected_converter_seen=ATOMIC_VAR_INIT(0);
static unsigned long started_at=0;
static int qa_mode=0;
static char output_path[192];
static struct {
  uint64_t input_buffers, be16_sync, missing_pts;
  uint64_t event_start,event_caps,event_time,event_bytes;
  uint64_t pcm_buffers, pcm_samples, pcm_nonzero, bad_maps, ignored_pcm;
  uint64_t pcm_wrapper_buffers, pcm_converter_buffers;
  uint64_t clipped, s16_buffers, s32_buffers, f32_buffers;
  double squared, peak;
  int pcm_channels, pcm_rate;
 } stats;
/* Counters intentionally separate the outer Realtek bin, its inner hardware
   sink, and the QA fakesink: a frame may cross both real elements. */
typedef struct {
  uint64_t buffers, pcm_buffers, pcm_samples, pcm_nonzero;
  uint64_t encoded_dts, encoded_ac3, dts_be16_sync, ac3_sync, other_caps;
  uint64_t event_stream_start, event_caps, event_segment_time, event_segment_other;
  uint64_t event_flush, bad_maps;
  double pcm_squared, pcm_peak;
  int channels, rate;
} RendererStats;
static RendererStats renderer[4];

static void resolve(void) {
#define RESOLVE(field,name) do { \
  void *p=dlsym(RTLD_NEXT,name); \
  memcpy(&a.field,&p,sizeof(p)); \
} while(0)
  RESOLVE(push,"gst_pad_push");
  RESOLVE(push_event,"gst_pad_push_event");
  RESOLVE(get_peer,"gst_pad_get_peer");
  RESOLVE(get_parent,"gst_pad_get_parent_element");
  RESOLVE(get_factory,"gst_element_get_factory");
  RESOLVE(object_unref,"gst_object_unref");
  RESOLVE(current_caps,"gst_pad_get_current_caps");
  RESOLVE(caps_size,"gst_caps_get_size");
  RESOLVE(caps_structure,"gst_caps_get_structure");
  RESOLVE(structure_name,"gst_structure_get_name");
  RESOLVE(structure_string,"gst_structure_get_string");
  RESOLVE(structure_int,"gst_structure_get_int");
  RESOLVE(mini_unref,"gst_mini_object_unref");
  RESOLVE(buffer_map,"gst_buffer_map");
  RESOLVE(buffer_unmap,"gst_buffer_unmap");
  RESOLVE(parse_segment,"gst_event_parse_segment");
#undef RESOLVE
  a.available = a.push && a.push_event && a.get_peer && a.get_parent &&
                a.get_factory && a.object_unref &&
                a.current_caps && a.caps_size && a.caps_structure &&
                a.structure_name && a.structure_string && a.structure_int &&
                a.mini_unref && a.buffer_map && a.buffer_unmap &&
                a.parse_segment;
}

static unsigned long mono_seconds(void) {
  struct timespec ts={0};
  return clock_gettime(CLOCK_MONOTONIC,&ts)==0 ? (unsigned long)ts.tv_sec : 0;
}
static int active(void) {
  if(!atomic_load_explicit(&enabled,memory_order_relaxed)) return 0;
  if(mono_seconds()-started_at >= R338_WINDOW_SECS) {
    atomic_store_explicit(&enabled,0,memory_order_relaxed);
    return 0;
  }
  return 1;
}
static int owned_by_decoder(GstPad *pad) {
  if(!pad || !a.available) return 0;
  GstElement *elem=a.get_parent(pad);
  if(!elem) return 0;
  GstElementFactory *fact=a.get_factory(elem);
  /* GstPluginFeature name is a GstObject field, not an exported\n     gst_plugin_feature_get_name function. Avoid failed dlsym gates. */
  const gchar *name=fact ? GST_OBJECT_NAME(fact) : NULL;
  int match=name && (!strcmp(name,"aleksdts16dec") ||
                      (qa_mode && !strcmp(name,"dtsdec")));
  a.object_unref(elem);
  return match;
}
static int owned_by_audioconvert(GstPad *pad) {
  if(!pad || !a.available)return 0;
  GstElement *element=a.get_parent(pad);
  if(!element)return 0;
  GstElementFactory *factory=a.get_factory(element);
  const gchar *name=factory?GST_OBJECT_NAME(factory):NULL;
  int yes=name && !strcmp(name,"audioconvert");
  a.object_unref(element);
  return yes;
}
static int peer_is_decoder(GstPad *pad) {
  if(!pad) return 0;
  GstPad *peer=a.get_peer(pad);
  if(!peer) return 0;
  int result=owned_by_decoder(peer);
  a.object_unref(peer);
  return result;
}
static void record_input(GstBuffer *buffer) {
  if(!buffer) return;
  GstMapInfo m;
  if(!a.buffer_map(buffer,&m,GST_MAP_READ)) {
    pthread_mutex_lock(&mu);stats.bad_maps++;pthread_mutex_unlock(&mu);
    return;
  }
  const int sync=m.size>=4 && m.data[0]==0x7f && m.data[1]==0xfe &&
                 m.data[2]==0x80 && m.data[3]==0x01;
  const int no_pts=!GST_BUFFER_PTS_IS_VALID(buffer);
  a.buffer_unmap(buffer,&m);
  atomic_store_explicit(&last_dts_sec,mono_seconds(),memory_order_relaxed);
  pthread_mutex_lock(&mu);
  stats.input_buffers++;
  stats.be16_sync+=sync;
  stats.missing_pts+=no_pts;
  pthread_mutex_unlock(&mu);
}
/* Observe a GStreamer pad feeding the actual Realtek sink bin or its
   internal hardware sink. In QA only, fakesink is accepted as a stand-in.
   Absence from a captured snapshot does not prove the audio sink was absent:
   a vendor binary may bypass gst_pad_push PLT interposition. */
static int renderer_stage(GstPad *pad) {
  if(!pad || !a.available)return 0;
  GstPad *peer=a.get_peer(pad);
  if(!peer)return 0;
  GstElement *element=a.get_parent(peer);
  int stage=0;
  if(element) {
    GstElementFactory *factory=a.get_factory(element);
    const gchar *name=factory ? GST_OBJECT_NAME(factory) : NULL;
    if(name) {
      if(!strcmp(name,"rtkalsasink"))stage=1;
      else if(!strcmp(name,"rasink"))stage=2;
      else if(qa_mode && !strcmp(name,"fakesink"))stage=3;
    }
    a.object_unref(element);
  }
  a.object_unref(peer);
  return stage;
}
static void observe_renderer(int stage,GstPad *pad,GstBuffer *buffer) {
  if(stage<1 || stage>3 || !pad || !buffer)return;
  int kind=0,channels=0,rate=0;
  GstCaps *caps=a.current_caps(pad);
  if(caps) {
    if(a.caps_size(caps)==1) {
      const GstStructure *st=a.caps_structure(caps,0);
      const gchar *type=st ? a.structure_name(st) : NULL;
      if(type && !strcmp(type,"audio/x-raw")) {
        const gchar *format=a.structure_string(st,"format");
        const gchar *layout=a.structure_string(st,"layout");
        if(format && !strcmp(format,"S16LE") &&
           (!layout || !strcmp(layout,"interleaved"))) {
          a.structure_int(st,"channels",&channels);
          a.structure_int(st,"rate",&rate);
          if(channels>=1 && channels<=8 && rate>=8000 && rate<=192000)kind=1;
        }
      } else if(type && !strcmp(type,"audio/x-dts"))kind=2;
      else if(type && (!strcmp(type,"audio/x-ac3") ||
                       !strcmp(type,"audio/x-eac3")))kind=3;
    }
    a.mini_unref((GstMiniObject*)caps);
  }
  guint64 samples=0,nonzero=0;
  int dts_sync=0,ac3_sync=0;
  double squared=0,peak=0;
  int bad_map=0;
  if(kind) {
    GstMapInfo map;
    if(!a.buffer_map(buffer,&map,GST_MAP_READ))bad_map=1;
    else {
      if(kind==1 && map.size%2==0 && map.size<=262144) {
        guint n=(guint)(map.size/2);
        if(n>MAX_PCM_PER_BUFFER)n=MAX_PCM_PER_BUFFER;
        for(guint i=0;i<n;i++) {
          const guint8 *p=map.data+(size_t)i*2;
          const int16_t v=(int16_t)((uint16_t)p[0]|((uint16_t)p[1]<<8));
          const double val=(double)v/32768.0;
          const double ab=fabs(val);
          samples++;
          nonzero+=v!=0;
          squared+=val*val;
          if(ab>peak)peak=ab;
        }
      } else if(kind==2 && map.size>=4) {
        dts_sync=map.data[0]==0x7f && map.data[1]==0xfe &&
                 map.data[2]==0x80 && map.data[3]==0x01;
      } else if(kind==3 && map.size>=2) {
        ac3_sync=map.data[0]==0x0b && map.data[1]==0x77;
      }
      a.buffer_unmap(buffer,&map);
    }
  }
  pthread_mutex_lock(&mu);
  RendererStats *o=&renderer[stage];
  o->buffers++;
  if(kind==1 && o->pcm_samples<MAX_PCM_TOTAL) {
    o->pcm_buffers++;
    o->pcm_samples+=samples;
    o->pcm_nonzero+=nonzero;
    o->pcm_squared+=squared;
    if(peak>o->pcm_peak)o->pcm_peak=peak;
    o->channels=channels;
    o->rate=rate;
  } else if(kind==2) {
    o->encoded_dts++;
    o->dts_be16_sync+=dts_sync;
  } else if(kind==3) {
    o->encoded_ac3++;
    o->ac3_sync+=ac3_sync;
  } else o->other_caps++;
  o->bad_maps+=bad_map;
  pthread_mutex_unlock(&mu);
}
static void observe_renderer_event(int stage,GstEvent *event) {
  if(stage<1 || stage>3 || !event)return;
  pthread_mutex_lock(&mu);
  RendererStats *o=&renderer[stage];
  switch(GST_EVENT_TYPE(event)) {
    case GST_EVENT_STREAM_START:o->event_stream_start++;break;
    case GST_EVENT_CAPS:o->event_caps++;break;
    case GST_EVENT_SEGMENT:{
      const GstSegment *segment=NULL;
      a.parse_segment(event,&segment);
      if(segment && segment->format==GST_FORMAT_TIME)o->event_segment_time++;
      else o->event_segment_other++;
      break;
    }
    case GST_EVENT_FLUSH_START:
    case GST_EVENT_FLUSH_STOP:o->event_flush++;break;
    default:break;
  }
  pthread_mutex_unlock(&mu);
}
static void record_pcm(GstPad *pad,GstBuffer *buffer,int from_converter) {
  if(!pad || !buffer) return;
  GstCaps *caps=a.current_caps(pad);
  if(!caps) return;
  int kind=0,channels=0,rate=0;
  if(a.caps_size(caps)==1) {
    const GstStructure *st=a.caps_structure(caps,0);
    if(st && a.structure_name(st) &&
       !strcmp(a.structure_name(st),"audio/x-raw")) {
      const gchar *fmt=a.structure_string(st,"format");
      const gchar *layout=a.structure_string(st,"layout");
      if(fmt && !strcmp(fmt,"S16LE"))kind=1;
      if(fmt && !strcmp(fmt,"S32LE"))kind=2;
      if(fmt && !strcmp(fmt,"F32LE"))kind=3;
      a.structure_int(st,"channels",&channels);
      a.structure_int(st,"rate",&rate);
      if((layout && strcmp(layout,"interleaved")) ||
         channels<1 || channels>8 || rate<8000 || rate>192000)kind=0;
    }
  }
  a.mini_unref((GstMiniObject*)caps);
  if(!kind)return;
  GstMapInfo m;
  if(!a.buffer_map(buffer,&m,GST_MAP_READ)) {
    pthread_mutex_lock(&mu);stats.bad_maps++;pthread_mutex_unlock(&mu);
    return;
  }
  guint stride=kind==1?2:4;
  if(m.size%stride || m.size>262144) {
    a.buffer_unmap(buffer,&m);
    pthread_mutex_lock(&mu);stats.ignored_pcm++;pthread_mutex_unlock(&mu);
    return;
  }
  guint n=(guint)(m.size/stride);
  if(n>MAX_PCM_PER_BUFFER)n=MAX_PCM_PER_BUFFER;
  uint64_t nz=0,clip=0;
  double sq=0,peak=0;
  for(guint i=0;i<n;i++) {
    const guint8 *p=m.data+(size_t)i*stride;
    double value=0;
    if(kind==1) {
      int16_t v=(int16_t)((uint16_t)p[0]|((uint16_t)p[1]<<8));
      value=(double)v/32768.0;
    } else if(kind==2) {
      int32_t v=(int32_t)((uint32_t)p[0]|((uint32_t)p[1]<<8)|
                          ((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24));
      value=(double)v/2147483648.0;
    } else {
      float v;
      memcpy(&v,p,sizeof(v));
      if(!isfinite(v))continue;
      value=v;
    }
    nz+=value!=0;
    double mag=fabs(value);
    clip+=mag>1.0;
    if(mag>peak)peak=mag;
    sq+=value*value;
  }
  a.buffer_unmap(buffer,&m);
  pthread_mutex_lock(&mu);
  if(stats.pcm_samples < MAX_PCM_TOTAL) {
    stats.pcm_buffers++;
    stats.pcm_wrapper_buffers+=from_converter==0;
    stats.pcm_converter_buffers+=from_converter!=0;
    stats.pcm_samples+=n;
    stats.pcm_nonzero+=nz;
    stats.clipped+=clip;
    stats.squared+=sq;
    if(peak>stats.peak)stats.peak=peak;
    stats.pcm_rate=rate;
    stats.pcm_channels=channels;
    stats.s16_buffers+=kind==1;
    stats.s32_buffers+=kind==2;
    stats.f32_buffers+=kind==3;
  }
  pthread_mutex_unlock(&mu);
}
static void record_event(GstEvent *event) {
  if(!event)return;
  if(GST_EVENT_TYPE(event)==GST_EVENT_STREAM_START) {
    /* A newly started DTS stream may use a different downstream convert pad.
       Clear only the pad selector, not aggregate telemetry. */
    atomic_store_explicit(&selected_converter_pad,(uintptr_t)0,memory_order_relaxed);
    atomic_store_explicit(&selected_converter_seen,0,memory_order_relaxed);
  }
  pthread_mutex_lock(&mu);
  switch(GST_EVENT_TYPE(event)) {
    case GST_EVENT_STREAM_START:stats.event_start++;break;
    case GST_EVENT_CAPS:stats.event_caps++;break;
    case GST_EVENT_SEGMENT: {
      const GstSegment *seg=NULL;
      a.parse_segment(event,&seg);
      if(seg && seg->format==GST_FORMAT_TIME)stats.event_time++;
      else stats.event_bytes++;
      break;
    }
    default: break;
  }
  pthread_mutex_unlock(&mu);
}
static void save_snapshot(unsigned elapsed) {
  char json[2800];
  pthread_mutex_lock(&mu);
  double rms=stats.pcm_samples && stats.squared>0 ?
             10*log10(stats.squared/(double)stats.pcm_samples) : -999.0;
  double peak=stats.peak>0 ? 20*log10(stats.peak) : -999.0;
  int count=snprintf(json,sizeof(json),
    "{\"schema\":\"aleks-dts-r338-interpose-v1\",\"elapsed_s\":%u,"
    "\"input_buffers\":%llu,\"be16_sync\":%llu,\"missing_pts\":%llu,"
    "\"event_start\":%llu,\"event_caps\":%llu,\"event_time\":%llu,"
    "\"event_bytes\":%llu,\"pcm_buffers\":%llu,\"pcm_sampled\":%llu,"
    "\"pcm_nonzero\":%llu,\"pcm_rms_dbfs\":%.2f,\"pcm_peak_dbfs\":%.2f,"
    "\"pcm_channels\":%d,\"pcm_rate\":%d,"
    "\"pcm_wrapper_buffers\":%llu,\"pcm_converter_buffers\":%llu,"
    "\"format_s16_buffers\":%llu,\"format_s32_buffers\":%llu,"
    "\"format_f32_buffers\":%llu,\"bad_maps\":%llu,"
    "\"ignored_pcm\":%llu,\"clipped\":%llu,"
    "\"raw_pcm_exported\":false,\"audio_files_created\":0,"
    "\"pipeline_mutated\":false,\"external_process_attached\":false,",
    elapsed,(unsigned long long)stats.input_buffers,
    (unsigned long long)stats.be16_sync,
    (unsigned long long)stats.missing_pts,
    (unsigned long long)stats.event_start,
    (unsigned long long)stats.event_caps,
    (unsigned long long)stats.event_time,
    (unsigned long long)stats.event_bytes,
    (unsigned long long)stats.pcm_buffers,
    (unsigned long long)stats.pcm_samples,
    (unsigned long long)stats.pcm_nonzero,rms,peak,
    stats.pcm_channels,stats.pcm_rate,
    (unsigned long long)stats.pcm_wrapper_buffers,
    (unsigned long long)stats.pcm_converter_buffers,
    (unsigned long long)stats.s16_buffers,
    (unsigned long long)stats.s32_buffers,
    (unsigned long long)stats.f32_buffers,
    (unsigned long long)stats.bad_maps,
    (unsigned long long)stats.ignored_pcm,
    (unsigned long long)stats.clipped);
  /* There are exactly three fixed factory categories, never actual element
     names, filenames or media caps strings. Keep each stage separate. */
  const char *kinds[4]={"","rtkalsasink","rasink","qa_fakesink"};
  for(int i=1;i<=3;i++) {
    if(count<=0 || count>=(int)sizeof(json))break;
    RendererStats *v=&renderer[i];
    const double rms=v->pcm_samples && v->pcm_squared>0 ?
         10*log10(v->pcm_squared/(double)v->pcm_samples) : -999.0;
    const double pk=v->pcm_peak>0 ? 20*log10(v->pcm_peak) : -999.0;
    const int written=snprintf(json+count,sizeof(json)-(size_t)count,
      "\"renderer_%s\":{\"buffers\":%llu,\"pcm_buffers\":%llu,"
      "\"pcm_samples\":%llu,\"pcm_nonzero\":%llu,\"rms_dbfs\":%.2f,"
      "\"peak_dbfs\":%.2f,\"channels\":%d,\"rate\":%d,"
      "\"dts_buffers\":%llu,\"dts_be16_sync\":%llu,"
      "\"ac3_buffers\":%llu,\"ac3_sync\":%llu,\"other_caps\":%llu,"
      "\"stream_start\":%llu,\"caps_events\":%llu,\"segment_time\":%llu,"
      "\"segment_other\":%llu,\"flush_events\":%llu,\"bad_maps\":%llu},",
      kinds[i],(unsigned long long)v->buffers,
      (unsigned long long)v->pcm_buffers,
      (unsigned long long)v->pcm_samples,
      (unsigned long long)v->pcm_nonzero,rms,pk,v->channels,v->rate,
      (unsigned long long)v->encoded_dts,
      (unsigned long long)v->dts_be16_sync,
      (unsigned long long)v->encoded_ac3,
      (unsigned long long)v->ac3_sync,
      (unsigned long long)v->other_caps,
      (unsigned long long)v->event_stream_start,
      (unsigned long long)v->event_caps,
      (unsigned long long)v->event_segment_time,
      (unsigned long long)v->event_segment_other,
      (unsigned long long)v->event_flush,
      (unsigned long long)v->bad_maps);
    if(written<0 || written>=(int)(sizeof(json)-(size_t)count)) {
      count=(int)sizeof(json);
      break;
    }
    count+=written;
  }
  if(count>0 && count<(int)sizeof(json)) {
    const int extra=snprintf(json+count,sizeof(json)-(size_t)count,
      "\"renderer_scope\":\"ALL_SINK_STREAMS_IN_PROCESS_NOT_DTS_EXCLUSIVE\","
      "\"raw_media_exported\":false}\n");
    if(extra>=0 && extra<(int)(sizeof(json)-(size_t)count))count+=extra;
    else count=(int)sizeof(json);
  }
  pthread_mutex_unlock(&mu);
  if(count<=0 || count>=(int)sizeof(json))return;
  char tmp[240];
  snprintf(tmp,sizeof(tmp),"%s.tmp",output_path);
  pthread_mutex_lock(&io_mu);
  int fd=open(tmp,O_CREAT|O_TRUNC|O_WRONLY|O_CLOEXEC|O_NOFOLLOW,0600);
  if(fd<0) {
    pthread_mutex_unlock(&io_mu);
    return;
  }
  ssize_t wrote=write(fd,json,count);
  close(fd);
  if(wrote!=count)unlink(tmp);
  else if(rename(tmp,output_path))unlink(tmp);
  pthread_mutex_unlock(&io_mu);
}
static void *writer_thread(void *unused) {
  (void)unused;
  unsigned elapsed=0;
  while(elapsed<R338_WINDOW_SECS && atomic_load(&enabled)) {
    struct timespec delay={2,0};
    nanosleep(&delay,NULL);
    elapsed+=2;
    if(elapsed>=R338_WINDOW_SECS)atomic_store(&enabled,0);
    save_snapshot(elapsed);
  }
  atomic_store(&enabled,0);
  save_snapshot(elapsed);
  return NULL;
}
__attribute__((constructor))
static void start_shim(void) {
  const char *permit=getenv("ALEKS_R338_ENABLE");
  if(!permit || strcmp(permit,"YES"))return;
  qa_mode=getenv("ALEKS_R338_ISOLATED_QA") &&
           !strcmp(getenv("ALEKS_R338_ISOLATED_QA"),"YES");
  if(!qa_mode) {
    char comm[80]={0};
    FILE *f=fopen("/proc/self/comm","r");
    if(f) {if(!fgets(comm,sizeof(comm),f))comm[0]=0;fclose(f);}
    if(strncmp(comm,"starfish-media-",15))return;
  }
  const char *dir=qa_mode?getenv("ALEKS_R338_QA_DIR"):"/run/aleks-r338/metrics";
  if(!dir)return;
  if(qa_mode && (strncmp(dir,"/tmp/aleks-r338-",16) || strstr(dir,"..") || strlen(dir)>125))
    return;
  if(!qa_mode && strcmp(dir,"/run/aleks-r338/metrics"))return;
  struct stat st;
  if(stat(dir,&st)!=0 || !S_ISDIR(st.st_mode) || (st.st_mode&0077))return;
  snprintf(output_path,sizeof(output_path),"%s/r338-%ld.json",dir,(long)getpid());
  started_at=mono_seconds();
  atomic_store(&enabled,1);
  pthread_t thread;
  if(pthread_create(&thread,NULL,writer_thread,NULL)==0) {
    pthread_detach(thread);
  } else atomic_store(&enabled,0);
}
__attribute__((destructor))
static void stop_shim(void) {
  if(!output_path[0])return;
  atomic_store(&enabled,0);
  save_snapshot((unsigned)(mono_seconds()-started_at));
}

GstFlowReturn gst_pad_push(GstPad *pad,GstBuffer *buffer) {
  pthread_once(&resolve_once,resolve);
  if(!a.push)return GST_FLOW_ERROR;
  if(a.available && active()) {
    if(peer_is_decoder(pad))record_input(buffer);
    int stage=renderer_stage(pad);
    if(stage)observe_renderer(stage,pad,buffer);
    if(owned_by_decoder(pad))record_pcm(pad,buffer,0);
    else if(owned_by_audioconvert(pad)) {
      /* Heuristic fallback only: vendor bin ghost-src push may bypass PLT.
         Require an actual decoder input within the last 5 seconds; label
         such PCM as converter-associated, not certified decoder output. */
      unsigned long last=atomic_load_explicit(&last_dts_sec,memory_order_relaxed);
      if(last && mono_seconds()-last<=5) {
        pthread_mutex_lock(&mu);
        int direct=stats.pcm_wrapper_buffers>0;
        pthread_mutex_unlock(&mu);
        if(!direct) {
          /* LG exposes several sequential audioconvert pads; count only one
             per DTS stream to avoid double RMS/sample accounting. */
          const unsigned long now=mono_seconds();
          uintptr_t chosen=atomic_load_explicit(&selected_converter_pad,memory_order_relaxed);
          const unsigned long seen=atomic_load_explicit(&selected_converter_seen,memory_order_relaxed);
          if(chosen && seen && now-seen>5) {
            uintptr_t expected=chosen;
            atomic_compare_exchange_strong(&selected_converter_pad,&expected,(uintptr_t)0);
          }
          uintptr_t empty=(uintptr_t)0;
          atomic_compare_exchange_strong(&selected_converter_pad,&empty,(uintptr_t)pad);
          if(atomic_load_explicit(&selected_converter_pad,memory_order_relaxed)==(uintptr_t)pad) {
            record_pcm(pad,buffer,1);
            atomic_store_explicit(&selected_converter_seen,now,memory_order_relaxed);
          }
        }
      }
    }
  }
  return a.push(pad,buffer);
}
gboolean gst_pad_push_event(GstPad *pad,GstEvent *event) {
  pthread_once(&resolve_once,resolve);
  if(!a.push_event)return FALSE;
  if(a.available && active()) {
    if(peer_is_decoder(pad))record_event(event);
    int stage=renderer_stage(pad);
    if(stage)observe_renderer_event(stage,event);
  }
  return a.push_event(pad,event);
}
