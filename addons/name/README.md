# name

Called nametoggle up to 1.5. Its settings were kept under that name: to keep them, copy the folder
`config\addons\nametoggle` to `config\addons\name` before loading it.

Shows and hides the names over characters' heads, by what they are over. A settings window for the
`namehook` plugin, which does the showing and hiding: the plugin has to be loaded.

```
/load namehook
/addon load name
```

- `/name`: opens or closes the settings
- `/name show <kind>...`, `/name hide <kind>...`, `/name toggle <kind>...`: shows or
  hides names of one kind or more: `self`, `party`, `alliance`, `players`, `mypet`, `pets`, `npcs`,
  `monsters`, or `all`

- `/name custom`, `/name custom on`, `/name custom off`: whether this addon draws
  the names or the game does

For example, `/name hide players alliance` leaves your party's the only players' names.

## Settings

Kept for each character. Each is on for names that are shown.

| Setting | Whose names |
|---|---|
| Own Name | Your own |
| Party Members | The others of your party, trusts among them |
| Alliance Members | The other parties of your alliance |
| Other Players | Every other player. A player on the plugin's whitelist is shown all the same: `/namehook whitelist add <name>` |
| My Pet | Your own pet |
| Other Pets | Anyone else's pet, trust or adventuring fellow |
| NPCs | What cannot be fought |
| Monsters | What can be fought, charmed players among them |
| Always Show Target | Your target's name is shown though names like it are hidden. Your own is not: with Own Name off it stays hidden while you have yourself targeted |

Names In View, under them, is how many names the game had to draw last frame, and how many of them
are hidden.

## Custom names

Experimental. With Custom Names on, in the settings' Custom Names tab, the names are drawn in winxi's
outlined text and not by the game: each in the colour the game gives it, with the game's icons before
it. Which names are shown is still set in the Settings tab; only how they look changes. It needs
namehook 1.10 or later.

| Setting | What it does |
|---|---|
| Custom Names (experimental) | On, the names are drawn in winxi's style; off, the game draws them, and the rest of the tab is put away |
| Maximum Font Size | The height of a name near to, 6 to 48 pixels. Called Font Size while names do not shrink |
| Minimum Font Size | The height of a name at the distance it is no longer drawn at; never more than the maximum |
| Shrink With Distance | A name gets smaller as it nears the distance it is no longer drawn at, from the maximum size to the minimum; off, names stay one size |
| Outline Thickness | The dark edge round each name, 0 to 4 pixels; at 0 the names are written plain |
| Font (experimental) | A font of Windows' own, chosen by its file in `C:\Windows\Fonts`; Default is the font everything else is written in |
| Name Format | How every name but a monster's is written: see [How a name is written](#how-a-name-is-written) |
| Monster Format | How a monster's name is written |
| Targeted Monster Format | How the name of the monster you have targeted is written. Left empty, it is written as other monsters' are |
| Checked Monster Format | How the name of a monster you have checked is written, until it dies or you leave the area. Left empty, checking a monster changes nothing of how its name is set out. For a monster that is both checked and targeted, this one is used |
| Show Icons | The game's icons before a name |
| Icon Size | An icon's side, as a percentage of the height of the names |
| Icon Spacing | The space between a name's icons and the name itself, 0 to 24 pixels |
| Show Mastery Stars | The three stars over the name of a player with a job mastered |

### How a name is written

Each of the four formats is a line of text. In it `[name]` stands for the name, `[distance]` for how
far the character is from you, in yalms to a tenth, as the game measures it, and `[level]` for the
levels a monster can be. Everything else is written as you type it.

| Format | Written |
|---|---|
| `[name]` | `Goblin` |
| `[name] [distance]` | `Goblin 12.3` |
| `[name] ([distance]y)` | `Goblin (12.3y)` |
| `[distance] - [name]` | `12.3 - Goblin` |
| `[name] Lv[level]` | `Goblin Lv8-10` |

A thing is in the colour the game gives the name unless you give it another. A colour is `#RRGGBB`,
`#RGB`, or one of `white`, `black`, `grey`, `red`, `green`, `blue`, `yellow`, `orange`, `purple`,
`pink`, `cyan`.

| Format | What is coloured |
|---|---|
| `[name] [distance:yellow]` | The distance |
| `[name:#FF8000] [distance]` | The name |
| `[name] [grey]([distance]y)[/]` | Everything from `[grey]` to `[/]`, or to the end of the line if there is no `[/]` |

Square brackets round anything else are written as they are, so a format such as `[NM] [name]` writes
`[NM] Goblin`. Only the letters, figures and signs of plain English can be written.

`[level]` is not the level of the one monster, which the game does not tell: it is the levels that
monster can be, as `5-6`, or as `8` where it can only be the one. They are from the tables in this
addon's `data` folder, one for each area, which are mobdb's, made from the server's own, and copied
here so that mobdb need not be installed. To bring them up to date, copy mobdb's `data` folder over
this one. For what the tables do not have (a player, an NPC, a monster the server makes as it goes)
`[level]` writes nothing, and what was typed round it is still written.

When you `/check` a monster, the game's answer has its level in it, and from then on `[level]` writes
that one level for that monster in place of the range. It is forgotten when the monster dies, when it
is no longer there to be seen, and when you leave the area, since the monster that next has its place
is another. Nothing is sent to the game for this: the addon only reads the answers to checks you make
yourself. A notorious monster, whose strength is impossible to gauge, gives no level.

`[checked]` writes a magnifying glass for a monster whose level is known that way, and nothing for any
other, so `[name] Lv[level][checked]` marks the levels that are a monster's own and not a range. It
takes a colour as the others do. The magnifying glass is one of the icons Ashita's own font has; a font
chosen for the names does not have it, and it is then drawn from Ashita's beside that font's letters.

To write a distance after the name of the monster you have targeted and no other, leave Monster Format
as `[name]` and set Targeted Monster Format to `[name] [distance]`. The Show Monster Distance and
Distance For Target Only settings of 1.9 and 1.10 are made into these lines when the addon is loaded.

The names are not drawn on the screen by this addon, as its windows are. An addon draws on the finished
picture, where nothing of the world can hide what it draws, and a name drawn there shows through
walls. So each name is set out here (`custom.lua`) as rectangles, one for each letter and icon, and
left with the plugin, which draws them in the game's own picture at the moment the game would have
drawn the name, as deep in the picture as the name is. A wall, the ground or a character in front of
a name hides it, or the part of it that it covers, as it hides the game's.

The letters are those of imgui's font, and where the game's picture is larger than its window (a
background resolution above the window's) they are made larger to match, so that they are as sharp as
the rest of the picture. They are kept at three sizes only: the largest a name can be, three quarters
of it and half of it. A name at its largest is drawn letter for letter; a smaller one is drawn from
the next size up, scaled down to fit, so that names shrink smoothly with distance and imgui is not
asked for letters of a new size at every step. What is set out in one frame is drawn in the next.

A name is drawn exactly when the game would have drawn it, and fades with its character as the game's
does. The game shrinks a name to nothing over the last of its distance; here it shrinks from the
maximum size to the minimum and fades out, or keeps its size and fades out over the last third.

The icons are drawn from the game's own picture of them, found in its memory (`icons.lua`); the
linkshell pearl is given its linkshell's colour.

With Custom Names off, the addon unloaded, or the plugin not recognising the client, the game draws
the names as before.

## The addon and the plugin

What is shown is the plugin's to keep, and can be changed there as well: by its own command
(`/namehook hide players`) or by another addon. The settings here and the plugin are kept the
same. They are given to the plugin when it is found, when another character's are loaded, and as they
change; and a change made in the plugin is taken into them, and saved.

If this addon is unloaded, names stay as they were last set, until the plugin is unloaded.
`/namehook show all` shows them all again. If the plugin is not loaded, the settings window says
so, and what is set is given to the plugin when it is.
