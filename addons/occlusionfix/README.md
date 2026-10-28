# occlusionfix

Stops characters (players, NPCs, monsters) blinking out of view when they stand near a wall, a door
frame, a counter or any other piece of scenery. Load it and it works. There is nothing to set.

- `/occlusionfix`: turns it off and on
- `/occlusionfix on` / `off`

Unload the addon and the game goes back to how it was.

## Why characters vanish

Each frame, the game decides whether a character is hidden behind the scenery. If it is, the game
skips drawing it. To decide, the game draws the character's rectangle on the screen against what the
world has drawn so far. It then copies a tiny 8×8 sample of the result back from the graphics card and
counts what passed. If nothing passed, the character is not drawn. You can still target it, and its
name still shows.

The sample is coarse, and it is taken at the window's size. So a character standing beside something
is often counted as covered while most of it is in plain view. It blinks in and out as the camera
moves. It is worst when the game's 3D resolution is higher than the window's (supersampling). It
happens with no addons loaded.

## What the addon does

It turns that test off for characters, at the three places the game makes it. Every character is
then drawn, and the depth buffer decides what is seen, as it does for everything else (it hides the
scenery's far side). Characters behind a wall still stay behind it.

The cost: the game now draws the characters that the test used to skip behind walls. A busy town can
notice this. In exchange, the test itself is skipped, and the test waits for the graphics card each
time.

The addon finds the three places by their bytes. It checks that all three call the same function
before it changes anything. If the game's code changes so that they are not found, the addon says so
and leaves the game alone.
