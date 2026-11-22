/*
 * AlekS DTS R341 isolated GstEvent adapter API.
 * LAB ONLY: no ABI/API integration with proprietary GstDecProxy.
 * SPDX-License-Identifier: MIT
 */
#ifndef ALEKS_R341_GST_GRANT_BRIDGE_H
#define ALEKS_R341_GST_GRANT_BRIDGE_H
#include <gst/gst.h>

typedef enum {
    R341_REPLAY_SKIP = 0,
    R341_REPLAY_ACCEPTED,
    R341_REPLAY_REJECTED,
    R341_REPLAY_STALE
} R341Replay;

typedef struct {
    GstPad *src;               /* Ref owned by this bridge; ONE pipeline only */
    GstEvent *cached_event;    /* Retained ORIGINAL real custom GstEvent */
    guint64 epoch, generation, serial;
    guint64 delivered_generation, delivered_serial;
    gint grant_port;
    guint tries;
    gboolean loaded, child_exists, hardware_child, flushing, suspended;
} R341Bridge;

void r341_init(R341Bridge *bridge);
gboolean r341_load(R341Bridge *bridge, GstPad *pipeline_src);
void r341_unload(R341Bridge *bridge);
guint64 r341_observe_real_grant(R341Bridge *bridge, GstEvent *event);
gboolean r341_original_ack(R341Bridge *bridge, guint64 epoch,
                           guint64 generation, guint64 serial,
                           gboolean accepted);
void r341_child_gone(R341Bridge *bridge);
void r341_child_new(R341Bridge *bridge, gboolean is_hardware_decoder);
void r341_release(R341Bridge *bridge);
void r341_flush_start(R341Bridge *bridge);
void r341_flush_stop(R341Bridge *bridge);
void r341_suspend(R341Bridge *bridge);
void r341_resume(R341Bridge *bridge);
R341Replay r341_replay(R341Bridge *bridge);
#endif