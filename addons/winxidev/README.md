# winxidev

Development only. Dummy copies of the UI windows (me, us, tgt, pet, inv, treas, recast), built out of plain
pieces, with an editor for laying them out and restyling them by hand. Nothing in it is live: what is
settled on here is written into the real windows' code afterwards.

- `/winxidev` opens or closes the editor; the dummy windows show while it is open

Pieces are text, bars, blocks of icons, spacers (a "fill" spacer takes the room left over in a row), and
rows, columns and repeats to hold them. Every piece has padding on each side and an offset; click one in a
dummy window or in the editor's list to select it. The orange outline is the piece with its padding, the
green one the piece itself.

The layouts are kept in `config\addons\winxidev\layouts.lua`, written by Save and when the addon unloads.
