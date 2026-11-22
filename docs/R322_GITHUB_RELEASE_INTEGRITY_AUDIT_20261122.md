# R322 — audit of the public AlekS-DTS-webOS GitHub repository

Date: 2026-11-22. Scope: **public repository artifacts and real kitchen LG installation integrity**, not a claim that all DTS playback cases are fixed.

## Source state and release artifacts

- Public repository `aerolit266/AlekS-DTS-webOS`, default branch `main`, verified against latest committed file contents. Before updates: commit `9b4d9132ccdf8a7ee226ea292c8a0b3eae5d4859`.
- The immutable R278 release archive is `downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz`, SHA256 `cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1`, matched `SHA256SUMS`.
- LGPL relink archive SHA256 `2723b1cd09b50df367161e5acff6d1d622c76856592c907d79ef606380c98ccf` matched. `SOFTWARE-NOTICES.txt` matched its manifest too.
- All **four original R278 ARM32 plugin** SHA256 values, both DTS Matroska fixtures and one AC3 fixture SHA256 matched embedded archive contents.
- The **original archive's** `install.sh` deliberately requires exact model **65NANO896PC**, firmware **03.60.96**, SDK **6.6.0** and specific system binary checksums. **This is not the universal installer.** It refuses B1 and other models before installing.
- The separate repository-root `install-universal.sh` (SHA256 `9c3ce62eeadcd638968a72bd29b3aefbbe349425c0ef739c455ab50c61de3a48`) is the intended ARMv7 compatibility *frontend*: it confirms real systemd `EnvironmentFiles`, validates source and plugin checksums, patches only model/firmware guard in a temporary copy, retains isolated DTS/AC3 GStreamer and rollback logic and fails closed on unknown architectures/service layouts. Its immutable raw GitHub URL at commit `9b4d9132ccdf8a7ee226ea292c8a0b3eae5d4859` was fetched and SHA256 verified on VPS. It is **not guaranteed compatible with untested LG hardware**.
- Reconstructed a temporary patched installer as a syntax/guard smoke test: `sh -n` PASS, model check gone, rollback/verification retained; no actual installation run.

## Live installed kitchen LG, read-only validation

Via the **existing** GameFree24 VPS MCP V3 → Alex Core task queue → TORMOZ webOS SDK `aleks-kitchen-root` route, task `d950ca8e6eb6769e4e00f0f898bc9b18` completed, exit0:

- `id -u=0`, `uname -m=aarch64` (kernel, not media ELF ABI), `umediaserver.service=active`.
- Current `EnvironmentFiles=/var/systemd/system/env/umediaserver.env (ignore_errors=yes)`.
- Four installed `/var/lib/webosbrew/aleks-dts-r278/plugins/*.so` SHA256 values match the immutable original R278 release (4/4).
- `cmp -s` installed `installed.env` vs active `/var/systemd/system/env/umediaserver.env` returned **0 (same bytes)**.
- No TV reboot, playback, config, rootfs, service or firmware changes. This verifies installed files and declared service state, not the fix for the initial DTS silence.

## Documentation corrections on GitHub

1. [Russian README](../README.md): made clear that R278 archive installer is model-bound, the separate universal frontend has a limited purpose, and kitchen LG real first DTS after reboot is **silently failing** until AC3→DTS. R318 and R320 real evidence linked, B1/eARC separate. Updated the kitchen compatibility row and retained the older engineering history with an explicit historical disclaimer.
2. [English README](../README.en.md): same update.
3. [PUBLIC-COMPATIBILITY.md](../PUBLIC-COMPATIBILITY.md): current kitchen cold-silent and recovered observations, R320 isolated PCM output and B1 unresolved eARC now prominent.
4. Both README install commands use **immutable commit URL** `9b4d9132ccdf8a7ee226ea292c8a0b3eae5d4859/install-universal.sh` with the unchanged verified SHA256, instead of `main/install-universal.sh` (which can drift).

## Reproducible automated QA

- New [tools/audit-public-github-r322.py](../tools/audit-public-github-r322.py) checks SHA256 manifest and archives, all 4 plugins + 3 fixtures, original model/rollback guard, universal frontend SHA and retained safety checks, shell/Python syntax, and local Markdown links and current documentation status. It performs **no** installation, service modification, device access or network fetch.
- First audit run caught a **typo in the new audit script** when transcribing the AC3 expected SHA256. Original archive and installer AC3 hash matched each other. Fixed the audit script and reran with immutable values; this was a QA transcription issue, **not a broken R278 release**.
- Latest validated checkout after CI addition commit `5c4bc7547d0199b06175018d8d5525d6f184f8e8`:

```text
R322_RELEASE_ARCHIVES_AND_MANIFEST=3_PASS
R322_RELEASE_4_PLUGINS_AND_3_FIXTURES=7_PASS
R322_MODEL_BOUND_ORIGINAL_AND_ROLLBACK=PASS
R322_SHELL_SYNTAX_PASS=41
R322_PYTHON_SYNTAX_PASS=13
R322_UNIVERSAL_INSTALLER_SHA_AND_GATES=PASS
R322_DOCUMENT_RELATIVE_LINKS_PASS=187
R322_REPRODUCIBLE_BOOTSTRAP_AND_FIELD_STATUS=PASS
RESULT=R322_PUBLIC_GITHUB_AUDIT_PASS
```

- GitHub Actions read-only CI [workflow](../.github/workflows/dts-public-integrity.yml) added for pushes and PRs. Uses pinned GitHub-owned checkout action SHA, read-only `contents: read` and runs the same no-network Python audit. YAML syntax validated on VPS with PyYAML, 2 steps. Initially observed on GitHub as `in_progress`; a successful Actions result requires later confirmation and must not be conflated with the confirmed VPS audit.

## Remaining limitations

- The real owner-confirmed kitchen defect **first DTS silent → AC3 → DTS audible**, previously captured R318, **has not been fixed**. R319–R320 showed isolated decoder PCM amplitude but not Lampa's live first-start buffer.
- LG OLED77 B1/webOS 6.3.2 tester has not supplied architecture, GStreamer, original installation success logs, or real eARC multichannel PCM metadata. There is no proof that the B1 installed R278 or that DTS 5.1 was negotiated through eARC. Avoid claiming universal passthrough.
- No physical test of `install-universal.sh install` on B1. The checked-out source, checksum audit and syntax tests do **not** replace an actual device test.
- If the original forum command is malformed when copied, direct users to a verified README pinned command or read-only compatibility preflight; never remove the ABI/rollback safeguards to make installation appear successful.

**Audit status: REPOSITORY PACKAGE INTEGRITY VERIFIED; DOCUMENTATION CORRECTED; KITCHEN INSTALLED PLUGINS VERIFIED; DTS FIRST-START FIX NOT DEPLOYED; B1 eARC 5.1 UNVERIFIED.**
