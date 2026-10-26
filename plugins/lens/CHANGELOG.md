# Changelog

## 0.94

- The grid builds about fifteen times faster (7.1 ms to 0.47 ms in a 32-bit build, the same grid to float precision): Panini's inverse without `acos` and `tan`, and the edges worked out once for a grid rather than at each of its points. A grid is built when the strength, mode, field of view or the game's copy changes, so this was a hitch on those frames, not a cost every frame.
- The grid's triangles are listed once, not at every build.
- Before the game's copy has been seen lately, the viewport tells the UI's quads from it before the device is asked anything else.
- `/lens status` says how many times the grid has been built and how long the last build took.
- The DLL's version resource says 0.94 (it said 0.92 in 0.93).

## 0.93

- The field of view's loads and the battle camera's two go through `CodeSite` (`plugins/common/CodePatch.h`): all of a group or none, the written given back where one will not go in, and given back only while still lens's, as the game's own constant; a load something else has pointed elsewhere since is left to it. A write is checked: before, a failed one was taken as done and lens said the field of view was set. The page lens points the loads at is never freed, so lens need not stay loaded for a load left pointing there.

## 0.92 — first release

- The world through a Panini or cylindrical projection (`/lens mode`, `/lens strength`), for wide screens without stretched edges. The menus and HUD are drawn over it unbent.
- Anti-aliasing for the world (`/lens aa`): each pixel the average of four reads over the patch of the world it covers, with the warp or without it (`/lens strength 0`).
- The field of view (`/lens fov`, or `/lens middle` to keep the middle of the screen as the game has it through the warp) and the world at the window's true proportions (`/lens square`).
- The camera's distance when you engage (`/lens battle same|<n>|0`).
- `/lens ultrawide on|off`: a preset for 3440x1440 (panini 25, aa, fov 68, square, battle 15) in place of your own settings, and back.
- `/lens off` is the game's own view; `/lens on` puts every setting back. Experimental.
