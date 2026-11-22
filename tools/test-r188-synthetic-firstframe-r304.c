/*
 * R304 isolated synthetic DTS-like frame contract for ORIGINAL R188 C99 core.
 * It uses a deliberately limited R122 test double (NOT the original probe).
 * No audio decoding, GStreamer, TV, or hardware output is tested.
 * SPDX-License-Identifier: MIT
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "r188_dts_framer.h"

#define ASSERT(x) do { if(!(x)) { \
    fprintf(stderr,"R304_ASSERT_FAIL line=%d expr=%s\n",__LINE__,#x); \
    exit(1); } } while(0)
static unsigned passes=0;
static void ok(const char *name) {
    ++passes;
    printf("R304_%s_PASS\n",name);
}
static void putbits(uint8_t *p,unsigned start,unsigned width,uint32_t v) {
    for(unsigned i=0;i<width;i++) {
        unsigned bit=start+i;
        unsigned shift=width-i-1u;
        uint8_t mask=(uint8_t)(1u<<(7u-(bit%8u)));
        if((v>>shift)&1u)p[bit/8u]|=mask;
        else p[bit/8u]&=(uint8_t)~mask;
    }
}
static void make_frame(uint8_t *p,size_t n,uint32_t ch,uint32_t rate,
                       uint32_t samples,uint8_t seed) {
    ASSERT(n>=96 && n<=R188_FRAME_CAP);
    ASSERT(samples%32u==0 && samples>=32 && samples<=4096);
    ASSERT(ch==2 || ch==6);
    ASSERT(rate==48000 || rate==44100);
    for(size_t i=0;i<n;i++)p[i]=(uint8_t)(seed+(uint8_t)i*31u);
    p[0]=0x7f;p[1]=0xfe;p[2]=0x80;p[3]=0x01;
    putbits(p,32,1,1);
    putbits(p,33,5,0);
    putbits(p,38,1,0);
    putbits(p,39,7,samples/32u-1u);
    putbits(p,46,14,(uint32_t)n-1u);
    putbits(p,60,6,ch==2?2u:9u);
    putbits(p,66,4,rate==48000?13u:8u);
}
typedef struct {
    const uint8_t *raw;
    size_t raw_len;
    size_t pos;
    unsigned count;
    uint64_t first_pts;
    uint64_t expected_pts;
    uint32_t rate,channels,samples;
    uint32_t fraction;
    int failed;
} Sink;
static int callback(void *ctx,const uint8_t *p,size_t n,uint64_t pts,
                    uint64_t dur,uint32_t rate,uint32_t ch) {
    Sink *s=ctx;
    if(!s || !p || !n || s->pos+n>s->raw_len ||
       memcmp(p,s->raw+s->pos,n) ||
       ch!=s->channels || rate!=s->rate ||
       pts!=s->expected_pts) {
        if(s)s->failed=1;
        return -1;
    }
    uint64_t numerator=(uint64_t)s->samples*1000000ull+s->fraction;
    uint64_t expected=numerator/s->rate;
    s->fraction=(uint32_t)(numerator%s->rate);
    if(dur!=expected) {
        s->failed=1;
        return -1;
    }
    s->pos+=n;
    s->count++;
    if(pts!=R188_NO_PTS)s->expected_pts+=dur;
    return 0;
}
static Sink sink_for(const uint8_t *raw,size_t size,unsigned ch,
                     unsigned rate,unsigned samples,uint64_t pts) {
    Sink s={0};
    s.raw=raw;s.raw_len=size;s.channels=ch;
    s.rate=rate;s.samples=samples;
    s.first_pts=pts;s.expected_pts=pts;
    return s;
}
static void test_fragmentation(size_t frame_len,uint32_t channels,
                               uint32_t rate,uint32_t samples,size_t chunk,
                               const char *label) {
    const unsigned frames=4;
    size_t n=frame_len*frames;
    uint8_t *raw=malloc(n);
    ASSERT(raw!=NULL);
    for(unsigned i=0;i<frames;i++)
        make_frame(raw+i*frame_len,frame_len,channels,rate,samples,
                   (uint8_t)(i*13u+3u));
    Sink out=sink_for(raw,n,channels,rate,samples,2500000);
    aleks_r188_framer framer;
    aleks_r188_reset(&framer);
    size_t at=0;
    while(at<n) {
        size_t use=n-at<chunk?n-at:chunk;
        ASSERT(aleks_r188_feed(&framer,raw+at,use,
            at==0?2500000:R188_NO_PTS,callback,&out)==0);
        at+=use;
    }
    ASSERT(!out.failed && out.pos==n && out.count==frames);
    ASSERT(framer.emitted==frames && framer.have==0 && !framer.terminal_error);
    ASSERT(framer.next_pts==out.expected_pts);
    free(raw);
    ok(label);
}
static int accept(void *x,const uint8_t *p,size_t n,uint64_t t,
                  uint64_t d,uint32_t r,uint32_t c){
    (void)x;(void)p;(void)n;(void)t;(void)d;(void)r;(void)c;
    return 0;
}
static int reject(void *x,const uint8_t *p,size_t n,uint64_t t,
                  uint64_t d,uint32_t r,uint32_t c){
    return accept(x,p,n,t,d,r,c)-1;
}
static void test_first_header_and_reset(void) {
    uint8_t frame[1024];
    make_frame(frame,sizeof(frame),2,48000,512,7);
    for(size_t head=1;head<=10;head++) {
        aleks_r188_framer f;aleks_r188_reset(&f);
        ASSERT(aleks_r188_feed(&f,frame,head,123456,accept,NULL)==0);
        ASSERT(f.have==head && f.emitted==0 && !f.terminal_error);
        ASSERT(f.frame_pts==123456);
        ASSERT(aleks_r188_feed(&f,frame+head,sizeof(frame)-head,
                  R188_NO_PTS,accept,NULL)==0);
        ASSERT(f.emitted==1 && f.have==0);
    }
    ok("HEADER_SPLITS_1_TO_10_BYTES");
    aleks_r188_framer f;aleks_r188_reset(&f);
    ASSERT(aleks_r188_feed(&f,frame,13,123456,accept,NULL)==0);
    ASSERT(f.have==13 && f.target==1024);
    aleks_r188_reset(&f);  /* GStreamer FLUSH_STOP / STREAM_START analogue */
    ASSERT(f.have==0 && f.target==0 && f.emitted==0);
    ASSERT(f.frame_pts==R188_NO_PTS);
    ASSERT(aleks_r188_feed(&f,frame,sizeof(frame),500000,accept,NULL)==0);
    ASSERT(f.emitted==1 && f.next_pts!=R188_NO_PTS);
    ok("FLUSH_OR_NEW_STREAM_RESETS_PARTIAL");
    aleks_r188_reset(&f);
    ASSERT(aleks_r188_feed(&f,frame,333,123456,accept,NULL)==0);
    ASSERT(f.have==333 && f.emitted==0);
    /* R188 C99 core has no EOS API; its GStreamer wrapper checks have>0. */
    ok("TRUNCATED_END_OF_INPUT_REMAINS_PENDING");
}
static void test_faults(void) {
    uint8_t frame[1024];
    make_frame(frame,sizeof(frame),2,48000,512,11);
    aleks_r188_framer f;aleks_r188_reset(&f);
    uint8_t bad[11]={0};
    ASSERT(aleks_r188_feed(&f,bad,sizeof(bad),0,accept,NULL)==-3);
    ASSERT(f.terminal_error && f.rejected==1);
    ASSERT(aleks_r188_feed(&f,frame,sizeof(frame),0,accept,NULL)==-2);
    ok("BAD_SYNC_TERMINAL_AND_NO_AUTO_RESYNC");
    aleks_r188_reset(&f);
    uint8_t invalid[11];
    memcpy(invalid,frame,sizeof(invalid));
    putbits(invalid,46,14,20); /* frame size 21, below 96 */
    ASSERT(aleks_r188_feed(&f,invalid,sizeof(invalid),0,accept,NULL)==-4);
    ASSERT(f.terminal_error);
    ok("INVALID_FRAME_SIZE_FAIL_CLOSED");
    aleks_r188_reset(&f);
    memcpy(invalid,frame,sizeof(invalid));
    putbits(invalid,66,4,0); /* unsupported frequency in test double */
    ASSERT(aleks_r188_feed(&f,invalid,sizeof(invalid),0,accept,NULL)==-4);
    ok("UNSUPPORTED_RATE_FAIL_CLOSED");
    aleks_r188_reset(&f);
    ASSERT(aleks_r188_feed(&f,frame,sizeof(frame),0,reject,NULL)==-6);
    ASSERT(f.terminal_error);
    ASSERT(aleks_r188_feed(&f,frame,11,0,accept,NULL)==-2);
    ok("DOWNSTREAM_REJECTION_TERMINAL");
    aleks_r188_reset(&f);
    ASSERT(aleks_r188_feed(&f,NULL,1,0,accept,NULL)==-1);
    ASSERT(aleks_r188_feed(&f,frame,R188_FEED_MAX+1u,0,accept,NULL)==-1);
    ASSERT(aleks_r188_feed(&f,NULL,0,0,accept,NULL)==0);
    ASSERT(aleks_r188_feed(NULL,frame,sizeof(frame),0,accept,NULL)==-1);
    ASSERT(aleks_r188_feed(&f,frame,sizeof(frame),0,NULL,NULL)==-1);
    ok("INPUT_BOUNDS_AND_NULL_GUARDS");
    aleks_r188_reset(&f);
    ASSERT(aleks_r188_feed(&f,frame,sizeof(frame),
                           UINT64_MAX-1000u,accept,NULL)==-7);
    ASSERT(f.terminal_error && f.emitted==0);
    ok("PTS_OVERFLOW_FAIL_CLOSED");
}
static void test_missing_pts(void) {
    uint8_t frame[1024];
    make_frame(frame,sizeof(frame),2,48000,512,13);
    aleks_r188_framer f;aleks_r188_reset(&f);
    for(unsigned i=0;i<3;i++) {
        ASSERT(aleks_r188_feed(&f,frame,sizeof(frame),
            R188_NO_PTS,accept,NULL)==0);
        ASSERT(f.next_pts==R188_NO_PTS);
        ASSERT(f.frame_pts==R188_NO_PTS);
    }
    ASSERT(f.emitted==3);
    ok("UNKNOWN_PTS_STAYS_UNKNOWN");
}
static void test_clock_reanchor(void) {
    uint8_t frame48[1024],frame44[1116];
    make_frame(frame48,sizeof(frame48),2,48000,512,5);
    make_frame(frame44,sizeof(frame44),6,44100,1024,6);
    aleks_r188_framer f;aleks_r188_reset(&f);
    ASSERT(aleks_r188_feed(&f,frame48,sizeof(frame48),1000000,accept,NULL)==0);
    ASSERT(aleks_r188_feed(&f,frame48,sizeof(frame48),
                           R188_NO_PTS,accept,NULL)==0);
    uint64_t old=f.next_pts;
    ASSERT(f.pts_fraction_rate==48000);
    ASSERT(aleks_r188_feed(&f,frame44,sizeof(frame44),2000000,accept,NULL)==0);
    ASSERT(old<2000000);
    ASSERT(f.frame_pts==2000000 && f.next_pts>2000000);
    ASSERT(f.pts_fraction_rate==44100);
    ASSERT(f.emitted==3);
    ok("DISCONTINUITY_AND_RATE_CHANGE_REANCHORS");
}
static void test_rational_long_run(void) {
    uint8_t frame[1116];
    make_frame(frame,sizeof(frame),6,44100,1024,11);
    aleks_r188_framer f;aleks_r188_reset(&f);
    const unsigned iterations=9000;
    for(unsigned i=0;i<iterations;i++){
        ASSERT(aleks_r188_feed(&f,frame,sizeof(frame),
            i==0?0:R188_NO_PTS,accept,NULL)==0);
    }
    uint64_t expected=(uint64_t)iterations*1024u*1000000ull/44100u;
    ASSERT(f.emitted==iterations && f.next_pts==expected);
    ASSERT(f.have==0);
    ok("NINE_THOUSAND_FRAMES_44100_RATIONAL_CLOCK");
}
static void test_deterministic_fuzz(void) {
    uint8_t raw[4*96];
    for(unsigned i=0;i<4;i++)
        make_frame(raw+96*i,96,2,48000,512,(uint8_t)i);
    uint32_t rng=0x30418801u;
    for(unsigned trial=0;trial<400;trial++){
        aleks_r188_framer f;aleks_r188_reset(&f);
        Sink out=sink_for(raw,sizeof(raw),2,48000,512,700000);
        size_t offset=0;
        while(offset<sizeof(raw)){
            rng=rng*1664525u+1013904223u;
            size_t chunk=1u+((rng>>10)%139u);
            if(chunk>sizeof(raw)-offset)chunk=sizeof(raw)-offset;
            ASSERT(aleks_r188_feed(&f,raw+offset,chunk,
                    offset==0?700000:R188_NO_PTS,callback,&out)==0);
            offset+=chunk;
        }
        ASSERT(f.have==0 && f.emitted==4 && out.count==4);
        ASSERT(!out.failed && out.pos==sizeof(raw));
    }
    ok("FOUR_HUNDRED_DETERMINISTIC_FRAGMENTATION_TRIALS");
}
int main(void) {
    test_fragmentation(1024,2,48000,512,1,"STEREO_ONE_BYTE_FRAGMENTS");
    test_fragmentation(1024,2,48000,512,2,"STEREO_TWO_BYTE_FRAGMENTS");
    test_fragmentation(1024,2,48000,512,3,"STEREO_THREE_BYTE_FRAGMENTS");
    test_fragmentation(1024,2,48000,512,7,"STEREO_SEVEN_BYTE_FRAGMENTS");
    test_fragmentation(1024,2,48000,512,11,"STEREO_ELEVEN_BYTE_FRAGMENTS");
    test_fragmentation(1024,2,48000,512,1023,"STEREO_1023_BYTE_FRAGMENTS");
    test_fragmentation(1024,2,48000,512,4096,"MULTIFRAME_SINGLE_BUFFER");
    test_fragmentation(1116,6,44100,1024,1,"SIX_CHANNEL_ONE_BYTE_FRAGMENTS");
    test_fragmentation(1116,6,44100,1024,97,"SIX_CHANNEL_97_BYTE_FRAGMENTS");
    test_fragmentation(1116,6,44100,1024,4096,"SIX_CHANNEL_MULTIFRAME_BUFFER");
    test_first_header_and_reset();
    test_faults();
    test_missing_pts();
    test_clock_reanchor();
    test_rational_long_run();
    test_deterministic_fuzz();
    printf("R304_SYNTHETIC_R188_C99_QA_%u_OF_%u_PASS\n",passes,passes);
    printf("R304_SCOPE_SYNTHETIC_HEADER_DOUBLE_NOT_ORIGINAL_R122_OR_REAL_DTS\n");
    printf("R304_REAL_LG_AUDIO_NOT_TESTED\n");
    return 0;
}
