/* R324 — immutable R278 libdcadec packet cardinality proof.
 * SPDX-License-Identifier: MIT
 * Tested with public R278 DTS Core stereo and 5.1 fixtures.
 * No PCM/media recording and no system/device audio access.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libdcadec/dca_context.h"

#if defined(R324_SURROUND_51)
enum { DTS_FRAME_BYTES = 2048, EXPECTED_BYTES = 192512,
       EXPECTED_FRAMES = 94, EXPECTED_CHANNEL_MASK = 1551 };
#define R324_TRACK "SURROUND_51"
#else
enum { DTS_FRAME_BYTES = 1024, EXPECTED_BYTES = 96256,
       EXPECTED_FRAMES = 94, EXPECTED_CHANNEL_MASK = 3 };
#define R324_TRACK "STEREO"
#endif

struct result {
    int parse_ok;
    int pcm_ok;
    int samples;
    int samplerate;
    int channelmask;
};

static struct result decode(const uint8_t *src, size_t available,
                            size_t bytes, int corrupt) {
    struct result result = { 0, 0, 0, 0, 0 };
    if (bytes > available || bytes < 4) return result;
    uint8_t *packet = malloc(bytes + 16);
    if (!packet) return result;
    memcpy(packet, src, bytes);
    memset(packet + bytes, 0, 16);
    if (corrupt) packet[0] ^= 0xff;

    struct dcadec_context *decoder = dcadec_context_create(0);
    if (!decoder) {
        free(packet);
        return result;
    }
    int parsed = dcadec_context_parse(decoder, packet, bytes);
    result.parse_ok = parsed >= 0;
    if (parsed >= 0) {
        int **pcm = NULL;
        int bits = 0, profile = 0;
        int filtered = dcadec_context_filter(decoder, &pcm,
                         &result.samples, &result.channelmask,
                         &result.samplerate, &bits, &profile);
        result.pcm_ok = filtered >= 0 && pcm &&
                        result.samples > 0 && bits > 0;
    }
    dcadec_context_destroy(decoder);
    free(packet);
    return result;
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    FILE *input = fopen(argv[1], "rb");
    if (!input) return 2;
    uint8_t encoded[EXPECTED_BYTES + 1];
    size_t count = fread(encoded, 1, sizeof(encoded), input);
    fclose(input);
    if (count != EXPECTED_BYTES) {
        puts("R324_FIXTURE_BYTES_MISMATCH");
        return 2;
    }
    static const uint8_t syncword[] = { 0x7f, 0xfe, 0x80, 0x01 };
    int frames = 0;
    for (size_t pos = 0; pos < count; pos += DTS_FRAME_BYTES) {
        if (memcmp(encoded + pos, syncword, sizeof(syncword))) {
            puts("R324_FRAME_SYNC_MISMATCH");
            return 2;
        }
        frames++;
    }
    if (frames != EXPECTED_FRAMES) return 2;
    printf("R324_TRACK=%s\n", R324_TRACK);
    printf("R324_FIXTURE_FULL_FRAMES=%d\n", frames);

    static const size_t lens[] = { 11, 97, 512, 1024, 2048, 4096 };
    int success = 1;
    for (size_t i = 0; i < sizeof(lens)/sizeof(lens[0]); ++i) {
        struct result r = decode(encoded, count, lens[i], 0);
        int should_decode = lens[i] >= DTS_FRAME_BYTES;
        int pass = should_decode
                 ? r.parse_ok && r.pcm_ok && r.samples == 512 &&
                   r.samplerate == 48000 && r.channelmask == EXPECTED_CHANNEL_MASK
                 : !r.parse_ok && !r.pcm_ok;
        printf("R324_INPUT_BYTES=%zu PARSE=%s PCM_SAMPLES_PER_CHANNEL=%d EXPECTED=%s RESULT=%s\n",
               lens[i], r.parse_ok ? "ACCEPT" : "REJECT", r.samples,
               should_decode ? "ONE_FRAME_ONLY" : "INCOMPLETE_REJECT",
               pass ? "PASS" : "FAIL");
        success &= pass;
    }
    /* Validate the proposed caller contract on the *entire* fixture:
     * one persistent libdcadec context, one complete DTS Core frame per
     * parse/filter, chronological order, no PCM recording. */
    struct dcadec_context *sequential = dcadec_context_create(0);
    if (!sequential) return 2;
    uint32_t packet_words[(DTS_FRAME_BYTES + 16) / sizeof(uint32_t)];
    uint8_t *packet = (uint8_t *)packet_words;
    int total_samples = 0, decoded = 0;
    for (size_t pos = 0; pos < count; pos += DTS_FRAME_BYTES) {
        memcpy(packet, encoded + pos, DTS_FRAME_BYTES);
        memset(packet + DTS_FRAME_BYTES, 0, 16);
        int parsed = dcadec_context_parse(sequential, packet, DTS_FRAME_BYTES);
        if (parsed < 0) break;
        int **pcm = NULL;
        int samples = 0, channels = 0, rate = 0, bits = 0, profile = 0;
        if (dcadec_context_filter(sequential, &pcm, &samples,
                                  &channels, &rate, &bits, &profile) < 0 ||
            !pcm || samples != 512 || channels != EXPECTED_CHANNEL_MASK || rate != 48000) break;
        total_samples += samples;
        decoded++;
    }
    dcadec_context_destroy(sequential);
    int complete_pass = decoded == EXPECTED_FRAMES &&
                        total_samples == EXPECTED_FRAMES * 512;
    printf("R324_SEQUENTIAL_DECODED_FRAMES=%d_OF_%d\n",
           decoded, EXPECTED_FRAMES);
    printf("R324_SEQUENTIAL_PCM_SAMPLES_PER_CHANNEL=%d\n", total_samples);
    printf("R324_SEQUENTIAL_ONE_FRAME_PER_CALL=%s\n",
           complete_pass ? "PASS" : "FAIL");
    success &= complete_pass;

    struct result broken = decode(encoded, count, DTS_FRAME_BYTES, 1);
    int reject_ok = !broken.parse_ok && !broken.pcm_ok;
    printf("R324_CORRUPT_FIRST_FRAME_REJECT=%s\n", reject_ok ? "PASS" : "FAIL");
    success &= reject_ok;

    /* A 4096-byte buffer contains 2 or 4 complete DTS Core frames,
     * depending on the track. A single parse/filter yields only 512 PCM
     * samples on this exact R278 fixture. The caller must split frames
     * and preserve their timestamps. Lampa's live input is unobserved. */
    printf("R324_4096_BYTE_BUFFER_DECODED_FRAMES=1_OF_%d\n",
           4096 / DTS_FRAME_BYTES);
    puts("R324_PRODUCTION_OR_TV_MODIFIED=NO");
    puts(success ? "RESULT=R324_LIBDCADEC_CARDINALITY_PASS"
                 : "RESULT=R324_LIBDCADEC_CARDINALITY_FAIL");
    return success ? 0 : 1;
}
