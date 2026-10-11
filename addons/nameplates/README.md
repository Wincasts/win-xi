# nameplates

Draws the names over characters' heads in place of the game. Experimental, and basic: each name is
written once, in winxi's outlined text, with players in white and everything else in pale green.

It needs the `nameplatew` plugin, 0.70 or later, with its experimental setting on:

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
list (whose it is, and the point in the world above the head where the game was about to write it)
and the game writes nothing. This addon reads the list each frame, empties it, works out where on
screen each point falls from the camera's view and projection, and writes the name there.

So nothing is guessed about which names should show: a name is drawn here exactly when the game would
have drawn it. A name fades with its character, as the game's does.

If this addon is unloaded, or turned off, the game draws the names again. If the plugin is unloaded,
or is too old, or does not recognise the client, this addon says so once and draws nothing.

## Not yet

The game's own colours for names (party, linkshell, claimed and so on), its icons beside a name, and a
choice of font and size.
