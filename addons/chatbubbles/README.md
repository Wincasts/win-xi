# chatbubbles (proof of concept)

Standalone Ashita v4 **configurable chat bubbles**, rendered by namehook in the world's
nameplate pass. They follow the speaker's current above-head position and are
depth-tested against the scene, like the names, instead of drawing on top of walls.

## Install / upgrade

Requires **namehook 1.24 or later**. Both the updated addon and updated plugin are
needed; updating only Lua will not enable world rendering.

1. Copy `plugins/namehook/build/namehook.dll` to `<Ashita>/plugins/namehook.dll`
   while the plugin is unloaded (or the game is closed).
2. Install this folder as `<Ashita>/addons/chatbubbles`.
3. Keep the project's `addons/libs/winxi/nameplates.lua` and `safe_memory.lua`
   installed in `<Ashita>/addons/libs/winxi/`.

```text
/load namehook
/addon load chatbubbles
/say Testing a speech bubble!
```

If upgrading in-game, unload `chatbubbles`, unload `namehook`, replace the DLL,
then load `namehook` and `chatbubbles` again. `/addon reload chatbubbles` alone
**does not reload the DLL**. `name` may remain installed and runs alongside the
bubbles. Do not load nameplate/nameplatew alongside namehook.

Messages last 8 seconds with a final 0.6-second fade. A new message replaces that
speaker's previous bubble. Own speech is read from outgoing chat packets without
requiring a server echo; other players' speech comes from incoming chat packets.
The normal chat log is unchanged. `/s` is the game's abbreviation for `/say`.

## Commands

| Command | Effect |
| --- | --- |
| `/chatbubbles` or `/chatbubbles settings` | Open/close the settings window |
| `/chatbubbles status` | Report state, compatibility, enabled-chat packet counts and last-frame anchors/matches/submissions |
| `/chatbubbles test` | Show an 8-second test bubble over your character, plus a fixed diagnostic UI label |
| `/chatbubbles target [text]` | Show an 8-second local test bubble on your current target; defaults to `Test speech bubble` |
| `/chatbubbles on` | Enable bubbles (the default) |
| `/chatbubbles off` | Disable and clear bubbles |
| `/chatbubbles clear` | Clear current messages |
| `/addon unload chatbubbles` | Remove bubbles without changing name filters |

The test's fixed label is intentionally still a UI overlay; speech bubbles are not.

## Settings

Open `/chatbubbles`. Settings are saved per character using Ashita's settings
library, including the global enable switch, colors and individual channel switches.
No DLL change is needed for these settings if namehook 1.24+ is already installed.

- **Appearance:** White bubbles and Dark bubbles presets, a Background RGBA
  picker, and **Match in-game chat text colors** (on by default). Real chat uses
  the colors currently selected in **FFXI Config → Font Colors**, including NPC
  dialogue. Text RGBA is the manual/fallback color when matching is off, for
  local test bubbles, or when the client lookup cannot be resolved. Its opacity
  applies even when using game RGB colors. Changes apply to active bubbles.
  Presets change manual colors but do not turn game-color matching on/off.
  Game-colored text gets a thin dark outline on light backgrounds, preserving
  the selected RGB while keeping white text readable on white bubbles.
- **Chat Modes:** individual switches for all 36 catalogued incoming chat packet
  modes (0–35), including Say, Shout, Tell, Party/Alliance, Linkshell 1/2, Yell,
  Emote, Unity, Assist channels, no-speaker variants, system and reserved modes.
  It also lists **NPC text channels 150, 151, 152, 142, 144 and 210**, using
  separate settings keys from player packet channels. Enable All / Disable All
  buttons apply to both groups. **Say and NPC dialogue 150/151 are enabled by
  default**; other channels are opt-in, especially private channels such as Tell.
  Channel 152 includes prompt traffic and is opt-in to avoid menu noise.

Disabled modes are rejected before message decoding; disabling a mode also hides
its currently active bubbles. Incoming channels use packet `0x017`; outgoing
channels use `0x0B5`, and your outgoing tells use `0x0B6`. Own speech therefore
does not depend on receiving a server echo. A channel can be enabled without a
visible bubble if its speaker is remote, unidentified, or absent from namehook's
current player list. Unknown/system modes are listed explicitly but may have no
usable speaker; enabling them does not manufacture an anchor. Player controls are
chat **packet** modes. NPC controls are the explicitly labelled **text-log** modes;
the two namespaces are kept separate rather than conflating their IDs.

Appearance is stored in a dedicated `appearance` settings group and passed to the
world renderer, separate from the `modes` group and packet reader. `colors.lua`
resolves real log modes through FFXI's live mode-to-palette-slot and palette-color
lookup tables. It scans instruction signatures, validates repeated table operands,
and uses read-only, VirtualQuery-checked memory access; it never patches or calls
client code. Palette snapshots refresh every 0.25 seconds, so in-game color edits
also update bubbles already visible. Incoming/outgoing packet modes are mapped to
log modes separately; NPC messages already carry log-mode IDs. Native colors use
0x80 as full intensity and are converted to the renderer's 0xFF range. Unknown
mappings or unsupported clients safely retain the manual color, with lookup
failures reported by `/chatbubbles status`. This follows the **native FFXI palette**,
not custom palettes configured separately in FancyChat or another chat replacement,
and uses one channel color per bubble rather than reproducing inline item colors. `config.lua`
owns settings/UI, `modes.lua` owns channel metadata, and `world.lua` owns rendering,
so additional appearance controls or channel policies can be added independently.
Local `test`/`target` commands bypass channel switches so tests still work when
all real chat channels are disabled.

To test without another player, select any nearby player, NPC or monster and run:

```text
/chatbubbles target Hello from your target!
```

This only creates a local visual bubble: no chat or packets are sent, and the target
is not made to speak to anyone else. The command also works with an active subtarget.
It re-enables bubbles if disabled. The bubble stays attached to that selected entity
if you change targets, expires after 8 seconds, and is removed by `clear`, `off`,
zoning or unloading. Entity index and server ID must both match, so another
same-named NPC or an entity reusing its index cannot inherit the test bubble.

## NPC dialogue (experimental, v0.7+)

The addon observes the game's original **`text_in`** event for NPC channels. This
provides the final localized dialogue after FFXI has resolved message IDs and
parameters, so no separate DAT parser is needed. Ordinary dialogue channels
**150 and 151 are enabled automatically** when upgrading older settings; saved
explicit NPC preferences are preserved. Additional NPC/prompt/system channels
152, 142, 144 and 210 can be enabled independently in Chat Modes.

Attribution is conservative:

- A `Speaker : dialogue` prefix is matched to a nearby non-player entity. The
  speaker prefix, colors and timed-message/prompt escapes are removed from the bubble.
- Direct message packets **0x027, 0x036, 0x02A and 0x043** provide entity identity
  for unnamed lines and can disambiguate multiple NPCs with the same name.
- Event-start packets **0x032, 0x033 and 0x034** provide an event initiator for
  resolving named dialogue even if it is temporarily absent from the name list.
  They are not blindly used for every cutscene speaker or unnamed narration.
- Ordinary unnamed dialogue may continue a recently identified NPC for up to
  10 seconds. Stale, ambiguous or unidentified lines are skipped; the current
  target is **never** used as a guess. NPC bubbles are bound to index + server ID.
- Duplicate copies of a line within 0.5 seconds do not restart its bubble timer.

The handler is read-only and uses original text even if another chat addon blocks
its normal log display. Chat Bubbles' own NPC channel switches control capture.
The normal chat log and dialogue choices are not modified or blocked.

To test, reload the addon, speak to a nearby NPC, then run `/chatbubbles status`
while dialogue is active. It reports **NPC text received/attributed** counters
and the last attribution failure. Received > 0 with attributed = 0 indicates a
speaker-identification problem; attributed > 0 without a bubble points to anchors,
visibility/depth, or a rendering issue. Cutscene actors or conversations that
suppress the client's nameplate pass can still lack anchors. That remains a
rendering limitation, not an NPC-channel setting.

## World rendering

`world.lua` writes to namehook's new **independent `NAMEBUBBLES` buffer**, not the
name replacement buffer used by `name`. No name categories are claimed, no
visibility overrides are changed, and no normal name is replaced by a bubble.
Bubbles work with stock names or Name's custom names, and when a name is hidden
using Name's filters.

The plugin draws bubbles at the speaker's current nameplate anchor during the
client's name-rendering pass, using the same depth-tested billboard renderer as
custom names. The contents prepared at present are used in the next world frame,
but the anchor comes from that frame's actual entity draw, not stale screen
coordinates. Each layer has independent textures and bounds caches. Bubbles also
carry a server ID to reject drawings if an entity index is reused.

The background, stepped pointer and UTF-8 glyphs are textured quads. They scale
slightly with distance and account for nonuniform background resolutions.
Windows-932 chat is converted to UTF-8 and auto-translate is expanded; glyph
coverage depends on the current ImGui font.

## Scope and limitations

- Player chat requires a nearby identifiable player. NPC text requires an
  attributable non-player speaker and a namehook anchor. Narration, menu-only
  text, ambiguous speakers and cutscene-only actors may be skipped. Combat log
  messages are not decoded as speech.
- Uses namehook's entity/name-rendering pass, so the game's **`/names on`** is
  required. Off-screen, distant or otherwise unlisted speakers have no bubble.
- Text wraps at 280 layout pixels. Bubbles are not clamped or rearranged to avoid
  overlapping other speakers or screen edges. The plugin clips/culls naturally.
- A single entity's bubble is limited to 256 quads (including the background and
  pointer); messages exceeding the budget are skipped rather than truncated.
- The plugin's shared buffer holds 16,384 quads across all speech bubbles.
- The background is a rectangle with a stepped pointer, not a rounded vector shape.
- `drawn` in the status output counts submissions to the native buffer. A submitted
  bubble can still be hidden by scene depth or culled by the native renderer.
- Area changes, disabling/unloading, and missing namehook clear current messages.
  If the addon stops updating unexpectedly, native drawings expire after 8 frames.

## If nothing appears

Run `/chatbubbles test`, then `/chatbubbles status` **while the test is active**.

- A compatibility warning means the updated DLL is not installed/loaded.
- The fixed label tests ImGui independently of world rendering.
- Active messages but zero anchors: check `/nh status` and `/names on`.
- Anchors but no matches: the speaker isn't in the current namehook list.
- Submissions but no visible bubble: check for occlusion and move the camera to
  leave space above the speaker. Check the Ashita error log for glyph/texture errors.

## Tests

From the repository root:

```sh
luajit tests/chatbubbles_check.lua
luajit tests/chatbubbles_world_check.lua
luajit tests/chatbubbles_config_check.lua
luajit tests/chatbubbles_npc_check.lua
luajit tests/chatbubbles_colors_check.lua
plugins/namehook/tests/run.sh
```

The first tests event handling against mocked Ashita/ImGui APIs, including local
target tests, same-name NPC isolation, identity checks and cleanup. The second tests
the actual FFI world buffer and quad writer on Linux/LuaJIT, including isolation,
UTF-8 glyphs, aspect correction, fading, budgets and compatibility. Native tests
cover hidden/stock/custom-name coexistence, entity identity, duplicate rejection,
quad bounds and drawing expiry. Configuration tests cover saved settings,
normalization, both tabs, presets, color controls and all channel switches.
NPC tests cover text-channel gating, original/blocked text events, named and
unnamed dialogue, all supported packet layouts, same-name disambiguation,
duplicate suppression, stale identities, prompt cleanup and safe failure paths.
Color tests cover client lookup signatures/operand validation, palette decoding,
first-match behavior, intensity conversion, incoming/outgoing and NPC mappings,
text opacity, live refresh, manual override and safe failure. The lookup was also
checked against a snapshot of the live client's lookup code and color tables.
Live NPC conversations/cutscenes and visual color matching still need an in-game check.
