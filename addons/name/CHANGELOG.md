# Changelog

## 1.54

- Timed, not counted, so that 144 frames a second is as 60: a leap in a name's size is believed once it has lasted a tenth of a second (it was 4 frames), which is longer than the game's own frame of a 30th under TrueFPS, where the game's full size for a target that has just been taken lasts five frames at 144; the sub target's size is held for half a second after (it was 30 frames); and Diagnostics sees a pause after half a second, as namehook 1.28 does. Needs namehook 1.28 for the game's names to be back after half a second at every frame rate.

## 1.53

- Settings nothing reads any more are no longer kept. Show Mob Level and Show Aggro Icons are gone, as is an unused one for status icons. Show Icons, Mob Letters and Double Letters, and the per-type health bar tables, are read once more from a file saved before the formats and shared bars took their place, brought over as before, and then let go of. A new character's settings, and a settled character's, are otherwise as they were.
- Functions nothing called are gone: `custom.PreviewFont`, `block_rules.Set`, `entity_types.Has`, `name_types.Get` and `Maximum`, and the badge image's `set`.

## 1.52

- Statuses taken off the list no longer come back. Ashita fills each place a saved list lacks from the default list, so a list saved shorter than the default came back with the default's tail on it, statuses unticked among them, some twice; a list emptied came back full. The default list is empty now, and a new character's ticked statuses are given once, as the settings are loaded (`statusListVersion`). A list saved before is kept with each status once, in order: what the merge had already added to it cannot be told from what was ticked, and stays until taken off again.

## 1.51

- The preferred defaults, those a new character starts with, are the author's settings as they are now: names 30 px at most and 10 at least, the sub-target's at 125%; health bars, while off, 120 × 7 px; statuses at 100%, 2 px right and 5 up, with 9, 14, 15 and 128–131 no longer ticked; Other Players and Other Pets shown, Always Show Target off; players' Normal and Alliance Colour Overrides on, pale blue and amber. A character's saved settings still come first.
- `name_defaults.lua` can give part of a table of named keys, as it does `nameColours`: the rest keeps the addon's own defaults. A list, or a setting's `T{ value }`, still takes their place whole.

## 1.50

- The monster tables and notorious monsters' placeholders are winxi's now (`libs/winxi/data`, read through `winxi.mobs`), where any addon can use them; the addon's own `data` and `placeholders` folders are gone. Name needs winxi 27.
- Both are made again from the Phoenix server's live branch as it is on GitHub (commit 9a4494d, 18 October): 27 monsters' level ranges in 14 areas are new, and 8 notorious monsters have more placeholders. Sea Horror on the ferries has none now, the ferries choosing their deck's monsters another way.
- Placeholders are read from the server's lottery slots in each area's data, where the server now keeps them, as well as from the scripts that still list theirs.

## 1.49

- Player Colour Overrides have **Looking For Party**: a player whose icons show they are seeking a party, with or without the star. After Dead, before Party and Alliance. The game has no colour of its own for it, so with it off the name keeps the colour its other state gives it.

## 1.48

- `[level]` takes **exact**: `[level: exact]` writes the monster's level only once a check has told it, and nothing before then or for one impossible to gauge, where plain `[level]` writes the database's range. Text around it, such as `Lv `, stays.

## 1.47

- Colour Overrides follow the states the game colours names by. Players: Normal, **Party**, **Alliance** and Dead. Enemies: Unclaimed, Claimed: You / Party / Alliance, Claimed: Others, **Call For Help** and Dead. NPCs: Normal and **Dead**. In Combat and Targeted are gone, and saved overrides for them are dropped.
- A state left off keeps the game's colour for it, where it fell to another override before: a monster called for help on is not coloured as Unclaimed, nor an alliance member as Normal.
- Call For Help is read from the entity update packet (0x0E): its flags have 0x20 while the call stands.

## 1.46

- Statuses' list leaves out the game's stand-ins, whose names are wholly in brackets — (None), (N/A) and the five (Imagery) — and the numbers the server has no status for (24–27, 224–226, 372–374, 514, 520, 521, and everything past 635). They were at the top of the list, and nothing is ever under them.

## 1.45

- The mob letter is smaller: its badge is about 68% of the name's height, where it was 78%, still sitting on the name's baseline. The plain letter drawn while the badges are not ready shrinks with it.

## 1.44

- Health Bars and Statuses each have **Entity Types**: which kinds of name have a bar, or a row of statuses — Yourself, Party Members, Alliance Members, Other Players, My Pet, Other Pets, NPCs and Monsters, all ticked to begin with. Status Preview keeps to them too.

## 1.43

- The presets are Default, Minimal, **Robust** and **Immersive**. Robust has everything: enemy aggro, level, spawn letters and distance, health bars at all times, status icons and check details. Immersive is near the game's own: names with player icons, health bars only in combat, and no levels, letters, status icons or check details. Hunter and Retail-Like are gone.
- Statuses → Display has **X Offset** and **Y Offset**, in screen pixels from -200 to 200, moving the row from where Position and Alignment put it.
- Statuses' Timers is gone, with the time written under the icons; a saved Timers setting is dropped.

## 1.42

- The Default preset's enemy format is `[aggro] [name] [letters]`: no level range, and the spawn letter at the end. Reset Format and a new character's settings give the same; saved formats are kept.

## 1.41

- A **General** tab, first. **Preset** gives the settings a premade look, Default, Minimal, Hunter or Retail-Like: the formats, the check line, health bars, status icons and check details, leaving font, sizes, colours, visibility and the chosen statuses; it says Custom when they are none of them. **Custom Nameplates** (on) is Name drawing the names: off, it lets them go at once and the game draws its own as namehook sizes them, Visibility still applying. **Health Bars** and **Status Icons** are there too. Diagnostics take Custom Nameplates off as chosen, with no log.

## 1.40

- Statuses → Display has **Icons**: Winxi Theme, to begin with, follows Custom Icons in `/wxi` as before; Game Icons and Custom Icons draw the game's or the custom set's whatever the theme has. The set is still the one chosen in `/wxi`.

## 1.39

- Health Bars is a tab of its own, second, with Enabled (the Health Bars switch that was under General Name Appearance), Combat Only and Health Bar Width and Height. The tabs are Names, Health Bars, Statuses and Visibility, and NM Tracking after `/name dev`.

## 1.38

- NM Tracking is a tab only after `/name dev`, for the session; `/name dev` again hides it. Tracking a monster chosen before goes on as it was.
- The Experimental Builder is gone. Enemy and check formats it saved are kept and drawn as before; Restore Original Check Line, under Enemy Names → Check Details, still takes a saved check format away.

## 1.37

- A target's name no longer pulses. The game takes the targeted name's colour toward white or dark and dips its opacity; the name, its outline and its spawn letters now keep the colour the pulse starts from at full opacity, as the icons already did. A change of colour that is no pulse, such as a monster turning red as it is claimed, shows at once.

## 1.36

- The health bar scales with its name. Health Bar Width and Height are the bar's size under a name at its largest, and the bar shrinks with the name as it goes further away, and grows with a hunted or sub-targeted one, where it had stayed one size at every distance.

## 1.35

- Health bars now use one shared enable toggle and width/height under **General Name Appearance**, for every entity type. One-time migration enables them if any old category enabled bars, taking dimensions from the first enabled Enemy → Player → NPC (Enemy if all were off). Old per-type tables remain archived, not active.
- Added **Combat Only** (off by default): each entity must have valid live identity/HP data, HP above zero and Engaged status 1. Targeting/claiming alone is not combat; unknown status hides bars, and the same filter applies to all types.
- Added optional per-category/state RGB overrides, applying jointly to name text, spawn letters and HP fill, including explicit name/letter token tints while enabled. Players: Normal/Combat/Targeted/Dead; enemies: Unclaimed/You-Party-Alliance Claim/Other Claim/Targeted/Dead; NPCs: Normal/Targeted. All default off. Dead takes precedence over target/live states; disabled live states fall back to underlying state/game colours. Claim classification uses active party/alliance server IDs, without guessing missing ownership data. Opacity, fading, independent icons and builder Apply ownership are unchanged.

- Added a roughly 0.2-second whole-nameplate fade once a monster is no longer rendered or its entity is removed, without timing out visible corpses. Preserves the disappearance deadline through late name calls/drawing gaps and lost entity data; respawn clears it, and a different entity reusing the index suppresses the stale label immediately.
- Restored spawn letters inheriting the displayed name colour and text opacity, including an explicitly coloured `[name]` before or after the letter. Explicit letter colours still override ordinary inheritance unless a state colour override is enabled. Plain fallback letters now share the prepared badge's name-font baseline to avoid a vertical jump when the atlas becomes ready; saved token ordering/spacing remain unchanged.

- Dead monsters now turn grey immediately instead of retaining their last live claim colour. Adopt the client's corpse grey when available, ignore subsequent stale red/white samples, and preserve the actual corpse fade. Default corpse grey overrides live `[name]` token colours unless a Dead state colour is enabled and resets on respawn, server-ID reuse or a break in drawing.
- Separated target text pulsing from icon opacity. Name glyphs follow the client's current RGB/alpha, with glyph alpha also fading their outlines; icons, overlays and mastery stars retain steady target opacity with their explicit/default icon colours. Spawn letters follow the name text instead. Distance and corpse fading still apply; the opacity hold resets when targeting ends, on respawn/reuse, or after a drawing gap.

- Removed Preview Health Bar from all three entity sections and retired session preview state. Health bars now always use validated live HP; shared dimensions are disabled while Health Bars is off.
- Removed the three Tokens & Examples dropdowns. Each format editor's (?) now lists its tokens/options and a complete example format with sample output, including Player Format's name/status-icon/distance tokens.

- Maximum/Minimum Name Size are back in **General Name Appearance**, shared by all entity types. Removed category and enemy-builder size overrides; the builder preview follows General immediately, and Apply leaves shared sizes untouched. Existing General values remain authoritative, with health-bar controls shared across every type.

- Fixed the composite seeking-party status icon drawing a full-size star over its base. Exported font-shape overlay geometry now preserves the game's half-size badge and small upper-left offset instead of drawing the next icon byte at full size. Ordinary seeking-party status has no badge; this is separate from the three job-mastery stars. Existing status visibility and mastery preferences are unchanged.

- Extended the enemy builder with a current-zone mobdb preview selector, including per-index variants, checked/targeted/distant-size toggles and a distance control. Preview /check results are explicitly simulated; source database entries and saved settings are never modified.
- Added readable mobdb values (`display=names` or `both`): resource-backed item/spell names with ID fallbacks, job abbreviations, verified immunity-mask labels (unknown bits retained) and readable respawn times. Resource names are cached with zone resets. Existing formats remain raw; newly added builder mobdb blocks use names.
- Added per-block AND conditions (`when=target+checked+nm+relevant`) and distance limits (`within=20`) for both rows, including literal labels. Conditions update dynamically in native rendering and preview, with hidden spacing suppressed. Relevant hides false/empty/zero data and neutral modifiers. Ordinary text stays unchanged; conditional Text blocks use generated, encoded text tokens. Expanded format-editor buffers to preserve long generated layouts.

- Added an **Experimental Builder** tab for enemy nameplates, ordered **Example → Builder → Blocks**. Both the name and check-information rows support draggable, reorderable blocks with colours, spacing and a selected-block inspector. All bundled mobdb fields, including drop/steal/despoil/spell IDs, immunity masks, detection, jobs, respawn and individual damage modifiers, are available as check items. Applied check formats use the normal /check duration/fade; an empty `checkFormat` preserves the original renderer. Health bars remain exclusively in regular settings and are never overwritten by builder Apply. Drafts are isolated until explicit Apply, with Reload/conflict protection. This builds two ordered lines, not arbitrary free-position rendering.

- Enemy formats now directly control level, aggro and letter visibility. Removed Show Level / Range, Show Aggro Icons, Mob Letters and Double Letters controls. `[letters: type=double]` continues AA, AB, etc. after Z; `[letters]` / `type=single` repeats A–Z. `[letter]` remains an alias, and single/double tokens can coexist. Old automatic/double-letter preferences migrate once into explicit tokens.

- Player icons are now an inline `[icons]` format token instead of a Show Icons checkbox. The default player format is `[icons: space=4][name]`; move or omit the token to position/hide icons. Existing icon visibility, size and spacing migrate into the player format once.
- Added per-token `space=` and `color=` options, icon `size=`/`gap=` options, and distance `decimals=`. For example: `[icons: size=90, gap=2, space=4][name] ([distance: decimals=2, color=yellow]y)`. Old colour shorthand remains supported; invalid options remain literal and numeric values are bounded.

- The Names tab now groups Font through Outline under General Name Appearance, followed by Player Names, Enemy Names and NPC Names. Each category exposes its own format editor, reset button and token examples. Player icons and enemy check options live in their matching categories; shared health-bar controls remain separate.
- Player formats now use saved character settings in production rather than a fixed baseline. Added a separately saved NPC format, defaulting to `[name]`; existing player/enemy format strings remain intact.

- Reorganized menus into Appearance, Visibility, Statuses and NM Tracking without changing saved settings. Appearance separates Text, Player Icons, Health Bars, Monster Names and Check Details; Diagnostics is a collapsed section there instead of part of visibility.
- Standardized labels and px/% units. Health-bar dimensions stay visible but disabled until shared Health Bars is on. Check Details uses an Icons & Text / Text Only dropdown backed by the existing setting.
- Moved monster formatting into collapsed Advanced Formatting with Reset Format and token examples. Long caveats/examples use expandable help; Statuses and NM Tracking have focused Display/Selected Statuses and Placeholder Options sections.

- Added saved Health Bar Width and Height controls under Name Appearance, defaulting to 60 × 6 screen pixels. Bars now use that fixed size rather than following name width/font height.

- Health-bar fill now matches the name's displayed colour rather than always being green.


- Added an opt-in Health Bar toggle in Names → Name Appearance. Damaged mob and player nameplates show a basic HP bar below check details, with below-name statuses moved beneath it. Full-health nameplates stay unchanged.


## 1.34

- Subtarget Scale, under Name Appearance: the name under the sub-target cursor (`<st>`, `<stpc>` and the like) can be drawn from 50% to 200% of the size of the others while you choose. 100% to begin with, as before.
- The name being chosen as a sub target keeps its own size against the game's: the game shrinks it and enlarges it to full size as a choice begins and ends, and these are no longer shown, at any Subtarget Scale. Only a walk's change of distance and Subtarget Scale change its size then.

## 1.33

- The names' letters are drawn from imgui's font texture as the namehook plugin reads it, and Name no longer asks imgui for it. Its id is 64 bits and a Lua integer in this game 32: once the texture was above 2 GB, as it can be after a while on Windows, Ashita could not hand it to Name at all, and the names were the game's for the rest of the session. Needs namehook 1.25, which comes with it, and winxi 4.
- Letters for monsters of the same name cut their badges from the font's texture the plugin drew from, which it holds while it draws; until it has drawn, the letters are plain. Never anything that is not a texture's address is given to Direct3D to read.
- Diagnostics say whether imgui has the font texture ready and what it says of it, and the log the texture the plugin drew from; the history notes each time imgui makes the texture again.

## 1.32 — first release

- Shows and hides the names over characters' heads by what they are (self, party, alliance, other players, pets, NPCs, monsters), through the namehook plugin, which comes with it.
- Draws the names in winxi's style: font, size near and far, outline, player icons, and monsters' level and aggro signs, written by a format of your own.
- What a check shows under a checked monster's name, and the statuses over a name.
- Experimental: a tracked notorious monster, and letters for monsters of the same name.
