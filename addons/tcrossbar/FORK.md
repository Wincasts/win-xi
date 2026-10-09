# This fork

tCrossBar by Thorny (https://github.com/ThornyFFXI/tCrossBar), version 2.21, with gdifonts by the same
author as plain files rather than a submodule. `readme.md` is the original's. What this fork changes:

- **Stands down for winxi windows.** While a winxi addon's window has the controller (the
  `winxi_controller_focus` plugin event), button presses are ignored, so the triggers do not bring up the
  crossbar and no macro fires behind the window. In `controller.lua`, marked `winxi:`.

- **Less work each frame.** The set blue magic is read only for a blue mage and a few times a second,
  not every frame for every job (`state/player.lua`). A slot's state is worked out ten times a second
  instead of every frame (`element.lua`). The double display no longer lists its slots afresh each frame
  (`doubledisplay.lua`). Smaller ones in `updaters/ability.lua` and `state/skillchain.lua`.

Changes are marked in the code with `fork:` (or `winxi:` for the one above), so that they can be found
again if the original is ever merged in.
