# partyhook — experimental 0.3

**Legacy standalone plugin.** New installations should use [uihook](../uihook/README.md), which
includes this party/target module alongside buff replacement. Do not load both DLLs together.
The implementation/validation notes below still apply; the legacy commands remain for rollback.

An opt-in Ashita v4 plugin for replacing the native **party/alliance HUD lists** and, independently,
**target box** with the `party` addon's existing frames, at their native UI render boundaries.
Normal Party rendering remains the default. User testing confirms party/rearranging, expanded-chat
hiding, target rendering/native arrows, menu overlap, subtarget range colours, rapid target changes,
despawns/doors, cutscenes, interface hide/show and independent mode toggles. **Zoning is not yet tested.**
These are user-reported results, not an exhaustive client/device compatibility validation.

## Install / update

Build with `plugins/partyhook/build.sh`. For an update, unload Party and the plugin **before replacing
the DLL**; 0.3 changes the shared ABI from 2 to 3. Update both the addon and DLL. Older plugin/addon pairs deliberately refuse to
communicate instead of interpreting the wrong buffer layout.

In game:

```
/addon unload party
/unload partyhook
```

From a terminal in this repository:

```
./deploy.sh push party
cp plugins/partyhook/build/partyhook.dll "$HOME/Games/PhoenixXI/plugins/"
```

Adjust the destination for another Ashita installation. Then in game:

```
/addon unload hideparty
/load partyhook
/addon load party
/pt native on
/pt native target on
/pt native status
```

The two saved opt-ins are independent:

- `/pt native on|off`: party and both alliance lists (including pets embedded in the main window).
- `/pt native target on|off`: main target, sub-target and target-of-target windows, replayed together
  at the stock `targetwi` boundary. Which target windows are visible still follows Party's Target settings.
- `/pt native status` (or `/pt native target status`): concise mode/readiness status. Cumulative
  debug counters and geometry diagnostics are hidden from settings and command output.
- Behavior → **Native HUD Replacement (Experimental)** exposes both settings.

**Do not run hideparty alongside either mode.** Its persistent visibility writes conflict with native
rendering and hide its overhead arrows. Loading partyhook alone does not hide anything.

During testing, watch for stock HUD bleeding through, missing frames/arrows, menu layering and
stuttering. The plugin retains its internal counters for ABI compatibility, but does not display them.

### Appearance and lifecycle

Current manual/automatic positions, scales, borders, backgrounds, text and bar styling are retained
by default. Outer window drop shadows are disabled for captured windows because winxi draws them on
ImGui's shared background list; bar/text shadows remain.

**Use Default UI Positioning is parked: hidden and forcibly disabled in this testing build.**
Older saved opt-ins are cleared, and runtime placement is gated off too. Its alliance-location
controls are hidden. Manual positions/corners/links are preserved and Automatic Positioning remains
available. With Automatic Positioning off, arrange each list in Organize; Alliance 3's default link
is below Alliance 2, not the main party. Use **Unlink** to move all three independently.

**Follow Default UI Behavior** is separate: native-rendered groups keep native member order, allow
solo drawing, follow the native window lifecycle instead of custom chat/map hide rules, and skip
addon idle/presence fading. Loading, interface-hide and cutscene guards still renew empty submissions.
Ordinary groups retain their existing rules. This does not reproduce stock appearance or every native
animation; native menus/arrows already retain their own rendering behavior in either mode.

Default behavior remains off by default and **is not live-validated**; previous user confirmations
describe the replacement modes before this optional setting. Native anchoring cannot be enabled.

The native target box is one window containing both its HUD information and its overhead arrows.
Target mode removes the stock HUD drawing, **not the native arrows**: their animation, position,
range colours and target/subtarget selection remain the client's own. It does not use hideparty's
Lua cursor implementation or install an alternate cursor addon.

All three custom target windows follow the native target window's drawing lifecycle. In particular,
a lingering custom fade/target-of-target cannot outlive a native target window that stops rendering.
Sub-target transitions, inactive targets and target index 0 (doors) still need live testing. A door
with no entity may retain its native arrow without having a custom target information bar.

Disabling one mode immediately releases only its own submissions, leaving the other mode active.
`/unload partyhook` restores the renderer and arrow call sites and leaves the stock HUD alone.
Organize mode uses ordinary ImGui windows and temporarily restores stock HUD frames. Expanded chat,
maps and other configured hiding rules (with default behavior off) **renew empty replacements** for enabled groups so
stock frames cannot reappear after the two-frame freshness timeout. Target arrows continue to follow
the game's normal visibility rules even while the custom target information is hidden.

To return fully to the old overlay setup, turn both native modes off, unload partyhook, and only then
reload hideparty if wanted. With either mode off and hideparty absent, that group's stock frames and
ordinary Party windows can both be visible.

## Rendering implementation

`Window::Render(this)` is detoured. Only the three party/alliance HUD windows and the target HUD
window are identified by their live objects' `+8` window pointers, not a remembered heap address.
The adjacent `partywin`, `raid1`, `raid2` menu-registry entries identify party globals; `targetwi`
identifies the target global. Both primary globals are independently cross-checked against hideparty's
code signature. Renderer/registry ambiguity leaves stock drawing enabled. Missing target/cursor
signatures disable target replacement without breaking recognized party replacement.

After each real opted-in window's content/background/border/titles, Lua calls a versioned shared-block
function pointer while that window is still ImGui's current one. C++ copies indexed triangles and
texture runs, CPU-clipping to each draw command's rectangle (D3D8 has no scissor), and retains textures.
Only after a complete copy does it zero source command element counts. Layout/hit-testing remain in
ImGui; anchor measurement, settings, tooltips and non-opted-in windows are never consumed. Native
menus disable captured-window mouse input/hover to avoid acting through covering menus.

At the native render call, C++ scales the previous submission from ImGui display pixels to the current
viewport, draws it, then runs the original native renderer. All four buffered/UP GPU draw callbacks
block submissions **only inside that native call**. No persistent visibility flags, list counts,
party indices, cursor offsets or navigation routines are changed. The client traverses windows in
several passes: replacement geometry replays once per HUD window per presented frame while native
HUD submissions are suppressed in every pass. The three custom target drawings have separate buffers
but replay as a group at `targetwi`; all three must be fresh before the stock target box is suppressed.

### Preserving native target arrows

Two signature-verified `E8` calls at the end of `Target::Draw` draw `anc_l`: one for the main target,
one for the subtarget, using the current animated sprite and the client's own coordinates and colour.
Both are cross-checked against the same independently recognized `Sprite::Draw` callee before either
is patched. Only these two CALLs are redirected, never the general sprite renderer. The wrapper passes
`this` and all eight stack words unchanged, permits GPU calls during the original sprite draw only
while in a replaced target window, then restores HUD suppression. Both call sites restore on unload.
Outside target replacement they simply run their original draws. No duplicate-arrow suppression is
added; the client retains its original passes/alpha behavior.

### Recent namehook/buffhook fixes retained

- No `ImTextureID` or font texture pointer crosses Lua. C++ reads texture-reference **fields**, not
  assertion-bearing `GetTexID` methods. IDs above `0x80000000` remain valid; low/sentinel IDs and
  pending/destroyed textures are rejected.
- Texture runs hold Direct3D references. A changed atlas texture prevents replaying stale glyph UVs.
- State blocks are released every Present, not retained across frame/reset boundaries.
- Repeated native render calls do not duplicate the replacement HUD geometry.

Submissions expire after two presented frames without renewal. Empty means intentionally hidden;
missing/stale means stock drawing. Failed capture leaves ImGui commands unconsumed and clears that
slot; failed replay leaves native drawing enabled. Limits per slot: 196,608 clipped vertices and
4,096 commands, with whole-capture rejection on overflow. ABI 3 retains the six slots/counters and
adds a geometry-source flag plus four viewport-normalized, frame-stamped rectangles; the shared block
is **168 bytes**. Rectangle discovery independently verifies the `Window::GetRect` pattern and its
in-module menu-manager address. Read native `+0x3a..0x40` bounds and, for `+0x99` scaled windows,
the menu-manager's width/640 and height/480 factors; normalize to the current D3D viewport before Lua
converts to ImGui display pixels. No native rectangle/visibility/navigation writes or pointers pass to
Lua. Geometry is recorded after original layout and expires after two frames. A missing geometry
signature disables anchoring, not working replacement modes. This is a prior-frame layout handoff.
Anchoring is currently gated off in Lua; these fields remain for ABI compatibility.

**Remaining validation:** optional default behavior, zoning, font rebuild/device reset recovery, full-alliance frame-rate cost,
and other client/render configurations. Initial user testing confirms native suppression, target
arrows, menu overlap and the target transitions listed above on the tested setup; batching/first-pass
behavior on other clients remains unproven. Handoff uses prior-frame geometry as buff/name replacement does.

## Checks

```
plugins/partyhook/build.sh
plugins/partyhook/tests/run.sh
plugins/partyhook/tests/performance.sh
luajit tests/party_hook_check.lua
luajit tests/party_hook_performance_check.lua
luajit tests/harness.lua party addons/party/party.lua tests/party_hook_integration_check.lua
luajit tests/harness.lua party addons/party/party.lua tests/party_native_positioning_check.lua
python3 plugins/partyhook/tests/check_client.py /path/to/ffximain.bin /path/to/ffximain.txt
```

C++/Wine tests cover renderer fixtures/ambiguity, detours/trampolines/restoration, registry checks,
arrow call-site/callee validation and restoration, scoped GPU bypass, clipped UV/colour interpolation,
and ABI size. Lua tests cover ABI gates (including rejecting the old DLL), reloads, six slots,
independent group disable, actual target-window capture timing, default-off migration, hidden empty
renewal past the timeout, Organize fallback, default-behavior solo/order/fading and loading guards,
parked native anchoring, cleared saved opt-ins, hidden controls and preserved ordinary positioning. The optional private codedump check verifies actual
signatures/call destinations. Do not commit/distribute the client dump. None emulates live GPU output.

### Optimization checks

Capture fast-accepts wholly inside triangles and rejects triangles wholly beyond one clipping edge;
partial triangles still use the original UV/colour-interpolating clipper. Post-clipped adjacent texture
runs merge without reordering; empty runs retain no texture. Retains are exception-safe. The 4,096
source-command limit remains independent of the merged run count. Replay checks the font atlas on
every pass but queries the viewport/transforms only once per successfully replayed slot/frame.
Native rectangle reads still sample the current viewport after original rendering; they are not cached
across native passes where layout or viewport state could change.

The portable host benchmark compares optimized clipping bit-for-bit against full clipping on 10,000
random triangles and tests run/reference ownership, failed retains, boundaries and ordering. A one-million
triangle workload (90% inside, 5% outside, 5% partial) measured 58.10 ms full vs 9.99 ms optimized on the
development host (~5.8× clipping speedup). Synthetic adjacent same-texture commands merge 1,000→1;
real gains depend on actual ImGui command/texture patterns. Neither result predicts whole-addon FPS.
Lua tests disable JIT and isolate allocating test doubles: stable renewal, native rectangles/anchoring,
and idle-disabled frames measure 0 B per call; idle shutdown issues no DLL queries/calls. Live client
GPU/CPU timings, full-alliance load and device recovery still need validation.

### Testing-build checklist

- Default positioning and alliance-native-location controls are absent; older enabled settings cannot
  reactivate native anchoring. Verify existing manual/automatic positions and links are unchanged.
- Settings and `/pt native status` show mode/readiness text without rising debug counters.
- Arrange alliances independently in Organize with Automatic Positioning off; unlink Alliance 3 from
  Alliance 2 if each should move separately.
- Remain leader after everyone leaves: header stays Party and Hide When Solo does not hide it.
  Leave/disband: header becomes Solo and Hide When Solo applies.
- Toggle default behavior: native party order/solo visibility, no idle/presence fades, native menu/chat
  layering; interface hide/cutscenes/loading must remain hidden. Ordinary groups must be unchanged.

### Live target checklist

- Select/switch PC, NPC and monster targets: one custom box, native overhead arrow still present.
- `<stnpc>`, `<stpc>`, `<stpt>`, `<stal>`: main/sub windows and arrows agree, native range tints remain.
- Target-of-target enabled; main/sub visibility toggles; no target; rapid switching/despawn; doors.
- Expanded chat and maps: custom bars hide without stock HUD reappearing; close to restore.
- Menus/macro palettes partially overlap; no tooltip/input through covering menus.
- Zoning, cutscenes, UI hide/show, font changes, output/menu resolution, device reset.
- Target mode off preserves party mode; party mode off preserves target mode; plugin unload restores
  stock target information and native arrows without patches left behind.

Party/alliance checks remain: solo/full party/trusts/pets, alliance joins/leaves, selection across all
18 slots and back, party-order rearrangement, keyboard/controller, and full-buff performance.

MIT, as buffhook; see `LICENSE.md`. Toolchain/SDK requirements are the same as buffhook.
