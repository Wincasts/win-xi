# Changelog

## namehook 1.41 — blocks frozen for 1.0

- The shared blocks (HookShared, HookCapabilities, HookDraw, HookBubbles, HookPopups, HookPopupDraw) are frozen at their 1.0 layout until 2.0 (plugins/ABI.md): each grows only at its end, records never, and `tools/abi_check.py` (in tests/run.sh) fails on any other change. lens's block is read by `lens::Live` when it is at least 1.0's size, so a newer lens that adds to it is still read. Nothing in any block's layout changed; ABI 3 as before.

## namehook 1.40 — safe patching of the client's code

- Every write to the client's code goes through `src/CodePatch.h`. Each site keeps its bytes as found; all the patches are made ready first and go in together, and a load that cannot write one takes back those it wrote and fails (-22 unreadable, -23 unwritable) with the client unchanged. Writes make each page writable only while writing, give it back its own protection and flush the instruction cache, instead of relying on the code pages being writable already.
- Unload gives a site back only while it holds what namehook wrote, and so never undoes a patch something else has put over it since. Such a site is left alone; namehook's module is then pinned, as the client may still call into it from there, unload reports -26, and loading again before a restart is refused with -24, and the refused load's own unload does nothing more. The stars' jump, which leads nowhere into namehook, is left the same way without stranding anything. `hidestars`/`showstars` and `othercalls` check the same before changing a site, and say when they cannot; a site something else has put back as found is written afresh by the next change. A write that goes in only in part leaves its site abandoned.
- Reads of the client's code beside the patches (the line calls and the functions they go to, the damage patch's surroundings) are checked as readable first; sections that are not committed are skipped when looking for calls, and a found call that overlaps a patch is not taken.
- Tests: commit, rollback after a failed write, a failed rollback, a site changed before it is written, conflicting writers on unload and on a live change, the real code memory across an execute-read page and a read-only one (protections restored) and before a no-access page, and the plugin's unload, stranding and refusal to load again.

## namehook 1.39 — scanner bounds and state-block failure handling

- Bound the whole decoded signature, including wildcard prefixes and trailing runs, before forming a candidate pointer. Missing modules, short images and malformed run encodings fail closed. Scan only committed readable image regions, retaining matches across adjacent readable protection regions. Literal/wildcard runs longer than 128 bytes are split, and one-byte literal needles are supported.
- Check state-block begin/end, capture and apply results. Failed capture does not mark cached state valid or proceed with drawing; failed name-state application attempts restoration, and failed application/restoration invalidates the run and stops further custom drawing until reinitialized. ABI 3 and capabilities are unchanged apart from the build number.
- Tests cover absent/short images, prefix/suffix bounds beside guard pages, final-position matches, malformed encodings and a fake device's state-record/capture/apply/restore failures and recovery.

## namehook 1.38 — damage popups listed, and claimable

- The client's damage popups (its numbers and "Miss!" over whoever was hit) go through the plugin. The damage patch, which already set their size, hands each to `OnDamagePopup` as the client is about to draw it, with its object, colour, place in the world, size factor and letter size. It is listed in a new block, `HookPopups` (magic `NAMEHOOKPOPUPS`, version 1), found apart from `HookShared` as the bubbles are, so ABI 3 is unchanged: an id kept while it is drawn, its text (`:` for a miss, drawn by the client's font as "Miss!"), who was hit and who hit them (from the effect's generator, reached through the popup's `+0xFC`: the actors at its `+0x40` and `+0x3C`, read from the running game for every popup, looked for among the entities' actors by the host), its colour and fading, and its place on screen as for a name. Each hit makes two popups, the number and a darker copy.
- An addon can claim the popups (`HookPopups::Claimed`, `ClaimFrame`): the client then draws none, and they are still listed. The claim lapses as a name claim does.
- The plugin draws an addon's quads for a claimed popup in its place: a `HookPopupDraw` (found through `HookPopups::Draw`) holds a drawing for each popup by id, in the names' quad format, drawn in the client's popup drawing at the point it gives, so the popup's rise and fade go with it. The host readies a camera, the textures and a horizontal fit for the popups once a frame (`BeginPopups`, `PrepareCamera` shared with the names), draws through the names' path with the popups' own bounds (`RenderCustom`'s `Layer`), captures the client's state afresh for each, and with `POPUP_DRAW_OVER` draws without the picture's depth.
- The extra code runs only where the client's code around the patch is as read from the running game (the point put in `[esp+0x14]` before it, the function's end `0xAE` after its start); otherwise the patch jumps past it, the popups are not listed and the client draws them as before. `/namehook status` says which.
- `/namehook popups` says last frame's popups in the chat log; `/namehook popups watch on|off` says each new one as it appears.
- tests/test.cpp: the block and the drawing buffer laid out as winxi.popups reads them; a claimed popup drawn from its own drawing at its point and the host readied once a frame, none for a popup without one, a drawing past the quads, one from another frame or a stale buffer; the patch's jumps, a popup listed once a frame with who was hit, who hit them and its screen place, each looked for once (none for no actor, an unknown one or no generator), its id kept and renewed, the names not made ready again for popups alone, the claim and its lapse, a full list, the command and the watch.

## namehook 1.37 — soft textured rectangles

- `QUAD_SOFT_RECT` no longer needs a constant texture coordinate: a textured, unedged quad that asks for it gets the same one-pixel screen-space fringe, each point with the texture coordinate of where it is in the quad (`SoftRectangle::InnerAt`/`OuterAt`), the outer fringe clamped to the quad's edge so it never samples past it. Name uses it for the fill of its textured health and cast bars. The capabilities sidecar says so (`FEATURE_SOFT_TEXTURE`, 16; Build 137). Older plugins draw such a quad hard.
- tests/test.cpp: the inner and outer points' places within the quad; the capability.

## namehook 1.36 — doubled colours

- A quad an addon draws can ask for its colour to be doubled as the client's own are (`QUAD_DOUBLED`, Flags bit 5): drawn with `D3DTOP_MODULATE2X`, 0x80 in a channel is the texture as it is and more brightens it. The client draws a linkshell pearl so, and a pearl's colour goes above 0x80; drawn plainly it could be no brighter than the icon, and was darker than the client's. Only the quad is doubled, never its edge or shadow. Such quads are runs of their own (`NameRun::doubled`), the stage put back to `MODULATE` after them. The capabilities sidecar says so (`FEATURE_DOUBLED`, 8; Build 136).
- tests/test.cpp: a doubled quad a run of its own, of the same texture, and the next not; the capability.

## namehook 1.35 — audit fixes and bounded submissions

- Add a versioned `NAMEHOOKCAPS` sidecar, without changing ABI 3, so newer Name/WinXI can verify independent icon outlines. Older consumers and speech bubbles retain their existing API.
- Cull Lens drawings using counter-transformed bounds, including shear and a conservative screen-space AA fringe. Fix names rejected by untransformed bounds despite reaching into the viewport after compensation.
- Merge adjacent runs whose slots point to the same texture; preserve all vertex/compositing order. Reject zero-alpha quads before expansion, and skip depth submissions whose maximum vertex alpha cannot meet the alpha-test threshold. No cross-texture reordering or removal of the occlusion pass.
- Remove the write-only plugin ID. Runtime/help, CMake and Windows resources now derive their version from `src/Version.h`.
- Test both Lens modes, sheared/contracted bounds, alias merging, alpha thresholds and unchanged ABI/capability structure.

## namehook 1.34 — independent icon outlines

- Optional ABI-3 `QUAD_EDGE_RADIUS` (flag 16) overrides the text edge radius using Reserved bits 8..23 in 1/256 target pixels, capped at 8. Low-byte edge opacity is unchanged. Explicit radii work with text outline zero and override the legacy tight-icon one-pixel cap; tight icons still omit the shadow.
- Rendering and culling share radius/opacity rules. Zero-width or zero-opacity edges skip halo/shadow copies, without changing fills or maximum geometry capacity.
- Name provides separate Icon Outline (0–3 px) and Icon Outline Opacity (0–100%) settings. All outlined icons use these controls; text, mastery stars and letter badges remain independent. Updated WinXI is required to submit explicit radii.

## namehook 1.33 — tight outlines for aggro/passive glyphs

- Optional ABI-3 `QUAD_TIGHT_EDGE` (flag 8) caps an outlined icon's halo at one render-target pixel and omits the downward shadow. Name opts its aggro/passive and tracked-monster `[aggro]` glyphs into this style at full outline opacity. Text and other icon outlines retain their existing rendering; Outline 0 still disables edges.
- The radius and shadow rules are shared with culling bounds and tested at zero, fractional and thick outline sizes. No new texture or draw-buffer capacity is needed; tight icons omit a shadow copy.

## namehook 1.32 — smoother name halos and health bars

- Custom name outlines use eight circularly spaced glyph-mask copies instead of four diagonal copies, with a restrained downward shadow. Text retains its colour, size and position; icon edge-opacity multipliers and the zero-outline setting still apply. Depth testing and the alpha-tested depth pass are unchanged.
- ABI 3 gains optional `QUAD_SOFT_RECT` (flag 4): constant-UV, unedged solid rectangles get a one-render-target-pixel alpha ramp around their edges, calculated after Lens counter-transformation. Subpixel fill slivers have reduced coverage instead of becoming opaque thick lines. Name uses it for HP bars without another texture or extra shared-buffer quads. Older plugins ignore the flag and retain hard edges.
- Draw-vertex and texture-run capacities include the worst-case halo/shadow expansion. Bounds include the new shadow and bar fringe. Geometry tests cover rotation, shear, nonuniform scaling, tiny fills and degenerate rectangles.

## namehook 1.31 — names under lens's cylindrical warp cheaper

- Built against lens 0.6's `warp.h`, whose cylindrical mapping finds its edge once a call instead of in every step: `lens::Counter`, worked out for each name each frame, takes about 2 µs a name in cylindrical mode where it took about 35 to 55 (some 3 ms a frame with 60 names on screen). Panini was cheap already. Nothing drawn changes.

## namehook 1.30 — names kept their shape under lens

- Under the lens plugin's warp (plugins/lens), which bends the world picture names are drawn into, each name and bubble an addon draws is put through the counter of the warp's stretch where it stands (`lens::Counter`, the inverse of the warp's local Jacobian), so that it comes out of the warp at its own shape and size, where before it was squeezed toward the sides of the screen. Names are still drawn in the world, so walls and terrain still hide them and their depth is still written. The warp is read from the block lens.dll exports as `LensWarp` (`lens/src/shared.h`) once a scene, with the scene's own projection for its fields of view; without lens, or with its warp off, the counter is the identity and names are placed as before. lens's tests/warp.cpp: an offset put through the counter comes out of the warp as it was, within a pixel.

## namehook 1.29 — its own settings, one client, tidier

- The settings and the whitelist are read from `config\namehook` alone. Those the plugin kept under its old name, nameplatehook, and nameplatew's (its `mode` made into hidden categories, its whitelist) were read before the first save; from nameplatew the categories are set by hand once, or with the name addon.
- Only the newer version of the client's name-drawing function is patched, the one the two line calls are hooked in; the older one, which Nameplate also patched and which gave a plugin that showed and hid names but listed none, is not looked for: a client with it does not load the plugin (`Plugin Load Error: "-14"`).
- The device's state is captured once for a run of names an addon has drawn, and put back after each, where it was captured before each: while the client draws nothing itself between two names, what was captured is still its state. The client drawing a line of a name itself (`ClientDrew`), a new scene's names and the frame's end each have it captured afresh. `/namehook keepstates off` captures it before every name as before, kept in `defaults.ini` (`KeepStates`); `/namehook status` says which. To be checked in the game: if what the client draws after the names looks wrong, turn it off.
- Tidier, with nothing changed: the version is said in one place (`NAMEHOOK_VERSION` in `Nameplate.h`: the help said 1.24 while the plugin was 1.28), the sizes and the stars are kept once where the client's patched code reads them, a function's address is written into a patch by one helper, a command's words are matched by their text alone, the operand reader of `bytes.h` is one function, and a wide-character `Debug` nothing called is gone. tests/test.cpp follows.

## namehook 1.28 — timed, not counted

- A claim lasts half a second without being made again, and a name the client draws more than once a frame is lifted for half a second after the last frame it did: timed by the system's steady clock (`HOOK_CLAIM_TIME`, `LIFT_TIME`, in microseconds), read once a frame. Both were 30 frames, half a second at 60 frames a second and a fifth of one at 144. tests/test.cpp: a clock that goes a frame on each time it is read; a claim lasts 72 frames at 144.

## namehook 1.27 — eight frames' grace

- What an addon has drawn (names and bubbles) is good for eight frames, not two (`HOOK_DRAW_FRAMES`). Under TrueFPS the game can present a few frames before the addons are next run, and with two the client's own names showed for a frame now and then, along with everything uihook replaces. An addon that stops without a word gives the names back within eight frames: about 90 ms at 90 fps.

## namehook 1.26 — loads after TrueFPS

- namehook loads when TrueFPS loaded first and has already patched the client's frame-step accessor, the function namehook finds gGame through. TrueFPS turns the accessor's first two bytes into a short jump to the padding after it, and the signature no longer matched: namehook failed with `Plugin Load Error: "-4"`, or loaded, depending on how soon after TrueFPS it ran. A second signature takes the accessor as TrueFPS leaves it; the address of gGame in it is unchanged.

## namehook 1.25 — imgui's font texture read by the plugin

- A texture of `1` (`HOOK_TEXTURE_FONT`), in the names' textures or the bubbles', is imgui's font texture, which the plugin reads itself each frame from Ashita's imgui. Its id is 64 bits and a Lua integer in this client 32: once the texture is above 2 GB, as it can be after a while on Windows, Ashita could not hand it to the addon at all, and Name's names were the client's for the rest of the session. `FontTexture` says which texture it drew from.
- `NAMEHOOK` is version 3 (`FontTexture` is new, after `TargetHeight`) and `NAMEBUBBLES` version 2, so that an older plugin, which would take `1` for an address, is not used by the addons that give it.

## namehook 1.24 — independent world-space bubbles

- Add a separate `NAMEBUBBLES` shared buffer for additive, depth-tested speech bubbles. It does not claim or replace names and works independently of category visibility, alongside stock names or Name's custom names. The existing `NAMEHOOK` v2 layout remains unchanged.
- Keep bubble textures and bounds caches separate from the custom-name layer. Validate bubble server IDs, entity indices, quad ranges and drawing freshness; stale drawings expire after two frames. The `chatbubbles` addon supplies `/say` text and glyph quads.

## Unreleased — rendering optimizations

- A name the client draws more than once in a frame, as it does for a player who is fishing, is listed and drawn for an addon once, where it was listed each time and drawn at each place: the name was doubled, and with the addon taking the last of them, could vanish. The call that draws all the names is taken over any other, and where it draws a name more than once, the highest of them: the client draws them in an order that changes as the camera moves, and taking the first had the name jump between the head and the feet. The client still draws a name it is left to draw each time, as it would. `/namehook status` says how many such repeats there were last frame.
- A name the client draws more than once in a frame no longer flickers as the count changes from frame to frame, as it does for a player fishing. The first of them is drawn for an addon at once, and one lower than halfway between the lowest and highest of the last frame that had more than one, within half a second, is drawn and listed where the highest was, with its size and colours. A lower one was left in the hope of a higher, and when none came the name vanished for two frames; or it was taken as it was, after a frame with one, and the name dropped for a frame. `/namehook status` says how many were moved up last frame.
- Support optional per-quad outline opacity, allowing small Name icons to use a softer edge without changing their fill or the text edge. The existing quad layout is unchanged: flag bit 1 enables an opacity byte in `Reserved`; ordinary and older quads retain full opacity.
- Use a fixed-capacity hash index for whitelist lookups, preserving case-insensitive matching and original list/save order. Adds update the index directly; removals and reloads invalidate it.
- Cache complete custom-name bounds per entity/drawing batch and skip vertex expansion and Direct3D submission when the entire drawing is outside the viewport. Bounds include outlines, stars, icons and check-detail lines; off-screen anchors alone are not culled.
- Cache name and damage scale factors until resolution or font settings change, instead of repeating divisions for each draw call.
- Calculate each outlined quad's faded outline colour once, reusing it for all four corners.
- Size the texture-run array for every expanded quad, including all four outline copies; alternating textures could previously exceed its capacity.
- Skip the depth-only pass for a name none of whose quads is at least half solid: that pass tests alpha against 0x80, which such a name cannot pass anywhere, so nothing drawn changes. Names fading in or out are then one pass and not two.
- Add `tests/benchmark.sh`, a CPU-only comparison of old linear whitelist lookup and the new index. It is not a rendering/FPS benchmark.
- Keep state-block lifetime unchanged: the SDK has no pre-reset callback to safely release retained client-resource references. Cross-frame state-block reuse and dynamic vertex buffers remain deferred pending reset handling and in-game measurements.

## namehook 1.23 - 2026-10-11

- Every call in the client to its two functions that draw a name's lines is found and taken, not only the two in the function that draws all the names: a name the client draws by another way is then shown, hidden, listed and drawn for an addon like any other. `/namehook othercalls off` goes back to taking only the two, and `on` to taking them all; the setting is kept in `defaults.ini` as `OtherCalls`.
- `/namehook status` says how many such calls there are, and how many lines drawn last frame were nobody's.

## namehook 1.22 - 2026-10-11

- The edge round a quad of a name an addon has drawn is as solid as the quad itself is, where it was as solid as the whole name: a part of a name that is fading takes its edge with it.

## namehook 1.21 - 2026-10-11

- `target on` no longer shows your own name: with own names hidden, your name stays hidden while you have yourself targeted.

## namehook 1.20 - 2026-10-11

- Renamed from nameplatehook to `namehook`: the DLL, the `/namehook` command and the `config\namehook` folder all carry the new name, and `/nh` is short for the command where `/nph` was.
- Until `config\namehook\defaults.ini` exists, the settings and the whitelist kept in `config\nameplatehook` are read, and failing those nameplatew's as before.
- The block is found by `NAMEHOOK` and eight 0s, where it was `NAMEPLATEHOOK` and three: an addon written for nameplatehook does not find it.

## nameplatehook 1.11 - 2026-10-11

Does what 1.10 does, with less work each frame:

- The names are made ready for addons once a frame, in the scene they were drawn in, and again only if more are drawn. The client ends a scene a dozen times a frame, and they were made ready each time, the camera asked after and every name copied.
- Everybody's pets are looked for once in 16 frames, not every frame: it is a look at every player and every pet there is. A pet that appears is taken for an NPC or a monster for a quarter of a second at most. The local player's own pet is still found every frame.
- A player's name is looked for on the whitelist by a number made from it, and compared only with the names that have the same number.
- The device's states for drawing an addon's names are made when the frame's first such name is drawn, not at the frame's first name of any kind; the device is asked for once a frame, not once a name; and a name drawn from one texture has it set once, not twice.

## nameplatehook 1.10 - 2026-10-11

- An addon can have the plugin draw names for it. It leaves each name set out as quads (a rectangle of a texture for each letter and icon) in `HookDraw`, found through the block's new `Draw`, and claims the name's category; the plugin draws the quads in the client's own picture where the client was about to draw the name, as deep in the picture as the name is, so that whatever is in front of the name hides it. `README.md` describes it.
- The block says how large the picture the client draws the world on is (`TargetWidth`, `TargetHeight`), which may be larger than its window. They and `Draw` are where `Reserved` was, and the block's `Version` is 2: an addon written for 1 does not read it.
- A name drawn that way is listed with a new flag, custom (0x100).
- Added `/nameplatehook probe`, which says what the client is drawing on as it draws a name. It is for finding out how a client draws, and is not in the help.
- The plugin answers Ashita's `Direct3DInitialize`, without which 1.00 was not loaded.

## nameplatehook 1.00 - 2026-10-11

Forked from nameplatew 0.60 as `nameplatehook`: the DLL, the `/nameplatehook` command (`/nph` for short) and the `config\nameplatehook` folder all carry the new name. nameplatew was itself forked from Nameplate-AshitaV4 0.1.0, of Nameplate 0.51; their changes are listed in nameplatew's `CHANGELOG.md`.

- Every name is sorted into one of eight categories (self, party, alliance, players, mypet, pets, npcs, monsters), and each category's names are shown or hidden with `/nameplatehook show|hide|toggle <category>...`. These take the place of nameplatew's `mode` and `alliance` commands, which are gone.
- Added `/nameplatehook target on|off`: the target's name is shown whatever its category.
- Added `/nameplatehook status`.
- The names the client was about to draw each frame are listed for addons, hidden ones among them: whose each is, its category, where it is in the world and on screen, its colours, what the client writes for it, and whether it is drawn. The list, and the settings beside it that an addon may write, are described in `README.md`.
- An addon can show or hide the name of one entity, and can claim categories whose names it draws itself in place of the client.
- The client's two calls that draw a name's lines are pointed at the plugin, when both are found where they are expected; they are put back on unload. On a client where they are not, names are shown and hidden all the same, and none are listed.
- Which categories are hidden, and the target setting, are kept in `defaults.ini` as `Hidden` and `AlwaysTarget`. Until that file exists, settings are read from nameplatew's `config\nameplatew\defaults.ini`, its `NameMode` becoming the categories it hid, and the whitelist from its `whitelist.txt`.
- The whitelist is as it was, and is of players only.
- Removed the Windower 4 entry points, which nameplatew did not build.
