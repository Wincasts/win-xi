# This fork

tCrossBar by Thorny (https://github.com/ThornyFFXI/tCrossBar), version 2.21, with gdifonts by the same
author as plain files rather than a submodule. `readme.md` is the original's. What this fork changes:

- **Prepare bindings for unavailable actions.** The binding editor's **Binding** tab has a
  **Show Unavailable Actions** toggle (off by default, saved with settings). It lists named
  abilities, spells, trusts and weaponskills from all jobs without requiring them to be learned,
  available at the current level, or exposed by a currently summoned pet. For example, enable it,
  choose Ability and Deploy to prepare a puppet command in town. Normal Spell/Trust categories
  and the exclusion of non-action ability-menu headers are retained. Items still come from the
  existing inventory-based lists. Toggling the filter preserves a selected action and custom macro,
  even if the selected action would normally be hidden. This only changes the editor's catalog:
  runtime availability/cost/recast indicators and the game's use requirements remain unchanged.

- **Optional player-context macro overrides.** Open a binding's **Context** tab, choose a **Player
  Context**, enable **Enable Override**, and enter its macro. Each context has its own toggle and
  command list; changing the dropdown edits another context without losing the previous one's text.
  Supported contexts are **Engaged** (status 1), **Idle** (status 0), and **Resting / Healing**
  (status 33, kneeling with `/heal`, not casting healing magic). These statuses are mutually exclusive.
  At the button press, the matching enabled override replaces the normal macro. Missing, disabled
  or empty overrides, unknown statuses and unavailable player data fall back to the normal macro.
  The same command queue, encoding and `/wait` support apply. The context and command list are
  captured at activation, so changing status during a wait does not switch macros mid-run. Icon,
  label, cost, availability and recast display still describe the original binding. Disabling an
  override keeps its text for later; enabling an empty override is rejected by the editor. Existing
  files without overrides or with only an Engaged override work unchanged, and overrides save at
  every scope, including Subjob (Palette).
  The optional `Overrides.<context> = { Enabled = true, Macro = T{ ... } }` data uses the keys
  `Engaged`, `Idle` and `Resting`. The `bindingcontext.lua` registry drives detection, editor options
  and persistence so additional contexts can be added consistently.
  This does not add special targeting automation: enter the desired game command(s), and verify
  subtarget confirmation/cancellation behavior in-game. Controller tab cycling includes Context;
  its macro text and checkbox are edited with mouse/keyboard, as the Appearance controls are.

- **Weapon bindings within each palette.** The **Weapon (Palette)** scope overrides slots for the
  equipped **main-hand weapon type** (Hand-to-Hand, Dagger, Sword, Great Sword, Axe, Great Axe,
  Scythe, Polearm, Katana, Great Katana, Club or Staff). Equip a weapon, open a binding, choose
  Weapon (Palette), and bind a weaponskill. Equip another type and repeat for the same slot.
  Switching main-hand types automatically refreshes bindings, polled every 100 ms. Different items
  of the same type share bindings; the sub-hand and ranged slots do not select this category.
  Empty main hand uses Hand-to-Hand; unavailable equipment uses shared bindings instead.
  Priority is **Weapon → Subjob → Palette → Job → Global**. Each palette's optional `Weapons`
  table is keyed by combat skill ID, so existing binding files remain compatible. Weapon bindings
  support the same player-context overrides as other scopes. An open editor keeps its original
  weapon category when equipment changes, preventing an unsaved draft from going into another
  type's bindings; reopen the editor to edit the newly equipped type.

- **Subjob bindings within each palette.** The binding menu's **Subjob (Palette)** scope overrides
  slots for one subjob within the active main job and palette, unless a Weapon binding takes priority.
  Unbound slots fall back through **Palette → Job → Global**. For example, keep shared actions at Job scope, then bind Provoke
  for /WAR and Utsusemi for /NIN at Subjob (Palette) scope. These overrides are saved in each
  palette's `Subjobs` table in the existing main-job binding file; old files work unchanged.
  **Behavior → Automatic Subjob Detection** is on by default and follows the equipped subjob.
  Turn it off to use **Binding Subjob** instead (also useful for configuring another subjob).
  Selecting None uses shared bindings only. The binding editor shows which subjob is being edited.
  This selects binding overrides, not a subjob-named palette; palette cycling still works normally.
  Job changes retain the original behavior of loading the first palette.

- **Winxi-styled configuration and binding editor.** `/tc` and the binding editor use
  `winxi.window`'s resizable settings windows, shared theme fonts and colors, and aligned control
  labels. The binding editor's Binding, Appearance and Context tabs fit their content without the
  old fixed-width child panels; the settings window scrolls when resized smaller. Controller field
  highlighting and tab cycling remain available. Neither window has a Winxi Theme tab; use `/wxi`
  to change the shared theme. Both windows require `addons/libs/winxi`.
  Controller-button mapping changes are saved immediately.

- **Stands down for winxi windows.** While a winxi addon's window has the controller (the
  `winxi_controller_focus` plugin event), button presses are ignored, so the triggers do not bring up the
  crossbar and no macro fires behind the window. A window that leaves the triggers free (its event's data
  ends `:pass`, as atlas's map does while browsing) leaves the triggers this addon's, and every button
  pressed while one is held. In `controller.lua`, marked `winxi:`.

- **Winxi's drop shadow under each frame.** Frame Shadow (Layouts tab, on to start) draws the Winxi
  Theme's shadow, as winxi.shadow draws one behind a window, under every macro element's frame, following
  the theme's Shadow settings. Made once into a texture for each size of frame (`frameshadow.lua`), and
  drawn for every element before any frame. With Match Theme Shadow off (Components tab, on to start)
  it takes the crossbar's own Shadow Opacity, Shadow Offset and Shadow Softness instead, and those need
  no winxi; following the theme without `addons/libs/winxi`, nothing is drawn.

- **Winxi's border art round each element.** Frame Border (Components tab, None to start) draws one of
  the Winxi Theme's border styles round every macro element's frame, or round its icon while Frame is
  off: Window Border follows the theme's own (none while that is the plain border), or any of the art by
  name. winxi.borders' nine slices drawn with sprite draws, corners 3 pixels and edges stretched, after
  every icon so nothing falls over it, faded by the theme's Border Opacity (`frameborder.lua`). Needs
  `addons/libs/winxi`; without it nothing is drawn.

- **The recast timer in winxi's text.** Each slot's recast timer is written centred on its icon in the
  Winxi Theme's font and Text Color with winxi.text's dark outline, at Recast Size (Components tab, 8
  to 40 px, 16 to start), in place of the layout's small text in its corner. gdifonts has neither the
  theme's font nor its outline, so it is drawn with imgui on the background draw list: over the
  crossbar, under every imgui window (`recasttext.lua`). Without `addons/libs/winxi` the layout's own
  Recast text is drawn as before.

- **A soft black backdrop.** Backdrop (Components tab, on to start) draws black behind the crossbar,
  darkest in the middle at Backdrop Opacity (50% to start) and fading smoothly to nothing towards its
  edge, an ellipse the panel's shape reaching Backdrop Size (130% of the panel to start, 50 to 300).
  One round gradient made once into a 128 by 128 texture and stretched over the panel with one sprite
  draw, before anything else in either display (`backdrop.lua`).

- **A gloss over each icon.** Gloss (Components tab, off to start) draws the light of a glass button over
  every icon: white over its upper part, brightest at the top and fading to a curved edge lowest in the
  middle, and a faint shade at the foot. Made once into a texture for each size of icon (`gloss.lua`),
  drawn over the icon and under the cross, trigger and skillchain overlays, faded by Gloss Opacity (0 to
  100%, 100 to start).

- **A cooldown swipe and cost tints.** Cooldown Swipe (Components tab, on to start) darkens the part
  of each icon still to come back while it recasts: a wedge from 12 o'clock shrinking clockwise, at
  Swipe Opacity (60% to start), run down smoothly between the slot's ticks. Charges (Ready, Quick Draw,
  stratagems) swipe for the next charge, their length known; for the rest the length is the most left
  seen since the recast began. All trigger groups in both displays are sampled even while hidden,
  so revealing a bar does not restart its swipe using only the remaining time. Cooldowns already in
  progress when the addon loads still use the first observed remaining time. Low MP and Low TP (on to start, each with its colour and alpha) lay a
  colour over a spell or ability whose MP cost is not met, or a weapon skill under 1000 TP or ability
  whose TP cost is not met. The updaters give the recast in seconds and which cost is short
  (`State.RecastLeft`, `RecastLength`, `LowMP`, `LowTP`, marked `winxi:`); `cooldown.lua` makes a
  texture for each of 60 steps of the turn and each size of icon as it is first wanted, and one white
  texture for the tints. Over the icon: tint, swipe, then gloss; the cross, trigger and skillchain over
  those.

- **Less work each frame.** The set blue magic is read only for a blue mage and a few times a second,
  not every frame for every job (`state/player.lua`). A slot's state is worked out ten times a second
  instead of every frame (`element.lua`). The double display no longer lists its slots afresh each frame
  (`doubledisplay.lua`). Smaller ones in `updaters/ability.lua` and `state/skillchain.lua`.

Changes are marked in the code with `fork:` (or `winxi:` for the one above), so that they can be found
again if the original is ever merged in.
