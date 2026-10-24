# Changelog

## 0.92 — first release

- The world through a Panini or cylindrical projection (`/lens mode`, `/lens strength`), for wide screens without stretched edges. The menus and HUD are drawn over it unbent.
- Anti-aliasing for the world (`/lens aa`): each pixel the average of four reads over the patch of the world it covers, with the warp or without it (`/lens strength 0`).
- The field of view (`/lens fov`, or `/lens middle` to keep the middle of the screen as the game has it through the warp) and the world at the window's true proportions (`/lens square`).
- The camera's distance when you engage (`/lens battle same|<n>|0`).
- `/lens ultrawide on|off`: a preset for 3440x1440 (panini 25, aa, fov 68, square, battle 15) in place of your own settings, and back.
- `/lens off` is the game's own view; `/lens on` puts every setting back. Experimental.
