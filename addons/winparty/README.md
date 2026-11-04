# winparty

Party, alliance, target and pet frames in the shared winxi style, following the compact layout of
the Windower addon [XivParty](https://github.com/Tylas11/XivParty). Each member occupies a single
line with HP, MP and TP. The target frames show your target, sub-target and target of target, with
HP, distance and debuffs.

## Highlights

- Compact frames for your party, alliance, pets and target that match your other winxi addons.
- Buffs and debuffs with their remaining time, and a mark on the ones you can remove.
- Party members' casts as they happen, and the debuffs seen to land on your target.
- With the uihook plugin, which comes with its download, it can replace the game's own party and
  target windows.

### Renamed from party and xiframes

Up to 0.4 this addon was called party.

- Load `winparty` in place of `party`, and remove the old `addons\party` folder.
- Each character's settings are brought over from `party` the first time it logs in.
- `/pt` and `/xif` still open the settings, as `/winparty` does.

Before that, it was called xiframes.

- The first time each character logs in, what xiframes kept for them (`config\addons\xiframes`) is
  brought over as the settings. You do not need to copy anything by hand. xiframes' folder is left as
  it was.
- Unload xiframes and load winparty in its place. Change `xiframes` to `winparty` in any script that
  loads it.
- `/xiframes` is no longer used.

It needs `libs/winxi`.

## Commands

```text
/winparty                        the settings (also /pt and /xif)
/winparty help                   every command, in the chat log
/winparty native on|off          the party and alliance lists in the game's place, with uihook
/winparty native target on|off   the target windows in the game's place, with uihook
/winparty native status          a short report on the uihook mode and whether it is ready
/winparty cursor                 tries again to load the selection cursor, and says how it went
```

- `/party` is left alone, for the game's own party chat.

## The windows

### Party

Your party, and the other two parties of your alliance.

- Each member is one line: the name, an HP bar, a smaller MP bar with their values, and TP as a number.
- **Selection**: a selected member has the game's moving cursor before their name. The name is blue
  for your target, and green for a sub-target or a party-cursor selection.
- **Leaders**: a leader has a circle before their name. It is yellow for the party's leader. The
  alliance's leader has a white one above it.
- **Level sync**: the level sync designee (the member the party is synced to) has a red circle at the
  right end of their line, at the same height as the party leader's circle (the upper of an alliance
  leader's two).
- Your own party's list grows upwards, and its buffs run to the left from the window.
- **Notices**: the game's own icons beside the window mark a party or alliance invite waiting for an
  answer (a green exclamation mark in a dark circle), and anything in the treasure pool (the chest).
- A name can run as far as the right end of its HP bar. Only past that is it cut short with "...".

### Target

Your target, sub-target and target of target. Each is a line of the same kind: the name, the HP bar,
the distance and the HP percentage.

- If you want, it shows the enemy's debuffs too: as letters under the line, or as status icons beside
  it, placed and sized like your party's buffs.
- **Lock-On Brackets** put a [ and a ] outside the main target's window while you are locked on to it
  (see [Target tab](#target-tab)).

### Pets

Your pet, and your party members' pets, are listed under your party, below a line.

- With **Show Statuses** on, each pet has its statuses beside it, as your party does. The game does not
  say what is on a pet. So these are the statuses seen to land on it in the battle messages.
- With **Show Durations** on, each status has an estimated time under it. The ones you cast are in
  **Your Color**.
- When a monster's debuff wears off a pet, nobody is told. So its icon stays until its usual time runs
  out. Removing it with a spell is seen.

### Using the mouse

- **Lock Windows** (click-through) lets clicks go through to the game. The windows still notice the
  mouse over them. With **Show Tooltips** on, their tooltips show either way. Another window drawn over
  them that takes the mouse stops them from showing.
- **Shift+drag** moves a window when **Lock Windows** is off. Hold Shift as you click the window, and
  the drag goes on until you let go of the mouse button. Without Shift the windows stay put, so a
  click on them does not move them.
- With Lock Windows on, the windows cannot be dragged, except while organizing.
- A window placed by Automatic Positioning or by uihook, or linked to another window, is not moved this
  way. (Organize unlinks it.)
- There is no click to target.

### Organize

**Organize**, at the bottom of the settings window, fills the windows with sample data so you can drag
them into place. While you organize, one sample member casts Cure IV.

## Settings

`/winparty` (or `/pt`, or `/xif`) opens the settings. The tabs are:

| Tab | What it holds |
|---|---|
| **Behavior** | **Positioning** (with the optional **Automatic Positioning**), then **uihook** while that plugin is loaded, then **Mouse Interaction**. |
| **Style** | How every window is drawn: sizes, fonts, bars and statuses. |
| **Party** | Settings for your party and alliance. |
| **Target** | Settings for the target windows. |
| **Pets** | Settings for pets. |
| **Visibility** | The hiding rules (**Hide Windows**), **Fade When Idle**, and which windows fade (**Fading**). |

There is no Winxi Theme tab in winparty. Use **wxi** for the shared colours, padding, shadows, window
borders, bar textures, bookends and custom status icons. The dark edge round names and values is
Winxi Theme's **Text Outline**, set in wxi for every addon. The settings window has no reset buttons
for its sections.

### Style tab

**Appearance**

- **Frame Scale**: how big the party lists and target windows are drawn, all together.
- **Bar Shadows**: Off, Simple (one layer) or Full (two layers). This is separate from Winxi's window
  shadows.

**Names** and **Values**

- **Name Font** and **Value Font** each choose a Windows font: one for the names, and one for the HP,
  MP and TP numbers (and a target's distance and HP percentage). **Theme Font** uses the font set in
  Winxi Theme. The defaults are `trebucbi.ttf` for names and `ubuntu-bi.ttf` for values.
- **Short Zone Names** (on by default): a member in another zone shows the game's own short name for
  the zone where their bars would be, or the full name where the game has no short one. When off, the
  full name is shown, cut short where it does not fit.

**Status Display**

- **Show Statuses** (on by default) draws the buff and debuff icons beside your party, alliance and
  pets. When off, every status setting (Status Display, Status Durations, Removable Marks, Status
  Filtering, Advanced: Status IDs) is greyed out but kept. A target's debuffs follow the Target tab.
- An icon limit of 1–32 (**Maximum Status Icons**), one or two rows (**Status Rows**), and which way
  icons grow (**Status Growth**): to the left, to the right, or towards the most space.
- **Fit Status Icons To Screen** keeps icons inside the screen edge. To be safe, in mixed sets it
  leaves room for the widest icon.
- **Status Overflow Count**: when needed, the last free place becomes a `+N` badge. If there is no
  room outside the window, the badge goes in the window's lower-left corner.
- Two rows make each line taller.

**Status Durations**

- **Show Durations** (off by default) writes the time left under each status icon: seconds, then
  minutes (`m`), then hours (`h`).
- Your own times are exact, read from the game.
- Your party's and a target's times are estimates, written in **Estimate Color** (yellow by default).
  They count from when the status was seen to land, or to appear on the member, using the server's
  usual time. Where that cannot be known, `-` is written.
- Statuses you cast are written in **Your Color** (green by default), so you can see when someone
  else's replaces yours.
- **Duration Text Size** sets how tall the times are, compared with the icons. **Duration Font** sets
  their font (the Value Font to begin with).
- The windows stay the same size: the icons get smaller to make room for the times under them.
- **Low Time Warning** (10 seconds by default, 0 for none) makes an icon that is running out fade out
  and in.

**Removable Marks** (off by default)

Puts a small dot in a dark border, inside the corner of each status you can remove, as the server
says:

- **Curable Mark Color** (light blue): on debuffs of your party, pets and a player target that Erase, a
  -na spell or a waltz removes;
- **Dispellable Mark Color** (amber): on a monster's buffs that Dispel removes.

A friend's buffs and a monster's debuffs are not marked.

**Only What You Can Remove** marks only what a spell you have learned can remove, at your level now:
your main job's level, or your support job's while it is not restricted. So level sync is followed.
Abilities like Healing Waltz are not counted yet. A status's tooltip names the spells that remove it,
and says when you can cast one.

**Status Filtering**

- **Debuffs First**: every debuff comes before every buff, nearest the window in the Status Growth
  direction. Priority Effects set the order within each kind.
- **Priority Effects** and **Hidden Effects** are lists you pick from. Search by name or ID, tick
  effects, and change the priority order with Up and Down. Priority order follows the list. Hidden
  effects always win. Other effects keep their usual order.
- The debuffs are the ones Erase or a waltz removes in Phoenix's `data/status_effects.yaml`, plus the
  harmful ones that cannot be removed (sleep, charm, doom, helix, enemy songs, dazes, the Geo downs and
  the like).

**Advanced: Status IDs** (folded by default)

You can type the same two lists as status numbers separated by commas (**Priority Status IDs** and
**Hidden Status IDs**). This is also where you enter numbers that have no name in the game's files.

**Warnings**

- **Low HP Warning**: shows a `!` below this HP (zero turns it off).
- **Flash TP When Ready** and **TP Ready Color** (blue to begin with). TP is ready at 1000.

**Advanced: Range Indicators** (folded by default)

- **Near Range** (in centimetres) and **Far Range** (in metres), and how much each dims the bars beyond
  it (**Beyond Near Range Opacity**, **Beyond Far Range Opacity**).
- The far range is always treated as at least the near range.
- These show rough distances. They do not promise that an action is in range.

### Party tab

- **Show Cast Bars** (Casting, on by default): while a member of your party or alliance casts a spell,
  their HP bar fills in pale blue as the cast goes. Their name becomes the spell's, and the time left is
  written where their HP was. The casts are seen in the server's messages, so the time is the spell's
  base cast time, marked `~`. The server's message that the spell finished or was interrupted ends it.
- **Alliance Scale** (Alliance): sizes the alliance's other two parties, on top of Frame Scale.
- **Advanced: Value Positioning** (folded): moves the HP, MP and TP numbers of the party, the alliance
  and pets.
- **Sort By Role** is hidden. Sorting you saved before still works as it did. Role sorting pauses
  while the game's own party selection is active.

### Target tab

- **Debuff List** (off to begin with) is a box of its own. It lists every debuff seen to land on your
  target, with its name and the time it has left, soonest to run out first. The time is an estimate,
  as the tooltips say. The target's name is the first line. There is no box while nothing is on the
  target.
  - It is a plain box, dragged by its body. **Lock Windows** holds it still. **Debuff List Position**
    places it, as dragging does.
  - **Winxi Theme** (off to begin with) draws it as a themed window instead, with its border,
    background and font. It is then moved, faded and organized as the target windows are.
  - It goes with the target, whichever target windows are shown, and counts the debuffs on its own.
- **Game Name Colors** (Names, off to begin with) writes the name in the colour the game gives it over
  the head:

  | Who | Colour |
  |---|---|
  | An enemy, unclaimed | yellow |
  | An enemy claimed by your party or alliance | red |
  | An enemy claimed by anyone else | purple |
  | An enemy after help is called for | orange |
  | A player | white, or blue in your party or alliance |
  | An NPC | green |
  | Anything dead | grey |

  With namehook loaded and the name on screen, the colour is read from the game itself, exactly, and
  held steady while the game makes the target's name pulse. Otherwise it is worked out: the NPC green,
  player white and party blue are measured from the game, and the enemy colours are close to it.
- **Monster Letters** (Names, on to begin with) puts a monster's spawn letter after its name, in a
  small box in the name's colour. The letter is A, B, C… among the monsters of one name in the area, by
  their places in the game's own list, so every player sees the same letters. After Z, it starts again
  at A. There is none for players or NPCs, or where the area's list cannot be read or does not match
  what the game shows.
- **Lock-On Brackets** (Lock-On, on to begin with) put a [ and a ] outside the left and right of the
  main target's window while you are locked on to it. They frame it without touching it, as the game
  frames its own target. They are drawn in the **Bracket Color** (white to begin with) with the theme's
  Text Outline.
- **Advanced: Value Positioning** (folded) moves the HP percentage and the distance, each on its own.
  The party's settings no longer move them.

### Pets tab

- **Pet Names** (Layout): `Pet`, `Owner: Pet` (default) or `Pet (Owner)`.

### Behavior tab: tooltips

- **Show Tooltips** (Mouse Interaction, next to Lock Windows) is off by default. When on, resting the
  mouse on the windows shows Winxi tooltips: full names, jobs and pet owners on the members, and each
  buff and debuff (icons, and a target's letters) with its estimated time left.
- Resting the mouse on a status icon shows its time left, the spell or move that put it there and who
  cast it (where that was seen), and what removes it.
- Tooltips follow **wxi → Tooltips**, including whether they show, their delay and their look.
- Tooltips with an enemy's times say plainly that they are estimates, not exact server timers.

### Debuff tracking

Tracking of enemy debuffs is cleared when the windows are turned off, when settings or the character
change, and when you enter or leave a zone, even while the windows are off. When the windows are
turned on again, tracking starts with only newly seen effects. It never rebuilds a full list of an
enemy's statuses.

## Positioning

### Automatic Positioning

Turn on **Behavior → Positioning → Automatic Positioning** (off by default) to place the windows from
the screen edges:

- Main party: bottom right, **15 pixels from the right and the bottom**, growing up and to the left.
- Target: **5 pixels above the main party**, following its actual height.
- Alliance 2: **15 pixels from the right**, at a fixed height kept free for the full layout.
- Alliance 3: **5 pixels below Alliance 2**, keeping their link.
- With both alliance parties and the main party full, **35 pixels are kept free between the bottom of
  Alliance 3 and the top of Target**.
- Pet space keeps at least **Pets → Reserved Pet Rows** free (default two, or one when party members'
  pets are hidden). It grows for the real number of pets, up to six. Choose six for a full party, so
  the layout does not move as pets appear.
- Room for a target's debuff letters is kept free too.
- Sub-target and target of target keep their own positions and links.

Window scale and text sizes do not change. Your own positions and the main party's saved corner are
kept. Turning Automatic Positioning off goes back to your own layout. Turn it off to drag those windows
where you want them.

### Placing windows yourself

With Automatic Positioning off, positions are fixed numbers of pixels. Use **Organize**, or Shift+drag
with Lock Windows off, to place the windows by hand. With Automatic Positioning off, arrange the
alliances on their own in Organize. Alliance 3 is linked below Alliance 2 by default, not to the main
party. Use **Unlink** to move all three lists separately.

### Screen size

- Window sizes use the saved scale. Changing the screen's shape (aspect ratio) does not stretch the
  bars.
- How it really looks, and how it behaves with Windows display scaling (DPI), still need checking in
  game.
- The original default positions include places beyond a 1920-pixel-wide screen.
- Very large windows cannot fit completely on small screens. Buff icons outside a window may still
  reach the screen edge.
- This is basic adjustment to screen size, not a layout that fully adapts to every screen.

## Selection cursor

A selected member gets the game's moving, right-pointing cursor, read from the game file
`ROM/119/51.DAT` and played at 15 frames a second.

- The cursor keeps the game's artwork and colours, and grows and shrinks with the name text.
- It sits over the window to the left of the name. It does not push the name over or change where the
  name is cut short. It may cover other parts of the window.
- No replacement cursor picture comes with winparty.
- Reload winparty after you change that game file, or a Pivot replacement of it.
- If the cursor cannot be loaded, winparty shows `>>` for the target and `>` for a sub-target or
  party-cursor selection, and tries again now and then.
- `/winparty cursor` tries again at once. It says whether loading failed at reading the file,
  understanding it, or making the picture, or that it loaded.
- This only draws a marker. It does not move or change the game's cursor.

## Changing the party order

While the game's party cursor is active, the party's buff icons are replaced with job labels beside
each member. This happens when you rearrange the party order, and when you choose a party member with
`<stpt>`/`<stal>`.

- The labels appear in all three party lists, including Alliance 2 and Alliance 3.
- A label looks like `[WAR15/RDM7]`. An unknown half is `---`, so a member that is wholly unknown shows
  `[---/---]`.
- Members in another zone get a label too.
- Labels always have an outline, even with Winxi Theme's Text Outline at 0.
- The buffs come back when the party cursor closes.
- Role sorting and idle fading pause while the party cursor is active.
- This is separate from winparty's Organize mode, and does not change the target or pet windows.

## With the uihook plugin (experimental)

With the [uihook](../../plugins/uihook/README.md) plugin, winparty's windows are drawn at the same
stage as the game's own windows, in their place, instead of on top of everything. So, for example, the
game's menus are drawn over them. Normal drawing stays the default.

### Install

- Use uihook for new installs. It does buff, party and target support in one plugin. Load
  `/load uihook` instead of `/load partyhook`, and never load both.
- winparty still supports the old partyhook, so you can go back to it. The notes below apply to both
  plugins.
- uihook comes in winparty's zip. From this repository, build it from
  [plugins/uihook](../../plugins/uihook/README.md), which also has the install and update steps.
- Unload winparty and partyhook before you replace the plugin file (DLL).
- **Do not run hideparty with either mode.** With hideparty loaded, winparty refuses to draw in the
  game's place, and says so.

### Turning it on

- `/winparty native on|off`: the party and alliance lists, including the pet rows in them.
- `/winparty native target on|off`: the target windows on their own. It takes over the main,
  sub-target and target-of-target windows together, at the stage where the game draws its target
  box. The normal Target settings still choose which are shown.
- `/winparty native status`: a short report on the mode and whether it is ready. The detailed debug
  counters are hidden.

In the settings, **Behavior → uihook** sits between Positioning and Mouse Interaction. It shows only
while uihook (or partyhook) is loaded. Its title is followed, in green, by the plugin found and its
version, for example `[uihook 1.60 found]`.

- **Use uihook** turns the plugin's drawing on or off as a whole. `/winparty native on` turns it on
  too.
- While it is on, **Party** and **Target** choose which windows the plugin draws in the game's place.
  Pets are rows of the Party windows, and go with Party.
- **Follow Default UI Behavior** sits with them, greyed out until Use uihook is on. Each row's
  sentence says what it does.
- Your choices are kept while the plugin is not loaded. `/winparty native status` says how the
  plugin's drawing is doing.
- Turning off one mode leaves the other alone.

### How it behaves

- **Target mode** keeps the **game's own arrows over the main target and sub-target**, with their
  placement, movement and range colours. winparty does not draw a cursor of its own. All the target
  windows appear and go with the game's own target window. Where there is no character (for example
  some doors), you may see an arrow without a winparty target window.
- **Shadows**: your own and automatic positions and your styles stay the defaults. The outer drop
  shadow is drawn with the party, alliance and target windows, using Winxi's shadow settings. Only the
  outer shadow is drawn in this mode, so it cannot darken the window background. Bar and text shadows
  do not change.
- **Fishing**: while a fish is on the line, the game draws the fish's stamina gauge with its party list
  (in the middle of the screen, not where the list sits). Party mode lets through what the game's party
  list draws outside the list. So the gauge shows and winparty's windows stay. This needs uihook 1.65.
  With an older uihook, the game's whole party list is given back for the fight instead, and
  winparty's party windows step aside so the party is not shown twice. This lasts from the bite until
  the fight ends: the fishing message ending or releasing the catch, a change of area, or the fight's
  time limit passing.

### Follow Default UI Behavior

**Follow Default UI Behavior** is a separate choice for the windows drawn in the game's place. With it
on, those windows:

- appear and go with the game's own windows, instead of following winparty's chat and map hiding
  rules;
- keep the game's member order;
- may show a party of one;
- do not use winparty's idle fading.

The loading, interface-hidden and cutscene checks still apply. Styles, sizes, pet and buff choices,
and windows not drawn in the game's place keep their normal settings. This is not an exact copy of the
game's windows or all their animations.

Follow Default UI Behavior is off by default and **has not yet been tested in live play**.

### Testing status

- Tested by players: party rearranging, chat hiding, target arrows, menu overlap, sub-target range
  colours, quick switching, monsters disappearing, doors, cutscenes, hiding and showing the interface,
  and turning each mode on and off separately.
- **Changing zone is still untested**, as are recovering after the graphics device resets and wider
  game version support.
- **Use Default UI Positioning is hidden and forced off in this testing build**, including if you
  turned it on before. Its alliance-location settings are hidden too. While it is parked like this,
  it cannot be turned back on through saved settings. Your own positions, corners and links are kept,
  and the normal Automatic Positioning still works.
- Organize uses ordinary windows and brings back the game's own windows for the time being. It
  changes your saved positions.

## Looks (set in wxi)

These are part of winxi's shared theme, so they apply to every window of every addon that follows the
same theme, including winparty's party, target and pet windows.

### Window borders

In **wxi → Styles → Window Border**, choose **Theme** (the default), **Brushed Silver**, **Bronze**,
**FFXI-inspired**, **Crystal**, **Royal Gold**, **Obsidian**, **Plain Obsidian**, **Royal Silver**,
**Royal Platinum**, **Mythril**, **Adaman**, **Jade** or **Amethyst**.

- The thin **3-pixel** edge replaces the window's normal border. It does not sit on top of it.
- Corners keep their size as windows resize, and borders fade with the window.
- Theme stays the default. If the border pictures are missing, the theme border still shows.
- **Border Opacity** (next to it) fades the border of every game window, plain or art: 100 is solid, 0
  is none. Settings windows keep a solid border.
- Choosing a border keeps your current theme background. For the FFXI-inspired look, use a dark navy
  background in Winxi Theme.
- Keep the theme padding at least **3 pixels** to leave room for these borders.

Preview: [the borders](../libs/winxi/assets/borders/preview.png).

### Window backgrounds

In **wxi → Styles → Window Background**, choose **Plain** (the default), **Gradient**,
**FFXI-inspired**, **Grain**, **Marble**, **Weave** or **Brushed Metal**.

Each is drawn in your Background Color, including its opacity, and fades with the window. It is drawn
on every game window. Settings windows stay plain.

Preview: [the backgrounds](../libs/winxi/assets/backgrounds/preview.png).

### Bar textures

In **wxi → Styles → Bar Texture**, choose **Original**, **Glass**, **Detailed**, **Crystal**,
**Satin**, **Runic**, **Classic FF**, **Radiant (Bright)**, **Chrome** (the default), **Flat**,
**Segmented**, **Ember**, **Kingdom**, **Magitek**, **Aether**, **Elven**, **Gothic**, **Enamel**,
**Enamel (Lit Rim)**, **Enamel (Gradient)**, **Glass Tube**, **Glass Tube (Deep)** or **Glass Enamel**.

Preview: [the bar textures](assets/bars/preview.png).

The choice applies to HP and MP bars across the party, target and pet windows. Colours, range fading,
bar sizes and the optional bookends work as before.

- **Bar Frame** draws a frame of its own in place of the texture's:
  - **Capsule Outline** is a thin rim in the cyan of the Rounded bookends, along the top and bottom of
    the bar;
  - **Capsule Outline (Silver)** is the same in Rounded Silver's colour;
  - neither is tinted by the HP or MP colour. With those bookends, the bar and its end caps are one
    capsule being filled. With other bookends, or none, its ends are square;
  - **Bar Texture** keeps the texture's own frame.
- **Bar Frame Opacity (%)** makes either frame see-through: 100 is solid, 0 hides it.
- **Fill End Glow (%)** puts a soft white light at the end of each fill, where it stops, as on the
  game's own bars: 0 is none, 100 is the brightest. It dims with the bar's range fading.
- **Custom Bar Backdrop** colours the empty part of the bars with **Bar Backdrop Color**, instead of a
  darker shade of the bar's own colour. Its transparency lets the dark trough show through.

### Bookends

Bookends are decorations at the two ends of a bar. Turn on **wxi → Styles → Bar Bookends**, then choose
**Bookend Style**: **Bar Texture** (the default), **Match Border**, any border's name, **Kingdom**,
**Magitek**, **Aether**, **Elven**, **Gothic**, **Rounded** or **Rounded Silver**.

Preview: [the bookends](assets/bookends/preview.png).

- **Bookend Opacity** (under Bookend Style) makes them see-through: 100 is solid, 0 hides them.
- They stay visible at any range, fade with the window, and work with all bar textures.
- If an ornament is missing, the bar's normal end cap is used.
- For the silver look, choose the **Royal Silver** border, **Radiant (Bright)** bars and **Match
  Border** bookends.

## Credits

The Original bar pictures are XivParty's, cut down to the bars themselves, with its licence.

## Pre-releases and release candidates

A test round's download is a **pre-release**. Its version ends in `-pre1`, `-pre2` and so on (in
`addon.version`, so `/addon list` and the settings window show it), and its notes say what it is.

- A pre-release that gets through a round with nothing left to fix becomes a **release candidate**,
  `-rc1`.
- A candidate that gets through a round unchanged is the release, with no ending on its version.

What to try in a round:

- **Loading**: `/addon load winparty` alone (the normal windows), then with `/load uihook` (the windows
  in the game's place, Use uihook on). Unload and load each again while the other stays loaded. With
  hideparty loaded too, winparty refuses to draw in the game's place, and says so.
- **The windows**: your party, an alliance's other two parties, pets, the target, sub-target and target
  of target, each with its bars, values, cursor, leader marks, debuffs and lock-on brackets. Also: a
  zone change, an invite waiting, the treasure pool, and fishing (the game's own target window, with
  its stamina gauge, while a fish is on the line).
- **The settings window**: every tab, each row doing what its sentence says, and settings greyed out
  under the setting they depend on. Style's fonts, bars, bookends and backgrounds. Advanced: Value
  Positioning. Saving and reloading the character's settings.
- **What to send**: a screenshot of the window in question, your settings file
  (`config\addons\winparty\<character>.lua`, which has nothing private in it but the character's name),
  and the lines of Ashita's log around any error. Say which pre-release you used: the version in
  `/addon list`.
