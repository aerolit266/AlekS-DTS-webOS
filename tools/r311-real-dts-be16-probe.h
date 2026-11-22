/*
 * AlekS R311: real DTS Core BE16 subset header probe for standalone
 * laboratory R188 framer. It replaces the R304 synthetic test double,
 * NOT the original lost R122 header. NOT a general-purpose DTS parser.
 *
 * The sample frequency and channel arrangement look-up semantics match
 * published libdcadec core header parsing (LGPL-2.1-or-later).
 * Fail closed on unsupported profile/invalid header; never resync/drop.
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#ifndef ALEKS_R311_REAL_DTS_BE16_PROBE_H
#define ALEKS_R311_REAL_DTS_BE16_PROBE_H
#include <stddef.h>
#include <stdint.h>
#define ALEKS_DTS_CORE_OK 0
typedef struct {
    uint32_t frame_bytes;
    uint32_t channels;
    uint32_t sample_rate;
} aleks_r122_dts_core_info;
static inline int aleks_r122_read_bits(const uint8_t *p,size_t n,
                                       unsigned *bit,unsigned width,
                                       uint32_t *result) {
    if(!p||!bit||!result||!width||width>32||
       *bit>n*8u||width>n*8u-*bit)return -1;
    uint32_t v=0;
    for(unsigned i=0;i<width;i++) {
        unsigned off=*bit+i;
        v=(v<<1)|((p[off/8u]>>(7u-(off%8u)))&1u);
    }
    *bit+=width;
    *result=v;
    return 0;
}
static inline int aleks_r122_dts_probe_be16(const uint8_t *p,size_t n,
                                              aleks_r122_dts_core_info *info) {
    static const uint8_t sync[4]={0x7f,0xfe,0x80,0x01};
    static const uint8_t channel_count[16]={
      1,2,2,2,2,3,3,4,4,5,6,6,6,7,8,8
    };
    static const uint32_t sample_rates[16]={
      0,8000,16000,32000,0,0,11025,22050,
      44100,0,0,12000,24000,48000,0,0
    };
    unsigned bit=32;
    uint32_t normal=0,deficit=0,crc=0,blocks_minus1=0;
    uint32_t size_minus1=0,amode=0,sfreq=0,bitrate=0;
    uint32_t lfe=0;
    if(!p||!info||n<11)return -1;
    for(unsigned i=0;i<4;i++)if(p[i]!=sync[i])return -2;
    if(aleks_r122_read_bits(p,n,&bit,1,&normal)||
       aleks_r122_read_bits(p,n,&bit,5,&deficit)||
       aleks_r122_read_bits(p,n,&bit,1,&crc)||
       aleks_r122_read_bits(p,n,&bit,7,&blocks_minus1)||
       aleks_r122_read_bits(p,n,&bit,14,&size_minus1)||
       aleks_r122_read_bits(p,n,&bit,6,&amode)||
       aleks_r122_read_bits(p,n,&bit,4,&sfreq)||
       aleks_r122_read_bits(p,n,&bit,5,&bitrate))return -3;
    /* Profile restriction: normal DTS Core BE16, 32-bit PCM sample deficit
       31, whole 8-block subbands, supported primary audio modes. */
    uint32_t blocks=blocks_minus1+1u;
    if(normal!=1||deficit!=31||blocks<8||blocks%8u||
       size_minus1+1u<96u||size_minus1+1u>16384u||
       amode>=16u||sfreq>=16u||!sample_rates[sfreq]||
       (bitrate>24u && bitrate!=29u && bitrate!=31u))return -4;
    /* At bit offset 85, the 2-bit LFE flag follows the 5-bit rate, reserved
       bit, drc, timestamp, auxiliary, HDCD, extension descriptor and
       extension present/sync bits (libdcadec core syntax). */
    bit=85u;
    if(aleks_r122_read_bits(p,n,&bit,2,&lfe) || lfe>2u)return -5;
    /* Input raw output channel count includes optional LFE. */
    uint32_t channels=(uint32_t)channel_count[amode]+(lfe!=0u);
    if(channels>8u)return -6; /* stay within bounded lab downstream caps */
    (void)crc;
    info->frame_bytes=size_minus1+1u;
    info->channels=channels;
    info->sample_rate=sample_rates[sfreq];
    return ALEKS_DTS_CORE_OK;
}
#endif
