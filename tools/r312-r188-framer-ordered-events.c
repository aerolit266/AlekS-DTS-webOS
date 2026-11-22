/*
 * AlekS DTS R188 GStreamer1.16.2 bounded Core frame assembler (LAB ONLY).
 * Element: aleksdtsr188framer. NOT a decoder. Rank NONE.
 * Encoded bytes are emitted unchanged as complete DTS Core BE16 frames.
 * Fail-closed on invalid sync/header, overflow, incomplete EOS or downstream
 * rejection. No arbitrary resync, lossy queues or program-wide overrides.
 * R312 experimental change: delay source SEGMENT until after actual output
 * CAPS, preventing sticky event order faults at the first DTS frame.
 * Rest of original R188 is byte-preserved apart from changes shown.
 * SPDX-License-Identifier: MIT. Copyright 2026 AlekS/GameFree24.
 */
#include <gst/gst.h>
#include <gst/gstplugin.h>
#include <string.h>
#include "r188_dts_framer.h"
#ifndef PACKAGE
#define PACKAGE "aleks-dts"
#endif
typedef struct {
 GstElement parent;
 GstPad *sink;
 GstPad *src;
 aleks_r188_framer framer;
 gboolean caps_known;
 guint last_channels,last_rate;
 GstFlowReturn downstream_result;
 GstEvent *pending_segment; /* R312 lab: hold SEGMENT until first source CAPS */
} AlekSDtsR188Framer;
typedef struct { GstElementClass parent_class; } AlekSDtsR188FramerClass;
G_DEFINE_TYPE(AlekSDtsR188Framer,aleks_dts_r188_framer,GST_TYPE_ELEMENT)

static GstStaticPadTemplate sink_tpl=
 GST_STATIC_PAD_TEMPLATE("sink",GST_PAD_SINK,GST_PAD_ALWAYS,
                         GST_STATIC_CAPS("audio/x-dts"));
static GstStaticPadTemplate src_tpl=
 GST_STATIC_PAD_TEMPLATE("src",GST_PAD_SRC,GST_PAD_ALWAYS,
                         GST_STATIC_CAPS("audio/x-dts"));

static int deliver_frame(void *context,const uint8_t *data,size_t size,
                        uint64_t pts_us,uint64_t duration_us,
                        uint32_t rate,uint32_t channels) {
 AlekSDtsR188Framer *self=(AlekSDtsR188Framer *)context;
 if(!self->caps_known || self->last_channels!=channels ||
    self->last_rate!=rate) {
    GstCaps *caps=gst_caps_new_simple("audio/x-dts",
       "channels",G_TYPE_INT,(gint)channels,
       "rate",G_TYPE_INT,(gint)rate,NULL);
    gboolean ok=gst_pad_set_caps(self->src,caps);
    gst_caps_unref(caps);
    if(!ok) {
        self->downstream_result=GST_FLOW_NOT_NEGOTIATED;
        return -1;
    }
    self->caps_known=TRUE;
    self->last_channels=channels;self->last_rate=rate;
 }
 /* Guarantee stream-start -> CAPS -> SEGMENT -> first encoded buffer.
    The upstream raw filesrc normally sends SEGMENT before a DTS header
    becomes available. R188 forwarded it early (GStreamer sticky warning).
    Do not change the compressed bytes or timestamps. */
 if(self->pending_segment) {
    GstEvent *segment=self->pending_segment;
    self->pending_segment=NULL;
    if(!gst_pad_push_event(self->src,segment)) {
       self->downstream_result=GST_FLOW_NOT_NEGOTIATED;
       return -1;
    }
 }
 if((pts_us!=R188_NO_PTS && pts_us>((UINT64_MAX-1ull)/1000ull)) ||
    duration_us>((UINT64_MAX-1ull)/1000ull)) {
    self->downstream_result=GST_FLOW_ERROR;
    return -1;
 }
 GstBuffer *out=gst_buffer_new_allocate(NULL,size,NULL);
 if(!out) {
    self->downstream_result=GST_FLOW_ERROR;
    return -1;
 }
 gst_buffer_fill(out,0,data,size);
 if(pts_us!=R188_NO_PTS) {
    GST_BUFFER_PTS(out)=pts_us*1000ull;
    GST_BUFFER_DTS(out)=GST_CLOCK_TIME_NONE;
 } else {
    GST_BUFFER_PTS(out)=GST_CLOCK_TIME_NONE;
    GST_BUFFER_DTS(out)=GST_CLOCK_TIME_NONE;
 }
 GST_BUFFER_DURATION(out)=duration_us*1000ull;
 self->downstream_result=gst_pad_push(self->src,out);
 return self->downstream_result==GST_FLOW_OK?0:-1;
}
static GstFlowReturn on_chain(GstPad *pad,GstObject *parent,GstBuffer *buffer){
 (void)pad;
 AlekSDtsR188Framer *self=(AlekSDtsR188Framer *)parent;
 GstMapInfo map={0};
 if(!gst_buffer_map(buffer,&map,GST_MAP_READ)){
    gst_buffer_unref(buffer);
    return GST_FLOW_ERROR;
 }
 uint64_t pts=GST_CLOCK_TIME_IS_VALID(GST_BUFFER_PTS(buffer))
    ?(GST_BUFFER_PTS(buffer)/1000ull):R188_NO_PTS;
 self->downstream_result=GST_FLOW_OK;
 int result=aleks_r188_feed(&self->framer,map.data,map.size,
                           pts,deliver_frame,self);
 gst_buffer_unmap(buffer,&map);
 gst_buffer_unref(buffer);
 if(result==0)return GST_FLOW_OK;
 if(result==-6 && self->downstream_result!=GST_FLOW_OK)
    return self->downstream_result;
 GST_ELEMENT_ERROR(self,STREAM,DECODE,
    ("R188 invalid or unframeable DTS Core buffer"),
    ("framer_error_code=%d",result));
 return GST_FLOW_ERROR;
}
static gboolean on_event(GstPad *pad,GstObject *parent,GstEvent *event){
 (void)pad;
 AlekSDtsR188Framer *self=(AlekSDtsR188Framer *)parent;
 switch(GST_EVENT_TYPE(event)){
  case GST_EVENT_STREAM_START:
  case GST_EVENT_FLUSH_STOP:
   if(self->pending_segment) {
      gst_event_unref(self->pending_segment);
      self->pending_segment=NULL;
   }
   aleks_r188_reset(&self->framer);
   self->caps_known=FALSE;
   self->last_rate=self->last_channels=0;
   break;
  case GST_EVENT_SEGMENT:
   if(!self->caps_known) {
      /* A segment may be sent before enough compressed bytes arrive
         to determine the actual output rate and channel count. */
      if(self->pending_segment)gst_event_unref(self->pending_segment);
      self->pending_segment=event; /* ownership moves to this element */
      return TRUE;
   }
   break;
  case GST_EVENT_EOS:
   if(self->framer.have || self->framer.terminal_error) {
      GST_ELEMENT_ERROR(self,STREAM,DECODE,
          ("R188 incomplete DTS Core frame at EOS"),
          ("unconsumed_bytes=%lu",(unsigned long)self->framer.have));
      gst_event_unref(event);
      return FALSE;
   }
   break;
  default:break;
 }
 return gst_pad_push_event(self->src,event);
}
static void aleks_dts_r188_framer_finalize(GObject *object) {
 AlekSDtsR188Framer *self=(AlekSDtsR188Framer *)object;
 if(self->pending_segment) {
    gst_event_unref(self->pending_segment);
    self->pending_segment=NULL;
 }
 G_OBJECT_CLASS(aleks_dts_r188_framer_parent_class)->finalize(object);
}
static void aleks_dts_r188_framer_class_init(AlekSDtsR188FramerClass *klass){
 G_OBJECT_CLASS(klass)->finalize=aleks_dts_r188_framer_finalize;
 GstElementClass *element=GST_ELEMENT_CLASS(klass);
 gst_element_class_add_static_pad_template(element,&sink_tpl);
 gst_element_class_add_static_pad_template(element,&src_tpl);
 gst_element_class_set_static_metadata(element,
  "AlekS bounded DTS Core BE16 frame assembler R188", "Codec/Parser/Audio",
  "Reconstructs complete DTS encoded frames from bounded packet fragments",
  "AlekS/GameFree24");
}
static void aleks_dts_r188_framer_init(AlekSDtsR188Framer *self){
 self->sink=gst_pad_new_from_static_template(&sink_tpl,"sink");
 self->src=gst_pad_new_from_static_template(&src_tpl,"src");
 gst_pad_set_chain_function(self->sink, GST_DEBUG_FUNCPTR(on_chain));
 gst_pad_set_event_function(self->sink, GST_DEBUG_FUNCPTR(on_event));
 gst_element_add_pad(GST_ELEMENT(self),self->sink);
 gst_element_add_pad(GST_ELEMENT(self),self->src);
 aleks_r188_reset(&self->framer);
 self->caps_known=FALSE;
 self->last_rate=self->last_channels=0;
 self->downstream_result=GST_FLOW_OK;
 self->pending_segment=NULL;
}
static gboolean plugin_init(GstPlugin *plugin){
 return gst_element_register(plugin,"aleksdtsr188framer",
                             GST_RANK_NONE,aleks_dts_r188_framer_get_type());
}
GST_PLUGIN_DEFINE(GST_VERSION_MAJOR,GST_VERSION_MINOR,aleksdtsr188framer,
 "AlekS DTS bounded frame assembler R188 - isolated experiment",
 plugin_init,"0.1.0-r312-lab","LGPL","AlekS DTS",
 "https://github.com/aerolit266/AlekS-LG-65NANO896PC")