# Name tooltip catalogue

Edit the text below each Label/Location block. Keep IDs unchanged.
See [editing instructions](README.md).

## name.tracking.monster
Label: Tracked NM
Location: NM Tracking → Tracked Monster

Track a notorious monster in this area. Requires [aggro] in Mob Format and Show Aggro Icons. The choice is saved when you leave.

## name.tracking.size
Label: Target Size (%)
Location: NM Tracking → Tracked Monster

Enlarge the tracked monster's whole nameplate. Placeholders keep their normal size.

## name.tracking.placeholders
Label: Label Placeholders
Location: NM Tracking → Placeholder Options

Replace placeholder names with "Placeholder". The rest of each nameplate is unchanged.

## name.health_bars.entity_types
Label: Entity Types
Location: Health Bars → Entity Types

Whether names of this kind have a health bar.

## name.format.player
Label: Player Format
Location: Names → Player Names

How player names are written. Tokens:
[name] - the player's name.
[party] - a party or alliance member's sign: Alliance Leader, Party Leader, another party's leader, Alliance Member or Party Member. None while you are alone.
[icons] - the game's player icons.
[distance] - distance in yalms.
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

How enemy names are written, targeted and checked ones included. Tokens:
[name] - the enemy's name.
[level] - the level range the area's tables give, or the exact level once checked.
[aggro] - the sign of whether it is aggressive, once known.
[checked] - a magnifying glass once a check has told its level.
[letters] - its spawn-slot letter, in stable entity-index order; [letter] is the same.
[distance] - distance in yalms.
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
[vendor] - a coin for an NPC that sells: gil shops, guild merchants and outpost vendors.
[icons] - the game's icons, when it gives any.
[distance] - distance in yalms.
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

Restore this category's default format without changing other settings.

## name.appearance.font
Label: Font
Location: Names → General Name Appearance

A font of Windows' own, by its file in C:\Windows\Fonts. Default is the font everything else is written in.

## name.appearance.bold
Label: Bold
Location: Names → General Name Appearance

Makes names and check-detail text heavier, by drawing each letter twice, a pixel apart. Icons, stars and outline thickness are unchanged.

## name.appearance.smooth_font
Label: Smooth Font
Location: Names → General Name Appearance → beside Bold

Smooth Font builds a cached text atlas from glyphs rasterised at four times the normal resolution. Each output pixel averages the full source area, with transparent padding around the glyph. It can smooth curves and diagonals, especially under Lens. Off uses the original hinted glyphs for comparison.

Name size, spacing, baseline and outline thickness are kept. Bold works independently; icons and letter badges are unchanged. Uses more font-atlas memory and may soften very small text. Atlas generation happens on startup or font/size changes, not every frame. Direct glyph rendering is used while the atlas is preparing or unavailable. Off releases Name's generated atlas; ImGui may retain shared source-font atlas memory until it reclaims or rebuilds it. Disabled by default.

## name.appearance.maximum_size
Label: Maximum Name Size (px)
Location: Names → General Name Appearance

Nearby name size shared by players, enemies and NPCs. Independent of health-bar dimensions.

## name.appearance.minimum_size
Label: Minimum Name Size (px)
Location: Names → General Name Appearance

Smallest distant name size shared by every entity type.

## name.appearance.subtarget_size
Label: Subtarget Size (%)
Location: Names → General Name Appearance

Size of the name under the subtarget cursor while choosing a target. 100% is normal size.

## name.appearance.letter_spacing
Label: Letter Spacing (px)
Location: Names → General Name Appearance

Extra space between the letters of every name, in pixels at the name's largest; it shrinks with the name. 0 is the font's own spacing. A [name], [level] or [distance] token's spacing= option sets its own, e.g. [name: spacing=2].

## name.appearance.icon_outline
Label: Icon Outline (px)
Location: Names → General Name Appearance

Outline thickness for player, party-role, vendor, aggro/passive, sense and check icons, independent of Text Outline. Zero disables icon outlines without fading the artwork. Width follows name distance and render-resolution scaling. Aggro/passive icons remain shadow-free, but follow this width instead of the previous fixed one-pixel cap. Requires namehook 1.35 and WinXI 47; an older plugin leaves native names intact with an update warning. Mastery stars and letter badges retain their own rendering.

## name.appearance.text_outline_opacity
Label: Text Outline Opacity (%)
Location: Names → General Name Appearance

Opacity of the outline round text only: names, levels, distances, check details and cast text. 0% hides it, 100% is the outline colour's full opacity. Letters, icon outlines and name opacity are unchanged; distance fading still applies. Default 100%.

## name.appearance.icon_outline_opacity
Label: Icon Outline Opacity (%)
Location: Names → General Name Appearance

Opacity of icon outlines only: 0% hides the outlines, 100% uses full configured outline-colour opacity. Icon fills, text outlines and name opacity are unchanged. Applies uniformly across outlined icon types and all player-icon sources; normal distance/entity fading still applies. Default 100%.

## name.players.icon_source
Label: Player Icon Source
Location: Names → Player Names

Artwork for the game's player-name icons and mastery stars. Game DATs reads the installed menu DAT and its glyph mapping, including Pivot replacements when redirect_fopens is enabled. Bundled uses Name's included atlas. Custom loads addons/name/assets/player-icons-custom.png with the bundled atlas layout and normal PNG alpha. Copy player-icons.png as a starting template; a higher-resolution version may use the same proportional layout. Missing or unsupported sources fall back to Bundled. Reload Name after changing artwork or Pivot packs. Party/alliance role icons, vendor and monster icons are independent.

## name.players.icon_source_fallback
Label: Player icon fallback
Location: Names → Player Names

The selected player-icon source could not be loaded; Name tries the bundled atlas instead. Your source selection is retained. Game DAT failures retry at most every ten seconds; reloading Name or switching sources also retries. Custom file loads retry through the shared image loader. Reason: {reason}

## name.enemies.check_enabled
Label: Enabled
Location: Check Details → Check Details

Show difficulty, detection and linking information for five seconds after checking a monster.

## name.enemies.check_size
Label: Size (%)
Location: Check Details → Check Details

Size of check text and icons relative to the name. Applies to both display styles.

## name.enemies.check_abbreviate
Label: Abbreviate Difficulty
Location: Check Details → Check Details

Use short difficulty labels beside detection/link details: TW, IEP, EP, DC, EM, T, VT and IT. Difficulty shown alone is in full words; Impossible to Gauge stays ???.

## name.enemies.check_style
Label: Display Style
Location: Check Details → Check Details

Choose icons with text, or a text-only description, such as: TW, Sight Aggro, Link: Goblin (Sight). Detection can be Sight, Sound, Blood, Magic, JA, Scent and the true senses, several separated by a slash; Link names the monster family and how it detects.

## name.appearance.outline
Label: Text Outline (px)
Location: Names → General Name Appearance

Choose the text outline thickness. 0 disables text outlines without changing icon outlines. Icon Outline and Icon Outline Opacity control icons separately (requires namehook 1.35 and WinXI 47).

## name.health_bars.enabled
Label: Enabled
Location: Health Bars → Health Bars

One shared health-bar setting for every entity, including pets/trusts and NPCs. Requires valid HP data. Full-health entities normally have no bar; while their cast bar is active, an enabled/eligible HP row stays visible above it so damage does not move the cast bar.

## name.health_bars.combat_only
Label: Combat Only
Location: Health Bars → Health Bars

Show bars only for the entity whose status is Engaged (1) and HP is above zero. Being targeted or claimed alone is not combat. Missing status data hides the bar. Applies to every type.

## name.health_bars.width
Label: Bar Width (px)
Location: Health Bars → Shared Bar Size

One width, including the border, for HP and cast bars. Both use the same horizontal origin and shrink with the name. With both rows present, HP is above cast. Existing saved HP-bar widths are retained; the setting is editable when either kind of bar is enabled.

## name.health_bars.height
Label: Bar Height (px)
Location: Health Bars → Shared Bar Size

One height, including the border, for HP and cast bars. Both shrink with the name and use the same gap between rows. Action name and timer appear below the cast row, with statuses below those when configured underneath.

## name.colours.section
Label: Colour Overrides
Location: Names → Player / Enemy / NPC Names

The states the game colours names by. An override applies together to name text, spawn letters and HP fill; a state not overridden keeps the game's colour. Icons and client opacity are unchanged.

## name.colours.state
Label: State Override
Location: Names → Colour Overrides

Override this state for the name, letters and matching health-bar fill, including explicit name/letter token colours. Off: the game's colour for it. RGB only. Opacity, distance fading and disappearance fading remain controlled by the renderer; a target's name does not pulse.

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

A premade look: it sets the formats, health bars, status icons and check details. Font, sizes, colours, visibility and the chosen statuses are kept. Custom: the settings are none of these.

## name.general.custom_names
Label: Enable Name
Location: General

Enable Name's custom nameplates. Off: the game draws its own, as namehook sizes them (/namehook fontsize), unstretched; saved Visibility rules still say which are shown. Name's health bars and status icons are not drawn while it is off. All other Name settings are greyed out until enabled again; their saved values are kept.

## name.statuses.enabled
Label: Enabled
Location: Statuses → Display

Show the statuses selected below on visible nameplates. Your own and your party's statuses come from the game; everyone else's from effects seen in server messages, so effects applied out of sight or before you entered the area may be unknown.

## name.statuses.icons
Label: Icons
Location: Statuses → Display

Which icons the statuses are drawn with. Winxi Theme follows Custom Icons in /wxi; Game Icons are the game's own; Custom Icons are the custom set's (the one chosen in /wxi, FFXIV to begin with), and the game's for a status the set has none for.

## name.statuses.size
Label: Size (%)
Location: Statuses → Display

An icon's height, as a percentage of the height of the names. With custom icons, each is as wide as the set's icons are for that height; the game's are square.

## name.statuses.position
Label: Position
Location: Statuses → Display

Above the name, over the mastery stars where it has them, or below it, under the line a checked monster's details are written on while they are shown.

## name.statuses.alignment
Label: Alignment
Location: Statuses → Display

Which side of the name the row is level with: its left, where its icons begin, its middle, or its right.

## name.statuses.offset_x
Label: X Offset (px)
Location: Statuses → Display

Moves the row right from where Position and Alignment put it, in screen pixels; below 0, left.

## name.statuses.offset_y
Label: Y Offset (px)
Location: Statuses → Display

Moves the row down from where Position and Alignment put it, in screen pixels; below 0, up.

## name.statuses.preview
Label: Preview
Location: Statuses → Display

Puts the first few ticked statuses over every name that is shown, whatever it is really under, to see how the row looks. Not kept: it is off again when the addon is loaded.

## name.statuses.entity_types
Label: Entity Types
Location: Statuses → Entity Types

Whether names of this kind have a row of statuses.

## name.statuses.search
Label: Search
Location: Statuses → Selected Statuses

Part of a status's name, or its number. Only a ticked status is drawn over a name.

## name.statuses.selected_only
Label: Selected Only
Location: Statuses → Selected Statuses

Lists only the statuses that are ticked.

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

Every player who is not of your party or alliance. A player on the plugin's whitelist is shown all the same: /namehook whitelist add <name>

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

Your target's name is shown though names like it are hidden. Your own is not: with Own Name off it stays hidden while you have yourself targeted.

## name.diagnostics.enabled
Label: Enable Diagnostics
Location: General → Diagnostics

Record renderer problems and write a log when custom names stop.

## name.diagnostics.in_view
Label: Names In View
Location: General → Diagnostics

The names the game had to draw last frame: near enough, and on screen.

## name.diagnostics.custom_names
Label: Custom Names
Location: General → Diagnostics

Whether Name is drawing the names. When it stops for more than half a second the game draws its own, the reason is said in the chat log once, and a log is written.

## name.diagnostics.log
Label: Diagnostic Log
Location: General → Diagnostics

Writes what Name and the namehook plugin are doing now, and what happened lately, to a small text file in config\addons\name\logs. This detailed log can contain character names, paths, formats and raw errors. For sharing, prefer Write Report, which omits them.

## name.readability.crowd
Label: Crowd Decluttering
Location: Visibility → Crowd Decluttering

Optional and off by default. In a sustained crowd, simplify ordinary plates to their name, monster letters and aggro cue. Hide secondary text, player/vendor icons, stars, check details, HP bars and status rows. Never move plates or hide their core name. Your target, subtarget, yourself, party, alliance, own pet, whitelisted/charmed players, tracked NM/placeholders and observed active casters (with Cast Bars enabled) stay fully detailed. A deliberately name-less format remains name-less.

## name.readability.crowd_threshold
Label: Crowd Threshold (names)
Location: Visibility → Crowd Decluttering

Enter crowd mode when this many wanted, positive-scale name anchors are inside the output window. This is a crowd estimate, not overlap or occlusion detection. Exit only at three fewer names, and apply Hold Time both ways.

## name.readability.crowd_hold
Label: Hold Time (ms)
Location: Visibility → Crowd Decluttering

The crowd condition must remain stable this long before details are hidden or restored. Combined with the three-name exit margin, this prevents flicker as people cross the screen edge. Targets and other protected plates remain fully detailed immediately.

## name.readability.distance
Label: Distance Colours
Location: Names → Distance Thresholds

Optional and off by default. Colour existing [distance] tokens at Warning and Danger thresholds. Explicit token colours take precedence; other tokens, text outlines, icons and layout are unchanged. These are measured distance thresholds, not guaranteed spell or ability ranges.

## name.readability.distance_warning
Label: Warning Distance (y)
Location: Names → Distance Thresholds

Use Warning Colour at or beyond this many yalms, until Danger Distance is reached. The comparison uses the measured distance, not its rounded display. Danger Distance is kept at least as large as Warning Distance.

## name.readability.distance_danger
Label: Danger Distance (y)
Location: Names → Distance Thresholds

Use Danger Colour at or beyond this many yalms. At an equal Warning and Danger threshold, Danger takes precedence. No distance is invented when the client has no valid value.

## name.readability.distance_hysteresis
Label: Exit Margin (y)
Location: Names → Distance Thresholds

After a warning starts, distance must fall below its threshold minus this margin to clear it. Entry still happens at the configured threshold. This prevents colour flicker around a boundary; 0 disables the margin. The margin is limited to less than Warning Distance so the warning can always clear. State resets on identity, zone, configuration and enable changes.

## name.readability.distance_colors
Label: Warning / Danger Colour
Location: Names → Distance Thresholds

Tint only distance tokens without an explicit token colour. Nameplate fading still applies; opacity, other text and artwork are unaffected. The nearer band uses the token's usual inherited colour.

## name.diagnostics.report
Label: Support Report
Location: General → Diagnostics

Write a shareable report to config\addons\name\logs. Includes Name/WinXI/namehook capability-build versions, capability flags, display and draw counts, generated atlas dimensions, artwork source/fallback and recorded failure counts. Omits character/entity names, chat, paths, format strings, raw errors and history. Available without enabling diagnostics; recent failure history is collected only with diagnostics on. /name report also works when Enable Name is off. Nothing is uploaded.

## name.cast_bars.enabled
Label: Enabled
Location: Cast Bars → Cast Bars

Show observed spell casts under visible names. Uses the same width, height and starting position as HP bars; an enabled and eligible HP bar is drawn above it, including full HP while casting. The fill inherits the resolved entity-name colour (including explicit name-token colours and fading), with action name and timer below as the bar fills. Active casters remain detailed in crowd mode. Base timings are estimates (~), not live Fast Cast/modifier measurements. Finish/interrupt packets take precedence. If the estimate ends first, show Waiting with a full bar; unknown durations show elapsed time (+) with no fabricated fill. Casts already in progress when enabled cannot be recovered without a start packet.

## name.cast_bars.weaponskills
Label: Show Weaponskills
Location: Cast Bars → Cast Bars

Also show readied weaponskills and monster TP moves, using estimated base preparation times where known. Completed/instant weaponskills briefly show their name and Used with a full bar; no fake charge-up is invented when there is no ready packet. Disabled by default. Spell and weaponskill bars stop on interrupts, death, despawn, zone change or a safety timeout. These are observations, not predictions of an enemy's next move.

## name.cast_bars.skill_text_only
Label: Text Only for Weaponskills
Location: Cast Bars → Cast Bars

Show weaponskills and monster TP moves as their name and timer alone, with no bar, in the place the bar would start. On by default. Spells keep their bar. Needs Show Weaponskills.

## name.cast_bars.auto_width
Label: Auto-scale to Name
Location: Cast Bars → Cast Bars

Extend the cast bar to fit the visible entity name, counting visible letter badges as part of the name in either token order. Off by default. The saved shared Bar Width remains the minimum, so short names do not shrink the bar. Uses the rendered name/letter span and intervening spaces, not the action caption, vendor/player icons or surrounding distance/check details. Centres both bar rows under that span; an eligible HP row extends with the cast row so they remain aligned. Without an active cast/preview, HP keeps its usual saved width and position. Hidden name/letter tokens are not counted; formats with neither keep the saved width. Height is unchanged, and normal nameplate scaling still applies.

## name.cast_bars.name_scale
Label: Cast Name Size (%)
Location: Cast Bars → Cast Text

Size of the action-name text relative to the nameplate font, independent of the timer. Default 75% preserves the original appearance; 25–200% is available. Does not change the bar dimensions or nameplate text. Large percentages upscale the existing font and may look softer. Status rows are moved down to clear the resized captions.

## name.cast_bars.timer_scale
Label: Timer Size (%)
Location: Cast Bars → Cast Text

Size of the remaining/elapsed timer text relative to the nameplate font, independent of the action name. Default 75% preserves the original appearance; 25–200% is available. Used and Waiting use this size too. Does not change the bar dimensions; normal fading still applies.

## name.cast_bars.preview
Label: Preview
Location: Cast Bars → Cast Bars

Session-only animated preview under visible names, clearly labelled Preview. Tune shared bar dimensions, cast-name size and timer size without waiting for a cast. Uses the actual cast-bar layout, name colour, auto-width and your real HP row when enabled. With Show Weaponskills on, the sample alternates spell and TP-move styles. Real casts take precedence. No packets, actor records or saved preview setting are created. Stops shortly after leaving this settings section/window, and resets when Name/cast bars are disabled or settings reloaded.

## name.cast_text.show_name
Label: Show Action Name
Location: Cast Bars → Cast Text

Write the spell, weaponskill or TP move's name under the cast bar. On by default.

## name.cast_text.show_timer
Label: Show Timer
Location: Cast Bars → Cast Text

Write the time left (~), the time so far (+), Waiting or Used under the action's name. On by default.

## name.cast_text.colour
Label: Text Colour
Location: Cast Bars → Cast Text

What the action name and timer are written in: White (the default), Name Colour (the same colour as the name and its cast bar) or Custom. Normal fading still applies.

## name.cast_text.custom_colour
Label: Custom Colour
Location: Cast Bars → Cast Text

The colour of the action name and timer when Text Colour is Custom.
