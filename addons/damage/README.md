# damage

Draws the damage numbers the game pops up over whoever was hit in winxi's style: in the theme's font,
with the theme's text outline, in the game's own colour, rising and fading where and as the game's do.
The game draws none of its own while it is on.

It needs the namehook plugin, 1.38 or newer (`/load namehook`), which hands the game's popups to
addons and draws an addon's in their place, and winxi 54.

- Each hit is one number. The game makes two popups for a hit, the number and a darker copy under it;
  the copy is left out.
- A miss says "Miss!".
- The size follows the game's for each popup, 26 pixels on the screen at its full size.
- What is in front of a number hides it, as it hides the game's.

## Commands

- `/damage on` draws the numbers in winxi's style (on when loaded)
- `/damage off` leaves them to the game

There are no settings yet.
