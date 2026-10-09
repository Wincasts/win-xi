# xiframes
party, target and pet frames in the style of the Windower addon
[XivParty](https://github.com/Tylas11/XivParty)'s compact layout, in winxi's themed windows. It is
xilite with everything else taken out: there is no `me`, and no other way of drawing the frames.

- `us` displays the party and the other two alliance parties: a line a member with the name, an HP
  bar and a smaller MP bar with their values, and TP as a value. The member targeted has `>>` before
  their name, in blue. Your own party's list grows upwards, and has its buffs running leftwards from
  the window.
- `tgt` displays your target, sub-target and target of target, each as a line of the same kind: the
  name, the HP bar with its percentage, and the distance.
- `pet` lists your pet, and your party members' pets, under your party below a line. It has no
  window of its own.

The size, the text sizes, where the values sit and the outline are set on the `us` tab,
for all three.

## usage
`/xiframes` (or `/xif`) will bring up the config menu

The first time a character loads it, their settings for these frames are brought over from xilite:
where each window is, what it shows, how the lists are drawn, what is linked to what, and the
theme, fading and hiding rules. After that the two keep their settings apart.

The bar images are XivParty's, in `assets/xivparty` with its licence. Needs `libs/winxi`.
