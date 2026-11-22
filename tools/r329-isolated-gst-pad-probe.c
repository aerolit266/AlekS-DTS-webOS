/*
 * R329: isolated GStreamer pad-level signal path observability.
 *
 * Counts DTS input framing, STREAM_START/CAPS/SEGMENT ordering, and decoded
 * S16LE PCM energy (count/RMS/peak). Never outputs audio bytes, pad strings,
 * media titles, URLs, PTS values, or arbitrary GStreamer logs.
 *
 * Important: this executable attaches only to a NEW gst_parse_launch
 * pipeline terminating at fakesink. It NEVER attaches to another process,
 * changes a plugin registry, or touches an LG media service.
 * SPDX-License-Identifier: MIT
 */
#include <gst/gst.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENCODED_BYTES_MAX (8U * 1024U * 1024U)
#define PCM_SAMPLES_MAX (8U * 1024U * 1024U)
typedef struct {
    guint64 input_buffers, input_bytes, input_sync_be16, invalid_pts;
    guint64 stream_events, caps_events, segment_events, flush_events, eos_events;
    guint64 order_violations, bad_input_map, bad_pcm_map;
    guint64 pcm_buffers, pcm_samples, pcm_nonzero, pcm_bytes;
    guint64 segment_time, segment_bytes, segment_other;
    guint64 caps_dts, caps_other, frames_before_events;
    gdouble pcm_squared_sum;
    guint32 pcm_peak;
    gboolean seen_stream, seen_caps, seen_segment;
    gint expected_channels, pcm_channels, pcm_rate;
    gboolean pcm_s16;
} R329Stats;

static GstPadProbeReturn inspect_encoded(GstPad *pad, GstPadProbeInfo *info,
                                          gpointer ctx) {
    (void)pad;
    R329Stats *s = (R329Stats *)ctx;
    if (GST_PAD_PROBE_INFO_TYPE(info) & GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM) {
        GstEvent *e = GST_PAD_PROBE_INFO_EVENT(info);
        switch (GST_EVENT_TYPE(e)) {
            case GST_EVENT_STREAM_START:
                s->stream_events++;
                s->seen_stream = TRUE;
                s->seen_caps = FALSE;
                s->seen_segment = FALSE;
                break;
            case GST_EVENT_CAPS: {
                s->caps_events++;
                if (!s->seen_stream) s->order_violations++;
                GstCaps *caps = NULL;
                gst_event_parse_caps(e, &caps);
                if (caps && gst_caps_get_size(caps) > 0) {
                    const GstStructure *st = gst_caps_get_structure(caps, 0);
                    if (g_strcmp0(gst_structure_get_name(st), "audio/x-dts") == 0)
                        s->caps_dts++;
                    else s->caps_other++;
                }
                s->seen_caps = TRUE;
                break;
            }
            case GST_EVENT_SEGMENT: {
                s->segment_events++;
                if (!s->seen_stream || !s->seen_caps) s->order_violations++;
                const GstSegment *segment = NULL;
                gst_event_parse_segment(e, &segment);
                if (!segment) s->segment_other++;
                else if (segment->format == GST_FORMAT_TIME) s->segment_time++;
                else if (segment->format == GST_FORMAT_BYTES) s->segment_bytes++;
                else s->segment_other++;
                s->seen_segment = TRUE;
                break;
            }
            case GST_EVENT_FLUSH_STOP:
                s->flush_events++;
                s->seen_segment = FALSE;
                break;
            case GST_EVENT_EOS:
                s->eos_events++;
                break;
            default: break;
        }
        return GST_PAD_PROBE_OK;
    }
    if (!(GST_PAD_PROBE_INFO_TYPE(info) & GST_PAD_PROBE_TYPE_BUFFER))
        return GST_PAD_PROBE_OK;
    if (!s->seen_stream || !s->seen_caps || !s->seen_segment) {
        s->order_violations++;
        s->frames_before_events++;
    }
    GstBuffer *b = GST_PAD_PROBE_INFO_BUFFER(info);
    if (!b) { s->bad_input_map++; return GST_PAD_PROBE_OK; }
    s->input_buffers++;
    s->input_bytes += gst_buffer_get_size(b);
    if (!GST_BUFFER_PTS_IS_VALID(b)) s->invalid_pts++;
    GstMapInfo map;
    if (!gst_buffer_map(b, &map, GST_MAP_READ)) {
        s->bad_input_map++;
        return GST_PAD_PROBE_OK;
    }
    if (map.size >= 4 && map.data[0] == 0x7f && map.data[1] == 0xfe &&
        map.data[2] == 0x80 && map.data[3] == 0x01)
        s->input_sync_be16++;
    gst_buffer_unmap(b, &map);
    return GST_PAD_PROBE_OK;
}

static GstPadProbeReturn inspect_pcm(GstPad *pad, GstPadProbeInfo *info,
                                     gpointer ctx) {
    (void)pad;
    R329Stats *s = (R329Stats *)ctx;
    if (GST_PAD_PROBE_INFO_TYPE(info) & GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM) {
        GstEvent *e = GST_PAD_PROBE_INFO_EVENT(info);
        if (GST_EVENT_TYPE(e) == GST_EVENT_CAPS) {
            GstCaps *caps = NULL;
            gst_event_parse_caps(e, &caps);
            if (caps && gst_caps_get_size(caps) > 0) {
                const GstStructure *st = gst_caps_get_structure(caps, 0);
                const gchar *fmt = gst_structure_get_string(st, "format");
                s->pcm_s16 = g_strcmp0(gst_structure_get_name(st), "audio/x-raw") == 0 &&
                             g_strcmp0(fmt, "S16LE") == 0;
                gst_structure_get_int(st, "channels", &s->pcm_channels);
                gst_structure_get_int(st, "rate", &s->pcm_rate);
            }
        }
        return GST_PAD_PROBE_OK;
    }
    if (!(GST_PAD_PROBE_INFO_TYPE(info) & GST_PAD_PROBE_TYPE_BUFFER))
        return GST_PAD_PROBE_OK;
    GstBuffer *b = GST_PAD_PROBE_INFO_BUFFER(info);
    s->pcm_buffers++;
    if (!b) { s->bad_pcm_map++; return GST_PAD_PROBE_OK; }
    GstMapInfo map;
    if (!gst_buffer_map(b, &map, GST_MAP_READ)) {
        s->bad_pcm_map++;
        return GST_PAD_PROBE_OK;
    }
    if (!s->pcm_s16 || map.size % 2 ||
        s->pcm_bytes + map.size > PCM_SAMPLES_MAX * 2ULL) {
        s->bad_pcm_map++;
        gst_buffer_unmap(b, &map);
        return GST_PAD_PROBE_OK;
    }
    s->pcm_bytes += map.size;
    for (gsize i = 0; i < map.size; i += 2) {
        gint16 pcm = (gint16)((guint16)map.data[i] |
                             ((guint16)map.data[i + 1] << 8));
        guint32 mag = pcm >= 0 ? (guint32)pcm : (guint32)(-(gint32)pcm);
        s->pcm_samples++;
        s->pcm_nonzero += pcm != 0;
        if (mag > s->pcm_peak) s->pcm_peak = mag;
        s->pcm_squared_sum += (gdouble)pcm * (gdouble)pcm;
    }
    gst_buffer_unmap(b, &map);
    return GST_PAD_PROBE_OK;
}

static void print_result(const R329Stats *s, gboolean done, gint exit_code) {
    gdouble rms = s->pcm_samples ?
        sqrt(s->pcm_squared_sum / (gdouble)s->pcm_samples) : 0.0;
    gdouble dbfs = rms > 0 ? 20.0 * log10(rms / 32768.0) : -999.0;
    gdouble peak = s->pcm_peak ? 20.0 * log10((gdouble)s->pcm_peak / 32768.0) : -999.0;
    printf("R329_EOS=%s\n", done ? "YES" : "NO");
    printf("R329_INPUT_STREAM_START=%" G_GUINT64_FORMAT "\n", s->stream_events);
    printf("R329_INPUT_DTS_CAPS=%" G_GUINT64_FORMAT "\n", s->caps_dts);
    printf("R329_INPUT_SEGMENT_TIME=%" G_GUINT64_FORMAT "\n", s->segment_time);
    printf("R329_INPUT_SEGMENT_BYTES=%" G_GUINT64_FORMAT "\n", s->segment_bytes);
    printf("R329_INPUT_SEGMENT_OTHER=%" G_GUINT64_FORMAT "\n", s->segment_other);
    printf("R329_INPUT_BUFFERS=%" G_GUINT64_FORMAT "\n", s->input_buffers);
    printf("R329_INPUT_BE16_SYNC=%" G_GUINT64_FORMAT "\n", s->input_sync_be16);
    printf("R329_INPUT_BYTES=%" G_GUINT64_FORMAT "\n", s->input_bytes);
    printf("R329_INPUT_MISSING_PTS=%" G_GUINT64_FORMAT "\n", s->invalid_pts);
    printf("R329_EVENT_ORDER_ERRORS=%" G_GUINT64_FORMAT "\n", s->order_violations);
    printf("R329_PCM_S16LE=%s\n", s->pcm_s16 ? "YES" : "NO");
    printf("R329_PCM_RATE=%d\n", s->pcm_rate);
    printf("R329_PCM_CHANNELS=%d\n", s->pcm_channels);
    printf("R329_PCM_BUFFERS=%" G_GUINT64_FORMAT "\n", s->pcm_buffers);
    printf("R329_PCM_SAMPLES=%" G_GUINT64_FORMAT "\n", s->pcm_samples);
    printf("R329_PCM_NONZERO=%" G_GUINT64_FORMAT "\n", s->pcm_nonzero);
    printf("R329_PCM_RMS_DBFS=%.2f\n", dbfs);
    printf("R329_PCM_PEAK_DBFS=%.2f\n", peak);
    printf("R329_BAD_MAPS=%" G_GUINT64_FORMAT "\n", s->bad_pcm_map + s->bad_input_map);
    printf("R329_AUDIO_FILES_CREATED=0\n");
    printf("R329_RAW_PCM_EXPORTED=NO\n");
    printf("R329_CONNECTED_TO_LIVE_MEDIA=NO\n");
    printf("RESULT=%s\n", exit_code == 0 ? "R329_PAD_PROBE_PASS" : "R329_PAD_PROBE_FAIL");
}

int main(int argc, char **argv) {
    if (argc != 5) {
        fputs("R329_USAGE: r329-probe <stereo|surround> <matroska|raw> <fixture> <blocksize>\n", stderr);
        return 2;
    }
    gboolean surround = strcmp(argv[1], "surround") == 0;
    if (!surround && strcmp(argv[1], "stereo") != 0) return 2;
    gboolean raw = strcmp(argv[2], "raw") == 0;
    if (!raw && strcmp(argv[2], "matroska") != 0) return 2;
    unsigned block = 0;
    if (sscanf(argv[4], "%u", &block) != 1 ||
        (raw && block != 1 && block != 11 && block != 97 && block != 4096) ||
        (!raw && block != 0)) return 2;
    const char *name = strrchr(argv[3], '/');
    name = name ? name + 1 : argv[3];
    const char *allowed = surround ? (raw ? "surround.dts" : "surround.mka")
                                  : (raw ? "stereo.dts" : "stereo.mka");
    if (strcmp(name, allowed) != 0) return 2;
    gst_init(&argc, &argv);
    gchar *spec = raw ?
        g_strdup_printf(
            "filesrc location=\"%s\" blocksize=%u ! "
            "audio/x-dts ! aleksdtsr188framer ! queue ! dtsdec name=decoder ! "
            "audioconvert ! audio/x-raw,format=S16LE,channels=%u,rate=48000 ! "
            "identity name=pcm_monitor ! fakesink sync=false",
            argv[3], block, surround ? 6U : 2U) :
        g_strdup_printf(
            "filesrc location=\"%s\" ! matroskademux name=dm "
            "dm.audio_0 ! queue ! dtsdec name=decoder ! "
            "audioconvert ! audio/x-raw,format=S16LE,channels=%u,rate=48000 ! "
            "identity name=pcm_monitor ! fakesink sync=false",
            argv[3], surround ? 6U : 2U);
    GError *err = NULL;
    GstElement *pipe = gst_parse_launch(spec, &err);
    g_free(spec);
    if (!pipe || err) {
        if (err) g_error_free(err);
        if (pipe) gst_object_unref(pipe);
        puts("RESULT=R329_PIPELINE_CREATE_FAILED");
        return 2;
    }
    R329Stats stats = {0};
    stats.expected_channels = surround ? 6 : 2;
    GstElement *decoder = gst_bin_get_by_name(GST_BIN(pipe), "decoder");
    GstElement *pcm = gst_bin_get_by_name(GST_BIN(pipe), "pcm_monitor");
    GstPad *encoded = decoder ? gst_element_get_static_pad(decoder, "sink") : NULL;
    GstPad *decoded = pcm ? gst_element_get_static_pad(pcm, "src") : NULL;
    if (!encoded || !decoded) {
        puts("RESULT=R329_PAD_ATTACHMENT_FAILED");
        if (encoded) gst_object_unref(encoded);
        if (decoded) gst_object_unref(decoded);
        if (decoder) gst_object_unref(decoder);
        if (pcm) gst_object_unref(pcm);
        gst_object_unref(pipe);
        return 2;
    }
    gst_pad_add_probe(encoded, GST_PAD_PROBE_TYPE_BUFFER |
        GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM, inspect_encoded, &stats, NULL);
    gst_pad_add_probe(decoded, GST_PAD_PROBE_TYPE_BUFFER |
        GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM, inspect_pcm, &stats, NULL);
    GstBus *bus = gst_element_get_bus(pipe);
    gboolean eos = FALSE, error_event = FALSE;
    GstStateChangeReturn state = gst_element_set_state(pipe, GST_STATE_PLAYING);
    if (state == GST_STATE_CHANGE_FAILURE) error_event = TRUE;
    else {
        GstMessage *msg = gst_bus_timed_pop_filtered(bus, 15 * GST_SECOND,
                                         GST_MESSAGE_EOS | GST_MESSAGE_ERROR);
        if (!msg) error_event = TRUE;
        else {
            eos = GST_MESSAGE_TYPE(msg) == GST_MESSAGE_EOS;
            error_event = !eos;
            gst_message_unref(msg);
        }
    }
    gst_element_set_state(pipe, GST_STATE_NULL);
    int ok = eos && !error_event && stats.stream_events > 0 &&
        stats.caps_dts > 0 && stats.segment_time > 0 &&
        stats.segment_bytes == 0 && stats.segment_other == 0 &&
        stats.order_violations == 0 && stats.bad_input_map == 0 &&
        stats.bad_pcm_map == 0 && stats.input_buffers == 94 &&
        stats.input_sync_be16 == 94 &&
        stats.pcm_s16 && stats.pcm_rate == 48000 &&
        stats.pcm_channels == stats.expected_channels &&
        stats.pcm_samples == (guint64)94 * 512 * stats.expected_channels &&
        stats.pcm_nonzero > 0;
    print_result(&stats, eos, ok ? 0 : 1);
    gst_object_unref(bus);
    gst_object_unref(encoded);
    gst_object_unref(decoded);
    gst_object_unref(decoder);
    gst_object_unref(pcm);
    gst_object_unref(pipe);
    return ok ? 0 : 1;
}
