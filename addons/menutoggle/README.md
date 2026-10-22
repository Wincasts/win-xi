# menutoggle

Makes the controller's menu button (Start, Options on a PlayStation pad) open and close the main menu.
The game opens the main menu on the first press and moves on to the social menu on the second; with
this addon the second press closes the main menu instead.

- `/menutoggle`: turns it off and on
- `/menutoggle on` / `off`

## How it works

When Start is pressed and the main menu (`menuwind`) is on top, the press is kept from the game and
the cancel button is pressed for it, held for a moment and let go. At any other time, in a submenu or
with no menu open, Start reaches the game as usual.

Cancel is taken to be Circle on a DirectInput (PlayStation) controller and B on an XInput one. It needs
the `winxi` library, for the name of the menu on top.
