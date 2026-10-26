# Name / namehook code and optimization audit

Audited revision: `9862c98` (Name 1.78, namehook 1.38). The original audit was report-only; subsequent runtime fixes are summarized below. Existing unrelated working-tree changes were left alone. No deployment was performed. The native build was regenerated locally.

**Resuming with another agent? Read [`HANDOFF.md`](HANDOFF.md) first** for the current working-tree state, validation commands, client smoke-test checklist and remaining priorities.

## Remediation status (Name 1.79 / namehook 1.39)

The original findings below are retained as the audit record. Follow-up changes now:

- **Fix findings 1–2:** invalidate the live buffer and cached writers before releasing any textures; relinquish the claim; register deterministic, idempotent addon-unload cleanup.
- **Fix finding 3:** validate decoded signature spans/encoding, bound complete candidates, handle missing/short images, and scan only readable committed regions. Guard-page regressions also cover matches across adjacent readable protection regions.
- **Fix finding 4:** discard lookup/writer caches on observed unload/rebinding, key lookups by owner as well as sequence, and refuse mismatched entity records. An unload/reload entirely between observations still requires a host generation signal to detect reliably.
- **Fix finding 5:** test the minimum-version guard without duplicating an obsolete numeric string.
- **Harden risk B:** checked state-block record/capture/apply/restore policies stop drawing and invalidate cached capture on failure; a fake device tests the failure/recovery paths. Live device-reset validation is still required.
- Remove the small temporary table in target-colour pulse checks; do not claim a general performance speedup from noisy synthetic samples.

Follow-up validation: all **27 Name Lua checks pass**, native core/guard-page/fake-device tests pass under Wine, party name-colour and Damage integration checks pass, and the 1.39 DLL builds successfully. An additional 100,000-case scanner comparison against a naive matcher, plus malformed-encoding inputs, passes ASan/UBSan using unchanged extracted portable scanner bodies. `git diff --check` is clean. No deployment was performed.

Risk A is addressed in namehook 1.40 (`src/CodePatch.h`: transactional install with rollback, page-protection handling and instruction-cache flushing, ownership-checked restore and live changes, pinning when a site cannot be given back); `FindCallsIn` still scans bytes without decoding instructions, now with readable-section and overlap checks. Native draw instrumentation, GPU profiling and in-client reset/occlusion/Lens certification remain open. They were not silently bundled into the confirmed-defect fixes. Shared ABI/capabilities are unchanged; deploy updated WinXI alongside Name when these changes are released.

## Scope and confidence

Reviewed addon lifecycle/controller, custom layout and glyph/atlas paths, packet-derived display state, visibility/colours/readability, shared-memory API, native classification/publication/submission, signature scanning, patch installation/restoration, and relevant tests/build scripts. The shared `addons/libs/winxi/nameplates.lua` interface and shell unload behavior are included because they directly affect this pair.

Findings below distinguish reproduced logic defects from native hardening risks. This is a source and synthetic-test audit, not an in-client rendering certification: Wine core tests do not instantiate `AshitaNameplate`, execute client patches, or exercise an actual Direct3D device. Live GPU timings, reset behavior, client instruction compatibility, occlusion, and Lens output still require client validation.

## Findings

### 1. High — plugin-loss cleanup can write into unloaded DLL memory

Locations:
- `addons/name/custom.lua:1118–1123`
- `addons/name/bar_art.lua:153–160`
- `addons/libs/winxi/nameplates.lua:433–444,485–488`
- Plugin-loss caller: `addons/name/name.lua:354–359`

`custom.Deactivate()` calls `BarArt.Release()` **before** `nameplates.ClearDrawing()`. If an owned textured-bar sheet exists, `art.Release()` calls `nameplates.SetTexture(special.Slot, 0)`. `SetTexture` follows the module-local `draw` pointer cached by the preceding `BeginDrawing`; it does not resolve a live plugin. After namehook unload, this points into the unloaded DLL. The subsequent `ClearDrawing` is designed to validate the current plugin and clear that cached pointer, but is too late.

A harness probe with an installed mock bar sheet recorded:

```
cached draw write -> free -> invalidate current buffer
```

The ordering is reproduced; an actual access violation depends on the DLL memory mapping. The ordinary plain-bar default does not enter the sheet-release branch, which is why the existing lifecycle fixture misses it.

Recommended fix: invalidate the current shared buffer and discard cached writer state before **any** texture release. Make teardown safe after plugin disappearance, including stale `draw`/`drawing` pointers. Add a textured-bar plugin-loss regression, not just a no-GPU lifecycle test.

### 2. High — addon unload never invalidates its published texture addresses

Locations:
- `addons/name/name.lua` event registration (packet/present only; no unload cleanup)
- `addons/name/custom.lua:1118–1139`
- `addons/libs/winxi/shell.lua:426–428`
- Native texture acquisition: `plugins/namehook/src/Ashita/Ashita.cpp:457–467,542–569`

The shell's unload handler only saves settings. Name never registers an unload handler calling `custom.Deactivate()`, clearing the shared draw buffer, or relinquishing its claim. Owned textures may then be finalized with their addresses still published. The plugin acquires its COM references when the next name pass begins, not when Lua submits the buffer. A newly submitted/replaced texture can therefore be destroyed before native `RetainTextures` calls `AddRef()` on that address.

Already-retained textures have native references and are protected, but this does not protect a replacement that has not yet been consumed. Draw freshness remains eight frames and claims remain live for half a second; neither is a resource-ownership barrier.

Harness probe: activate rendering ownership, wrap `filtered_text.Release`, then call `H.unload()`: **0 cleanup calls**, expected 1.

Recommended fix: register deterministic unload cleanup, invalidate the buffer before releasing owners, and relinquish the claim while the plugin is still live. First fix finding 1 so unload cleanup cannot inherit its unsafe order. Test unload immediately after submission and immediately after texture replacement, before the first native scene consumes it.

### 3. High — signature scanning does not bound the complete candidate

Locations:
- `plugins/namehook/src/findsignature.h:30–39,206–244,248–317`

The loop bounds only the selected literal needle, not the entire signature:
- `n - m` underflows when the module/image is absent or shorter than the needle.
- Candidates before `rewind` are accepted for checking; `haystack - rewind` can precede the image.
- A trailing literal/wildcard suffix can extend beyond the image even while the selected needle fits.
- `GetModuleInformation` failure is not checked before scanning.

Reproduced using the unmodified scanner-function bodies, extracted into a standalone C++ probe with a supplied haystack:
- A wildcard-prefix signature whose literal matches at offset zero returns **image − 1**, rather than no match. UBSan reports unsigned-offset pointer overflow.
- A zero-length haystack with a nonmatching allocated backing buffer causes an **AddressSanitizer heap-buffer-overflow** as the unsigned loop bound runs past it.

Recommended fix: fail closed on missing/short images; compute the complete decoded signature span; constrain candidate starts to `[0, imageSize - fullSpan]`; and validate prefix/suffix ranges before comparison. Prefer readable/executable PE regions rather than blindly assuming all of `SizeOfImage` is readable. Add missing-module, short-image, prefix-underflow and suffix-overflow tests. The current core tests do not execute `Init()` and consequently do not cover these failures.

### 4. Medium — entity lookup cache survives plugin reload with the wrong owner

Locations:
- `addons/libs/winxi/nameplates.lua:205–213,308–334`
- Consumer: `addons/party/namecolors.lua:140`

`Find()` invalidates its `places` cache only when `hook.Sequence` changes. It does not key it by hook owner/generation, and observing unload clears `block` and capabilities but not `places`/`placedAt`. A replacement DLL starts its sequence again. If that sequence equals the cached one, the old entity-to-slot mapping is used for the new list.

Reproduced with two ABI-compatible blocks, both sequence 1 and count 1:
1. First block contains entity 1; populate `Find(1)`.
2. Observe plugin unload and reload.
3. Second block contains entity 2.
4. `Find(1)` incorrectly returns entity **2**, and `Find(2)` returns **nil**.

Recommended fix: reset lookup state on observed unload/rebinding and key the cache by connection generation as well as sequence. Validate the returned record's entity index defensively. Merely comparing addresses is insufficient when the loader reuses the DLL's address. Add this scenario to shared API tests.

Limitation: unload/reload entirely between observations also requires an explicit connection-generation signal or equivalent owner validation; `IsLoaded()` alone cannot detect that transition.

### 5. Low — capability regression test has a stale required-version assertion

Locations:
- `tests/namehook_capabilities_check.lua:46`
- `addons/name/name.lua:9`

The test expects `needs winxi 49`; Name currently requires 52. The version guard correctly rejects WinXI 45, but the test then fails. This is a test expectation defect, not a production capability-guard failure.

Recommended fix: synchronize the required-version expectation, ideally testing guard behavior without duplicating a version string in unrelated capability assertions. Keep a separate explicit check for the actual minimum version if that value itself is the contract being tested.

## Native hardening risks requiring targeted client/fault-injection tests

### A. Patch writes rely on ambient writable code pages and unconditional restoration

Locations: `plugins/namehook/src/Nameplate.cpp:785–789,1946–1988,2240–2278`.

Installation, live updates, and removal write client instructions with plain memory stores/`CopyMemory`. There is no local `VirtualProtect` handling, `FlushInstructionCache`, transactional rollback, or verification that the plugin still owns the bytes being restored. A read/execute-only code page can fault; another patch installed later can be overwritten on unload. Whether code pages are already writable depends on the host/client environment, which was not validated here.

Recommendation: use one checked patch abstraction, validate expected originals/current ownership, temporarily obtain the required protection, restore protection, flush the instruction cache, and roll back partial installation. Document the execution-thread/quiescence assumption; multi-byte code writes are not atomic. Validate with protected-page and competing-patch fixtures.

Related review point: `FindCallsIn` scans every byte for `E8 rel32`, without decoding instruction boundaries. Matching bytes inside an immediate/displacement are possible; range and target matching alone are not proof of a real call instruction. Do not expand this hook strategy without instruction-boundary validation or an explicit call-site allowlist.

### B. Rendering proceeds after unchecked state-block failures

Locations: `plugins/namehook/src/Ashita/Ashita.cpp:630–660,840–880`.

`BeginStateBlock`, `CaptureStateBlock`, and `ApplyStateBlock` results are not checked consistently. In particular, a failed capture still sets `m_StatesCaptured = true`, proceeds to draw, and later applies potentially stale saved state. Resource loss/reset is the important fault-injection case. The synthetic core suite does not compile this host renderer.

Recommendation: fail closed before drawing if capture/application fails, mark cached state invalid, and exercise failure/recovery and reset paths using a fake Direct3D device or client fault instrumentation. Ensure temporary state-block tokens are associated with the device that created them.

## Optimization assessment

### Measured addon-side baseline

Default synthetic benchmark, 500 timed frames per case, this host, mocked Ashita/ImGui:

| Names | Letters | CPU ms/frame | Allocated KiB/frame | Quads |
|---:|:---:|---:|---:|---:|
| 0 | off | 0.010 | 2.70 | 0 |
| 32 | off | 0.032 | 4.62 | 224 |
| 128 | off | 0.106 | 9.28 | 896 |
| 256 | off | 0.200 | 14.67 | 1792 |
| 0 | on | 0.004 | 2.85 | 0 |
| 32 | on | 0.102 | 5.09 | 288 |
| 128 | on | 0.396 | 11.84 | 1152 |
| 256 | on | 0.789 | 20.85 | 2304 |

Warm fixtures report no badge readback/upload. These are individual local samples, not GPU timings or a full-feature crowd benchmark; do not interpret the 0-name difference as a meaningful speedup. Letters add about 0.59 ms at 256 names in this fixture.

Native whitelist benchmark, one million lookups, 50% hits/misses:

| Entries | Linear ms | Indexed ms | Speedup |
|---:|---:|---:|---:|
| 8 | 32.230 | 30.281 | 1.06× |
| 64 | 57.987 | 30.061 | 1.93× |
| 512 | 161.158 | 33.068 | 4.87× |

The indexed whitelist is justified at larger sizes. No rewrite is indicated.

### Prioritized optimization work

1. **Instrument native submission before changing rendering.** Eight halo directions plus shadow/fill and a depth pass can dominate real cost. Measure vertices expanded, texture runs, colour/depth draws, state captures, and culled plates. `RenderCustom` already batches adjacent aliases and skips fully offscreen drawings; preserve alpha/depth ordering rather than sorting arbitrary quads by texture. Consider a dynamic vertex buffer only after measuring `DrawPrimitiveUP` overhead.
2. **Measure feature combinations and cold transitions.** Current performance fixtures are warm, short-name CPU cases. Add full-length names, bold/smooth font, 12 statuses, HP/cast captions, textures, nonuniform targets and Lens. Measure atlas rebuild peaks on font/size changes separately from steady state. Packing/readback/rasterization is synchronous; a cold atlas can stall even with an excellent warm benchmark.
3. **Profile and reduce allocation churn, not just cache misses.** The 256-name letter case allocates approximately 20.85 KiB/frame (about 2.93 MiB/s at 144 FPS). Find its sources with LuaJIT allocation/trace profiling before changes. Check repeated FFI references, transient tables and cache-reset cliffs. `pulseOf` creates `{0, 0x80}` on target-colour checks; replacing that table is a small safe candidate, not an explanation for all per-name allocations.
4. **Consider reusing native state-block definitions across frames.** The host deletes and recreates two state blocks each present. This is measurable potential driver overhead, but any reuse must handle reset/device changes and recapture saved state correctly. Fix and test failure handling first.
5. **Expose buffer saturation.** Safe limits exist (16,384 global quads, 256 per name), but `Quad` silently drops overflow. With 256 plates, the global budget averages only 64 quads per plate; long bold names plus details can exceed it well before the per-name limit. Report dropped quads/names and consider graceful detail reduction. Never increase shared struct capacities without an ABI plan.

Existing good choices: bounded glyph-run/format caches, cached size rungs, immutable badge definitions, per-frame entity-answer reuse, lazy status reads, quad range checks, timed claims, separate additive layers, texture `AddRef`/`Release` ownership on the native side, and adjacent texture-run merging. Preserve these while fixing lifecycle defects.

## Validation executed

- 27 relevant Lua checks from `tests/run.sh`: **26 passed; 1 failed** (finding 5).
- `plugins/namehook/tests/run.sh`: **all checks passed** under Wine; environment emitted Mesa/EGL warnings.
- `plugins/namehook/build.sh`: **build succeeded**, `build/namehook.dll` regenerated; not deployed.
- `plugins/namehook/tests/benchmark.sh`: **completed**, results above.
- `python3 -m unittest discover -s tools -p test_build_name_cast_times.py`: **4 passed**.
- Additional temporary probes reproduced cleanup ordering, missing unload cleanup, lookup reload identity, and scanner invalid-pointer/out-of-bounds behavior.

Local logs and temporary probes: `/tmp/name-audit/` (ephemeral, not committed). The standalone scanner probe substitutes only module retrieval/platform includes; its scanner-function bodies are extracted unchanged from the audited header.

## Recommended fix order

1. Repair teardown ordering and writer-pointer invalidation.
2. Add unload cleanup with texture ownership regressions.
3. Bound scanner candidates and test absent/short/edge-case images.
4. Reset lookup caches on connection changes; repair the stale version assertion.
5. Add checked patch/state-block failure handling and native rendering instrumentation.
6. Re-run synthetic checks, then validate unload/reload, textured bars, device loss, TrueFPS, Lens and occlusion in the client before deployment.
