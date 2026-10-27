# Name tooltip catalogue

Edit the text below each Label/Location block. Keep IDs unchanged.
See [editing instructions](README.md).

## name.tracking.monster
Label: Tracked NM
Location: NM Tracking → Tracked Monster

Marks one notorious monster of this area, and each monster it can spawn from, with a hunt sign in place of the [aggro] icon. Enemy Format needs [aggro]. The choice is kept when you leave the area.

## name.tracking.size
Label: Target Size (%)
Location: NM Tracking → Tracked Monster

How much larger the tracked monster's whole nameplate is drawn. Its placeholders stay the usual size.

## name.tracking.placeholders
Label: Label Placeholders
Location: NM Tracking → Placeholder Options

Writes "Placeholder" in place of each placeholder's name. The rest of its nameplate is unchanged.

## name.health_bars.entity_types
Label: Entity Types
Location: Bars → Health Bar Entity Types

Whether names of this kind have a health bar.

## name.format.player
Label: Player Format
Location: Names → Player Names

How player names are written. Tokens:
[name] - the player's name.
[party] - their party or alliance role: Alliance Leader, Party Leader, another party's leader, Alliance Member or Party Member. Nothing while you are alone.
[icons] - the game's player icons.
[distance] - distance in yalms.
[space] - a gap: [space: 8] for 8 px, 4 without. Only between two things written.
Anything else is written as it is.

Options go after a colon, e.g. [name: color=yellow, space=4]:
Any token - color=yellow or #FF8000; space=0-64, pixels after it; when=target+checked+nm+relevant; within=1-100 yalms.
[name], [distance] - spacing=0-10, pixels between letters.
[icons], [party] - size=25-300, % of the name's height.
[icons] - gap=0-24, pixels between icons.
[party] - replace, its sign in place of the game's icons.
[distance] - decimals=0-2.

Example format:
[party][icons][name] ([distance]y)
Example result: [party sign][icons] Player Name (12.4y)
## name.format.enemy
Label: Enemy Format
Location: Names → Enemy Names

How enemy names are written. Tokens:
[name] - the enemy's name.
[level] - its level range, or its exact level once checked.
[aggro] - whether it is aggressive, once known.
[checked] - a magnifying glass once it has been checked.
[letters] - its spawn letter, the same on everyone's screen; [letter] is the same.
[distance] - distance in yalms.
[space] - a gap: [space: 8] for 8 px, 4 without. Only between two things written.
Anything else is written as it is; a token with nothing known is left out.

Options go after a colon, e.g. [name: color=yellow, space=4]:
Any token - color=yellow or #FF8000; space=0-64, pixels after it; when=target+checked+nm+relevant; within=1-100 yalms.
[name], [level], [distance] - spacing=0-10, pixels between letters.
[level] - exact, only a checked level; nocombat, none while it fights.
[aggro], [checked] - size=25-300, % of the name's height.
[letters] - type=single or double (AA, AB after Z).
[distance] - decimals=0-2.

Example format:
[aggro] Lv [level]. [name] [letters] ([distance]y)
Example result: [aggro icon] Lv 80-82. Goblin Butcher A (12.4y)
## name.format.npc
Label: NPC Format
Location: Names → NPC Names

How NPC names are written. Tokens:
[name] - the NPC's name.
[vendor] - a coin for an NPC that sells: shops, guild merchants and outpost vendors.
[icons] - the game's icons, when it gives any.
[distance] - distance in yalms.
[space] - a gap: [space: 8] for 8 px, 4 without. Only between two things written.
Anything else is written as it is.

Options go after a colon, e.g. [name: color=yellow, space=4]:
Any token - color=yellow or #FF8000; space=0-64, pixels after it; when=target+checked+nm+relevant; within=1-100 yalms.
[name], [distance] - spacing=0-10, pixels between letters.
[vendor], [icons] - size=25-300, % of the name's height.
[icons] - gap=0-24, pixels between icons.
[distance] - decimals=0-2.

Example format:
[vendor][name] ([distance]y)
Example result: [coin] Babubu (4.2y)
## name.format.reset
Label: Reset Format
Location: Names → All format editors

Puts back this format's default. Nothing else changes.

## name.appearance.font
Label: Font
Location: Names → General Name Appearance

The font names are written in: one from C:\Windows\Fonts, or Default, the font everything else is written in.

## name.appearance.bold
Label: Bold
Location: Names → General Name Appearance

Bold: names and check details are written heavier. Icons and outlines are unchanged.

## name.appearance.smooth_font
Label: Smooth Font
Location: Names → General Name Appearance → beside Bold

Smooth Font: letters are drawn from a finer copy of the font, so curves and diagonals look smoother, especially under Lens. Very small text may look softer. Off to begin with.

## name.appearance.maximum_size
Label: Maximum Name Size (px)
Location: Names → General Name Appearance

How large a name is when close, for players, enemies and NPCs alike. Bars have a size of their own.

## name.appearance.minimum_size
Label: Minimum Name Size (px)
Location: Names → General Name Appearance

The smallest a name shrinks to as it gets farther away.

## name.appearance.subtarget_size
Label: Subtarget Size (%)
Location: Names → General Name Appearance

Size of the name under the subtarget cursor while you choose a target. 100% is its usual size.

## name.appearance.letter_spacing
Label: Letter Spacing (px)
Location: Names → General Name Appearance

Extra room between the letters of every name, in pixels at the name's largest; it shrinks with the name. 0 is the font's own spacing. A token can have its own: [name: spacing=2].

## name.appearance.icon_outline
Label: Icon Outline (px)
Location: Names → General Name Appearance

Thickness of the outline around icons: player, party role, vendor, aggro, sense and check icons. 0 draws them without one. Text Outline is separate; mastery stars and letter badges have their own.

## name.appearance.text_outline_opacity
Label: Text Outline Opacity (%)
Location: Names → General Name Appearance

How solid the outline around text is: names, levels, distances, check details and cast text. 0% hides it. Icon outlines are separate.

## name.appearance.icon_outline_opacity
Label: Icon Outline Opacity (%)
Location: Names → General Name Appearance

How solid the outline around icons is. 0% hides it. Text outlines are separate.

## name.players.icon_source
Label: Player Icon Source
Location: Names → Player Names

Where the player icons and mastery stars come from. Game DATs: the game's own artwork, Pivot replacements included. Bundled: the set Name comes with. Custom: addons/name/assets/player-icons-custom.png, laid out like the bundled player-icons.png. A source that cannot be loaded falls back to Bundled. Reload Name after changing the artwork.

## name.players.icon_source_fallback
Label: Player icon fallback
Location: Names → Player Names

The chosen icon source could not be loaded, so the bundled icons are used. Your choice is kept and tried again now and then, and when Name is reloaded. Reason: {reason}

## name.enemies.check_enabled
Label: Enabled
Location: Check Details → Check Details

After you check a monster, its difficulty, what it detects by and what it links with are written under its name for five seconds.

## name.enemies.check_size
Label: Size (%)
Location: Check Details → Check Details

Size of the check text and icons, relative to the name.

## name.enemies.check_abbreviate
Label: Abbreviate Difficulty
Location: Check Details → Check Details

Short difficulty labels (TW, IEP, EP, DC, EM, T, VT, IT) when detection or link details are written beside them. Difficulty on its own is written in full; Impossible to Gauge is always ???.

## name.enemies.check_style
Label: Display Style
Location: Check Details → Check Details

Icons with text, or text alone, e.g. TW, Sight Aggro, Link: Goblin (Sight). Detection can be Sight, Sound, Blood, Magic, JA, Scent or true sight and sound; Link names the family the monster helps and how it detects.

## name.appearance.outline
Label: Text Outline (px)
Location: Names → General Name Appearance

Thickness of the outline around text. 0 draws text without one. Icon Outline is separate.

## name.health_bars.enabled
Label: Enabled
Location: Bars → Health Bars

A health bar under names, pets, trusts and NPCs included. At full health there is no bar, except while a cast bar is shown, so the cast bar does not move when its owner takes damage.

## name.health_bars.combat_only
Label: Combat Only
Location: Bars → Health Bars

Health bars only on what is fighting and alive. Being targeted or claimed is not fighting.


## name.health_bars.preview
Label: Preview
Location: Bars → Shared Bar Settings

While this section is open, every name that can have a bar shows one, emptying and filling, and with cast bars on, a sample cast. Real bars and casts take its place. Nothing is saved; the preview stops shortly after you leave this section or close the window.
## name.health_bars.width
Label: Bar Width (px)
Location: Bars → Shared Bar Settings

Width of the health and cast bars, border included; the least they are with Fit to Name. Both shrink with the name. With both, the health bar is above the cast bar.

## name.health_bars.height
Label: Bar Height (px)
Location: Bars → Shared Bar Settings

Height of the health and cast bars, border included. Both shrink with the name. The cast's name and timer are written below the bars, and statuses below those when placed underneath.

## name.colours.section
Label: Colour Overrides
Location: Names → Player / Enemy / NPC Names

The states the game colours names by. An override colours the name, its spawn letter and its health bar fill; a state without one keeps the game's colour. Icons are unchanged.

## name.colours.state
Label: State Override
Location: Names → Colour Overrides

Colours the name, its letters and its health bar fill in this state, in place of the game's colour, even where a token has a colour of its own. Fading is unchanged.

## name.presets.default
Label: Default
Location: General → Preset

Player icons, enemy aggro and spawn letters, status icons and check details; no health bars.

## name.presets.minimal
Label: Minimal
Location: General → Preset

Names alone: no icons, levels, bars, statuses or check details.

## name.presets.robust
Label: Robust
Location: General → Preset

Everything there is to know: enemy aggro, level, spawn letters and distance, health bars at all times, status icons and check details.

## name.presets.immersive
Label: Immersive
Location: General → Preset

Close to the game's own: names with player icons, and health bars only in combat; no levels, letters, status icons or check details.

## name.general.preset
Label: Preset
Location: General

A ready-made look: it sets the formats, health bars, status icons and check details. Font, sizes, colours, visibility and the chosen statuses are kept. Custom: none of these.

## name.general.custom_names
Label: Enable Name
Location: General

Name draws the names over heads. Off, the game draws its own, at the size namehook gives them, and Name's bars and status icons are not drawn; the Visibility rules still apply. The other settings are greyed out, their values kept.

## name.statuses.enabled
Label: Enabled
Location: Statuses → Display

Shows the ticked statuses on the names. Your own and your party's are the game's; everyone else's are worked out from the battle messages, so effects you did not see may be missing.

## name.statuses.icons
Label: Icons
Location: Statuses → Display

Which icons the statuses are drawn with. Winxi Theme follows the Custom Icons setting in /wxi; Game Icons are the game's own; Custom Icons are the custom set chosen in /wxi, with the game's icon for a status the set lacks.

## name.statuses.size
Label: Size (%)
Location: Statuses → Display

Height of the status icons, relative to the name.

## name.statuses.position
Label: Position
Location: Statuses → Display

Above the name, over any mastery stars, or below it, under a checked monster's details.

## name.statuses.alignment
Label: Alignment
Location: Statuses → Display

Which side of the name the row lines up with: its left, middle or right.

## name.statuses.offset_x
Label: X Offset (px)
Location: Statuses → Display

Moves the row right, in pixels; below 0, left.

## name.statuses.offset_y
Label: Y Offset (px)
Location: Statuses → Display

Moves the row down, in pixels; below 0, up.

## name.statuses.preview
Label: Preview
Location: Statuses → Display

Shows the first few ticked statuses over every visible name, to see how the row looks. Not saved: off again when Name is reloaded.

## name.statuses.entity_types
Label: Entity Types
Location: Statuses → Entity Types

Whether names of this kind have a row of statuses.

## name.statuses.search
Label: Search
Location: Statuses → Selected Statuses

Part of a status's name, or its number. Only a ticked status is drawn.

## name.statuses.selected_only
Label: Selected Only
Location: Statuses → Selected Statuses

Lists only the ticked statuses.

## name.visibility.self
Label: Own Name
Location: Visibility → Players

The name over your own head.

## name.visibility.party
Label: Party Members
Location: Visibility → Players

The others of your party, trusts among them.

## name.visibility.alliance
Label: Alliance Members
Location: Visibility → Players

The other parties of your alliance.

## name.visibility.players
Label: Other Players
Location: Visibility → Players

Every player outside your party and alliance. A whitelisted player (/namehook whitelist add <name>) is shown all the same.

## name.visibility.my_pet
Label: My Pet
Location: Visibility → Pets

Your own pet.

## name.visibility.pets
Label: Other Pets
Location: Visibility → Pets

Anyone else's pet, trust or adventuring fellow.

## name.visibility.npcs
Label: NPCs
Location: Visibility → NPCs & Monsters

What cannot be fought: townspeople, doors, and the rest.

## name.visibility.monsters
Label: Monsters
Location: Visibility → NPCs & Monsters

What can be fought, charmed players among them.

## name.visibility.target
Label: Always Show Target
Location: Visibility → Target

Shows your target's name even when names of its kind are hidden. Your own stays hidden while Own Name is off.

## name.diagnostics.enabled
Label: Enable Diagnostics
Location: General → Diagnostics

Keeps a record of drawing problems, and writes a log when Name's names stop.

## name.diagnostics.in_view
Label: Names In View
Location: General → Diagnostics

The names the game drew last frame: close enough, and on screen.

## name.diagnostics.custom_names
Label: Custom Names
Location: General → Diagnostics

Whether Name is drawing the names now. When it stops for more than half a second, the game draws its own, the reason is said once in the chat log, and a log is written.

## name.diagnostics.log
Label: Diagnostic Log
Location: General → Diagnostics

Writes what Name and namehook are doing, and what happened lately, to config\addons\name\logs. It can contain character names, paths, formats and raw errors; for sharing, Write Report leaves those out.

## name.readability.crowd
Label: Crowd Decluttering
Location: Visibility → Crowd Decluttering

In a crowd, ordinary names are cut down to the name, spawn letter and aggro icon: no other text, icons, stars, check details, bars or statuses. Your target and subtarget, yourself, your party and alliance, your pet, whitelisted and charmed players, the tracked NM and anyone casting stay in full. Off to begin with.

## name.readability.crowd_threshold
Label: Crowd Threshold (names)
Location: Visibility → Crowd Decluttering

How many names on screen make a crowd. The crowd ends once there are three fewer.

## name.readability.crowd_hold
Label: Hold Time (ms)
Location: Visibility → Crowd Decluttering

How long a crowd has to last before details are hidden, and how long it has to be gone before they return, so names do not flicker as people cross the edge of the screen.

## name.readability.distance
Label: Distance Colours
Location: Names → Distance Thresholds

Colours the [distance] token when something is far away: Warning Colour from Warning Distance, Danger Colour from Danger Distance. A token with a colour of its own keeps it. These are distances, not spell or ability ranges. Off to begin with.

## name.readability.distance_warning
Label: Warning Distance (y)
Location: Names → Distance Thresholds

Warning Colour from this many yalms away, until Danger Distance. Danger Distance is kept at least this far.

## name.readability.distance_danger
Label: Danger Distance (y)
Location: Names → Distance Thresholds

Danger Colour from this many yalms away.

## name.readability.distance_hysteresis
Label: Exit Margin (y)
Location: Names → Distance Thresholds

Once a colour has come on, the distance has to fall this many yalms below its threshold before it goes off, so the colour does not flicker at the boundary. 0 turns the margin off.

## name.readability.distance_colors
Label: Warning / Danger Colour
Location: Names → Distance Thresholds

The colours of the distance at Warning and at Danger. Nearer than Warning Distance it keeps its usual colour.

## name.diagnostics.report
Label: Support Report
Location: General → Diagnostics

Writes a report for sharing to config\addons\name\logs: versions, what the plugin can do, counts of names and draws, the artwork source and failure counts. No character names, chat, paths, formats or errors. Works with diagnostics off; /name report does the same. Nothing is uploaded.

## name.cast_bars.enabled
Label: Enabled
Location: Bars → Cast Bars

A bar under a name while its owner casts a spell, filling as the cast goes on, with the spell's name and time left below. It is the name's colour and has the health bar's width and height; a health bar sits above it. Cast times are estimates (~): if the estimate runs out first, the bar waits full; if no time is known, the time so far (+) is shown instead.

## name.cast_bars.weaponskills
Label: Show Weaponskills
Location: Bars → Cast Bars

Also shows readied weaponskills and monster TP moves, with estimated preparation times where known; a finished one briefly shows its name and Used. These are what has been seen, not a prediction of what comes next. Off to begin with.

## name.cast_bars.skill_text_only
Label: Text Only for Weaponskills
Location: Bars → Cast Bars

Weaponskills and TP moves as name and timer alone, with no bar. Spells keep their bar. On to begin with.

## name.cast_bars.auto_width
Label: Fit to Name
Location: Bars → Shared Bar Settings

Health and cast bars grow to the width of the name and its spawn letter; Bar Width is the least they are. Icons, distances and check details do not count. Off to begin with.
## name.cast_bars.name_scale
Label: Cast Name Size (%)
Location: Bars → Cast Text

Size of the action's name, relative to the name text. 75% to begin with.

## name.cast_bars.timer_scale
Label: Timer Size (%)
Location: Bars → Cast Text

Size of the timer, relative to the name text; Used and Waiting too. 75% to begin with.

## name.cast_text.font
Label: Font
Location: Bars → Cast Text

The font the action's name and timer are written in. Same as Names (to begin with) is the names' font; Default is the font everything else is written in; or one from C:\Windows\Fonts. A font that cannot be loaded falls back to the names'.

## name.cast_text.show_name
Label: Show Action Name
Location: Bars → Cast Text

Writes the spell, weaponskill or TP move's name under the cast bar. On to begin with.

## name.cast_text.show_timer
Label: Show Timer
Location: Bars → Cast Text

Writes the time left (~), the time so far (+), Waiting or Used under the action's name. On to begin with.

## name.cast_text.colour
Label: Text Colour
Location: Bars → Cast Text

The colour of the action's name and timer: White (to begin with), Name Colour (the name's and its cast bar's) or Custom.

## name.cast_text.custom_colour
Label: Custom Colour
Location: Bars → Cast Text

The colour of the action's name and timer when Text Colour is Custom.
