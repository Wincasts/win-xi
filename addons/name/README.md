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
| Show Icons | The game's icons before a name |
| Icon Size | An icon's side, as a percentage of the height of the names |
| Icon Spacing | The space between a name's icons and the name itself, 0 to 24 pixels |
| Show Mastery Stars | The three stars over the name of a player with a job mastered |

The names are not drawn on the screen by this addon, as its windows are. An addon draws on the finished
picture, where nothing of the world can hide what it draws, and a name drawn there shows through
walls. So each name is set out here (`custom.lua`) as rectangles, one for each letter and icon, and
left with the plugin, which draws them in the game's own picture at the moment the game would have
drawn the name, as deep in the picture as the name is. A wall, the ground or a character in front of
a name hides it, or the part of it that it covers, as it hides the game's.

The letters are those of imgui's font, at the size asked for, and where the game's picture is larger
than its window (a background resolution above the window's) they are made larger to match, so that
they are as sharp as the rest of the picture. What is set out in one frame is drawn in the next.

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
