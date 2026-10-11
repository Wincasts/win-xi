# nameplates

Draws the names over characters' heads in place of the game. Experimental, and basic: each name is
written in winxi's outlined text, in the colour the game gives it, with the game's icons before it.

It needs the `nameplatew` plugin, 0.71 or later (0.72 for the Job Mastery stars), with its experimental
setting on:

```
/load nameplatew
/nameplatew custom on
/addon load nameplates
```

`/nameplatew save` keeps the setting. Which names there are to draw is still the plugin's to decide:
its `mode` and whitelist hide names as before, and this addon draws what is left.

- `/nameplates`: opens or closes the settings
- `/nameplates on`, `/nameplates off`, `/nameplates toggle`: whether this addon draws the names or the game does

## Settings

Kept for each character, and saved when the settings window is closed.

| Setting | What it does |
|---|---|
| Draw Names | Off, the game draws the names itself |
| Font Size | The height of the names, 8 to 48 pixels |
| Shrink With Distance | A name gets smaller as it nears the distance it is no longer drawn at, as the game's own does; off, names stay one size and fade out there |
| Outline Thickness | The dark edge round each name, 0 to 4 pixels; at 0 the names are written plain |
| Font (experimental) | A font of Windows' own, chosen by its file in `C:\Windows\Fonts`; Default is the font everything else is written in |
| Show Icons | The game's icons before a name |
| Icon Size | An icon's side, as a percentage of the height of the names |
| Show Mastery Stars | The three stars over the name of a player with a job mastered |

## How it works

The game works out, each frame, which names to draw and where. The plugin stands in the way of the
game's two calls that draw a name: with its setting on and this addon asking, it puts each name on a
list (whose it is, the point in the world above the head where the game was about to write it, what
the game was about to write, and in what colour) and the game writes nothing. This addon reads the list each frame, empties it, works out where on
screen each point falls from the camera's view and projection, and writes the name there.

So nothing is guessed about which names should show, or how: a name is drawn here exactly when the
game would have drawn it, in the game's colour for it (white, a party member's blue, an NPC's green
and so on), and fades with its character as the game's does. The game draws a name at one size out
to a distance, and then smaller and smaller until, at its furthest, it is nothing; names shrink the
same way here, or with Shrink With Distance off keep their size and fade out over the last third.

What is not the game's: a name here is written over the finished picture, so it is not hidden by a
wall or a character standing in front of it, as the game's is.

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

## Job Mastery stars

The game draws them as a second line of the name. The plugin notes with each name whether that line
was about to be drawn, and they are drawn here over the middle of the name as the game has them: a
small star, a large one, a small one. `/nameplatew hidestars` hides them here as it does in the game.
