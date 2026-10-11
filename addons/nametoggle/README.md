# nametoggle

Shows and hides the names over characters' heads, by what they are over. A settings window for the
`nameplatehook` plugin, which does the showing and hiding: the plugin has to be loaded.

```
/load nameplatehook
/addon load nametoggle
```

- `/nametoggle`: opens or closes the settings
- `/nametoggle show <kind>...`, `/nametoggle hide <kind>...`, `/nametoggle toggle <kind>...`: shows or
  hides names of one kind or more: `self`, `party`, `alliance`, `players`, `mypet`, `pets`, `npcs`,
  `monsters`, or `all`

- `/nametoggle custom`, `/nametoggle custom on`, `/nametoggle custom off`: whether this addon draws
  the names or the game does

For example, `/nametoggle hide players alliance` leaves your party's the only players' names.

## Settings

Kept for each character. Each is on for names that are shown.

| Setting | Whose names |
|---|---|
| Own Name | Your own |
| Party Members | The others of your party, trusts among them |
| Alliance Members | The other parties of your alliance |
| Other Players | Every other player. A player on the plugin's whitelist is shown all the same: `/nameplatehook whitelist add <name>` |
| My Pet | Your own pet |
| Other Pets | Anyone else's pet, trust or adventuring fellow |
| NPCs | What cannot be fought |
| Monsters | What can be fought, charmed players among them |
| Always Show Target | Your target's name is shown though names like it are hidden |

Names In View, under them, is how many names the game had to draw last frame, and how many of them
are hidden.

## Custom names

Experimental. With Custom Names on, in the settings' Custom Names tab, the names are drawn by this
addon and not by the game: each in winxi's outlined text, in the colour the game gives it, with the
game's icons before it. Which names are shown is still set in the Settings tab; only how they look
changes.

| Setting | What it does |
|---|---|
| Custom Names (experimental) | On, this addon draws the names; off, the game does, and the rest of the tab is put away |
| Maximum Font Size | The height of a name near to, 6 to 48 pixels. Called Font Size while names do not shrink |
| Minimum Font Size | The height of a name at the distance it is no longer drawn at; never more than the maximum |
| Shrink With Distance | A name gets smaller as it nears the distance it is no longer drawn at, from the maximum size to the minimum; off, names stay one size |
| Outline Thickness | The dark edge round each name, 0 to 4 pixels; at 0 the names are written plain |
| Font (experimental) | A font of Windows' own, chosen by its file in `C:\Windows\Fonts`; Default is the font everything else is written in |
| Hide Behind Walls (experimental) | A name is not drawn while a wall, the ground or a closed door is between the camera and it |
| Show Icons | The game's icons before a name |
| Icon Size | An icon's side, as a percentage of the height of the names |
| Show Mastery Stars | The three stars over the name of a player with a job mastered |

The plugin lists each name the game was about to draw: where it is, what the game writes for it, and
in what colour. While Custom Names is on this addon claims every name, so the game draws none, and
writes the wanted ones itself (`custom.lua`). So a name is drawn here exactly when the game would have
drawn it, and fades with its character as the game's does. The game shrinks a name to nothing over
the last of its distance; here it shrinks from the maximum size to the minimum and fades out, or
keeps its size and fades out over the last third.

A name here is written over the finished picture, so nothing in the picture hides it. With Hide
Behind Walls on, the game's own test of whether a line runs into the map is asked of the line from
the camera to each name (`sight.lua`): walls, the ground and closed doors hide a name, characters do
not, and a name is hidden whole or not at all.

The icons are drawn from the game's own picture of them, found in its memory (`icons.lua`), at up to
32 pixels where the game draws them at 16; the linkshell pearl is given its linkshell's colour.

With Custom Names off, the addon unloaded, or the plugin not recognising the client, the game draws
the names as before.

## The addon and the plugin

What is shown is the plugin's to keep, and can be changed there as well: by its own command
(`/nameplatehook hide players`) or by another addon. The settings here and the plugin are kept the
same. They are given to the plugin when it is found, when another character's are loaded, and as they
change; and a change made in the plugin is taken into them, and saved.

If this addon is unloaded, names stay as they were last set, until the plugin is unloaded.
`/nameplatehook show all` shows them all again. If the plugin is not loaded, the settings window says
so, and what is set is given to the plugin when it is.
