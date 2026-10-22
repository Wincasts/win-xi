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
  drawn for every element before any frame. With Match Theme Shadow off (Components tab, on to start)
  it takes the crossbar's own Shadow Opacity, Shadow Offset and Shadow Softness instead, and those need
  no winxi; following the theme without `addons/libs/winxi`, nothing is drawn.

- **Winxi's border art round each element.** Frame Border (Components tab, None to start) draws one of
  the Winxi Theme's border styles round every macro element's frame, or round its icon while Frame is
  off: Window Border follows the theme's own (none while that is the plain border), or any of the art by
  name. winxi.borders' nine slices drawn with sprite draws, corners 3 pixels and edges stretched, after
  every icon so nothing falls over it, faded by the theme's Border Opacity (`frameborder.lua`). Needs
  `addons/libs/winxi`; without it nothing is drawn.

- **A soft black backdrop.** Backdrop (Components tab, on to start) draws black behind the crossbar,
  darkest in the middle at Backdrop Opacity (50% to start) and fading smoothly to nothing towards its
  edge, an ellipse the panel's shape reaching Backdrop Size (130% of the panel to start, 50 to 300).
  One round gradient made once into a 128 by 128 texture and stretched over the panel with one sprite
  draw, before anything else in either display (`backdrop.lua`).

- **A gloss over each icon.** Gloss (Components tab, off to start) draws the light of a glass button over
  every icon: white over its upper part, brightest at the top and fading to a curved edge lowest in the
  middle, and a faint shade at the foot. Made once into a texture for each size of icon (`gloss.lua`),
  drawn over the icon and under the cross, trigger and skillchain overlays, faded by Gloss Opacity (0 to
  100%, 100 to start).

- **A cooldown swipe and cost tints.** Cooldown Swipe (Components tab, on to start) darkens the part
  of each icon still to come back while it recasts: a wedge from 12 o'clock shrinking clockwise, at
  Swipe Opacity (60% to start), run down smoothly between the slot's ticks. Charges (Ready, Quick Draw,
  stratagems) swipe for the next charge, their length known; for the rest the length is the most left
  seen since the recast began. Low MP and Low TP (on to start, each with its colour and alpha) lay a
  colour over a spell or ability whose MP cost is not met, or a weapon skill under 1000 TP or ability
  whose TP cost is not met. The updaters give the recast in seconds and which cost is short
  (`State.RecastLeft`, `RecastLength`, `LowMP`, `LowTP`, marked `winxi:`); `cooldown.lua` makes a
  texture for each of 60 steps of the turn and each size of icon as it is first wanted, and one white
  texture for the tints. Over the icon: tint, swipe, then gloss; the cross, trigger and skillchain over
  those.

- **Less work each frame.** The set blue magic is read only for a blue mage and a few times a second,
  not every frame for every job (`state/player.lua`). A slot's state is worked out ten times a second
  instead of every frame (`element.lua`). The double display no longer lists its slots afresh each frame
  (`doubledisplay.lua`). Smaller ones in `updaters/ability.lua` and `state/skillchain.lua`.

Changes are marked in the code with `fork:` (or `winxi:` for the one above), so that they can be found
again if the original is ever merged in.
