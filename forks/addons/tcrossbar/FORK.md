# This fork

tCrossBar by Thorny (https://github.com/ThornyFFXI/tCrossBar), version 2.21, with gdifonts by the same
author as plain files rather than a submodule. `readme.md` is the original's. What this fork changes:

- **Stands down for winxi windows.** While a winxi addon's window has the controller (the
  `winxi_controller_focus` plugin event), button presses are ignored, so the triggers do not bring up the
  crossbar and no macro fires behind the window. A window that leaves the triggers free (its event's data
  ends `:pass`, as atlas's map does while browsing) leaves the triggers this addon's, and every button
  pressed while one is held. In `controller.lua`, marked `winxi:`.

- **Winxi's drop shadow under each frame.** Frame Shadow (Layouts tab, on to start) draws the Winxi
  Theme's shadow, as winxi.shadow draws one behind a window, under every macro element's frame, following
  the theme's Shadow settings. Made once into a texture for each size of frame (`frameshadow.lua`), and
  drawn for every element before any frame. Needs `addons/libs/winxi`; without it nothing is drawn.

- **Winxi's border art round each element.** Frame Border (Components tab, None to start) draws one of
  the Winxi Theme's border styles round every macro element's frame, or round its icon while Frame is
  off: Window Border follows the theme's own (none while that is the plain border), or any of the art by
  name. winxi.borders' nine slices drawn with sprite draws, corners 3 pixels and edges stretched, after
  every icon so nothing falls over it, faded by the theme's Border Opacity (`frameborder.lua`). Needs
  `addons/libs/winxi`; without it nothing is drawn.

- **Less work each frame.** The set blue magic is read only for a blue mage and a few times a second,
  not every frame for every job (`state/player.lua`). A slot's state is worked out ten times a second
  instead of every frame (`element.lua`). The double display no longer lists its slots afresh each frame
  (`doubledisplay.lua`). Smaller ones in `updaters/ability.lua` and `state/skillchain.lua`.

Changes are marked in the code with `fork:` (or `winxi:` for the one above), so that they can be found
again if the original is ever merged in.
