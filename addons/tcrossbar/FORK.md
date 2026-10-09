# This fork

tCrossBar by Thorny (https://github.com/ThornyFFXI/tCrossBar), version 2.21, with gdifonts by the same
author as plain files rather than a submodule. `readme.md` is the original's. What this fork changes:

- **Stands down for winxi windows.** While a winxi addon's window has the controller (the
  `winxi_controller_focus` plugin event), button presses are ignored, so the triggers do not bring up the
  crossbar and no macro fires behind the window. In `controller.lua`, marked `winxi:`.

Changes are marked in the code with `fork:` (or `winxi:` for the one above), so that they can be found
again if the original is ever merged in.
