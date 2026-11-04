# winparty

Up to 0.4 this addon was called party. Load `winparty` in place of `party` and remove the old
`addons\party` folder: each character's settings are brought over from `party` the first time it logs in.
`/pt` and `/xif` still open the settings, as `/winparty` does.

Party, target and pet frames in winxi's themed windows. They have bars, and their layout follows
the compact one of the Windower addon [XivParty](https://github.com/Tylas11/XivParty).

- **Party**: your party and the other two alliance parties. Each member is one line: the name, an HP bar,
  a smaller MP bar with their values, and TP as a value. A selected member has the game's animated cursor before
  their name (the name is blue for the target, green for a subtarget or a party-cursor selection). A leader has a circle before their name: yellow for the party's leader, and the alliance's leader has a white one above it. The level sync designee has a red circle at the right end of their line, as high as the party leader's (the upper of an alliance leader's two). Your own party's list grows upwards, and
  its buffs run leftwards from the window. The game's own icons beside the window mark a party or
  alliance invite waiting for an answer (a green exclamation mark in a dark circle) and anything in the treasure pool (the chest).
  A name can run as far as the right end of its HP bar. Only past that is it cut short with "...".
  **Alliance Scale** (Party tab) sizes the other two parties together, on top of the Scale in Style.
  **Name Font** and **Value Font** (Style tab) each choose a Windows font: one for the names, one for the HP, MP and TP
  values. Theme Font, the default, is the font set in Winxi Theme.
  **Advanced: Value Positioning** (Party tab, collapsed) moves the HP, MP and TP values of the party, the
  alliance and pets.
- **Target**: your target, sub-target and target of target. Each is a line of the same kind: the name,
  the HP bar, the distance and the HP percentage. If you want, the enemy's debuffs too: as letters under the line, or as status icons beside it, placed and sized like your party's buffs.
  **Debuff List** (Target tab → Debuff List, off to begin with) is a box of its own listing every debuff seen to
  land on your target, its name and the time it has left (an estimate, as the tooltips say), the soonest to run
  out first; the target's name is its first line, and there is no box while nothing is on the target. It is a plain imgui box, dragged by its body (Lock Windows
  holds it still), and **Debuff List Position** places it, as a drag does too. **Winxi Theme** (off to begin with)
  draws it instead as a window of the theme, with its border, background and font, moved, faded and organized as
  the target windows are. It goes with the target whichever target windows are shown, and keeps the debuffs
  counted on its own.
  **Advanced: Value Positioning** (Target tab, collapsed) moves the HP percentage and the distance, each on
  its own. The party's offsets no longer move them.
  **Game Name Colors** (Target tab → Names, off to begin with) writes the name in the colour the game gives
  it over the head. An enemy is yellow while unclaimed, red when claimed by your party or alliance, purple when claimed by anyone
  else, and orange once help is called for. A player is white, or blue in your party or alliance. An NPC is green.
  Anything dead is grey. With namehook loaded and the name on screen, the colour is read from the game itself,
  exactly, and held steady while the game pulses the target's name. Otherwise it is worked out: the NPC green,
  the player white and the party blue are measured from the game, and the enemy colours are close to it.
  **Monster Letters** (Target tab → Names, on to begin with) puts a monster's spawn letter after its name, in
  a small box in the name's colour. The letter is written over the box (A, B, C… among the monsters of one name in
  the area, by their places in the game's own list, so every player sees the same; past Z, A again). There is none for
  players or NPCs, or where the area's list cannot be read or differs from what the game shows.
  **Lock-On Brackets** (Target tab → Lock-On, on to begin with) stand a [ and a ] outside the left and right
  of the main target's window while you are locked on to it. They enclose its frame without touching it, as the game frames its own target. They are drawn in the **Bracket
  Color** (white to begin with) with the theme's Text Outline.
- **Pets**: your pet, and your party members' pets, listed under your party below a line. With
  Show Statuses on, each pet has its statuses beside it, as your party's are. The game doesn't say what
  is on a pet, so these are the ones seen to land on it in the battle messages. With Show Durations on,
  each has an estimated time under it, and those you cast are in Your Color. When a monster's debuff
  wears off a pet nobody is told, so its icon stays until its usual time runs out. Removing it with a
  spell is seen.

## once called xiframes
The addon was called xiframes until it was renamed party (now winparty). The first time each character logs in with it,
what xiframes kept for them (`config\addons\xiframes`) is taken up as party's settings, so you need not
copy anything by hand; xiframes' folder is left as it was. Unload xiframes and load winparty in its
place (and change `xiframes` to `winparty` in any script that loads it).

## usage
`/winparty` (or `/pt`, or `/xif`) opens the settings; `/winparty help` lists every command in the chat log. `/party` is left alone for the game's own party chat;
`/xiframes` is no longer used. The Style tab sets how every frame is drawn (sizes,
fonts, bars, statuses). The Party, Target and Pets tabs have what belongs to each one. The dark edge round names
and values is Winxi Theme's Text Outline, set in wxi for every addon.
**Behavior** has **Positioning** (with the optional **Automatic Positioning**), then uihook while it is loaded, then
**Mouse Interaction**. **Visibility**, the last tab, has the hiding rules (**Hide Windows**), **Fade When Idle** and which windows fade (**Fading**).
There is no Winxi Theme tab in Party. Use **wxi** for shared colours, padding, shadows,
window borders, bar textures, bookends and custom status icons. Organize, at the foot of the window, fills the frames with sample data so you can drag them into place.
`/winparty perf` measures five seconds of render and packet-handler CPU time: average, median, p95,
p99 and worst latency. `/winparty perf counters` also counts addon-local entity reads, text
measurements, image submissions, texture-load attempts and status reorderings.

```text
/winparty                        the settings (also /pt and /xif)
/winparty help                   every command, in the chat log
/winparty perf                   five seconds of render and packet-handler CPU time
/winparty perf counters          the same, with operation counts
/winparty native on|off          native party/alliance lists, with uihook
/winparty native target on|off   native target windows, with uihook
/winparty native status          a short mode/readiness status
/winparty cursor                 retry loading the selection cursor, and say how it went
```

## customization

- **Style → Appearance → Scale** is a visible control. The **Sort By Role** toggle is hidden;
  sorting you saved before still works as it did. While the game's own party selection is active, role sorting pauses.
- **Style → Status Display** has an icon limit of 1–32, one or two rows, growth to the left, to the right or towards the most space,
  fitting to the screen edge, and overflow badges. Screen fitting plays safe: in mixed sets it reserves room for the widest icon. When needed, the last free slot becomes a `+N` badge; with no space outside the frame the
  badge uses the frame's lower-left corner. Two rows increase the row height.
- **Style → Status Durations → Show Durations**, off by default, writes the time left under each status
  icon: seconds, then minutes (`m`), then hours (`h`). Your own times are exact, read from the game.
  Your party's and a target's are estimates, written in **Estimate Color** (yellow by default): from when
  the status was seen to land, or to appear on the member, for the server's usual time. Where that cannot
  be known, `-` is written. Statuses you cast are written in **Your Color** (green by default), so you can
  see when someone else's replaces yours. **Duration Text Size** sets how tall the times are next to the
  icons, and **Duration Font** what font they are in (the Value Font's to begin with). The windows stay the same size: the icons get smaller to make room for the times under them.
  **Low Time Warning** (10 seconds by default, 0 for none) makes an icon running out fade out and in.
- **Style → Removable Marks**, off by default, puts a small dot in a dark border inside
  the corner of each status you can take off, as the server says: **Curable Mark Color** (light blue)
  on your party's, pets' and a player target's debuffs that Erase, a -na spell or a waltz removes, and
  **Dispellable Mark Color** (amber) on a monster's buffs that Dispel removes. A friend's buffs and a
  monster's debuffs are left unmarked. **Only What You Can Remove** marks only what a spell you have
  learned, at your level now, takes off: your main job's level, or your support job's while it is not
  restricted, so a level sync is followed. Abilities like Healing Waltz aren't counted yet. A status's
  tooltip names the spells that remove it and says when you can cast one.
- Resting the mouse on a status icon (Show Tooltips) shows its time left, the spell or move that put it
  there and who cast it, where that was seen, and what removes it.
- **Party → Casting → Show Cast Bars**, on by default: while a member of your party or the alliance casts a
  spell, their HP bar fills as the cast goes, in a pale blue, their name is the spell's, and the time
  left is written where their HP was. The casts are seen in the action packets, so the time is the
  spell's base cast time, marked `~`; the server's finish or
  interruption ends it. While you organize, one sample member casts Cure IV.
- **Style → Status Display → Show Statuses**, on by default, draws the buff and debuff icons beside your
  party, alliance and pets. Off, every status setting (Status Display, Status Durations, Removable Marks,
  Status Filtering, Advanced: Status IDs) is greyed out but kept; a target's debuffs follow the Target tab.
- **Style → Status Filtering** has Debuffs First and two effect pickers, Priority Effects and Hidden
  Effects. Search by name or ID, tick effects, and reorder priorities with Up and Down. Priority order
  follows the list, hidden effects win, and other effects keep their original order. You can type the same lists
  as comma-separated numeric IDs under **Advanced: Status IDs** (collapsed by default).
  That is also where you enter IDs that have no name in the game's resources. With Debuffs First,
  every debuff comes before every buff, nearest the frame in the Status Growth direction, and Priority
  Effects order each kind among itself. The debuffs are the ones Erase or a waltz removes in Phoenix's
  `data/status_effects.yaml`, plus the harmful ones that cannot be cancelled (sleep, charm, doom, helix,
  enemy songs, dazes, the Geo downs and the like).
- **Style → Warnings** has a low-HP `!` threshold (zero turns it off), Flash TP When Ready and TP Ready Color (blue to begin with). TP is ready at 1000.
  **Advanced: Range Indicators** has the near range (centimeters), the far range (meters) and both dimming
  levels. The far range is treated as at least the near range. These show rough distances. They do not
  promise that an action is in range.
- **Style → Appearance → Bar Shadows**: Off, Simple (one layer), or Full (two layers). This is
  separate from Winxi window shadows.
- **Behavior → Mouse Interaction → Show Tooltips**, beside Lock Windows, is off by default. On, hovering over
  the windows shows Winxi tooltips: full names, jobs and pet owners on the members, and each buff and
  debuff (icons and a target's letters) with its estimated time left. Off, there are none.
- **Lock Windows** (clickthrough) lets clicks through to the game, but the windows still notice the mouse over them. With Show Tooltips
  on, their tooltips show either way. Another window drawn over them that wants the mouse keeps them from showing.
- **Shift+drag** moves a window when **Lock Windows** is off. Hold Shift as you click the window, and the drag goes
  on until you let go of the mouse. Without Shift the windows stay put, so a click on them does not move them.
  With Lock Windows on they cannot be dragged, except while organizing. A window placed by Automatic
  Positioning or by uihook, or linked to another, is not moved this way (Organize unlinks it).
  Tooltips follow **wxi → Tooltips**, including visibility, delay and appearance.
  Tooltips with an enemy's durations say plainly that they are estimates, not exact server timers.
  There is no click to target.
- **Style → Names → Short Zone Names**, on by default: a member in another zone has the game's own short
  form of the zone's name where their bars would be, or the whole name where
  the game has none. Off, the whole name, cut short where it does not fit.
- **Pets → Layout → Pet Names**: `Pet`, `Owner: Pet` (default), or `Pet (Owner)`.
- The settings window has no section-reset buttons.

Debuff tracking clears on disable, on settings or character switches and on zone-in and zone-out,
including while the frames are disabled. When the frames are enabled again, tracking starts with only
newly seen effects, never a rebuilt complete enemy status list.

## Experimental Native HUD Replacement

Use [uihook](../../plugins/uihook/README.md) for new native-rendering installs; it combines
buff and party/target support. Load `/load uihook` instead of `/load partyhook`, and never load both.
The updated addon still supports the old partyhook, so you can roll back. The notes below
apply to both plugins.

The opt-in plugin draws the Party windows at the native HUD's rendering stage, not as a final overlay,
in place of the game's own. Normal rendering stays the default.
User testing confirms party/rearranging, chat hiding, target/native arrows, menu overlap, subtarget
range colours, rapid switching/despawns/doors, cutscenes, interface hide/show and independent toggles.
**Zoning is still untested**, as are font/device-reset recovery and wider client compatibility.

Install and update: [plugins/uihook](../../plugins/uihook/README.md).
Unload Party and partyhook before you replace the DLL; keep hideparty unloaded.

- `/winparty native on|off`: party/alliance lists, including embedded pet rows.
- `/winparty native target on|off`: target replacement on its own. It captures the main, sub-target and target-of-target
  windows together at the native target-box stage; the normal Target settings still choose which are shown.
- `/winparty native status`: a short mode/readiness status; cumulative debug counters are hidden.
- **Behavior → uihook**, between Positioning and Mouse Interaction, shows only while uihook (or partyhook) is loaded. Its title is followed in green by the plugin found
  and its version, e.g. `[uihook 1.60 found]`. **Use uihook** turns the
  hooking on or off as a whole. While it is on, **Party** and **Target** choose which windows the plugin
  draws in the game's place, and **Follow Default UI Behavior** sits with them, greyed until Use uihook is on; each row's sentence says what it does. Pets are rows of the
  Party windows and go with Party. The choices are kept while the plugin is not loaded. `/winparty native on` turns Use uihook on too; `/winparty native status` says how the hooking is doing.

While a fish is on the line, party mode lets through what the game's own party list draws outside the list,
because the game draws the fish's stamina gauge with it (in the middle of the screen, not where the list sits).
So the gauge shows and winparty's windows stay. This needs uihook 1.65. With an older uihook, the game's whole party
list is given back for the fight instead, and winparty's party windows step aside so the party is not shown twice. This lasts from the bite
until the fight ends (the client's fishing packet ending or releasing the catch, a change of area, or the
fight's time limit passing).

Target mode keeps the **game's own overhead main/subtarget arrows**, including their placement, animation
and range tints. No Lua replacement cursor is drawn. All custom target windows share the native target
window's lifecycle; no entity (for example some doors) may mean an arrow without a custom information bar.

Manual and automatic positions and styling stay the defaults. Outer window drop shadows are captured
with native-rendered party/alliance and target windows, using Winxi's shadow settings. Only the outer
shadow is drawn in native mode, so it cannot darken the existing window background. Bar and text shadows
are unchanged.

**Use Default UI Positioning is hidden and forced off for this testing build**, including old
saved opt-ins. Its alliance-location controls are hidden too. Manual positions, corners and links are
kept; the ordinary Automatic Positioning is still available. With Automatic Positioning off, arrange the
alliances on their own in Organize. Alliance 3 is linked below Alliance 2 by default, not to the main
party; use **Unlink** to move all three lists separately.

- **Follow Default UI Behavior** stays a separate opt-in for native-rendered groups: they follow the native
  window lifecycle rather than the custom chat/map hide rules, keep the native member order, may draw a solo
  party, and do not use the addon's idle/presence fading. The loading, interface-hide and cutscene guards stay.
  Styles, sizes, pet/buff choices and non-native groups keep their normal settings. This is not a
  pixel-for-pixel copy of the stock frames or all their animations.

Follow Default UI Behavior is off by default and **has not yet been live-tested**. Organize uses ordinary
windows and brings back the stock HUD frames for the time being; it edits the saved manual positions. Native anchoring
cannot be turned back on through saved settings while parked.
Turning off one mode leaves the other alone. Do not run hideparty alongside either mode.
The uihook plugin comes in winparty's zip; from this repository, build it from [plugins/uihook](../../plugins/uihook/README.md).

## Native Selection Cursor

Selected members get the animated, right-pointing cursor from the installed client's
`ROM/119/51.DAT`, played at 15 FPS. The cursor keeps the DAT's artwork and colours and scales
with the name text. It lies over the frame to the left of the name, without indenting the name or
changing where it is cut short; it may overlap other elements. No replacement cursor PNG is bundled.
Reload Party after changing the DAT or its overlay. If the DAT, sprites or texture cannot load,
Party falls back to `>>` for the target and `>` for subtarget/party-cursor selection, and retries
now and then. `/winparty cursor` retries at once and reports whether loading failed at DAT read,
DAT parsing or texture upload (or confirms that it loaded). This only draws a marker;
it does not move or change the game's cursor.

## Party-Order Rearrangement

While the native party cursor is active, the party buff icons are replaced with outlined job/subjob
labels beside each member. This covers party-order rearrangement
and choosing a party member with `<stpt>`/`<stal>`. The labels appear in all three party lists,
including Alliance 2 and Alliance 3. A label looks like `[WAR15/RDM7]`; an unknown half is `---`, so
a wholly unknown member shows `[---/---]`. Members in another zone also get a label.
Labels stay outlined even with Winxi Theme's Text Outline at 0. The buffs come back when the party cursor
closes. Role sorting and idle fading are paused while the party cursor is active.
This is separate from the addon's Organize mode and does not change the target or pet frames.

## Resolution And Scaling

Frame sizes use the saved style scale; changing the aspect ratio does not stretch the bars. The real
presentation and Windows DPI behaviour still need checking in game.

Turn on **Behavior → Positioning → Automatic Positioning** for the edge-relative layout
(off by default):

- Main party: bottom-right, **15px from the right and bottom**, growing upward and leftward.
- Target: **5px above the main party**, following its actual height.
- Alliance 2: **15px from the right**, at a steady vertical position reserved for the full layout.
- Alliance 3: **5px below Alliance 2**, keeping their existing vertical link.
- With both alliance parties and the main party fully expanded, **35px is reserved between the bottom
  of Alliance 3 and the top of Target**. Pet space reserves at least **Pets → Reserved Pet Rows**
  (default two, one when party pets are hidden), and grows for the real pet count, up to six.
  Choose six for a steady full-party reservation that does not move as pets appear.
  Target letter-debuff rows are also reserved.
- Sub-target and target of target keep their manual positioning and existing links.

Frame scale and text sizes are unchanged. Manual positions and the main party's saved corner are
kept, and turning off Automatic Positioning returns to the manual layout. Turn it off to drag
the managed frames to places of your own.

With this option off, positions stay absolute pixels. Use **Organize**, or Shift+drag with
Lock Windows off, to place frames by hand. The original defaults include positions beyond a 1920-wide output. Oversized frames
cannot fit completely on small screens, and buff icons that reach outside a window may still reach
the screen edge; this is basic adaptation, not a full responsive layout system.

## window borders
In **wxi → Styles → Window Border**, choose **Theme** (the default), **Brushed Silver**, **Bronze**, **FFXI-inspired**, **Crystal**, **Royal Gold**, **Obsidian**, **Plain Obsidian**, **Royal Silver**, **Royal Platinum**, **Mythril**, **Adaman**, **Jade** or **Amethyst**.
The border is part of winxi's theme, so it is drawn on every window of every addon that follows
the same theme, including this addon's party, target and pet windows.
The thin **3px** edging replaces the native window border; it does not sit on top of it.
Corners keep their size as windows resize, and borders fade with the window.
Theme stays the default; if textures are missing, the theme border stays visible.
**Border Opacity** (beside it) fades the border of every game window, plain or art: 100 is solid, 0 is none.
Settings windows keep a solid border.

Preview: [the borders](../libs/winxi/assets/borders/preview.png).

Choosing a border keeps your current theme background. For the FFXI-inspired look, use a dark navy
background in Winxi Theme. Keep the theme padding at least **3px** to leave room for these borders.

## window backgrounds
In **wxi → Styles → Window Background**, choose **Plain** (the default), **Gradient**, **FFXI-inspired**, **Grain**, **Marble**, **Weave** or **Brushed Metal**.
Each is drawn in your Background Color, its opacity included, and fades with the window. Like the
border, it is part of winxi's theme and drawn on every game window; settings windows stay plain.

Preview: [the backgrounds](../libs/winxi/assets/backgrounds/preview.png).

## bar textures
In **wxi → Styles → Bar Texture**, choose **Original**, **Glass**, **Detailed**, **Crystal**, **Satin**, **Runic**, **Classic FF**, **Radiant (Bright)**, **Chrome** (the default), **Flat**, **Segmented**, **Ember**, **Kingdom**, **Magitek**, **Aether**, **Elven**, **Gothic**, **Enamel**, **Enamel (Lit Rim)**, **Enamel (Gradient)**, **Glass Tube**, **Glass Tube (Deep)** or **Glass Enamel**.

Preview: [the bar textures](assets/bars/preview.png).

The choice applies to HP and MP across the party, target and pet frames.
Colours, range fading, bar sizes and the optional bookends still work as before.

**Bar Frame** draws a frame of its own in place of the texture's. **Capsule Outline** is a thin
rim in the cyan of the Rounded bookends, and **Capsule Outline (Silver)** in Rounded Silver's, along the
bar above and below. It is not tinted by the HP/MP colour. With those bookends the bar and its caps
are one capsule being filled; with others, or none, its ends are closed square. **Bar Texture** keeps
the texture's own frame. **Bar Frame Opacity (%)** makes either frame see-through: 100 is solid, 0 hides it.

**Fill End Glow (%)** puts a soft white light at the end of each fill, where it stops, as on the
game's own gauges: 0 is none, 100 the brightest. It dims with the bar's range fading.
**Custom Bar Backdrop** colours the empty part of the bars with **Bar Backdrop Color** instead
of a darker shade of the bar's own colour; its alpha lets the dark trough show through.

## matching bookends
Turn on **wxi → Styles → Bar Bookends**, then choose **Bookend Style**: **Bar Texture** (the default), **Match Border**, any border's name, **Kingdom**, **Magitek**, **Aether**, **Elven**, **Gothic**, **Rounded** or **Rounded Silver**.

Preview: [the bookends](assets/bookends/preview.png).

**Bookend Opacity** (under Bookend Style) makes them see-through: 100 is solid, 0 hides them.
They stay visible whatever the range, fade with the window, and work with all bar textures.
Missing ornaments fall back to the bar's existing cap.
For the silver combination, choose the **Royal Silver** border, **Radiant (Bright)** bars,
and **Match Border** bookends.

The Original bar images are XivParty's, cut down to the bars themselves, with its licence.
Needs `libs/winxi`.

## Pre-releases and release candidates

A testing round's package is a **pre-release**: the version carries `-pre1`, `-pre2`... (in `addon.version`, so
`/addon list` and the settings window say it), and its notes say what it is. A pre-release that comes
through a round with nothing left to fix becomes a **release candidate**, `-rc1`. A candidate that runs a
round untouched is the release, its version without a suffix.

What to try in a round:

- **Loading**: `/addon load winparty` alone (the overlay windows), then with `/load uihook` (the native
  windows, Use uihook on); unload and load each again while the other stays. With hideparty loaded too,
  party refuses its native windows and says so.
- **The windows**: your party, an alliance's other two parties, pets, the target, sub-target and target
  of target, each with its bars, values, cursor, leader marks, debuffs and lock-on brackets; a zone
  change, an invite waiting, the treasure pool, and fishing (the game's own target window, with its
  stamina gauge, while a fish is on the line).
- **The settings window**: every tab, each row doing what its sentence says, dependents greyed under
  their parent; Style's fonts, bars, bookends and backgrounds; Advanced: Value Positioning; saving and
  reloading the character's settings.
- **What to send**: a screenshot of the window in question, your settings file
  (`config\addons\winparty\<character>.lua`, nothing private in it but the character's name), and the
  lines of Ashita's log around any error. Say which pre-release: the version in `/addon list`.

