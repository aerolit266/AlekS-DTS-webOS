/*
 * AlekS DTS R188 bounded Core BE16 frame assembler, independent C99 core.
 * SPDX-License-Identifier: MIT. Copyright (c) 2026 AlekS/GameFree24.
 *
 * Not a DTS decoder. No arbitrary sync scanning or concealed frame drops.
 * Input must start at the beginning of a DTS Core frame (or continuation of
 * a frame already in progress); malformed data fail closed for this segment.
 * Max retained 16384 bytes, max single feed 1 MiB, fixed
 * uses 11 bytes; complete frame requires R122 validated header.
 *
 * DTS packet PTS: the first chunk's PTS anchors a frame; if a new complete
 * frame starts within the same chunk, advance by parsed frame duration.
 * PTS interpolation retains the exact rational fraction in 1/sample_rate
 * units; rounding does not accumulate. This is not clock drift correction.
 */
#ifndef ALEKS_R188_DTS_FRAMER_H
#define ALEKS_R188_DTS_FRAMER_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "r122_dts_core_probe.h"
#define R188_FRAME_CAP 16384u
#define R188_FEED_MAX (1024u*1024u)
#define R188_NO_PTS UINT64_MAX
typedef struct {
    uint8_t frame[R188_FRAME_CAP];
    size_t have;
    uint16_t target;
    uint32_t sample_rate;
    uint32_t channels;
    uint32_t samples;
    uint64_t frame_pts;
    uint64_t next_pts;
    /* Remainder of samples*1e6 / sample_rate; prevents cumulative PTS drift.
     * Never carry residue across explicit timestamp discontinuities or a
     * change of audio sample_rate. */
    uint32_t pts_fraction;
    uint32_t pts_fraction_rate;
    uint32_t emitted;
    uint32_t rejected;
    int terminal_error;
} aleks_r188_framer;
typedef int (*aleks_r188_emit_fn)(void *user,
    const uint8_t *data,size_t len,uint64_t pts,uint64_t duration,
    uint32_t rate,uint32_t channels);
static inline void aleks_r188_reset(aleks_r188_framer *s) {
    if(!s)return;
    memset(s,0,sizeof(*s));
    s->frame_pts=R188_NO_PTS;
    s->next_pts=R188_NO_PTS;
    s->pts_fraction=0;
    s->pts_fraction_rate=0;
}
static inline uint32_t aleks_r188_samples(const uint8_t *header) {
    /* Following 32-bit BE16 sync:
     * 1-bit normal, 5 deficit, 1 CRC, 7-bit NBLKS_MINUS1.
     * DTS samples per block = 32.
     */
    uint32_t bits=0;
    unsigned pos=32u+1u+5u+1u;
    if(aleks_r122_read_bits(header,11u,&pos,7u,&bits))return 0;
    return (bits+1u)*32u;
}
static inline uint64_t aleks_r188_frame_duration(uint32_t samples,
                                                  uint32_t rate) {
    if(!rate || !samples)return 0;
    /* Microsecond rounding, bounded at 4096 samples. */
    return ((uint64_t)samples*1000000ull+(rate/2u))/rate;
}
static inline int aleks_r188_feed(aleks_r188_framer *s,const uint8_t *data,
    size_t len,uint64_t pts,aleks_r188_emit_fn callback,void *userdata) {
    static const uint8_t sync[4]={0x7f,0xfe,0x80,0x01};
    size_t offset=0;
    if(!s||!callback||(!data&&len)||len>R188_FEED_MAX)return -1;
    if(s->terminal_error)return -2;
    if(!len)return 0;
    while(offset<len){
        size_t remaining,copy;
        if(!s->have) {
            if(pts!=R188_NO_PTS && offset==0) {
                /* An explicit source PTS anchors the clock: no synthetic
                 * fractional residue may leak across discontinuities.
                 * On stable forward input it may be retained if exact match. */
                if(s->next_pts!=pts){
                    s->pts_fraction=0;
                    s->pts_fraction_rate=0;
                }
                s->frame_pts=pts;
            } else s->frame_pts=s->next_pts;
        }
        if(s->have<11){
            remaining=11u-s->have;
            copy=len-offset<remaining?len-offset:remaining;
            memcpy(s->frame+s->have,data+offset,copy);
            s->have+=copy;offset+=copy;
            /* Reject impossible BE16 header as soon as observable. */
            for(size_t i=0;i<s->have&&i<4;i++){
                if(s->frame[i]!=sync[i]){
                    s->rejected++;s->terminal_error=1;
                    return -3;
                }
            }
            if(s->have<11)continue;
            aleks_r122_dts_core_info info;
            int parsed=aleks_r122_dts_probe_be16(s->frame,11,&info);
            if(parsed!=ALEKS_DTS_CORE_OK ||
               info.frame_bytes<96||info.frame_bytes>R188_FRAME_CAP){
                s->rejected++;s->terminal_error=1;
                return -4;
            }
            s->target=info.frame_bytes;
            s->channels=info.channels;
            s->sample_rate=info.sample_rate;
            s->samples=aleks_r188_samples(s->frame);
            if(!s->samples||!aleks_r188_frame_duration(s->samples,s->sample_rate)){
                s->rejected++;s->terminal_error=1;
                return -5;
            }
        }
        if(s->have<s->target){
            remaining=(size_t)s->target-s->have;
            copy=len-offset<remaining?len-offset:remaining;
            memcpy(s->frame+s->have,data+offset,copy);
            s->have+=copy;offset+=copy;
        }
        if(s->have==s->target){
            if(s->pts_fraction_rate!=s->sample_rate) {
                s->pts_fraction=0;
                s->pts_fraction_rate=s->sample_rate;
            }
            uint64_t dividend=(uint64_t)s->samples*1000000ull+s->pts_fraction;
            uint64_t dur=dividend/s->sample_rate;
            uint32_t next_fraction=(uint32_t)(dividend%s->sample_rate);
            uint64_t current=s->frame_pts;
            /* Never overflow the sentinel R188_NO_PTS. Source unit is us.
             * Fail closed rather than wrapping time backwards. */
            if(current!=R188_NO_PTS && current>UINT64_MAX-1-dur){
                s->terminal_error=1;s->rejected++;return -7;
            }
            if(callback(userdata,s->frame,s->target,current,dur,
                        s->sample_rate,s->channels)!=0){
                s->terminal_error=1;return -6;
            }
            s->emitted++;
            s->pts_fraction=next_fraction;
            s->next_pts=current==R188_NO_PTS?R188_NO_PTS:current+dur;
            s->have=0;s->target=0;
            s->sample_rate=0;s->channels=0;s->samples=0;
        }
    }
    return 0;
}
#endif