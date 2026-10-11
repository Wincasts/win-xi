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

## The addon and the plugin

What is shown is the plugin's to keep, and can be changed there as well: by its own command
(`/nameplatehook hide players`) or by another addon. The settings here and the plugin are kept the
same. They are given to the plugin when it is found, when another character's are loaded, and as they
change; and a change made in the plugin is taken into them, and saved.

If this addon is unloaded, names stay as they were last set, until the plugin is unloaded.
`/nameplatehook show all` shows them all again. If the plugin is not loaded, the settings window says
so, and what is set is given to the plugin when it is.
