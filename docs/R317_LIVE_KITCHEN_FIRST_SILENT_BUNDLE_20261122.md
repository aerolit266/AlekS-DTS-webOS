# R317 — one-file kitchen LG DTS first-silent capture

Date: 2026-11-22. **LIVE HARDWARE `idle` PASS**, NOT yet first silent vs audible. Production R278 unchanged.

## Goal

The owner repeatedly reproduced the genuine bug: after a reboot, the first DTS selection has no sound; AC3 plays; returning to DTS restores sound. R314 and R316 only captured an `idle` status. We need to collect both earlier R308 first-buffer/error telemetry and R316 per-stream audio policy *quickly in one read-only invocation*, without depending on extra downloads while DTS is already silent.

## Artifact and reproducibility

[tools/kitchen-first-silent-bundle-r317.py](../tools/kitchen-first-silent-bundle-r317.py), original commit `0a61942d4ac84ac5a02d500448ba83b264618b91`; SHA256 `e5f9f184a2d5b0c6df3bb44c1d419eb346486a77c6e7f64f371006355cb17ef8`.

One Python3 source embeds **exact pinned R308 shell source** SHA256 `1235dc9ff013ae73f0089cecac93056ac0ce00ffa8d049ce2e0c8d9b027ed7bc` and **exact pinned R316 Python source** SHA256 `62990f6669e52e0c1ccd4544348e223debf632511c344d8ec4cee07a10954560`; verifies both SHA256 in memory before executing. No network, package installation or persistent files required during actual capture once the one-file bundle is loaded.

`python3 kitchen-first-silent-bundle-r317.py capture idle|silent|audible` (ARM only) executes the read-only R308 and R316 probes, validates both end markers and stage, prints only strictly allowlisted scalar telemetry as `R317_JSON={...}` plus `RESULT=R317_CAPTURE_FULL|PARTIAL`. It never outputs raw LS2/journal data, media names, URLs or environment values; never switches tracks or changes service/sink/volume. Stage is **owner-observed**, not an acoustic detection.

`compare silent.json audible.json` is for two saved bounded JSON outputs, rejects invalid stage/machine/provenance, malformed values, inverted timestamps, and >30-minute separation. Emits only changed named scalars. Differences are correlation, not proof of root cause.

## Offline QA on VPS

- Immutable R317 source fetched; Python py_compile PASS; outer SHA256 PASS.
- AST-extracted embedded R308/R316 source SHA256 PASS independently, without executing embedded code.
- Non-ARM `capture idle` fails closed PASS.
- Mocked `silent` and `audible` Python subprocesses tested end-to-end; result `FULL` and release library matches 4/4 PASS; test-only private URL/title strings absent from output PASS.
- Pair comparator detected exactly two injected differences (`R130_NO_INPUT_CAPS=1→0`; `OUTPUT_ADEC0_MAIN_MUTED=true→false`) PASS. Wrong stage refused PASS.
- QA files were temporary and automatically removed. Synthetic mock is **not** a real cold-silent sample.

## LIVE kitchen LG verification

Used existing, previously authorized GameFree24 VPS MCP V3 → local `alex-core.service` task_queue → TORMOZ → existing `ares-novacom` device profile `aleks-kitchen-root`, with no new key, forward, service or access grants.

1. Downloaded immutable R317 to LG temporary file `/tmp/aleks-r317-20261122.py`; SHA256 on LG `e5f9f184a2d5b0c6df3bb44c1d419eb346486a77c6e7f64f371006355cb17ef8` PASS.
2. Executed **`capture idle`** only (user had not reported current silence). Device task `dc39e4bee0fac71067ec29f0a20336e1`, COMPLETED exit 0, `RESULT=R317_CAPTURE_FULL`; UTC `2026-11-22T11:10:55+00:00`, machine `aarch64`.
3. Actual R308: four production R278 plugin SHA matches 4/4, Starfish 2, decoder wrapper holders 1, PCM6 RUNNING, hw delta 96,768 frames in 2 seconds, app delta 97,024; six native error counters all zero in bounded journal (one recent journal row).
4. Actual R316: `INPUT_CODEC_DTS=1`; stream count 2, both active and unmuted, no pending policy. One active `ADEC0→MAIN` route, zero `ADEC1/AMIXER→MAIN`. Output connection `ADEC0→MAIN` has `muted=false`, `outputMode=null` (same as historical owner-confirmed audible R290/R293); external speaker output; ALSA `S16_LE, stereo, 48000 Hz`.
5. The capture returned only filtered scalar keys. Did not capture an acoustic speaker signal or identify first-silent event.

**Important:** `FULL` means both diagnostics executed and their required fields were returned; **it does not mean audible sound**. Do not present this `idle` session as evidence of the silent startup, or as a fix.

## Next physical decision gate

When the first naturally occurring silent DTS state is explicitly confirmed by the owner, acquire R317 `capture silent` *before* changing tracks. After owner manually switches DTS→AC3→DTS and confirms audible playback, acquire R317 `capture audible`, compare within 30 minutes. If both sets of scalar metrics are identical, native first DTS buffer/CAPS/SEGMENT and per-stream PCM/sink-level trace is still needed; do not replace R278 or alter native LG services based on this test.

Root cause: **NOT VERIFIED**. Fix deployed: **NO**. Production R278, system audio services and webOS firmware: **UNMODIFIED**.
