/*
 * AlekS DTS R330 — isolated same-process audio priming differential.
 * Sequence: DTS stereo cold -> AC3 5.1 -> DTS stereo warm ->
 *           DTS 5.1 cold -> AC3 5.1 -> DTS 5.1 warm.
 *
 * The process creates and destroys its OWN pipelines ending in fakesink.
 * No hooks into another process; no user movie; no audio files, no PCM
 * samples printed; no ALSA, media services, firmware or registry changes.
 *
 * Invocation: r330-sequence /tmp/aleks-r330-XXX/stereo.mka
 *              /tmp/aleks-r330-XXX/ac3.mka
 *              /tmp/aleks-r330-XXX/surround.mka
 * SPDX-License-Identifier: MIT
 */
#define _POSIX_C_SOURCE 200809L
#include <gst/gst.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

typedef struct {
  guint64 compressed_buffers, dts_be16_frames, ac3_sync_frames;
  guint64 stream_start, caps, segment_time, segment_bytes;
  guint64 missing_pts, order_errors;
  guint64 pcm_buffers, pcm_samples, pcm_nonzero, pcm_peak;
  gdouble square_total;
  gboolean saw_stream, saw_caps, saw_segment, saw_s16le;
  gint channels, rate;
  guint wrong_pcm_buffer;
  guint map_failures;
} Stats;

typedef struct {
  const char *tag;
  const char *media;
  const char *path;
  guint channels;
  gboolean is_dts;
} Phase;

static GstPadProbeReturn compressed_probe(GstPad *p, GstPadProbeInfo *info, gpointer ctx) {
  (void)p;
  Stats *s = ctx;
  if (GST_PAD_PROBE_INFO_TYPE(info) & GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM) {
    GstEvent *ev = GST_PAD_PROBE_INFO_EVENT(info);
    switch (GST_EVENT_TYPE(ev)) {
      case GST_EVENT_STREAM_START:
        s->stream_start++;
        s->saw_stream = TRUE;
        s->saw_caps = s->saw_segment = FALSE;
        break;
      case GST_EVENT_CAPS:
        s->caps++;
        s->order_errors += !s->saw_stream;
        s->saw_caps = TRUE;
        break;
      case GST_EVENT_SEGMENT: {
        s->order_errors += !s->saw_stream || !s->saw_caps;
        const GstSegment *segment = NULL;
        gst_event_parse_segment(ev, &segment);
        if (segment && segment->format == GST_FORMAT_TIME) s->segment_time++;
        else s->segment_bytes++;
        s->saw_segment = TRUE;
        break;
      }
      case GST_EVENT_FLUSH_STOP: s->saw_segment = FALSE; break;
      default: break;
    }
    return GST_PAD_PROBE_OK;
  }
  if (!(GST_PAD_PROBE_INFO_TYPE(info) & GST_PAD_PROBE_TYPE_BUFFER)) return GST_PAD_PROBE_OK;
  s->order_errors += !s->saw_stream || !s->saw_caps || !s->saw_segment;
  GstBuffer *b = GST_PAD_PROBE_INFO_BUFFER(info);
  s->compressed_buffers++;
  if (!GST_BUFFER_PTS_IS_VALID(b)) s->missing_pts++;
  GstMapInfo map;
  if (!gst_buffer_map(b, &map, GST_MAP_READ)) {
    s->map_failures++;
    return GST_PAD_PROBE_OK;
  }
  if (map.size >= 4 && map.data[0] == 0x7f &&
      map.data[1] == 0xfe && map.data[2] == 0x80 && map.data[3] == 0x01)
    s->dts_be16_frames++;
  if (map.size >= 2 && map.data[0] == 0x0b && map.data[1] == 0x77)
    s->ac3_sync_frames++;
  gst_buffer_unmap(b, &map);
  return GST_PAD_PROBE_OK;
}

static GstPadProbeReturn pcm_probe(GstPad *p, GstPadProbeInfo *info, gpointer ctx) {
  (void)p;
  Stats *s = ctx;
  if (GST_PAD_PROBE_INFO_TYPE(info) & GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM) {
    GstEvent *ev = GST_PAD_PROBE_INFO_EVENT(info);
    if (GST_EVENT_TYPE(ev) == GST_EVENT_CAPS) {
      GstCaps *caps = NULL;
      gst_event_parse_caps(ev, &caps);
      if (caps && gst_caps_get_size(caps)) {
        const GstStructure *st = gst_caps_get_structure(caps, 0);
        const gchar *fmt = gst_structure_get_string(st, "format");
        s->saw_s16le = !g_strcmp0(gst_structure_get_name(st), "audio/x-raw") &&
                       !g_strcmp0(fmt, "S16LE");
        gst_structure_get_int(st, "channels", &s->channels);
        gst_structure_get_int(st, "rate", &s->rate);
      }
    }
    return GST_PAD_PROBE_OK;
  }
  if (!(GST_PAD_PROBE_INFO_TYPE(info) & GST_PAD_PROBE_TYPE_BUFFER)) return GST_PAD_PROBE_OK;
  GstBuffer *b = GST_PAD_PROBE_INFO_BUFFER(info);
  s->pcm_buffers++;
  GstMapInfo map;
  if (!b || !gst_buffer_map(b, &map, GST_MAP_READ)) {
    s->map_failures++;
    return GST_PAD_PROBE_OK;
  }
  if (!s->saw_s16le || (map.size & 1) || map.size > (2 * 1024 * 1024) ||
      s->pcm_samples + map.size/2 > 8 * 1024 * 1024) {
    s->wrong_pcm_buffer++;
    gst_buffer_unmap(b, &map);
    return GST_PAD_PROBE_OK;
  }
  for (gsize i = 0; i < map.size; i += 2) {
    const gint16 v = (gint16)((guint16)map.data[i] |
                          ((guint16)map.data[i+1] << 8));
    guint32 absval = v >= 0 ? (guint32)v : (guint32)(-(gint32)v);
    s->pcm_samples++;
    s->pcm_nonzero += (v != 0);
    if (absval > s->pcm_peak) s->pcm_peak = absval;
    s->square_total += (gdouble)v * (gdouble)v;
  }
  gst_buffer_unmap(b, &map);
  return GST_PAD_PROBE_OK;
}

static gboolean name_ok(const gchar *path, const char *basename) {
  if (!g_str_has_prefix(path, "/tmp/aleks-r330-")) return FALSE;
  for (const char *c = path; *c; c++)
    if (!(g_ascii_isalnum(*c) || *c == '/' || *c == '.' ||
          *c == '_' || *c == '-')) return FALSE;
  if (strstr(path, "..") || !g_str_has_suffix(path, basename)) return FALSE;
  struct stat st;
  if (lstat(path, &st) != 0 || !S_ISREG(st.st_mode) ||
      st.st_size < 1000 || st.st_size > 400000) return FALSE;
  return TRUE;
}

static gboolean run_phase(const Phase *phase, Stats *s) {
  /* No runtime callbacks modify other processes, sound or state. */
  gchar *pipeline_str = g_strdup_printf(
    "filesrc location=\"%s\" ! matroskademux name=dm "
    "dm.audio_0 ! queue ! decodebin name=decoder ! "
    "audioconvert ! audio/x-raw,format=S16LE,channels=%u,rate=48000 ! "
    "identity name=metric ! fakesink sync=false",
    phase->path, phase->channels);
  GError *error = NULL;
  GstElement *pipeline = gst_parse_launch(pipeline_str, &error);
  g_free(pipeline_str);
  if (!pipeline || error) {
    if (pipeline) gst_object_unref(pipeline);
    if (error) g_error_free(error);
    return FALSE;
  }
  GstElement *decoder = gst_bin_get_by_name(GST_BIN(pipeline), "decoder");
  GstElement *metric = gst_bin_get_by_name(GST_BIN(pipeline), "metric");
  GstPad *input = decoder ? gst_element_get_static_pad(decoder, "sink") : NULL;
  GstPad *output = metric ? gst_element_get_static_pad(metric, "src") : NULL;
  gboolean ok = FALSE;
  GstBus *bus = NULL;
  if (!input || !output) goto finish;
  gst_pad_add_probe(input, GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM |
      GST_PAD_PROBE_TYPE_BUFFER, compressed_probe, s, NULL);
  gst_pad_add_probe(output, GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM |
      GST_PAD_PROBE_TYPE_BUFFER, pcm_probe, s, NULL);
  bus = gst_element_get_bus(pipeline);
  if (gst_element_set_state(pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE)
    goto finish;
  GstMessage *message = gst_bus_timed_pop_filtered(bus, 12 * GST_SECOND,
                                   GST_MESSAGE_EOS | GST_MESSAGE_ERROR);
  if (!message) goto finish;
  ok = GST_MESSAGE_TYPE(message) == GST_MESSAGE_EOS;
  gst_message_unref(message);
finish:
  gst_element_set_state(pipeline, GST_STATE_NULL);
  if (bus) gst_object_unref(bus);
  if (input) gst_object_unref(input);
  if (output) gst_object_unref(output);
  if (decoder) gst_object_unref(decoder);
  if (metric) gst_object_unref(metric);
  gst_object_unref(pipeline);
  if (!ok || s->stream_start == 0 || s->caps == 0 ||
      s->segment_time == 0 || s->segment_bytes != 0 ||
      s->order_errors || s->map_failures || s->wrong_pcm_buffer ||
      !s->saw_s16le || s->channels != (gint)phase->channels ||
      s->rate != 48000 || s->pcm_samples == 0 || s->pcm_nonzero == 0)
    return FALSE;
  if (phase->is_dts) {
    if (s->compressed_buffers != 94 || s->dts_be16_frames != 94 ||
        s->pcm_samples != 94ULL * 512 * phase->channels ||
        s->missing_pts != 0) return FALSE;
  } else if (s->ac3_sync_frames == 0) return FALSE;
  return TRUE;
}

static void report(const Phase *phase, const Stats *s, gboolean pass) {
  const gdouble rms = s->pcm_samples ?
    sqrt(s->square_total / s->pcm_samples) : 0.0;
  printf("R330_STAGE=%s\n", phase->tag);
  printf("R330_STAGE_RESULT=%s\n", pass ? "PASS" : "FAIL");
  printf("R330_STAGE_INPUT_COMPRESSED=%" G_GUINT64_FORMAT "\n", s->compressed_buffers);
  printf("R330_STAGE_DTS_BE16=%" G_GUINT64_FORMAT "\n", s->dts_be16_frames);
  printf("R330_STAGE_AC3_SYNC=%" G_GUINT64_FORMAT "\n", s->ac3_sync_frames);
  printf("R330_STAGE_MISSING_PTS=%" G_GUINT64_FORMAT "\n", s->missing_pts);
  printf("R330_STAGE_EVENT_ORDER_ERRORS=%" G_GUINT64_FORMAT "\n", s->order_errors);
  printf("R330_STAGE_PCM_SAMPLES=%" G_GUINT64_FORMAT "\n", s->pcm_samples);
  printf("R330_STAGE_PCM_NONZERO=%" G_GUINT64_FORMAT "\n", s->pcm_nonzero);
  printf("R330_STAGE_PCM_RMS_DBFS=%.2f\n",
         rms > 0 ? 20 * log10(rms / 32768.0) : -999.0);
  printf("R330_STAGE_PCM_PEAK_DBFS=%.2f\n",
         s->pcm_peak ? 20 * log10(s->pcm_peak / 32768.0) : -999.0);
}
static gboolean same_dts(const Stats *a, const Stats *b) {
  if (a->compressed_buffers != b->compressed_buffers ||
      a->dts_be16_frames != b->dts_be16_frames ||
      a->missing_pts != b->missing_pts ||
      a->pcm_samples != b->pcm_samples ||
      a->pcm_nonzero != b->pcm_nonzero ||
      a->pcm_peak != b->pcm_peak) return FALSE;
  const gdouble diff = fabs(a->square_total - b->square_total);
  return diff < 1e-3;
}

int main(int argc, char **argv) {
  if (argc != 4 ||
      !name_ok(argv[1], "/stereo.mka") ||
      !name_ok(argv[2], "/ac3.mka") ||
      !name_ok(argv[3], "/surround.mka")) {
    puts("RESULT=R330_INVALID_FIXED_FIXTURES");
    return 2;
  }
  gst_init(&argc, &argv);
  const Phase phase[] = {
    {"DTS2_COLD", "dts2", argv[1], 2, TRUE},
    {"AC3_PRIME_1", "ac3", argv[2], 6, FALSE},
    {"DTS2_AFTER_AC3", "dts2", argv[1], 2, TRUE},
    {"DTS51_COLD", "dts51", argv[3], 6, TRUE},
    {"AC3_PRIME_2", "ac3", argv[2], 6, FALSE},
    {"DTS51_AFTER_AC3", "dts51", argv[3], 6, TRUE}
  };
  Stats results[G_N_ELEMENTS(phase)] = {{0}};
  gboolean all = TRUE;
  for (gsize i = 0; i < G_N_ELEMENTS(phase); i++) {
    gboolean ok = run_phase(&phase[i], &results[i]);
    report(&phase[i], &results[i], ok);
    if (!ok) { all = FALSE; break; }
  }
  gboolean eq2 = all && same_dts(&results[0], &results[2]);
  gboolean eq51 = all && same_dts(&results[3], &results[5]);
  printf("R330_DTS2_COLD_WARM_SAME_PCM=%s\n", eq2 ? "YES" : "NO");
  printf("R330_DTS51_COLD_WARM_SAME_PCM=%s\n", eq51 ? "YES" : "NO");
  printf("R330_EXTERNAL_STASFISH_ATTACH=NO\n");
  printf("R330_AUDIO_FILES_CREATED=0\n");
  printf("R330_ALSA_OUTPUT_MODIFIED=NO\n");
  printf("RESULT=%s\n",
         all && eq2 && eq51 ? "R330_ISOLATED_SEQUENTIAL_QA_PASS" :
                               "R330_ISOLATED_SEQUENTIAL_QA_FAIL");
  return all && eq2 && eq51 ? 0 : 1;
}
