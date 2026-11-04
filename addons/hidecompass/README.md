# hidecompass

Hides the game's compass as soon as it is loaded. The compass can be shown or hidden again at any
time with `/hidecompass`.

## Highlights

- A cleaner screen without the compass.
- Show or hide it at any time with a single command.
- Nothing to configure.

## Commands

- `/hidecompass`: hides the compass, or shows it again
- `/hidecompass hide` (or `h`): hides it
- `/hidecompass show` (or `s`): shows it again
- `/hidecompass help`: lists the commands

When you show the compass again, it fades in, as it does after a cutscene.

## If it stops working

The addon looks for the compass in the game's program files. A game update can move it. If the addon
cannot find it, it says so when it loads ("Failed to locate required pointer") and does nothing.
