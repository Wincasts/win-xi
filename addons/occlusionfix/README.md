# occlusionfix

Stops characters (players, NPCs and monsters) from blinking out of sight when they stand near a wall,
a door frame, a counter or other scenery. Load it and it works. There is nothing to set.

## Why use it

- Characters next to walls and scenery stay on screen instead of flickering in and out.
- It fixes a problem the game has even with no addons loaded.
- There is nothing to set up, and unloading it puts the game back as it was.

## Commands

- `/occlusionfix`: turns the fix off or on
- `/occlusionfix on` / `/occlusionfix off`

Unload the addon and the game goes back to how it was.

## Why characters vanish

Each frame, the game checks whether a character is hidden behind scenery. If it thinks so, it does not
draw the character. You can still target it, and its name still shows.

The check is rough:

- The game tests only a small outline of the character against the scenery drawn so far.
- It reads back a tiny 8×8 sample of that test from the graphics card, at the window's size.
- If nothing in the sample shows through, the character is not drawn.

So a character beside a wall is often counted as hidden, even when most of it is in plain view. It
blinks in and out as the camera moves. This is worst when the game's 3D resolution is higher than the
window's size (supersampling). It happens even with no addons loaded.

## What the addon does

The addon turns this check off for characters, in the three places the game makes it. Every character
is then drawn. The game's normal depth test still decides what you see, as it does for everything
else, so a character behind a wall still stays hidden behind it.

The cost: the game now draws the characters that the check used to skip behind walls. You may notice
this in a busy town. In return, the check itself is skipped, and the check made the game wait for the
graphics card each time.

## If it stops working

The addon finds those three places in the game's code by their content. Before it changes anything, it
checks that all three call the same game function. If a game update changes them, the addon says so and
leaves the game alone.
