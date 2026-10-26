# namehooktest

A tool for checking namehook 1.46's newer parts in game, not an addon to play with: it draws at your
target, and where its parts agree, they are right. Needs namehook 1.46 and winxi 62.

```
/addon load namehooktest
/nht                                  what is on, how each part is doing, and what to look for
/nht layer|camera|over|slot [on|off]  each part (on or off alone toggles)
```

- **layer** (on to start): a **green cross** at the target, anchored to it (a layer's drawing at an
  entity), and a **red square** round the same point, anchored to the world (from last frame's names).
  They should sit one on the other, the square a frame behind when the target moves.
- **camera** (on to start): a **blue dot** where `winxi.camera` puts that point on the screen: on the
  cross, under lens's warp as well as without it.
- **over** (off to start): the cross and square drawn over everything. Off, a wall or another character
  between you and the target hides them, as it hides a name.
- **slot** (off to start): monsters claimed through a claim slot above Name's claim. The target's name
  is an **orange bar**; every other monster's name is left to Name as it draws them (or hidden, without
  Name), as a lower claim has it.

What to look for, and what each part tells about namehook: the cross and square together say that drawings
at an entity and at a point of the world land where names do; the dot on them says the shared camera, and
`winxi.camera`'s lens warp, agree with namehook's own; the bar alone among Name's names says claim slots
hand each name to the highest claim that drew it.

Unloading gives the layer and the slot back.
