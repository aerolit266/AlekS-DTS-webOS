/*
 * R304 synthetic R122 test double for isolated R188 assembler QA.
 * NOT the original R122, NOT an audio decoder, NOT a DTS conformance parser.
 * Encodes a DTS-like BE16 header with only those bit fields R188 uses.
 * SPDX-License-Identifier: MIT
 */
#ifndef ALEKS_R304_SYNTHETIC_R122_TEST_DOUBLE_H
#define ALEKS_R304_SYNTHETIC_R122_TEST_DOUBLE_H
#include <stdint.h>
#include <stddef.h>
#define ALEKS_DTS_CORE_OK 0
typedef struct {
    uint32_t frame_bytes;
    uint32_t channels;
    uint32_t sample_rate;
} aleks_r122_dts_core_info;
static inline int aleks_r122_read_bits(const uint8_t *p,size_t n,
                                      unsigned *bit,unsigned width,
                                      uint32_t *result){
    if(!p||!bit||!result||width==0||width>32||*bit>n*8||width>n*8-*bit)
        return -1;
    uint32_t v=0;
    for(unsigned i=0;i<width;i++){
        unsigned off=*bit+i;
        v=(v<<1)|((p[off/8]>>(7-(off%8)))&1u);
    }
    *bit+=width;*result=v;
    return 0;
}
static inline int aleks_r122_dts_probe_be16(const uint8_t *p,size_t n,
                                             aleks_r122_dts_core_info *info){
    static const uint8_t sync[4]={0x7f,0xfe,0x80,0x01};
    if(!p||!info||n<11)return -1;
    for(unsigned i=0;i<4;i++)if(p[i]!=sync[i])return -1;
    unsigned pos=46;uint32_t frame_minus1=0,amode=0,sfreq=0;
    if(aleks_r122_read_bits(p,n,&pos,14,&frame_minus1))return -1;
    if(aleks_r122_read_bits(p,n,&pos,6,&amode))return -1;
    if(aleks_r122_read_bits(p,n,&pos,4,&sfreq))return -1;
    /* Chosen synthetic test codes only. Deliberately not DTS compliant. */
    if(amode!=2 && amode!=9)return -1;
    if(sfreq!=13 && sfreq!=8)return -1;
    info->frame_bytes=frame_minus1+1;
    info->channels=amode==2?2:6;
    info->sample_rate=sfreq==13?48000:44100;
    return ALEKS_DTS_CORE_OK;
}
#endif
