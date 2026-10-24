# Changelog

## Unreleased

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
