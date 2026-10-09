# winxidev

Development only. Copies of the UI windows (me, us, tgt, pet, inv, treas, recast), drawn with the same
widgets, colours and theme as the real ones, to lay out and restyle by hand and to leave notes on. Nothing
in it is live: what is settled on here is written into the real windows' code afterwards.

- `/winxidev` opens or closes the editor; the copies show while it is open

With the mouse:

- click a piece and drag it to move it (its offset); drag a window by its outermost piece
- the green handles on the selected piece change its size (or, for a row or column, the gap between its pieces)
- the orange handles just outside it change its padding, a side each
- what is changing is shown by the mouse as it is dragged

Pieces are text, bars, icons (the game's status or item icons), buttons, tabs, spacers (a "fill" spacer
takes the room left over in a row), and rows, columns and repeats to hold them. A repeat draws its pieces
several times: change one copy and they all change. The editor adds, moves, copies and deletes pieces and
has every number to type in.

Every piece and every window can carry a note. A piece with one has a yellow corner, and the note shows
when the mouse rests on it.

Save (and unloading the addon) writes `config\addons\winxidev\layouts.lua`, and all the notes, with
where each one is, to `notes.txt` beside it.
