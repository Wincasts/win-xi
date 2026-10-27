# Changelog

## 0.3.5

- The player's and the party's buffs are read by winxi 64's `winxi.partystatus`, which name reads them through too, so the two show the same. The player's own are now the game's status icons (as buff and name show them) rather than its list of buffs, and none are read while changing areas. Requires winxi 64.

## 0.3.4

- The settings' tooltips reread for plain words: each says what its setting does, in a line or two. Far Range has one now. Priority Effects and Hidden Effects describe the picker, not a list of numbers; Near Range says what it dims; Automatic Positioning says where the windows go, not the pixel counts; the uihook section's say what the windows do in the game's place.

## 0.3.3

- uihook's party block is read as plugins/ABI.md promises (winxi 57's `winxi.abi`): the same Version and at least the size this knows, so a newer uihook that adds to the block is still read. Requires winxi 57.
- Native windows are refused while hideparty is loaded, which hides the very frames they replace: the windows are given back to the game and `/pt native status` says to unload hideparty. hideparty 1.3 says it is loaded through winxi 56's `winxi.presence`. Requires winxi 56.
- uihook alone: the retired partyhook plugin is no longer looked for.
- hideparty is no longer packaged with party.
- Requires winxi 55. Where namehook was unloaded and loaded again between two of its looks (party asks only while it has a target), what it had found in the old DLL was read: party's crash on 2026-10-26, an access violation in d3d_present. winxi 55's nameplates.Hook checks namehook's DLL is still the one its block was found in.

## 0.3.2

- A new **Visibility** tab, the last, holds the hiding rules (Hide Windows, formerly Behavior → Visibility)
  and Fading, moved out of Behavior. The settings are the same and are kept.
- Behavior's sections are Positioning, uihook (while it is loaded), then Mouse Interaction.
- **Advanced: Value Positioning** moves from Style to the Party tab: the HP, MP and TP Value Offsets, as they were.
  The Target tab has one of its own, **HP % Offset** and **Distance Offset**: a target's HP percentage and
  distance no longer go with the party's TP offset. Settings from before give them that offset once, so they
  stay where they were.
- **Game Name Colors** (Target tab → Names): the target's name in the game's colour for it, by claim, call for
  help, party and alliance, NPC and death. Off to begin with. With namehook loaded and the name on screen it is
  the game's own colour, read from the plugin and held steady through the target's pulse.
- Leader marks: the party leader's dot is yellow and the alliance leader's white (it was red). The **level sync
  designee** has a red dot at the right end of their line, as high as the party leader's (the upper of an alliance leader's two), (the party's flag 0x100, as the server sends it).
- **Monster Letters** (Target tab → Names, on to begin with): a monster's spawn letter after its name in a
  small box in the name's colour, the same letter name writes over it. Needs winxi 52, which now holds name's
  letters and its reading of the game's lists of names.
- **Lock-On Brackets** (Target tab → Lock-On, on to begin with): while you are locked on to your target, a
  [ and a ] stand outside the left and right of its window, enclosing the frame without touching it, in the **Bracket Color** (white to begin with),
  edged with the theme's Text Outline. The sample target shows them while the settings are open.
- **Fishing**: while a fish is on the line, uihook lets through what the game's party list draws outside the
  list, as the game draws the fish's stamina gauge with it (in the middle of the screen): the gauge shows, the
  rest of the game's list stays hidden and Party's windows stay. Needs uihook 1.65; with an older one the game's
  whole party list is given back for the fight and Party's party windows step aside.
- **TP Ready Color** (Style → Warnings): the colour TP of 1000 or more is written in, blue to begin with.
  Flash TP When Ready pulses it toward a lighter shade of the chosen colour.
- The value offsets reach further: 140 either way across, enough to put a figure anywhere along a frame from
  either end, and 40 up or down, past a line's top and bottom (40 both ways before).
- Behavior → uihook: Hook Into uihook is **Use uihook**, no longer marked experimental. The title is followed in
  green by the plugin found and its version, e.g. [uihook 1.60 found]. The explanations of Use uihook, Party,
  Target and Follow Default UI Behavior are in a (?) after each, not the control's own tooltip. The native
  rendering status line under them is gone; `/pt native status` still gives it, no longer called experimental.
- **Shift+drag** moves a window while Clickthrough is off: Shift held as it is clicked, the drag kept until the
  mouse is let go. Without Shift the windows no longer move when clicked. Not with Clickthrough on, nor for a
  window placed by Automatic Positioning or uihook or linked to another; organizing drags as before.
- Tooltips show with **Clickthrough** on: it lets clicks and drags through to the game, no longer hovering. Hover
  Details is no longer greyed with Clickthrough on, and a target's debuff letters are hovered by their place, as
  the icons and names already were.
- Hover Details is **Show Tooltips**, and is the one setting for every tooltip on the windows: the members' (full
  name, job and pet owner) and the buffs' and debuffs'. Off, as it begins, there are none; before, a member's job
  and the status icons had tooltips without it.

## 0.3.1

- A window placed by Automatic Positioning cannot be dragged, as the README says: it was, and imgui laid it
  out where the drag took it while it was drawn back in its place, so its background seemed to slide under it.
- Titles no longer stretch across the whole screen (winxi 51, below).

## 0.3

- Six smooth bar textures (winxisettings → Styles → Bar Texture), shaded from top to foot with nothing along the bar, so the fill looks the same at any HP: Enamel, Enamel (Lit Rim), Enamel (Gradient), Glass Tube, Glass Tube (Deep) and Glass Enamel.
- Fill End Glow (%): a soft light at the end of each HP and MP fill, 35 to begin with; 0 for none.
- Custom Bar Backdrop and Bar Backdrop Color: the empty part of the bars in a colour of your own.
- Bar Frame (winxisettings → Styles): Capsule Outline and Capsule Outline (Silver), a thin rim in the Rounded bookends' colours in place of the texture's frame, so that the bar and its caps are one capsule being filled. Bar Texture keeps the texture's own. Bar Frame Opacity (%) makes either see-through, down to none at 0.
- Bookend Style adds Rounded and Rounded Silver, round ends after the game's own gauges that sit beyond the bar's ends.

- Show Statuses (Style → Status Display, on to begin with) turns the party's and alliance's buff and debuff icons on and off; off, the status settings are greyed and kept. A target's debuffs follow the Target tab as before.
- TP Ready Threshold is gone: TP is ready, and flashes with Flash TP When Ready, at 1000. A saved threshold is dropped.
- uihook is the last section of Behavior.

- Debuffs First puts every debuff before every buff, nearest the frame in the Status Growth direction. Defense Down, Evasion Down, Magic Defense/Accuracy/Attack Down, Max TP Down, Threnody, Nocturne, Magic Evasion Down, the Geo downs, dazes and others were counted as buffs; the debuffs are now those Erase or a waltz removes in Phoenix's status data, and the harmful ones that cannot be cancelled. A Priority Effect that is a buff no longer goes ahead of the debuffs; the priorities order each kind.

- Profiles are gone: the Profiles [Experimental] tab, its four presets and the named profiles. Profiles saved by earlier versions are dropped from the settings.

- Hover Details no longer list a member's statuses: the tooltip has their name, job and pet owner, and each status icon keeps its own tooltip. The +N badge of statuses that did not fit no longer has one. The uihook section of Behavior is shown only while uihook (or partyhook) is loaded.

- Behavior's Native HUD Replacement section is now **uihook**: it says whether uihook (or the older partyhook) is loaded, and **Hook Into uihook** turns the hooking on or off as a whole. While it is on, **Party** and **Target** choose which windows it draws in the game's place, with Follow Default UI Behavior beside them; pets are rows of the Party windows and go with them. Greyed while the plugin is not loaded, the choices kept. Settings that had Party or Target hooked begin with Hook Into uihook on; `/pt native on` turns it on.

- Sleep on an enemy, or on a player the target window shows, is taken off when they are hit, hurt by a spell, weapon skill, ability or additional effect, or cured, as the server wakes them then and tells only the one who put the sleep there. One with Poison, Dia, Bio, an elemental debuff or Requiem on them is woken by the server's next regen tick, so their sleep is given three seconds at most (winxi.debuffs).

- Short Zone Names (Style → Names, on to begin with): a member in another zone has the game's own short form of the zone's name where their bars would be, as Ashita's `zones.names_abbr` reads it from the game, or the whole name where there is none. Off, the whole name as before, cut short where it does not fit.

- The Kingdom bar texture is plainer: one dark line, one bright rail and one shade line, with nothing drawn inside the frame, over a flat dark back without the other styles' highlight. At the party frames' scale the earlier four alternating rails smeared into a second frame inside the empty part of the bar.

- Name Font and Value Font are winxi's own control (widgets.FontFile), Clickthrough too (widgets.Lock), and the settings' tooltips are winxi.tooltip's, so winxisettings' Tooltips tab applies. Outline Text is gone: the names' and values' dark edge is Winxi Theme's Text Outline, scaled with the frames, and its colour the theme's Outline Color. Needs winxi 25.

## 0.2 — first release

- Restore outer window shadows for native-rendered party/alliance and target windows. Capture the exterior shadow on the window's own draw list rather than leaking it onto ImGui's background list; preserve theme opacity/offset/blur, disabled shadows and ordinary/Organize rendering. Update Party and Winxi's shadow module only; no uihook/legacy partyhook DLL or ABI change. Offline geometry/routing checks pass; live appearance/layering still needs validation.

- Testing-build cleanup: hide cumulative native-hook counters/geometry diagnostics in settings and `/pt native status`, retaining concise mode/readiness/errors. Hide Use Default UI Positioning and its alliance-location controls, clear saved opt-ins and gate anchoring off at runtime. Preserve manual positions/corners/links and ordinary Automatic Positioning. Native replacement and the independent behavior option remain available. Addon-only change; ABI 3/DLL unchanged.

- Fix Solo/Party classification after everyone else leaves: the remaining leader is still in a one-member party, using the same native leader flag as the leadership badge. Keep the Party header and do not apply Hide When Solo until the player actually leaves/disbands. Preserve Alliance labeling/visibility and guard absent-player state. Add regression coverage for the party→one-member leader→true solo transition.

- Optimization check: keep existing 10 Hz roster/pet caches, zero-allocation layout/status/debuff paths and hidden/faded work skipping. Avoid unused manual-layout display queries, main-entity lookup with ToT disabled, all target-memory polling when all target windows are disabled, repeated idle hook shutdowns and unchanged mode-diagnostic formatting. Extend isolated allocation, target/subtarget semantics and hook cleanup tests; partyhook also fast-paths clipping and merges compatible texture runs. Offline measurements are not live FPS results.

- Add default-off **Use Default UI Positioning** and **Follow Default UI Behavior** under experimental native replacement. Requires the new **partyhook 0.3 / ABI 3** DLL alongside this addon. Independent stock rectangles anchor main party/target bottom-right and each alliance top-right without overwriting manual positions/corners/links or changing styling. Alliance 2/3 can each opt out for manual placement even with automatic layout enabled; unlink Alliance 3 from Alliance 2 in Organize to move all lists independently. Optional native behavior keeps native member order/solo visibility/lifecycle and skips addon idle/presence fades, while retaining loading/UI-hide/cutscene guards and leaving ordinary groups unchanged. Offline geometry/scaling, placement, independence and behavior tests pass; new options have not been live-tested.

- New independent target opt-in: `/pt native target on|off` (Behavior → Native HUD Replacement). Requires partyhook 0.2 / ABI 2 DLL update. Main/sub/target-of-target frames replay together at the stock target-box stage, preserving the client's own overhead main/subtarget arrows via two verified native call sites. No Lua cursor replacement. Hidden target frames renew empty submissions; party mode is unaffected by target mode changes. User reports target rendering/arrows, menu overlap, subtarget range colours, switching/despawns/doors, cutscenes, UI hiding and independent toggles working. Zoning and font/device-reset recovery remain untested.

- Native replacement: hiding Party for expanded chat, maps or other visibility rules renews empty replacements instead of releasing the hook and allowing stock lists to reappear. Disabling native mode/Party, unloading or organizing still restores stock lists.

- Experimental, default off: `partyhook` native party/alliance rendering (`/pt native on|off|status`, or Behavior). Captures existing styled windows in C++ and replays at the native window render boundary while retaining native logic. Separate plugin build/install; unload hideparty first. Target replacement has its own opt-in. Initial party/rearranging and chat-hiding feedback is positive; broader navigation, layering and reset validation remains pending. See the plugin README.

- Party, alliance, target and pet frames in winxi's windows, with bars and a layout after XivParty's compact one.
- Buffs and debuffs beside your party, with limits, rows, growth, Debuffs First, and effects to put first or hide.
- Frame Scale, Alliance Scale, name and value fonts and sizes, bar shadows, range dimming, a low-HP warning and the TP-ready flash.
- Automatic Positioning lays the frames out from the screen's edges.
- Experimental: Profiles, with four presets and up to 20 of your own.
- Comes with hideparty, to hide the game's own party frames: `/addon load hideparty`, then `/hideparty`.
