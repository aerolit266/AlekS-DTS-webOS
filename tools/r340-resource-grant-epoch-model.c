/*
 * AlekS DTS R340: resource-grant replay decision model (OFF-DEVICE LAB ONLY).
 *
 * Hypothesis under test: uMS may issue a one-time acquired-resource grant
 * before a decoder child exists; a newly created decoder needs the cached
 * grant, including after AC3 <-> DTS track selection.
 *
 * This is a bounded, pure C99 STATE MODEL; it does NOT inject a GStreamer
 * event or open an ALSA/OMX device. Do not treat test PASS as an LG fix.
 *
 * Contract: never manufacture a grant; only replay an already observed
 * grant in the SAME loaded pipeline epoch, on a NEW decoder generation,
 * after the previous child has been removed. One unacknowledged delivery
 * is pending at most. Failed/stale acknowledgments cannot mark success.
 * STREAM_START and FLUSH do not revoke a pipeline grant; only a genuine
 * RELEASE/UNLOAD does. No user media bytes or identifiers are retained.
 *
 * SPDX-License-Identifier: MIT
 */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef enum {
    R340_LOAD, R340_UNLOAD, R340_STREAM_START, R340_DTS_CAPS,
    R340_AC3_CAPS, R340_GRANT, R340_RELEASE, R340_CHILD_NEW,
    R340_CHILD_GONE, R340_FLUSH_START, R340_FLUSH_STOP
} R340_Event;

typedef enum {
    R340_NONE = 0, R340_FORWARD_ORIGINAL_GRANT, R340_REPLAY_CACHED_GRANT
} R340_Action;

typedef struct {
    R340_Action action;
    uint32_t epoch;
    uint32_t generation;
    uint32_t grant_version;
    int port;
} R340_Decision;

typedef struct {
    uint32_t epoch, generation, grant_version;
    uint32_t delivered_gen, delivered_version;
    uint32_t pending_gen, pending_version;
    uint32_t deliveries, accepted, rejected, stale_acks, replayed;
    bool loaded, child, grant, flushing, pending;
    int port, codec;
} R340_State;

static uint32_t advance(uint32_t old) {
    return old == UINT32_MAX ? 1u : old + 1u;
}

static void reset(R340_State *s) {
    uint32_t next_epoch = advance(s->epoch);
    memset(s, 0, sizeof(*s));
    s->epoch = next_epoch;
    s->port = -1;
}

static R340_Decision none(void) {
    R340_Decision d = {R340_NONE, 0, 0, 0, -1};
    return d;
}

static bool delivered(const R340_State *s) {
    return s->delivered_gen == s->generation &&
           s->delivered_version == s->grant_version &&
           s->generation != 0 && s->grant_version != 0;
}

static R340_Decision maybe_issue(R340_State *s, bool from_grant) {
    R340_Decision d = none();
    if (!s->loaded || !s->child || !s->grant || s->flushing ||
        s->pending || delivered(s))
        return d;
    s->pending = true;
    s->pending_gen = s->generation;
    s->pending_version = s->grant_version;
    ++s->deliveries;
    d.action = from_grant ? R340_FORWARD_ORIGINAL_GRANT :
                            R340_REPLAY_CACHED_GRANT;
    d.epoch = s->epoch;
    d.generation = s->generation;
    d.grant_version = s->grant_version;
    d.port = s->port;
    if (!from_grant) ++s->replayed;
    return d;
}

static R340_Decision apply(R340_State *s, R340_Event event, int port) {
    assert(s != NULL);
    R340_Decision result = none();
    if (event == R340_LOAD) {
        reset(s);
        s->loaded = true;
        return result;
    }
    if (event == R340_UNLOAD) {
        reset(s);
        return result;
    }
    if (!s->loaded) return result;
    switch (event) {
        case R340_STREAM_START:
            /* Same uMS pipeline: a stream switch is NOT a resource release. */
            break;
        case R340_DTS_CAPS: s->codec = 1; break;
        case R340_AC3_CAPS: s->codec = 2; break;
        case R340_GRANT:
            if (port < 0 || port > 15) return result;
            if (!s->grant || s->port != port) {
                s->grant_version = advance(s->grant_version);
                s->pending = false;
                s->delivered_version = 0;
            }
            s->grant = true;
            s->port = port;
            return maybe_issue(s, true);
        case R340_RELEASE:
            s->grant = false;
            s->port = -1;
            s->pending = false;
            s->pending_gen = 0;
            s->pending_version = 0;
            s->delivered_gen = 0;
            s->delivered_version = 0;
            break;
        case R340_CHILD_GONE:
            s->child = false;
            s->pending = false;
            s->pending_gen = 0;
            s->pending_version = 0;
            s->delivered_gen = 0;
            s->delivered_version = 0;
            break;
        case R340_CHILD_NEW:
            if (s->child) {
                /* Never generate an extra grant for duplicate child signals. */
                return result;
            }
            s->child = true;
            s->generation = advance(s->generation);
            return maybe_issue(s, false);
        case R340_FLUSH_START:
            s->flushing = true;
            /* Pending delivery is invalid after a flush; still keep grant. */
            s->pending = false;
            break;
        case R340_FLUSH_STOP:
            s->flushing = false;
            return maybe_issue(s, false);
        case R340_LOAD:
        case R340_UNLOAD: break;
    }
    return result;
}

static bool acknowledge(R340_State *s, R340_Decision d, bool accepted) {
    if (d.action == R340_NONE || !s->loaded || !s->child ||
        !s->grant || !s->pending || s->flushing ||
        s->epoch != d.epoch || s->generation != d.generation ||
        s->grant_version != d.grant_version ||
        s->port != d.port || s->pending_gen != d.generation ||
        s->pending_version != d.grant_version) {
        ++s->stale_acks;
        return false;
    }
    s->pending = false;
    if (accepted) {
        s->delivered_gen = d.generation;
        s->delivered_version = d.grant_version;
        ++s->accepted;
    } else {
        ++s->rejected;
    }
    return true;
}

static void invariants(const R340_State *s) {
    assert(s->epoch > 0);
    assert(!s->pending || (s->loaded && s->child && s->grant));
    assert(!s->pending || (s->pending_gen == s->generation &&
                           s->pending_version == s->grant_version));
    assert(!s->grant || (s->loaded && s->port >= 0 && s->port <= 15));
    assert(s->accepted <= s->deliveries);
    assert(s->replayed <= s->deliveries);
    assert(!s->child || s->loaded);
}

static void unit(void) {
    R340_State s = {0};
    R340_Decision d;
    unsigned pass = 0;

    /* Cold DTS CAPS before grant; genuine late grant is sent once. */
    apply(&s, R340_LOAD, 0);
    apply(&s, R340_STREAM_START, 0);
    apply(&s, R340_DTS_CAPS, 0);
    d = apply(&s, R340_CHILD_NEW, 0);
    assert(d.action == R340_NONE);
    d = apply(&s, R340_GRANT, 0);
    assert(d.action == R340_FORWARD_ORIGINAL_GRANT && d.port == 0);
    assert(acknowledge(&s, d, true));
    assert(apply(&s, R340_GRANT, 0).action == R340_NONE);
    ++pass;

    /* AC3 switch replaces decoder; cache grant once for child generation. */
    apply(&s, R340_CHILD_GONE, 0);
    apply(&s, R340_STREAM_START, 0);
    apply(&s, R340_AC3_CAPS, 0);
    d = apply(&s, R340_CHILD_NEW, 0);
    assert(d.action == R340_REPLAY_CACHED_GRANT && d.port == 0);
    assert(acknowledge(&s, d, true));
    assert(apply(&s, R340_CHILD_NEW, 0).action == R340_NONE);
    ++pass;

    /* DTS switch reuses same pipeline grant; 1 replay, no fake resource. */
    apply(&s, R340_CHILD_GONE, 0);
    apply(&s, R340_DTS_CAPS, 0);
    d = apply(&s, R340_CHILD_NEW, 0);
    assert(d.action == R340_REPLAY_CACHED_GRANT);
    assert(acknowledge(&s, d, true));
    assert(apply(&s, R340_STREAM_START, 0).action == R340_NONE);
    ++pass;

    /* Grant before first child is cached; no resource is invented. */
    apply(&s, R340_UNLOAD, 0);
    apply(&s, R340_LOAD, 0);
    assert(apply(&s, R340_GRANT, 0).action == R340_NONE);
    d = apply(&s, R340_CHILD_NEW, 0);
    assert(d.action == R340_REPLAY_CACHED_GRANT);
    assert(acknowledge(&s, d, true));
    ++pass;

    /* Simulated sink rejection does not mark grant delivered. */
    apply(&s, R340_CHILD_GONE, 0);
    d = apply(&s, R340_CHILD_NEW, 0);
    assert(d.action == R340_REPLAY_CACHED_GRANT);
    assert(acknowledge(&s, d, false));
    assert(!delivered(&s));
    d = apply(&s, R340_GRANT, 0);
    assert(d.action == R340_FORWARD_ORIGINAL_GRANT);
    assert(acknowledge(&s, d, true));
    ++pass;

    /* DELAY/flush suppresses delivery and does not drop the original grant. */
    apply(&s, R340_CHILD_GONE, 0);
    apply(&s, R340_FLUSH_START, 0);
    assert(apply(&s, R340_CHILD_NEW, 0).action == R340_NONE);
    d = apply(&s, R340_FLUSH_STOP, 0);
    assert(d.action == R340_REPLAY_CACHED_GRANT);
    assert(acknowledge(&s, d, true));
    ++pass;

    /* Stale acknowledgement after child teardown never confirms grant. */
    apply(&s, R340_CHILD_GONE, 0);
    d = apply(&s, R340_CHILD_NEW, 0);
    assert(d.action == R340_REPLAY_CACHED_GRANT);
    apply(&s, R340_CHILD_GONE, 0);
    assert(!acknowledge(&s, d, true));
    ++pass;

    /* RELEASE invalidates cache, without resource synthesis. */
    apply(&s, R340_RELEASE, 0);
    assert(apply(&s, R340_CHILD_NEW, 0).action == R340_NONE);
    assert(apply(&s, R340_GRANT, 0).action == R340_FORWARD_ORIGINAL_GRANT);
    ++pass;

    /* Port change is a genuinely new resource event. */
    apply(&s, R340_UNLOAD, 0);
    apply(&s, R340_LOAD, 0);
    apply(&s, R340_CHILD_NEW, 0);
    d = apply(&s, R340_GRANT, 0);
    assert(acknowledge(&s, d, true));
    d = apply(&s, R340_GRANT, 1);
    assert(d.action == R340_FORWARD_ORIGINAL_GRANT && d.port == 1);
    assert(acknowledge(&s, d, true));
    ++pass;

    /* New pipeline epoch may not replay old pipeline grant. */
    apply(&s, R340_UNLOAD, 0);
    apply(&s, R340_LOAD, 0);
    assert(apply(&s, R340_CHILD_NEW, 0).action == R340_NONE);
    assert(!s.grant);
    ++pass;

    /* Invalid grant cannot activate or be replayed. */
    assert(apply(&s, R340_GRANT, -1).action == R340_NONE);
    assert(apply(&s, R340_GRANT, 999).action == R340_NONE);
    assert(!s.grant);
    ++pass;

    /* Stale ACK from an older epoch is rejected. */
    d = apply(&s, R340_GRANT, 0);
    assert(d.action == R340_FORWARD_ORIGINAL_GRANT);
    apply(&s, R340_UNLOAD, 0);
    apply(&s, R340_LOAD, 0);
    assert(!acknowledge(&s, d, true));
    ++pass;

    /* No event is emitted before a real load (fail-closed). */
    apply(&s, R340_UNLOAD, 0);
    assert(apply(&s, R340_GRANT, 0).action == R340_NONE);
    assert(apply(&s, R340_CHILD_NEW, 0).action == R340_NONE);
    assert(!s.grant && !s.child);
    ++pass;
    printf("R340_DETERMINISTIC=%u/13 PASS\n", pass);
    assert(pass == 13);
}

/* Fixed-seed fuzz: no external clocks, inputs, heap or I/O. */
static uint32_t rnd(uint32_t *seed) {
    *seed = (*seed * 1664525u) + 1013904223u;
    return *seed;
}

static void fuzz(void) {
    const uint32_t trials = 25000;
    uint32_t seed = 0xD7C0DE26u;
    uint32_t emissions = 0;
    for (uint32_t i = 0; i < trials; ++i) {
        R340_State s = {0};
        apply(&s, R340_LOAD, 0);
        for (unsigned j = 0; j < 40; ++j) {
            uint32_t q = rnd(&seed);
            R340_Event event = (R340_Event)(q % 11u);
            int port = (q & 0x100u) ? 0 : ((q & 0x200u) ? 1 : 16);
            R340_Decision d = apply(&s, event, port);
            if (d.action != R340_NONE) {
                assert(event == R340_GRANT || event == R340_CHILD_NEW ||
                       event == R340_FLUSH_STOP);
                assert(s.loaded && s.child && s.grant && s.pending);
                assert(d.port == s.port && d.epoch == s.epoch);
                ++emissions;
                if ((rnd(&seed) & 3u) != 0)
                    assert(acknowledge(&s, d, true));
                else if ((rnd(&seed) & 3u) != 0)
                    assert(acknowledge(&s, d, false));
            }
            invariants(&s);
        }
    }
    assert(emissions > 200);
    printf("R340_FUZZ=%u*40 PASS emissions=%u\n", trials, emissions);
}

int main(void) {
    unit();
    fuzz();
    puts("RESULT=R340_PURE_C99_GRANT_REPLAY_MODEL_13_AND_1M_PASS");
    return 0;
}
