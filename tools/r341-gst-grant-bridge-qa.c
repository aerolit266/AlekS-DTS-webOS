/*
 * AlekS DTS R341 isolated GStreamer bridge regression.
 * Virtual pads only: no LG device, decoder, PCM, sink hardware or uMS.
 * SPDX-License-Identifier: MIT
 */
#include "r341-gst-grant-bridge.h"
#include <stdio.h>

typedef struct {
    guint accepted, rejected;
    gint last_port;
    gboolean reject_once, always_reject, release_during_event;
    R341Bridge *bridge;
} Sink;

static gboolean on_event(GstPad *pad, GstObject *parent, GstEvent *event) {
    Sink *s = (Sink *)gst_pad_get_element_private(pad);
    gboolean result = TRUE;
    (void)parent;
    if (GST_EVENT_TYPE(event) == GST_EVENT_CUSTOM_DOWNSTREAM &&
        gst_event_has_name(event, "acquired-resource")) {
        gint port = -1;
        const GstStructure *st = gst_event_get_structure(event);
        if (!s || !st || !gst_structure_get_int(st, "audio-port", &port)) {
            result = FALSE;
        } else if (s->reject_once || s->always_reject) {
            s->reject_once = FALSE;
            ++s->rejected;
            result = FALSE;
        } else {
            ++s->accepted;
            s->last_port = port;
            if (s->release_during_event && s->bridge)
                r341_release(s->bridge);
        }
    }
    gst_event_unref(event);
    return result;
}

static GstPad *pad_new(GstPadDirection direction, Sink *sink) {
    GstPad *p = gst_pad_new(NULL, direction);
    g_assert_nonnull(p);
    if (direction == GST_PAD_SINK) {
        gst_pad_set_element_private(p, sink);
        gst_pad_set_event_function(p, GST_DEBUG_FUNCPTR(on_event));
    }
    g_assert_true(gst_pad_set_active(p, TRUE));
    return p;
}

static void link_pads(GstPad *src, GstPad *sink) {
    g_assert_cmpint(gst_pad_link(src, sink), ==, GST_PAD_LINK_OK);
}
static void unlink_pads(GstPad *src, GstPad *sink) {
    g_assert_true(gst_pad_unlink(src, sink));
}
static GstEvent *grant(gint port) {
    return gst_event_new_custom(GST_EVENT_CUSTOM_DOWNSTREAM,
        gst_structure_new("acquired-resource", "audio-port", G_TYPE_INT, port, NULL));
}
static guint64 remember(R341Bridge *b, gint port) {
    GstEvent *ev = grant(port);
    guint64 token = r341_observe_real_grant(b, ev);
    gst_event_unref(ev);
    return token;
}

static guint tests = 0;
#define PASS(msg) do { ++tests; g_print("R341_QA_%02u=%s PASS\n", tests, msg); } while(0)

int main(int argc, char **argv) {
    gst_init(&argc, &argv);
    R341Bridge b;
    r341_init(&b);
    GstPad *src = pad_new(GST_PAD_SRC, NULL);
    Sink a = {0, 0, -1, FALSE, FALSE, FALSE, NULL};
    Sink c = {0, 0, -1, FALSE, FALSE, FALSE, NULL};
    Sink d = {0, 0, -1, FALSE, FALSE, FALSE, NULL};
    GstPad *sink_a = pad_new(GST_PAD_SINK, &a);
    GstPad *sink_c = pad_new(GST_PAD_SINK, &c);
    GstPad *sink_d = pad_new(GST_PAD_SINK, &d);

    /* No grant before load, even if the event looks valid. */
    g_assert_cmpuint(remember(&b, 0), ==, 0);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_SKIP);
    PASS("DENY_BEFORE_LOAD");

    g_assert_true(r341_load(&b, src));
    g_assert_false(r341_load(&b, src));
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_SKIP);
    PASS("EXACTLY_ONE_LOAD");

    GstEvent *invalid = gst_event_new_custom(GST_EVENT_CUSTOM_UPSTREAM,
        gst_structure_new_empty("acquired-resource"));
    g_assert_cmpuint(r341_observe_real_grant(&b, invalid), ==, 0);
    gst_event_unref(invalid);
    invalid = gst_event_new_custom(GST_EVENT_CUSTOM_DOWNSTREAM,
        gst_structure_new("acquired-resource", "audio-port", G_TYPE_STRING, "0", NULL));
    g_assert_cmpuint(r341_observe_real_grant(&b, invalid), ==, 0);
    gst_event_unref(invalid);
    g_assert_cmpuint(remember(&b, -1), ==, 0);
    g_assert_cmpuint(remember(&b, 16), ==, 0);
    g_assert_null(b.cached_event);
    PASS("VALIDATED_AUTHENTIC_EVENT");

    /* Keep original event pointer and only replay to the new hardware child. */
    guint64 t = remember(&b, 0);
    g_assert_cmpuint(t, >, 0);
    r341_child_new(&b, FALSE); /* software AlekS DTS decoder */
    link_pads(src, sink_a);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_SKIP);
    g_assert_cmpuint(a.accepted, ==, 0);
    PASS("SOFTWARE_DECODER_NO_HW_GRANT");

    r341_child_gone(&b);
    r341_child_new(&b, TRUE);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_ACCEPTED);
    g_assert_cmpuint(a.accepted, ==, 1);
    g_assert_cmpint(a.last_port, ==, 0);
    PASS("EARLY_GRANT_LATE_CHILD");

    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_SKIP);
    r341_child_new(&b, TRUE); /* duplicate signal must do nothing */
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_SKIP);
    g_assert_cmpuint(a.accepted, ==, 1);
    PASS("NO_DUPLICATE_ACCEPTED_GRANT");

    r341_child_gone(&b);
    unlink_pads(src, sink_a);
    link_pads(src, sink_c);
    r341_child_new(&b, TRUE);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_ACCEPTED);
    g_assert_cmpuint(a.accepted, ==, 1);
    g_assert_cmpuint(c.accepted, ==, 1);
    PASS("CHILD_SWAP_NO_CROSS_SINK");

    /* Flush denies delivery but does not fabricate a new grant. */
    r341_child_gone(&b);
    r341_flush_start(&b);
    r341_child_new(&b, TRUE);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_SKIP);
    r341_flush_stop(&b);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_ACCEPTED);
    g_assert_cmpuint(c.accepted, ==, 2);
    PASS("FLUSH_LIFECYCLE");

    /* Reject once, then explicitly retry; never auto-loop. */
    r341_child_gone(&b);
    r341_child_new(&b, TRUE);
    c.reject_once = TRUE;
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_REJECTED);
    g_assert_cmpuint(c.rejected, ==, 1);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_ACCEPTED);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_SKIP);
    PASS("REJECT_AND_EXPLICIT_RETRY");

    r341_child_gone(&b);
    r341_child_new(&b, TRUE);
    c.always_reject = TRUE;
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_REJECTED);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_REJECTED);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_SKIP);
    c.always_reject = FALSE;
    PASS("RETRY_CAP_TWO");

    /* Confirm a real event that went through normal GStreamer delivery. */
    r341_child_gone(&b);
    r341_child_new(&b, TRUE);
    GstEvent *real = grant(1);
    t = r341_observe_real_grant(&b, real);
    const guint64 epoch = b.epoch, generation = b.generation;
    g_assert_true(gst_pad_push_event(src, real)); /* consumes original */
    g_assert_true(r341_original_ack(&b, epoch, generation, t, TRUE));
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_SKIP);
    g_assert_cmpint(c.last_port, ==, 1);
    PASS("ORIGINAL_FORWARD_ACK_PREVENTS_DUPLICATE");

    r341_child_gone(&b);
    r341_child_new(&b, TRUE);
    g_assert_false(r341_original_ack(&b, epoch, generation, t, TRUE));
    g_assert_false(r341_original_ack(&b, epoch, b.generation, t+1, TRUE));
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_ACCEPTED);
    PASS("STALE_ACK_DENIED");

    /* Same GstEvent object is idempotent; different one is a real update. */
    GstEvent *same = grant(1);
    guint64 x = r341_observe_real_grant(&b, same);
    g_assert_cmpuint(r341_observe_real_grant(&b, same), ==, x);
    gst_event_unref(same);
    g_assert_cmpuint(x, >, t);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_ACCEPTED);
    PASS("OBJECT_DEDUP_AND_NEW_GRANT");

    r341_release(&b);
    r341_child_gone(&b);
    r341_child_new(&b, TRUE);
    g_assert_null(b.cached_event);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_SKIP);
    PASS("RELEASE_INVALIDATES_GRANT");

    g_assert_cmpuint(remember(&b, 0), >, 0);
    r341_suspend(&b);
    g_assert_null(b.cached_event);
    r341_resume(&b);
    r341_child_new(&b, TRUE);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_SKIP);
    PASS("POLICY_REVOKE_REQUIRES_NEW_GRANT");

    g_assert_cmpuint(remember(&b, 2), >, 0);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_ACCEPTED);
    g_assert_cmpint(c.last_port, ==, 2);
    PASS("NEW_VALID_GRANT_AFTER_RESUME");

    /* Re-entrancy: release inside the sink must defeat post-ACK mutation. */
    r341_child_gone(&b);
    r341_child_new(&b, TRUE);
    c.bridge = &b;
    c.release_during_event = TRUE;
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_STALE);
    g_assert_null(b.cached_event);
    c.release_during_event = FALSE;
    PASS("REENTRANT_RELEASE_SUPPRESSES_STALE_ACK");

    /* Another pipeline, another bridge: event MUST NOT leak. */
    R341Bridge b2;
    r341_init(&b2);
    GstPad *src2 = pad_new(GST_PAD_SRC, NULL);
    Sink other = {0, 0, -1, FALSE, FALSE, FALSE, NULL};
    GstPad *sink2 = pad_new(GST_PAD_SINK, &other);
    g_assert_true(r341_load(&b2, src2));
    link_pads(src2, sink2);
    r341_child_new(&b2, TRUE);
    g_assert_cmpint(r341_replay(&b2), ==, R341_REPLAY_SKIP);
    g_assert_cmpuint(other.accepted, ==, 0);
    PASS("PIPELINE_ISOLATION");

    /* No usable cache survives a new load epoch, even with a fresh child. */
    g_assert_cmpuint(remember(&b, 0), >, 0);
    guint64 prior_epoch = b.epoch;
    r341_unload(&b);
    g_assert_true(r341_load(&b, src));
    g_assert_cmpuint(b.epoch, !=, prior_epoch);
    r341_child_new(&b, TRUE);
    g_assert_cmpint(r341_replay(&b), ==, R341_REPLAY_SKIP);
    PASS("UNLOAD_RELOAD_EPOCH_ISOLATION");

    /* Other source/sink unchanged: not a real device, only pad test objects. */
    g_assert_cmpuint(a.accepted, ==, 1);
    g_assert_cmpuint(other.accepted, ==, 0);
    PASS("NO_EXTERNAL_PIPELINE_TRAFFIC");

    r341_unload(&b2);
    r341_unload(&b);
    unlink_pads(src2, sink2);
    unlink_pads(src, sink_c);
    gst_pad_set_active(src, FALSE);
    gst_pad_set_active(src2, FALSE);
    gst_pad_set_active(sink_a, FALSE);
    gst_pad_set_active(sink_c, FALSE);
    gst_pad_set_active(sink_d, FALSE);
    gst_pad_set_active(sink2, FALSE);
    gst_object_unref(src);
    gst_object_unref(src2);
    gst_object_unref(sink_a);
    gst_object_unref(sink_c);
    gst_object_unref(sink_d);
    gst_object_unref(sink2);

    g_assert_cmpuint(tests, ==, 20);
    g_print("R341_GSTREAMER_BRIDGE_QA=%u/20 PASS\n", tests);
    return 0;
}