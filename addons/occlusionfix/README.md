# occlusionfix

Stops characters (players, NPCs, monsters) blinking out of view when they stand near a wall, a door
frame, a counter or any other piece of scenery. Load it and it works; nothing to set.

- `/occlusionfix`: turns it off and on
- `/occlusionfix on` / `off`

Unloading the addon puts the game back as it was.

## Why characters vanish

The game decides each frame whether a character is hidden behind the scenery, and skips drawing it if
so. It does this by drawing the character's rectangle on the screen against what the world has drawn so
far, copying a tiny 8×8 sample of the result back from the graphics card and counting what passed. If
nothing passed, the character is not drawn, though it can still be targeted and its name still shows.

The sample is coarse and is taken at the window's size, so a character standing beside something is
often counted as covered while most of it is in plain view, and it blinks in and out as the camera
moves. It is worst when the game's 3D resolution is higher than the window's (supersampling), and it
happens with no addons loaded.

## What the addon does

It turns that test off for characters, at the three places the game makes it, so every character is
drawn and the depth buffer, which hides the scenery's far side as it does for everything else, decides
what is seen. Characters behind a wall still stay behind it.

The cost is drawing the characters that the test used to skip behind walls, which a busy town can
notice; the test itself, which waits for the graphics card each time, is skipped in exchange.

The addon finds the three places by their bytes, and checks that all three call the same function
before changing anything. If the game's code changes so that they are not found, the addon says so and
leaves the game alone.
