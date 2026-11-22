# R313 — kitchen DTS paired-capture correctness fixes (2026-11-22)

Status: **OFFLINE QA PASS on FI VPS; kitchen LG NOT TESTED; R278 UNMODIFIED**.

## Confirmed scenario

Owner-observed first DTS after TV reboot silent; AC3 audible; returning to DTS restores sound. This is a repeatable physical symptom but has not been captured with synchronized native Gst/PCM/sink evidence. No inference of a particular decoder defect is justified yet.

## Parser defects in R310

1. R308 prints an LS2 query status `QUERY_STATUS=VALUES_UNGROUPED` plus *individual allowlisted policy values* such as `"muted":false` or `"outputMode":"pcm"`. R310 compared only the status, so real policy changes could be mislabeled `SAME` despite different mute/route/codec fields.
2. R308 prints both `ALSA_HW_FRAMES_2S=...` and `ALSA_APPL_FRAMES_2S=...` on a **single line**. The R310 AWK parser parsed the first value as the rest of the line and failed to record the second counter separately. These are evidence-format errors, **not** proof of defective LG runtime.

## Fix

New separate script: [tools/kitchen-dts-paired-r313.sh](../tools/kitchen-dts-paired-r313.sh).
Final source commit `c98010718945854985c5a491248431443f035497`;
SHA256 `02addd961b793730cd5dbe8fd41b7c8d6f20e171af9a6145c38ec4ef9d7166c6`.

- Preserves all R310 safeguards: ARM-only interactive `capture`, explicit owner confirmation SILENT/AUDIBLE, SHA256-pinned R308, read-only snapshots, no automated media switching, no service/firmware/plugin modifications. Offline `compare` runs on Linux without TV.
- Accumulates only R308's allowlisted LS2 keys `codec, source, sink, soundOutput, outputMode, muted, streamType` in deterministic order, and compares these together with LS2 query result status.
- Correctly separates AL​SA hardware and application pointer deltas from the combined R308 line. (These are pointer *increments* over two seconds, not proven decoded audible samples.)
- Keeps the same 13 top-level comparison metrics and flags changes without claiming stream-level causality.

## Fresh FI VPS verification

Fetched immutable R313 commit directly, shell syntax `PASS`, SHA256 verified as above. Synthetic capture pair with unchanged CODEC fields in reversed order and changed OUTPUT `outputMode`/`muted`, changed `R130_NO_INPUT_CAPS`, and changed `ALSA_APPL_FRAMES_2S`:

```
CODEC_SAME_ORDER_INDEPENDENT=PASS
OUTPUT_FIELD_CHANGED=PASS
ALSA_HW_CORRECT=PASS
ALSA_APPL_CORRECT=PASS
DIFFERENCE_COUNT=PASS    # exactly 3 changed top-level metrics
BAD_STAGE=REJECTED
NONARM=REJECTED
LINK=REJECTED
RESULT=R313_OFFLINE_QA_PASS
```

Test staging in `/tmp/aleks-r313-check.*` cleaned automatically. No real DTS silence captured; all samples artificial.

## Live release gate / boundaries

R313 must only be invoked on the real kitchen LG **with existing device-access authorization and when DTS is first silent**; it must not be used to manufacture the silent state. `capture` still expects a human-observed transition after manually switching DTS→AC3→DTS. A script cannot verify audible output by itself. Neither success of LS2 nor moving ALSA pointers proves per-track PCM or speaker output. If the LG LS2 services do not expose policy properties, `QUERY_*` can remain `ERROR/UNAVAILABLE`; do not synthesize data.

No existing TV-side prohibition is overridden by this offline work. Do not change webOS, UMS, plugin rank, DTS decoder or firmware based solely on simulated output or isolated R312 Gst tests.

**Root cause kitchen:** NOT VERIFIED. **Physical R313 capture:** NOT RUN. **Fix deployed to LG:** NO.
