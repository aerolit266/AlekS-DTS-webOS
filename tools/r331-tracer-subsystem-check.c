/*
 * R331: native GStreamer tracing subsystem activation diagnostics.
 * Only observes the factories and active tracer objects in this
 * isolated process. Never attaches to another process or records audio.
 * Usage: r331-tracer-subsystem-check
 * SPDX-License-Identifier: MIT
 */
#include <gst/gst.h>
#include <gst/gsttracer.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
  if (argc != 1) return 2;
  gst_init(&argc, &argv);
  GList *active = gst_tracing_get_active_tracers();
  GList *factories = gst_tracer_factory_get_list();
  unsigned active_count = 0, r331_count = 0, factories_count = 0;
  for (GList *n = active; n; n=n->next) {
    active_count++;
    GstTracer *tracer = GST_TRACER(n->data);
    const gchar *type = G_OBJECT_TYPE_NAME(tracer);
    if (type && g_strcmp0(type, "AlekSR331Tracer") == 0)
      r331_count++;
  }
  for (GList *n = factories; n; n=n->next) {
    factories_count++;
  }
  printf("R331_GST_ACTIVE_TRACER_COUNT=%u\n",active_count);
  printf("R331_GST_ACTIVE_ALEKS_TRACER_COUNT=%u\n",r331_count);
  printf("R331_GST_KNOWN_TRACER_FACTORIES=%u\n",factories_count);
  printf("R331_GST_PROCESS_LIVE_STARFISH=NO\n");
  printf("RESULT=R331_GST_TRACING_SUBSYSTEM_OBSERVED\n");
  g_list_free_full(factories,(GDestroyNotify)gst_object_unref);
  g_list_free_full(active,(GDestroyNotify)gst_object_unref);
  return 0;
}
