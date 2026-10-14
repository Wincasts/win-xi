# hideparty (winxi's change)

atom0s's hideparty, which hides the game's own party and target frames (`/hideparty`, `/hideparty hide`,
`/hideparty show`), with one change.

While the game's party cursor is out (a member is being picked from the party list, in the party menu or
as a sub-target) the party frames are shown again, and hidden once it has gone. The game's cursor cannot
move freely between party frames that are hidden: it is thrown out of the one it enters and on to the
next, so that it was trapped in the alliance and could not return to the party. The target frame stays
hidden throughout.
