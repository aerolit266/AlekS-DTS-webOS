# R314 — real kitchen LG read-only DTS baseline, 2026-11-22

Status: **LIVE HARDWARE READ-ONLY PASS** for an `idle` R308 capture; **FIRST-SILENT ROOT CAUSE NOT VERIFIED**. R278 unchanged.

## Authorized connection and integrity

- Existing path: GameFree24 VPS MCP V3 → existing `alex-core.service` task queue → authorized `pc-9070-tormoz` → installed `ares-novacom.cmd` SDK profile `aleks-kitchen-root` → kitchen LG. No new port forward, account, key, tunnel, SDK profile or service.
- VPS hostname mediarus.com; `127.0.0.1:22022` was listening but new SSH login was rejected (publickey/password). Working AlekS Core route was independently documented and verified in docs/DEVICE_ACCESS.md.
- LG `id -u=0`, `uname -m=aarch64`, `umediaserver.service=active` at 2026-11-22 10:52:18 UTC.
- Attempted one compound shell command first; Windows SDK quoting truncated it, command returned shell syntax error; **R308 did NOT execute** in that attempt. Split into ordinary device commands. Downloaded exact SHA-pinned public R308 in the device temporary folder; on-device `sha256sum` confirmed `1235dc9ff013ae73f0089cecac93056ac0ce00ffa8d049ce2e0c8d9b027ed7bc`. Only then executed `sh /tmp/aleks-r308-r314-a9.sh idle`. Cleanup command completed without error afterwards.

## Actual R308 observation — UTC 2026-11-22T10:53:37Z

Capture explicitly used **`STAGE=idle`** because the owner had not stated this was the first silent DTS after reboot; do not relabel this trace as silent or audible.

| Signal | Real result |
| --- | --- |
| installed `libgstaleksdts.so` | SHA256 `5c3b798d...` matching R278 hall release |
| installed `libgstaleksdts16dec.so` | `dfefb960...` matching |
| installed `libgstaleksdtscaps.so` | `1995a6b6...` matching |
| installed `libgstaleksdtsr130optin.so` | `9b7adb27...` matching |
| umediaserver / audiooutputd | active / active |
| starfish processes / DTS wrapper holders | 2 / 1 |
| ALSA card0/pcm6p/sub0 | RUNNING |
| ALSA hw pointer growth across 2 s | 96,256 frames |
| ALSA app pointer growth across 2 s | 96,768 frames |
| LG audio API codec | dts |
| audiooutput source / sink | ADEC0 / MAIN |
| audiooutput muted | false |
| audiooutput outputMode | null |
| inspected native journal window | 1 row / 4 min; 6 tested error counters zero |
| snapshot exit/result | R308_READ_ONLY_CAPTURE_COMPLETE |

No raw movie paths/URLs/media samples or unredacted audio logs saved to repo. Initial downloaded script is a temporary file, not a plugin deployment.

## Difference against prior evidence

- Historical **R290, R293 audible session**, with owner's confirmed DTS sound, already reported `source=ADEC0 sink=MAIN muted=false outputMode=null`. Therefore `outputMode=null` in this R314 sample is **not evidence of current mute or sink malfunction**.
- In the historical **silent R280/R283** the same DTS codec and mapped custom libraries were reported, but matching ALSA first-frame and sink telemetry were not captured. No valid silent vs audible PCM comparison can yet be made.
- ALSA pointer movement reflects PCM device progress; neither it nor the mapping and codec identify which element generates the samples, nonzero sample amplitude, or actual acoustic speaker output.
- Six zero journal counters in one bounded window **do not rule out errors** outside the window or through uninstrumented paths.

## Practical next step — no more synthetic releases

At the next **naturally occurring first silent DTS** after TV reboot, before changing tracks, request a verified `R308 silent` snapshot through the same authorized active bridge (or have owner execute it). After the owner's manual AC3→DTS and actual audible confirmation, take `R308 audible`, compare with the existing R313 script (corrected LS2/ALSA parser) on the VPS. Keep both labels explicitly owner-observed. If matching scalar data cannot separate states, request targeted authorized native GStreamer source-buffer/CAPS and sink/PCM instrumentation in isolation; do not infer causality from counters.

**R278 TV install unchanged; no video, audio route, UMS, driver, registry, rank, kernel, rootfs or firmware changed.**

**Release gate:** Do not install experimental R312 or modify LG audio services without confirmed failing-path evidence and rollback-tested isolated build.
