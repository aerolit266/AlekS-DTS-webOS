# R315–R316 | Real kitchen LG per-stream DTS policy baseline

**Date:** 2026-11-22. **Status:** R316 READ-ONLY TV QA PASS, first-silent vs audible pairing STILL NOT CAPTURED. R278 production unchanged.

## Why this probe exists

In the owner-confirmed defect, after reboot the first DTS track is silent, AC3 is audible, and the following DTS track is audible. Historical silent and audible sessions both registered `codec=dts` and mapped AlekS DTS libraries; R314 also measured live PCM6 and `ADEC0->MAIN` in an `idle` snapshot. This does **not** distinguish parser/CAPS from native LG sink establishment. We need specific stream-level policy state at the first real silence, not more offline models.

WebOS OSE documents read-only `com.webos.service.audio/getStreamStatus`, `UMI/getStatus`, `getSoundOutput`:
https://www.webosose.org/docs/reference/ls2-api/com-webos-service-audio/
LG's consumer firmware may have different payload shapes and permissions.

## Technical implementation

- Exploratory source: `tools/observe-kitchen-dts-policy-r315.py`, commit `522aabd8a029c56ba158e7fba51ccc764a05ce18`, SHA256 `057e102776f179901b3d2cf293b2c5540e3b161afa2093716bd41fe464650f2a`.
- Corrected source: [tools/observe-kitchen-dts-policy-r316.py](../tools/observe-kitchen-dts-policy-r316.py), final commit `a2cfb606fb3b3a24597aa13fc15db53beee130af`, SHA256 `62990f6669e52e0c1ccd4544348e223debf632511c344d8ec4cee07a10954560`.
- R316 safely traverses bounded nested LS2 objects. R315 had missed nested `codec` and nested `audio[]` `source/sink/muted/outputMode`; its UMI active/muted zero counters were falsely reassuring when the keys were absent. R316 emits both actual known denominator and number of true values. No raw LS2 replies, URLs, media names, token data or environment are printed.
- Reads six LS2 getters plus allowlisted ALSA `/proc/asound/card0/pcm6p/sub0/{status,hw_params}`. Max 4 s per getter; no subscriptions. ARM-only guard. Accepted stage `idle|silent|audible` is user observation, not an acoustic measurement. No audio samples captured and no volume, track, service or driver manipulation.

## Verification

**VPS:** Python compile PASS. R315 x86 ARM guard PASS; mocked 13 checks and redaction PASS. R316 16 tests with actual kitchen-like nested JSON, missing boolean fields, codec nested array, string null and private fields PASS. Final R316 immutably downloaded, SHA256 checked, Python compile PASS.

**Real kitchen LG through existing authorized AlekS Core / TORMOZ / ares-novacom:** R315 SHA verified on LG, executed `idle` and succeeded. First live R316 source commit cc97988c was SHA verified and ran; it exposed nested DTS codec properly and 48000 Hz. R316 FINAL source commit a2cfb606 was then downloaded and on-device SHA256 verified, executed `idle`, exit 0, result marker `R316_READ_ONLY_POLICY_COMPLETE`. The owner did **not** confirm audible/silent for these sessions, so they remain `idle`.

## Actual R316 final live observations

| Metric | Result |
| --- | --- |
| streamObject count | 2 |
| activeStatus known / true | 2 / 2 |
| muted known / true | 2 / 0 |
| policyStatus known / true | 2 / 0 |
| active MAIN routes | 1 |
| source ADEC0 -> sink MAIN | 1 |
| ADEC1 -> MAIN | 0 |
| AMIXER -> MAIN | 0 |
| UMI audio entries | 3; active/mute/policy boolean fields all absent, not false |
| getSourceStatus | RETURN_FALSE (not proof of absent media streams) |
| getSoundOutput | tv_external_speaker |
| audiooutput/audio/getStatus | one ADEC0->MAIN audio connection, muted=false, outputMode=null |
| tv/getAudioInputProperty | one DTS codec field, zero AC3 |
| ALSA PCM6 | RUNNING, RW_INTERLEAVED, S16_LE, stereo, 48000 Hz |

These are the currently active runtime's actual scalar LS2/ALSA observations. **No audio-amplitude measurement**, no actual first-silent state. The `outputMode=null` value agrees with prior owner-confirmed audible R290/R293; it is not an error signal on its own.

**Interpretation:** The queried state has **only one active stream bound to MAIN**, via ADEC0. It does not demonstrate an ADEC1/AMIXER collision on MAIN. We cannot extrapolate to the cold-silent state or rule out decoder/sink handoff timing.

**Cleanup:** After the final read, LG temporary probe files `/tmp/aleks-r315-20261122-qa.py` and `/tmp/aleks-r316-20261122.py` removed; verified `R315_R316_TMP_CLEAN_PASS`, remote task COMPLETED exit0. No deployed files or services changed.

## Decision gate

The next useful hardware measurement is **when the owner confirms first DTS is silent before any AC3 switch**: stage `silent` with pinned R308 + R316 from the same existing authorized channel, then `audible` only after manually switching AC3->DTS and confirming sound. Compare count of active MAIN streams, mute/policy flags, CODEC, PCM6 state + deltas and R130 error counters. If scalar values remain identical, the fault lies below these APIs or in content/PCM and needs narrower native pipeline instrumentation; no codec plugin replacement or production self-heal hack without causal evidence and rollback.

**Root cause: NOT VERIFIED. Auto fix: NOT DEPLOYED. Production R278: PRESERVED.**
