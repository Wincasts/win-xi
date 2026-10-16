# Changelog

## 0.3 — optional default HUD placement/behavior (live validation pending)

- Current testing build parks native anchoring: addon controls hidden, saved opt-ins reset and runtime gating forced off. Hide cumulative counters/geometry from normal settings and `/pt native status`; retain mode/readiness/errors. Internal DLL counters/geometry and ABI 3 remain unchanged, so this cleanup needs only an addon update.

- Optimization pass: trivial triangle accept/reject before full CPU clipping; merge contiguous post-clipped same-texture runs with exception-safe retained references; omit fully clipped runs; avoid duplicate-pass viewport queries while retaining font checks; precompute viewport scale per replay. Preserve the source-command/vertex safety limits and scoped native-arrow suppression.
- Avoid formatting unchanged Lua mode diagnostics and repeatedly stopping an already-idle hook. Keep per-call DLL liveness validation wherever cached pointers are used. Isolated interpreter-mode tests report zero steady-state allocation for renewal/rectangle/idle paths and verify cleanup after partial renewal failure.
- Add a portable CPU benchmark/regression check: 10,000 exact randomized clipping comparisons plus texture-run ownership/order/failed-retain tests. One 90%-inside workload measured ~5.8× faster clipping; this is not an in-game FPS/GPU benchmark. ABI remains 3.

- Add default-off **Use Default UI Positioning** and **Follow Default UI Behavior** controls. Read each live native HUD rectangle independently; preserve manual positions/corners/links and custom styling. Main party/target anchor bottom-right, alliances top-right; no invented sub/ToT rectangles.
- Separate Alliance 2/3 default-location checkboxes permit independent manual placement even with automatic layout enabled. Existing Alliance 3 → Alliance 2 links remain optional; neither alliance is implicitly linked to the main party.
- Default behavior uses native party order/solo drawing/lifecycle, bypassing custom chat/map hide rules and addon idle/presence fading only for native groups. Loading/interface-hide/cutscene guards remain. This is not full stock animation/style emulation.
- Shared ABI **3**, **168 bytes**: add a verified native geometry source and four normalized/frame-stamped rectangles. Missing geometry discovery does not disable rendering replacement. **Both addon and DLL must be updated.**
- Build, Wine geometry/ABI checks, static private-client discovery and Lua placement/behavior tests pass. New positioning/scaling/behavior still require live validation; earlier 0.2 user confirmations do not cover these options.

## 0.2 — independent target replacement (zoning validation pending)

- User-reported live checks pass for target rendering/native arrows, menu overlap, subtarget range colours, rapid target changes/despawns/doors, cutscenes, interface hide/show and independent mode toggles. Zoning has not yet been tested; font/device-reset recovery and broader compatibility remain open.

- Add `/pt native target on|off`, independent from the party-list mode. Capture main/sub/target-of-target into three additional buffers and replay together at targetwi. Validate the target registry global against hideparty's code signature.
- Preserve the client's own overhead target/subtarget arrows: verify and redirect only their two native E8 calls, check both original destinations against the recognized sprite function, and permit GPU output only inside those draws while target HUD suppression is active. Keep native coordinates, animation, range colours and selection; restore both calls on unload. No general sprite-function detour or Lua cursor replacement.
- Shared ABI 2, size 84: six DrawnFrame entries and a preserved-arrow counter. Old ABI pairs are rejected safely. Per-slot release permits disabling one group without releasing the other; hidden groups renew empty frames before visibility rules.
- Extend Wine fixtures, cursor suppression scopes, private client-dump discovery checks, and Lua tests for six windows/independent modes. Existing party behavior remains opt-in/default off. DLL replacement is required for this update.

## 0.1 — experimental prototype

- Default-off native Party/alliance replacement: versioned synchronous C++ ImGui capture, clipped indexed geometry, retained textures, native-window replay and scoped GPU suppression without persistent visibility/input writes.
- Identify the three HUD globals through the native menu registry, cross-checked against hideparty's primary code signature; reject ambiguous renderer/registry matches.
- Follow namehook/buffhook's recent texture fixes: no Lua ImTextureID conversion or font texture dereference, field-only C++ texture resolution, no low/sentinel texture addresses, font-change fallback, per-frame state-block release, and duplicate-render suppression.
- Fail open on missing/stale/failed submissions; addon opt-in commands, settings and diagnostics; ordinary windows in Organize mode. Native anchoring and target replacement are not implemented.
- Builds on Linux; Wine detour/registry/clipping tests and Lua lifecycle/integration tests. Static signatures match the private Phoenix codedump. In-game testing remains required.
