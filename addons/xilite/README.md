# xilite
the four windows of xitools that replace the game's own, and nothing else.
- `me` displays information about the player
- `us` displays information about the party
- `tgt` displays information about your target or subtarget
- `pet` displays information about your pet

xitools' other tools (`tracker`, `cast`, `crafty`, `fishe`, `week`) are not here, nor is anything they
need: load xitools for those, with its own `me`, `us`, `tgt` and `pet` switched off.

## XivParty Style
An experimental setting of `us`: the party lists arranged the way the compact layout of the Windower
addon [XivParty](https://github.com/Tylas11/XivParty) arranges them, with its bars, inside this
addon's own themed windows. A member is a line: the name, an HP bar and a smaller MP bar with their
figures, and TP as a figure. The game's cursor points at the member targeted, and the buffs of your
own party run leftwards from its window. The bar, cursor and leader images are XivParty's, in
`assets/xivparty` with its licence.

## usage
`/xilite` (or `/xil`) will bring up the config menu

The first time a character loads it, their settings for the four windows are brought over from
xitools: where each is, what it shows, what is linked to what, and the colours, fading and hiding
rules. After that the two keep their settings apart.

Needs `libs/winxi`.
