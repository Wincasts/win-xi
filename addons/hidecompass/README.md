# hidecompass

Hides the game's own compass. The compass is hidden as soon as you load the addon.

## Why use it

- It takes the compass off your screen, if you do not want it there.
- You can show it again at any time with one command.
- There is nothing to set up: load it and the compass is gone.

## Commands

- `/hidecompass`: hides the compass, or shows it again
- `/hidecompass hide` (or `h`): hides it
- `/hidecompass show` (or `s`): shows it again
- `/hidecompass help`: lists the commands

When you show the compass again, it fades in, as it does after a cutscene.

## If it stops working

The addon looks for the compass in the game's program files. A game update can move it. If the addon
cannot find it, it says so when it loads ("Failed to locate required pointer") and does nothing.
