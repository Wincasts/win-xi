# hidecompass

Hides the game's own compass. It is hidden from the moment the addon loads.

- `/hidecompass`: toggles the compass
- `/hidecompass hide` (or `h`): hides it
- `/hidecompass show` (or `s`): shows it again
- `/hidecompass help`: lists the commands

## How it works

The client keeps one compass object, with a state it steps through itself: hidden, asked to show, fading
in, shown, fading out. Its drawing is skipped while the state is hidden. Each frame the game draws the
compass and then, if it finds it hidden and nothing is in the way, asks for it to be shown again; the
addon sets it back to hidden before the next frame is drawn. Showing it again is left to the game: the
addon simply stops, and the compass fades in as it does after a cutscene.

The object is found by a signature in `FFXiMain.dll`, read from the Phoenix client. If a client update
moves things, the addon says on loading that it failed to locate the pointer, and does nothing.
