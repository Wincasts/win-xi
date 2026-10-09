# xilite
the four windows of xitools that replace the game's own, and nothing else.
- `me` displays information about the player
- `us` displays information about the party
- `tgt` displays information about your target or subtarget
- `pet` displays information about your pet

xitools' other tools (`tracker`, `cast`, `crafty`, `fishe`, `week`) are not here, nor is anything they
need: load xitools for those, with its own `me`, `us`, `tgt` and `pet` switched off.

## XivParty Style
An experimental setting of `us`: the party lists drawn the way the Windower addon
[XivParty](https://github.com/Tylas11/XivParty) draws them in its default layout. Your own party is
a list of rows (job icon, job and sub job, name, HP, MP and TP bars with their figures, buffs), and
each of the other two alliance parties a grid of small cells. The images are XivParty's, in
`assets/xivparty` with its licence.

## usage
`/xilite` (or `/xil`) will bring up the config menu

The first time a character loads it, their settings for the four windows are brought over from
xitools: where each is, what it shows, what is linked to what, and the colours, fading and hiding
rules. After that the two keep their settings apart.

Needs `libs/winxi`.
