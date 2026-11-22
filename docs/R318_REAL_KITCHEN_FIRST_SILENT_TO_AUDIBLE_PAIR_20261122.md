# R318 — real kitchen LG DTS silent → audible paired capture

Date: **2026-11-22**, LG kitchen, user playing Lampa. **First genuine owner-confirmed cold-start DTS silence and manual AC3→DTS audible recovery successfully captured on the same TV**.

## Reproduction

1. Owner restarted kitchen LG, entered Lampa, selected a DTS track and independently confirmed **NO SOUND** before any AC3 switch.
2. Assistant used the existing authorized GameFree24 VPS MCP V3 → Alex Core task queue → TORMOZ → `aleks-kitchen-root` webOS SDK channel to run SHA256-pinned `tools/kitchen-first-silent-bundle-r317.py` **`capture silent`** (the assistant did not manipulate playback).
3. First real failing capture at **2026-11-22T11:18:15+00:00**, task `3943e5d7909e5d0b77e58cde37d451e5`, completed exit0, `RESULT=R317_CAPTURE_FULL`. Captured the user-observed silence, NOT an acoustic recording.
4. Owner manually switched **DTS→AC3→DTS** and explicitly confirmed **DTS sound now works**.
5. Assistant ran the same pinned source already present on TV with **`capture audible`** (task `4d04da2eb72ffbe74dfe3076d219a7e9`, completed exit0). Second capture at **2026-11-22T11:21:18+00:00**, `RESULT=R317_CAPTURE_FULL`.
6. Each stage's strictly allowlisted JSON stored privately on VPS, directory mode 0700 / files 0600:
   - `/opt/gamefree24-vps-mcp/private/dts-r317-20261122/cold-silent-111815Z.json` SHA256 `c90f4eb1457be5c79d9c2e3eb18f8d311b7efadbb0a81f328d24dfe1430c39df`.
   - `/opt/gamefree24-vps-mcp/private/dts-r317-20261122/recovered-audible-112118Z.json` SHA256 `2a5f56f3a3bb78883cf80cc8b8728ef4f390807926f7831fdda4fd1347df9ae2`.
   - Readback validated against each completed task. **These private files are not in GitHub.**

## Exact comparison (same immutable R317 comparator)

R317 SHA256 `e5f9f184a2d5b0c6df3bb44c1d419eb346486a77c6e7f64f371006355cb17ef8` was independently verified on TV and VPS; `compare` ran on the genuine private pairs:

| Metric | Cold DTS silent | DTS audible after AC3 switch |
| --- | --- | --- |
| first user-observed audio state | **silent** | **audible** |
| Stage timestamps | 11:18:15 UTC | 11:21:18 UTC |
| capture coverage | FULL | FULL |
| installed R278 plugin SHA matches | 4/4 | 4/4 |
| Starfish media processes | 2 | 2 |
| mapped AlekS DTS wrapper holders | 1 | 1 |
| LG codec | DTS | DTS |
| audiooutput | ADEC0→MAIN, mute=false, outputMode=null | same |
| sound output | tv_external_speaker | same |
| stream count / active | 2 / 2 | 2 / 2 |
| stream mute / pending policy | 0 / 0 | 0 / 0 |
| active MAIN routes | exactly one: ADEC0 | same |
| ALSA PCM6 | RUNNING | RUNNING |
| negotiated ALSA | S16_LE, 2 channels, 48000 Hz | same |
| ALSA hw frames / 2 s | 97,792 | 96,768 |
| ALSA appl frames / 2 s | 97,792 | 96,512 |
| bounded R130 event limit, missing/unknown CAPS | 0 | 0 |
| bounded GStreamer not-negotiated, native sink/DCADEC hints | 0 | 0 |
| bounded journal rows | 1 | 1 |

Comparator output:

```text
CHANGED=R308.ALSA_HW_FRAMES_2S SILENT=97792 AUDIBLE=96768
CHANGED=R308.ALSA_APPL_FRAMES_2S SILENT=97792 AUDIBLE=96512
CHANGED_METRICS=2
CAPTURE_COVERAGE=FULL,FULL
RESULT=R317_COMPARE_COMPLETE
```

The difference of 1,024 hw frames and 1,280 appl frames in **independent two-second sampling intervals** is consistent with sampling jitter and cannot by itself establish the cause of silence.

## Findings and elimination limits

**Proved during the owner's actual silent interval:** DTS input recognized, installed decoder library mapped, output route ADEC0→MAIN reported unmuted, PCM6 RUNNING at 48kHz, two active streams and no reported pending policy, and hardware/application PCM pointers were moving. All of these scalar observations persisted after sound returned. Therefore **these scalars do not discriminate silent vs audible and do not justify a rank-only, mute-only or outputMode-only production fix**.

**Not proved:** a continuous stream of actual *nonzero PCM samples* reached ALSA, which plugin instance decoded the first DTS packets, decoded audio RMS, whether LG proprietary audiooutput sent or dropped audible samples, or precise event ordering in the actual native pipeline. The absence of the six searched error markers in a bounded one-row journal window does **not** establish that the pipeline is error-free.

The evidence suggests investigating **actual sample amplitude/provenance and the handoff into the final audio renderer during first DTS start**, not changing exposed LS2 mute/route/caps and not making an automatic AC3-track-switch workaround. A reversible, isolated **non-recording per-buffer amplitude/counter** or instrumented Gst branch may distinguish *all-zero PCM* from *output sink not rendering nonzero PCM*. Native instrumentation should be designed/tested separately; any service/plugin deployment still requires explicit review, backout and regression.

## Production/safety

- No resets, remote media track switches, service restarts, plugin reinstallation, modification of rootfs/UMS, driver, firmware, or speaker settings performed by assistant.
- User manual AC3→DTS recovered sound.
- Production R278 remains intact.
- Root cause: **NOT VERIFIED**.
- Permanent correction: **NOT DEPLOYED**.
- Owner no longer needs to keep TV in failing state; a definitive pair has been securely recorded.
