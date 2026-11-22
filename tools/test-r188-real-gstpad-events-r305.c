/*
 * R305 genuine GStreamer GstPad dispatch regression, isolated LAB ONLY.
 * Uses stock R188 GStreamer plugin and R304 synthetic header test double.
 * Actual GstEvents STREAM_START, FLUSH_START/STOP, EOS are delivered through
 * linked pads. No real DTS decoding, no audio sink, no television, no uMS.
 * SPDX-License-Identifier: MIT
 */
#include <gst/gst.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#define R305_REQUIRE(c, name) do { if(!(c)){ \
    fprintf(stderr,"R305_FAIL line=%d test=%s\n",__LINE__,name);exit(1);} \
}while(0)
typedef struct {
    GstElement *framer;
    GstPad *up,*down,*src,*sink;
    guint received, starts, flush_starts, flush_stops, eos, caps, metadata_caps;
    guint rate,channels;
    gsize consumed, expected_len;
    const guint8 *expected;
    GstClockTime first_pts;
    gboolean failed;
} Rig;
static guint passed;

static void bits(guint8 *buf,guint start,guint width,guint value) {
    for(guint i=0;i<width;i++) {
        guint b=start+i;
        guint8 mask=(guint8)(1u<<(7u-b%8u));
        if((value>>(width-i-1u))&1u)buf[b/8u]|=mask;
        else buf[b/8u]&=(guint8)~mask;
    }
}
static void mkframe(guint8 *out,gsize n,guint ch,guint rate,guint samples) {
    R305_REQUIRE(n>=96 && n<=16384,"frame_bound");
    memset(out,0xa5,n);
    out[0]=0x7f;out[1]=0xfe;out[2]=0x80;out[3]=0x01;
    bits(out,32,1,1);
    bits(out,33,5,0);
    bits(out,38,1,0);
    bits(out,39,7,samples/32u-1u);
    bits(out,46,14,(guint)n-1u);
    bits(out,60,6,ch==2?2:9);
    bits(out,66,4,rate==48000?13:8);
}
static GstFlowReturn receive(GstPad *pad,GstObject *parent,GstBuffer *buffer) {
    (void)parent;
    Rig *r=g_object_get_data(G_OBJECT(pad),"rig");
    GstMapInfo map={0};
    if(!gst_buffer_map(buffer,&map,GST_MAP_READ)){
        r->failed=TRUE;
    }else {
        if(!r->expected || r->consumed+map.size>r->expected_len ||
           memcmp(r->expected+r->consumed,map.data,map.size)!=0 ||
           !GST_CLOCK_TIME_IS_VALID(GST_BUFFER_DURATION(buffer)) ||
           GST_BUFFER_DURATION(buffer)==0)
            r->failed=TRUE;
        if(r->received==0 && GST_BUFFER_PTS(buffer)!=r->first_pts)
            r->failed=TRUE;
        r->consumed+=map.size;
        r->received++;
        gst_buffer_unmap(buffer,&map);
    }
    gst_buffer_unref(buffer);
    return r->failed?GST_FLOW_ERROR:GST_FLOW_OK;
}
static gboolean event_sink(GstPad *pad,GstObject *parent,GstEvent *event) {
    (void)parent;
    Rig *r=g_object_get_data(G_OBJECT(pad),"rig");
    switch(GST_EVENT_TYPE(event)){
        case GST_EVENT_STREAM_START:r->starts++;break;
        case GST_EVENT_FLUSH_START:r->flush_starts++;break;
        case GST_EVENT_FLUSH_STOP:r->flush_stops++;break;
        case GST_EVENT_EOS:r->eos++;break;
        case GST_EVENT_CAPS:{
            r->caps++;
            GstCaps *caps=NULL;
            gst_event_parse_caps(event,&caps);
            if(caps && gst_caps_get_size(caps)>0) {
                GstStructure *st=gst_caps_get_structure(caps,0);
                gint rate=0,ch=0;
                if(gst_structure_get_int(st,"rate",&rate) &&
                   gst_structure_get_int(st,"channels",&ch)){
                    r->metadata_caps++;
                    r->rate=(guint)rate;r->channels=(guint)ch;
                }
            }
            break;
        }
        default:break;
    }
    gst_event_unref(event);
    return TRUE;
}
static Rig create_rig(void) {
    Rig r={0};
    r.framer=gst_element_factory_make("aleksdtsr188framer",NULL);
    R305_REQUIRE(r.framer!=NULL,"factory");
    r.sink=gst_element_get_static_pad(r.framer,"sink");
    r.src=gst_element_get_static_pad(r.framer,"src");
    r.up=gst_pad_new("r305-up",GST_PAD_SRC);
    r.down=gst_pad_new("r305-down",GST_PAD_SINK);
    R305_REQUIRE(r.sink&&r.src&&r.up&&r.down,"pads");
    /* rig pointer is rebound to caller's stable address below */
    return r;
}
static void start_rig(Rig *r) {
    gst_pad_set_chain_function(r->down,GST_DEBUG_FUNCPTR(receive));
    gst_pad_set_event_function(r->down,GST_DEBUG_FUNCPTR(event_sink));
    g_object_set_data(G_OBJECT(r->down),"rig",r);
    R305_REQUIRE(gst_pad_link(r->up,r->sink)==GST_PAD_LINK_OK,"link_up");
    R305_REQUIRE(gst_pad_link(r->src,r->down)==GST_PAD_LINK_OK,"link_down");
    R305_REQUIRE(gst_pad_set_active(r->up,TRUE),"activate_up");
    R305_REQUIRE(gst_pad_set_active(r->down,TRUE),"activate_down");
    /* Element pads activate on PAUSED; no clocked rendering takes place. */
    GstStateChangeReturn state=gst_element_set_state(r->framer,GST_STATE_PAUSED);
    R305_REQUIRE(state!=GST_STATE_CHANGE_FAILURE,"element_paused");
}
static void destroy_rig(Rig *r) {
    gst_element_set_state(r->framer,GST_STATE_NULL);
    gst_pad_set_active(r->up,FALSE);
    gst_pad_set_active(r->down,FALSE);
    gst_pad_unlink(r->up,r->sink);
    gst_pad_unlink(r->src,r->down);
    gst_object_unref(r->sink);
    gst_object_unref(r->src);
    gst_object_unref(r->up);
    gst_object_unref(r->down);
    gst_object_unref(r->framer);
}
static gboolean send_start(Rig *r,const char *id) {
    GstCaps *caps=gst_caps_new_empty_simple("audio/x-dts");
    gboolean a=gst_pad_push_event(r->up,gst_event_new_stream_start(id));
    gboolean b=gst_pad_push_event(r->up,gst_event_new_caps(caps));
    GstSegment seg;
    gst_segment_init(&seg,GST_FORMAT_TIME);
    gboolean c=gst_pad_push_event(r->up,gst_event_new_segment(&seg));
    gst_caps_unref(caps);
    return a&&b&&c;
}
static GstFlowReturn sendbytes(Rig *r,const guint8 *buf,gsize size,
                               GstClockTime pts) {
    GstBuffer *b=gst_buffer_new_allocate(NULL,size,NULL);
    R305_REQUIRE(b!=NULL,"buffer_alloc");
    gst_buffer_fill(b,0,buf,size);
    GST_BUFFER_PTS(b)=pts;
    return gst_pad_push(r->up,b);
}
static void check_case(const char *name) {
    passed++;
    g_print("R305_%s_PASS\n",name);
}
static void test_full(void) {
    Rig r=create_rig();start_rig(&r);
    guint8 frame[1024];mkframe(frame,sizeof(frame),2,48000,512);
    r.expected=frame;r.expected_len=sizeof(frame);r.first_pts=1000000000ull;
    R305_REQUIRE(send_start(&r,"r305-full"),"start_full");
    /* Fragmented frame, with PTS only on initial source buffer. */
    for(gsize i=0;i<sizeof(frame);i++)
        R305_REQUIRE(sendbytes(&r,frame+i,1,i==0?r.first_pts:GST_CLOCK_TIME_NONE)==GST_FLOW_OK,"fragmented_push");
    R305_REQUIRE(gst_pad_push_event(r.up,gst_event_new_eos()),"eos_full");
    R305_REQUIRE(r.received==1&&r.consumed==1024&&!r.failed,"full_frame");
    R305_REQUIRE(r.starts==1&&r.eos==1&&r.caps>=1,"events_full");
    R305_REQUIRE(r.metadata_caps>=1&&r.rate==48000&&r.channels==2,"metadata_full");
    destroy_rig(&r);check_case("FRAGMENTED_FIRST_FRAME_REAL_EOS");
}
static void test_flush(void) {
    Rig r=create_rig();start_rig(&r);
    guint8 frame[1024];mkframe(frame,sizeof(frame),2,48000,512);
    r.expected=frame;r.expected_len=sizeof(frame);r.first_pts=2500000000ull;
    R305_REQUIRE(send_start(&r,"r305-old"),"start_old");
    R305_REQUIRE(sendbytes(&r,frame,13,100000000ull)==GST_FLOW_OK,"partial13");
    R305_REQUIRE(r.received==0,"partial_not_emitted");
    R305_REQUIRE(gst_pad_push_event(r.up,gst_event_new_flush_start()),"flush_start");
    R305_REQUIRE(gst_pad_push_event(r.up,gst_event_new_flush_stop(TRUE)),"flush_stop");
    R305_REQUIRE(send_start(&r,"r305-after-flush"),"new_after_flush");
    R305_REQUIRE(sendbytes(&r,frame,sizeof(frame),r.first_pts)==GST_FLOW_OK,"fresh_frame");
    R305_REQUIRE(gst_pad_push_event(r.up,gst_event_new_eos()),"eos_flush");
    R305_REQUIRE(r.received==1&&r.consumed==1024&&!r.failed,"flush_reset");
    R305_REQUIRE(r.flush_starts>=1&&r.flush_stops>=1&&r.starts>=2&&r.eos==1,"flush_events");
    destroy_rig(&r);check_case("FLUSH_STOP_CLEARS_SPLIT_HEADER");
}
static void test_stream_restart(void) {
    Rig r=create_rig();start_rig(&r);
    guint8 frame[1024];mkframe(frame,sizeof(frame),2,48000,512);
    r.expected=frame;r.expected_len=sizeof(frame);r.first_pts=500000000ull;
    R305_REQUIRE(send_start(&r,"r305-stream-A"),"stream_a");
    R305_REQUIRE(sendbytes(&r,frame,37,100000000ull)==GST_FLOW_OK,"split37");
    R305_REQUIRE(send_start(&r,"r305-stream-B"),"stream_b");
    R305_REQUIRE(sendbytes(&r,frame,sizeof(frame),r.first_pts)==GST_FLOW_OK,"stream_b_full");
    R305_REQUIRE(gst_pad_push_event(r.up,gst_event_new_eos()),"eos_stream_B");
    R305_REQUIRE(r.received==1&&r.starts>=2&&r.eos==1&&!r.failed,"stream_start_reset");
    destroy_rig(&r);check_case("STREAM_START_CLEARS_SPLIT_FRAME");
}
static void test_reject_eos(void) {
    Rig r=create_rig();start_rig(&r);
    guint8 frame[1024];mkframe(frame,sizeof(frame),2,48000,512);
    R305_REQUIRE(send_start(&r,"r305-incomplete"),"start_incomplete");
    R305_REQUIRE(sendbytes(&r,frame,71,100000000ull)==GST_FLOW_OK,"partial71");
    gboolean accepted=gst_pad_push_event(r.up,gst_event_new_eos());
    R305_REQUIRE(!accepted&&r.received==0&&r.eos==0,"reject_partial_eos");
    destroy_rig(&r);check_case("EOS_REJECTS_INCOMPLETE_FRAME");
}
static void test_replay_after_eos(void) {
    Rig r=create_rig();start_rig(&r);
    guint8 frame[1024];mkframe(frame,sizeof(frame),2,48000,512);
    r.expected=frame;r.expected_len=sizeof(frame);r.first_pts=100000000ull;
    R305_REQUIRE(send_start(&r,"r305-first"),"start_first");
    R305_REQUIRE(sendbytes(&r,frame,sizeof(frame),r.first_pts)==GST_FLOW_OK,"first");
    R305_REQUIRE(gst_pad_push_event(r.up,gst_event_new_eos()),"eos_first");
    R305_REQUIRE(r.received==1&&r.eos==1,"first_done");
    R305_REQUIRE(gst_pad_push_event(r.up,gst_event_new_flush_start()),"replay_flush_start");
    R305_REQUIRE(gst_pad_push_event(r.up,gst_event_new_flush_stop(TRUE)),"replay_flush_stop");
    R305_REQUIRE(send_start(&r,"r305-second"),"start_second");
    r.expected=frame;r.expected_len=sizeof(frame);r.consumed=0;
    r.received=0;r.first_pts=200000000ull;
    R305_REQUIRE(sendbytes(&r,frame,sizeof(frame),r.first_pts)==GST_FLOW_OK,"second");
    R305_REQUIRE(gst_pad_push_event(r.up,gst_event_new_eos()),"eos_second");
    R305_REQUIRE(r.received==1&&r.eos==2&&!r.failed,"reopen_same_element");
    destroy_rig(&r);check_case("REOPEN_AFTER_EOS_FLUSH_STREAM_START");
}
int main(int argc,char **argv) {
    R305_REQUIRE(argc==2,"plugin_arg");
    gst_init(&argc,&argv);
    GError *error=NULL;
    GstPlugin *p=gst_plugin_load_file(argv[1],&error);
    if(!p){fprintf(stderr,"R305_PLUGIN_LOAD_FAIL %s\n",error?error->message:"unknown");return 2;}
    gst_object_unref(p);
    test_full();
    test_flush();
    test_stream_restart();
    test_reject_eos();
    test_replay_after_eos();
    g_print("RESULT=R305_GSTPAD_EVENTS_%u_OF_%u_PASS\n",passed,passed);
    g_print("SCOPE=EXPERIMENTAL_R188_WITH_SYNTHETIC_R122_NO_REAL_DTS_OR_LG\n");
    return 0;
}
