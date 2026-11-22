/*
 * AlekS DTS R341: isolated resource-grant bridge (no webOS/decproxy hook).
 * Strictly one uMS pipeline per bridge instance; the caller must invoke all
 * methods on the SAME serialized GStreamer control thread.
 *
 * An actual acquired-resource custom downstream event is borrowed on observe,
 * then retained via gst_event_ref; no grant is synthesized. The original event
 * continues through the ordinary upstream path. After a new HARDWARE child is
 * linked and ready, replay goes through that pipeline's own source pad.
 *
 * The caller must report the original event's delivery ACK with the matching
 * generation/serial; otherwise duplicate delivery is possible.
 * Not a deployment-ready fix: integration with LG decproxy is unverified.
 * SPDX-License-Identifier: MIT
 */
#include "r341-gst-grant-bridge.h"

static guint64 advance(guint64 x) {
    return (x == G_MAXUINT64) ? 1 : x + 1;
}

static void drop_grant(R341Bridge *b) {
    if (b->cached_event) {
        gst_event_unref(b->cached_event);
        b->cached_event = NULL;
    }
    b->grant_port = -1;
    b->delivered_generation = 0;
    b->delivered_serial = 0;
    b->tries = 0;
}

void r341_init(R341Bridge *b) {
    g_return_if_fail(b != NULL);
    *b = (R341Bridge){0};
    b->grant_port = -1;
}

/* load() must be called only for the source pad owned by this pipeline. */
gboolean r341_load(R341Bridge *b, GstPad *src) {
    g_return_val_if_fail(b != NULL, FALSE);
    g_return_val_if_fail(GST_IS_PAD(src), FALSE);
    if (GST_PAD_DIRECTION(src) != GST_PAD_SRC) return FALSE;
    if (b->loaded) return FALSE;
    b->epoch = advance(b->epoch);
    b->src = gst_object_ref(src);
    b->loaded = TRUE;
    b->flushing = FALSE;
    b->suspended = FALSE;
    b->generation = 0;
    b->serial = 0;
    b->child_exists = FALSE;
    b->hardware_child = FALSE;
    drop_grant(b);
    return TRUE;
}

void r341_unload(R341Bridge *b) {
    g_return_if_fail(b != NULL);
    drop_grant(b);
    if (b->src) {
        gst_object_unref(b->src);
        b->src = NULL;
    }
    b->loaded = FALSE;
    b->child_exists = FALSE;
    b->hardware_child = FALSE;
    b->flushing = FALSE;
    b->suspended = FALSE;
    b->generation = 0;
    b->serial = 0;
    b->epoch = advance(b->epoch);
}

/* Zero means rejected; nonzero token is valid only until release/new grant. */
guint64 r341_observe_real_grant(R341Bridge *b, GstEvent *event) {
    g_return_val_if_fail(b != NULL, 0);
    if (!b->loaded || b->suspended || !event ||
        GST_EVENT_TYPE(event) != GST_EVENT_CUSTOM_DOWNSTREAM ||
        !gst_event_has_name(event, "acquired-resource"))
        return 0;
    const GstStructure *st = gst_event_get_structure(event);
    gint port = -1;
    if (!st || !gst_structure_get_int(st, "audio-port", &port) ||
        port < 0 || port > 15) return 0;

    /* A second observe of the same object is not a second grant. */
    if (event == b->cached_event) return b->serial;
    GstEvent *new_ref = gst_event_ref(event);
    drop_grant(b);
    b->cached_event = new_ref;
    b->grant_port = port;
    b->serial = advance(b->serial);
    return b->serial;
}

/* Must be called AFTER normal gst_pad_push_event returned. */
gboolean r341_original_ack(R341Bridge *b, guint64 epoch,
                           guint64 generation, guint64 serial,
                           gboolean accepted) {
    g_return_val_if_fail(b != NULL, FALSE);
    if (!b->loaded || !b->cached_event || !b->child_exists ||
        !b->hardware_child || b->flushing || b->suspended ||
        b->epoch != epoch || b->generation != generation ||
        b->serial != serial)
        return FALSE;
    if (accepted) {
        b->delivered_generation = generation;
        b->delivered_serial = serial;
    }
    return TRUE;
}

void r341_child_gone(R341Bridge *b) {
    g_return_if_fail(b != NULL);
    if (!b->loaded) return;
    b->child_exists = FALSE;
    b->hardware_child = FALSE;
    b->delivered_generation = 0;
    b->delivered_serial = 0;
    b->tries = 0;
}

void r341_child_new(R341Bridge *b, gboolean hardware) {
    g_return_if_fail(b != NULL);
    if (!b->loaded || b->suspended || b->child_exists) return;
    b->generation = advance(b->generation);
    b->child_exists = TRUE;
    b->hardware_child = !!hardware;
    b->delivered_generation = 0;
    b->delivered_serial = 0;
    b->tries = 0;
}

void r341_release(R341Bridge *b) {
    g_return_if_fail(b != NULL);
    drop_grant(b);
}

void r341_flush_start(R341Bridge *b) {
    g_return_if_fail(b != NULL);
    b->flushing = TRUE;
}
void r341_flush_stop(R341Bridge *b) {
    g_return_if_fail(b != NULL);
    b->flushing = FALSE;
}
void r341_suspend(R341Bridge *b) {
    g_return_if_fail(b != NULL);
    drop_grant(b);
    b->child_exists = FALSE;
    b->hardware_child = FALSE;
    b->suspended = TRUE;
}
void r341_resume(R341Bridge *b) {
    g_return_if_fail(b != NULL);
    b->suspended = FALSE;  /* A new real grant remains mandatory. */
}

/*
 * Exactly one explicit replay attempt on link-ready, optionally one explicit
 * retry on sink refusal. No background/event-loop retry or auto-resume.
 */
R341Replay r341_replay(R341Bridge *b) {
    g_return_val_if_fail(b != NULL, R341_REPLAY_SKIP);
    if (!b->loaded || b->suspended || b->flushing || !b->cached_event ||
        !b->child_exists || !b->hardware_child || !b->src ||
        !gst_pad_is_active(b->src) || !gst_pad_is_linked(b->src) ||
        (b->delivered_generation == b->generation &&
         b->delivered_serial == b->serial) || b->tries >= 2)
        return R341_REPLAY_SKIP;

    const guint64 epoch = b->epoch, generation = b->generation, serial = b->serial;
    GstEvent *out = gst_event_ref(b->cached_event);
    b->tries++;
    const gboolean ok = gst_pad_push_event(b->src, out); /* consumes out */

    /* Event callback may have released or unloaded this bridge re-entrantly. */
    if (!b->loaded || b->epoch != epoch || b->generation != generation ||
        b->serial != serial || !b->cached_event || b->suspended ||
        b->flushing || !b->child_exists || !b->hardware_child)
        return R341_REPLAY_STALE;
    if (ok) {
        b->delivered_generation = generation;
        b->delivered_serial = serial;
        return R341_REPLAY_ACCEPTED;
    }
    return R341_REPLAY_REJECTED;
}