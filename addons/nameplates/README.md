# nameplates

Draws the names over characters' heads in place of the game. Experimental, and basic: each name is
written in winxi's outlined text, in the colour the game gives it, with the game's icons before it.

It needs the `nameplatew` plugin, 0.71 or later, with its experimental setting on:

```
/load nameplatew
/nameplatew custom on
/addon load nameplates
```

`/nameplatew save` keeps the setting. Which names there are to draw is still the plugin's to decide:
its `mode` and whitelist hide names as before, and this addon draws what is left.

- `/nameplates`: toggles between this addon drawing the names and the game drawing them
- `/nameplates on`, `/nameplates off`: sets which
- `/nameplates help`: lists the commands

## How it works

The game works out, each frame, which names to draw and where. The plugin stands in the way of the
game's two calls that draw a name: with its setting on and this addon asking, it puts each name on a
list (whose it is, the point in the world above the head where the game was about to write it, what
the game was about to write, and in what colour) and the game writes nothing. This addon reads the list each frame, empties it, works out where on
screen each point falls from the camera's view and projection, and writes the name there.

So nothing is guessed about which names should show, or how: a name is drawn here exactly when the
game would have drawn it, in the game's colour for it (white, a party member's blue, an NPC's green
and so on), and fades with its character as the game's does. Where the game draws a name smaller and
smaller as it nears the distance it stops at, it is faded out here over the last third of that.

## Icons

What the game writes for a name begins with its icons (the linkshell pearl, the party's flags, the
bazaar's bag, GM and the rest), each a single character of the game's own font. They are drawn here
from the game's own picture of them, found in its memory (`icons.lua`), so they are whatever icons the
client has, a DAT mod's included. That picture holds each icon 32 pixels square; the game draws them at
16, and here they are drawn from all 32. The pearl is given its linkshell's colour, as the game gives it.

The picture is not drawn from as it is, since nothing in it is more than about half solid (the game
draws it at twice its strength): a copy is made once, with that put right. If the client's picture is
kept some other way than the one `icons.lua` knows, the game's own is used, and the icons are fainter
than they should be. If the game's font is not found at all, names are drawn without icons.

If this addon is unloaded, or turned off, the game draws the names again. If the plugin is unloaded,
or is too old, or does not recognise the client, this addon says so once and draws nothing.

## Not yet

A choice of font and size, and the Job Mastery stars, which the game draws on a line of their own.
