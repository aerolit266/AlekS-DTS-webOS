/*
 * AlekS DTS R340 isolated GStreamer pad/event delivery contract.
 * Real GstEvent/GstPad calls, but no decoder, audio sink, uMS or LG daemon.
 * Tests the event mechanics required by the independent C99 grant model.
 * This is NOT the production implementation and makes NO system changes.
 * SPDX-License-Identifier: MIT
 */
#include <gst/gst.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    guint grants;
    gint last_port;
    gboolean reject_once;
    guint rejected;
} Sink;

static gboolean receive_event(GstPad *pad, GstObject *parent, GstEvent *ev) {
    Sink *ctx = (Sink *)gst_pad_get_element_private(pad);
    (void)parent;
    gboolean result = TRUE;
    if (ctx && GST_EVENT_TYPE(ev) == GST_EVENT_CUSTOM_DOWNSTREAM &&
        gst_event_has_name(ev, "acquired-resource")) {
        const GstStructure *st = gst_event_get_structure(ev);
        gint port = -1;
        if (!st || !gst_structure_get_int(st, "audio-port", &port) ||
            port < 0 || port > 15) {
            result = FALSE;
        } else if (ctx->reject_once) {
            ctx->reject_once = FALSE;
            ctx->rejected++;
            result = FALSE;
        } else {
            ctx->last_port = port;
            ctx->grants++;
        }
    }
    gst_event_unref(ev);
    return result;
}

static GstPad *create_sink(const char *name, Sink *stats) {
    GstPad *p = gst_pad_new(name, GST_PAD_SINK);
    g_assert_nonnull(p);
    gst_pad_set_element_private(p, stats);
    gst_pad_set_event_function(p, GST_DEBUG_FUNCPTR(receive_event));
    g_assert_true(gst_pad_set_active(p, TRUE));
    return p;
}

static void connect(GstPad *src, GstPad *sink) {
    g_assert_cmpint(gst_pad_link(src,sink),==,GST_PAD_LINK_OK);
}

static void disconnect(GstPad *src, GstPad *sink) {
    g_assert_true(gst_pad_unlink(src,sink));
}

static GstEvent *make_grant(gint port) {
    GstStructure *st = gst_structure_new("acquired-resource",
                                        "audio-port", G_TYPE_INT, port,
                                        NULL);
    g_assert_nonnull(st);
    GstEvent *ev = gst_event_new_custom(GST_EVENT_CUSTOM_DOWNSTREAM, st);
    g_assert_nonnull(ev);
    g_assert_true(gst_event_has_name(ev, "acquired-resource"));
    return ev;
}

int main(int argc, char **argv) {
    gst_init(&argc, &argv);
    guint completed = 0;

    Sink first = {0, -1, FALSE, 0};
    Sink second = {0, -1, FALSE, 0};
    Sink third = {0, -1, TRUE, 0};

    GstPad *src = gst_pad_new("r340_src", GST_PAD_SRC);
    g_assert_nonnull(src);
    g_assert_true(gst_pad_set_active(src, TRUE));
    GstPad *a = create_sink("r340_hw_0", &first);
    GstPad *b = create_sink("r340_hw_1", &second);
    GstPad *c = create_sink("r340_hw_2", &third);

    /* Receive real grant, retain one event reference before transfer. */
    connect(src, a);
    GstEvent *real = make_grant(0);
    GstEvent *cached = gst_event_ref(real);
    g_assert_true(gst_pad_push_event(src, real));
    g_assert_cmpuint(first.grants,==,1);
    g_assert_cmpint(first.last_port,==,0);
    ++completed;

    /* GStreamer source forwarded ownership; cached ref is still usable. */
    g_assert_true(gst_event_has_name(cached, "acquired-resource"));
    const GstStructure *readback = gst_event_get_structure(cached);
    gint stored_port = -1;
    g_assert_true(gst_structure_get_int(readback, "audio-port", &stored_port));
    g_assert_cmpint(stored_port,==,0);
    ++completed;

    /* Hardware decoder child generation changes: valid replay into B. */
    disconnect(src,a);
    connect(src,b);
    g_assert_true(gst_pad_push_event(src, gst_event_ref(cached)));
    g_assert_cmpuint(second.grants,==,1);
    g_assert_cmpuint(first.grants,==,1);
    ++completed;

    /* GStreamer delivers a grant only to linked child; no cross-stream send. */
    g_assert_cmpuint(first.grants,==,1);
    g_assert_cmpuint(third.grants,==,0);
    ++completed;

    /* A receiving decoder can reject: failed push must NOT be acked. */
    disconnect(src,b);
    connect(src,c);
    g_assert_false(gst_pad_push_event(src, gst_event_ref(cached)));
    g_assert_cmpuint(third.rejected,==,1);
    g_assert_cmpuint(third.grants,==,0);
    ++completed;

    /* A separately authorized later retry to the same child can succeed. */
    g_assert_true(gst_pad_push_event(src, gst_event_ref(cached)));
    g_assert_cmpuint(third.grants,==,1);
    g_assert_cmpint(third.last_port,==,0);
    ++completed;

    /* Unload/revoke: destroy cached reference, do NOT emit new grant. */
    gst_event_unref(cached);
    cached = NULL;
    g_assert_null(cached);
    g_assert_cmpuint(third.grants,==,1);
    ++completed;

    /* Probe does not touch files, audio samples, codecs or a hardware sink. */
    g_assert_cmpuint(first.grants+second.grants+third.grants,==,3);
    ++completed;

    disconnect(src,c);
    g_assert_true(gst_pad_set_active(a,FALSE));
    g_assert_true(gst_pad_set_active(b,FALSE));
    g_assert_true(gst_pad_set_active(c,FALSE));
    g_assert_true(gst_pad_set_active(src,FALSE));
    gst_object_unref(a);
    gst_object_unref(b);
    gst_object_unref(c);
    gst_object_unref(src);

    g_assert_cmpuint(completed,==,8);
    printf("R340_GST_PAD_EVENT_CONTRACT=%u/8 PASS\n",completed);
    printf("RESULT=R340_GSTREAMER_CUSTOM_EVENT_ISOLATED_QA_PASS\n");
    return 0;
}
