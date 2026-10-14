# targetcursor in hideparty — details

The long-form record behind the target cursor hideparty draws while the game's target frame is hidden:
why the anchoring works the way it does, how the size, opacity and range colours were established, and
the full attribution. Carried over from Hiken's targetcursor, whose drawing is the only part changed: it
draws the game's own `anc_l` sprites from `ROM/119/51.DAT` through `winxi.cursor`, in place of the PNG
sheets it shipped with. The settings named here are at the top of `targetcursor.lua`.

---

## Why the height was wrong

Short version: **cursor height is a per-instance property, not a per-model one.**

FFXI stores a render scale on every creature at `actorPointer + 0x698`, and the
cursor hangs at the anchor bone's height **multiplied by that scale**:

```
anchor height = (bone 2 height − model render base height) × modelScale
```

This is easy to miss, because two creatures with the same name and the same
skeleton can have different scales. Any attempt to tabulate cursor height by
race, by bone count or by zone produces a table that works on your sample and
breaks in the next zone.

The evidence was four Yagudo in Tahrongi Canyon with an identical skeleton —
75 bones, bone 2 dz = −2.750 — where Scribe and Acolyte read `0.8500` and
Mendicant and Persecutor read `1.0000`. The two reading 0.85 were exactly the two
whose cursors were wrong. Reading the field per creature made every "race
constant" and every "zone-specific" quirk disappear at once.

Two other fixes came out of the same work:

- **Horizontal position** comes from the model's render base
  (`+0x678`/`+0x67C`/`+0x680`), not the bone. Taking all three axes from the bone
  drags in its model-space horizontal offset, which swings the cursor sideways as
  the model turns and as you rotate the camera.
- **Moghouse doors** report target index 0 — a null entity at the zone origin,
  which is why the cursor drew on the floor. Their real position lives in the
  target-actor struct at `+0x34`. World doors are different again and must use the
  entity position: for door-type objects `+0x678` is an *orientation* vector, not
  a position.

Verified against the game's own cursor on all five player races, on mobs and NPCs
across multiple zones, on child models, and on world and moghouse doors.

---

## The cursor

FFXI's **target box and target arrow are a single UI primitive** — confirmed both in `ROM/119/51.DAT`
and by walking the live primitive tree — which is why hiding the target frame takes the arrow with it,
and why hideparty draws one in its place.

The arrow is the `anc_l` sprite group of `51.DAT`: six frames over the same 64×64 DXT3 atlas, `anc`, as
the party cursor `anc_s`. The cells are stored as 32×20, pointing right; each group says which corners
around its pivot a cell is drawn to, and `anc_l`'s turn it to point down, 20×32, with the pivot at the
tip. The tip is put at the anchor point, and the frames run at the game's own 15fps (its UI runs at
30fps and holds each frame for two ticks).

### Size

**`cursorScaleFactor` assumes your menu and background resolutions match.** If they
do — which is the common case, and the default — `1.0` is correct at *any*
resolution and there is nothing to set.

If they differ, the rule is:

```
cursorScaleFactor = background height ÷ menu height
```

FFXI draws its menu layer at the **menu** resolution and stretches it up to the
**background** resolution. Its cursor is therefore that ratio larger than the
art's native size, while hideparty draws it at a fixed pixel size. Verified at
three points:

| Background | Menu | Factor | |
|---|---|---|---|
| 1920×1080 | 1920×1080 | **1.0** | verified |
| 2560×1440 | 1920×1080 | **1.333** | verified; the sub cursor measures 26×44 px against its native 20×32 — 1.30 and 1.375, bracketing 1.333 |
| 2560×1440 | 2560×1440 | **1.0** | verified |

The third row is what settles it. The background resolution is unchanged between
rows two and three, so resolution alone cannot explain the factor returning to
1.0 — only the ratio can.

**If your cursor looks too small, check your menu resolution before touching this
setting** — the mismatch is usually unintentional.

### Opacity

`cursorOpacity` and `subCursorOpacity` multiply the art's own per-pixel alpha, so soft edges stay soft.
They are separate so that the main cursor can be faded back while the sub cursor stays bright, since its
colour carries range information and a faded red is easy to misread. At 1.0 both are drawn as the game
draws them:

| | |
|---|---|
| stored — `anc` in the client's own `51.DAT`, max alpha | 102/255 = **0.400** |
| drawn — sub cursor core, five independent plateau solves | **0.798 ± 0.005** |
| ratio | **1.995** |

**The client draws the cursor at exactly twice its stored alpha.** The mechanism is not confirmed — a
×2 alpha op in the fixed-function texture stage (`D3DTOP_MODULATE2X`) would do it, and so would drawing
the sprite twice. The measurement itself is solid: five of six plateau solves, across three colours and
four screenshots, agree to half a percent. `winxi.cursor` doubles each DXT3 alpha nibble as it loads the
atlas, so the texture already holds what the game puts on screen. (Alpha is stored in 4-bit steps of 17,
and 102 is exactly 6/15, so the ceiling is an art choice rather than a decode artifact.)

**0.80 and the range colours are per-client figures**, measured on Phoenix beta. Another server, or a
local install, may differ. `cursorScaleFactor` is the exception: it follows a rule — the ratio of your
background and menu resolutions — rather than being a per-setup constant.

### Recolouring the main cursor

Off by default — the main cursor is drawn as the game draws it. To tint it, set an RGB triple:

```lua
local colorMainCursor = { 120, 255, 140 }   -- nil = leave the art alone
```

The tint is a colour **multiply**, so it is applied to a grey copy of the cursor rather than the coloured
art — multiplying a tint into already-coloured art gives a muddy result. `winxi.cursor` makes the grey
copy as it loads: every pixel of a DXT3 block is a blend of the block's two end colours, so greying
those (by luma, scaled so the brightest is white) greys the whole sprite and leaves alpha alone.

This recolours the main cursor unconditionally. The **sub** cursor ignores it and stays driven by range,
since its colour carries information.

### Placement

These are measured against the game's own cursor and should not need changing:

```lua
local anchorBone      = 2      -- top of the body on every skeleton measured; -1 = model base
local anchorHeight    = 0.0    -- extra nudge in world units, positive raises
local anchorSmoothing = 0.04   -- how fast the damped height follows the bone
local objectPosOffset = 0x34   -- position offset for moghouse doors
```

---

## Sub cursor range colors

When you select a spell or ability, the game tints its sub cursor by whether the
action can actually reach the target — red out of range, yellow almost, blue in
range. The cursor reproduces that:

```
blue    if  sqrt(clientDistance) <= maxYalms + hitbox
yellow  if  <= maxYalms + hitbox + 0.95
red     otherwise
```

Every term is read live from the client, so there is **no spell table** and
nothing to maintain when a server rebalances an ability:

| Source | |
|---|---|
| `ITarget:GetActionTargetMaxYalms()` | the selected action's own range |
| `IEntity:GetModelHitboxSize(index)` | the target's hitbox |
| `IEntity:GetDistance(index)` | the client's own distance |

Three details cost real effort to establish, so they are worth stating plainly:

- **`GetDistance` returns the distance SQUARED**, and it is **horizontal only**,
  while the client's own check is three-dimensional. The height difference has to
  be added back by hand from `GetLocalPositionZ`, or the cursor stays blue well
  past the real edge whenever a target is above or below you.
- **A ranged attack gets no hitbox**, and `ITarget:GetActionId()` is the only way
  to know it is one — it reads 0, where every spell and ability carries its own
  id. `SubTargetFlags` cannot tell them apart (16 from a menu, 18 from a macro,
  the same for a spell) and neither can `ActionType`, which reads 71 for both.
- **`ModelHitboxSize` is already scaled.** It is the entity's live hitbox, not a
  per-model constant — the same Yagudo model reads 1.5 at model scale 1.00 and 1.2
  at 0.85. Multiplying it by the model scale double-counts.
- **The allowance is exactly the hitbox.** No constant, no per-race adjustment.
  Players are not a special case; they just have small hitboxes (a Mithra reads
  0.4, a Galka 0.8, a Savanna Rarab 1.1, a Yagudo 1.2–1.5, an NM 3.6).

Calibrated over seven walks against the game's own cursor, across three model
scales, two spells, players, mobs and an NM.

### Configuration

```lua
local rangeColors     = true
local colorInRange    = { 121, 107, 255 }
local colorNearRange  = { 255, 255, 103 }
local colorOutOfRange = { 255, 108,  97 }
```

Set `rangeColors = false` for a sub cursor that is always `colorInRange`.

All three colors are sampled from the game's own sub cursor rather than chosen
by eye. Each was shot twice in the same position, once against a dark surface and
once against a bright sky, which gives two equations per pixel and lets the
cursor's own alpha be solved instead of assumed:

```
observed_dark  = color * a + dark  * (1 - a)
observed_light = color * a + light * (1 - a)
```

Both are worth knowing because neither matches its name. The in-range blue is a
**violet at hue 247**, not the sky blue it reads as — an earlier `{ 130, 205, 255 }`
guess was wrong by 44° of hue and still looked plausible in play. The near-range
yellow is a **pure lemon**, R and G equal at hue 60, where a guessed amber
`{ 255, 225, 110 }` sat 12° away. Only the red was close: a guessed
`{ 255, 95, 95 }` was 3° off the measured hue of 4°.

The blue was measured twice. The first attempt, `{ 101, 86, 195 }`, got the hue
right and the brightness badly wrong: it averaged the brightest quartile of the
cursor and treated that core as opaque. The core is not opaque — its alpha is
0.80 — so part of what was measured was the dark wall behind it. Re-solved
against two different skies, which agreed on the color to within 3 levels, the
blue comes out **half again brighter** than that first figure.

All three were finally solved against the 0.80 drawn ceiling, anchoring each shot
on the fact that the brightest channel clips at 255. The implied plateau alpha
came out at 0.794, 0.801, 0.798, 0.805 and 0.798 across five of the six shots —
the agreement that established the ceiling in the first place. The sixth, red
over the dark wall, reads 0.745 because that frame's core never reaches full
coverage, which is also why red's two estimates differ by 6–11 levels where
yellow's agree to 1.

These are the measured colours **as-is**, with no headroom correction. Each solves to a near-saturated
core — 255 in the brightest channel for red and yellow, 249 for blue — and since the tint is a multiply,
the grey copy it multiplies must reach full white at its core for them to come out at the game's
brightness; the grey copy is scaled so that it does. Against the game's own sub cursor, that reproduces
it to **within 1.6 levels per channel**, checked against both skies of the calibration pair.

**`colorInRange` owns the sub cursor's colour in every state**, not just the in-range one. States with
no action target — using an item, and the frame or two entering stnpc/stpc — are tinted with it too, so
changing that one value moves the whole sub cursor. The name still fits — items are self-targeted, and
the range logic already treats self-only actions as in range.

If the grey copy cannot be made, the cursor is drawn untinted; if the cursor cannot be loaded at all,
hideparty says so once in chat.

`rangeYellowBand` (0.95) is the width of the yellow band, the one value measured
rather than read from the client; the seven runs ranged 0.88–1.04.

---

## Smoothing

Bone height is low-pass filtered so breathing and run cycles do not reach the
cursor. Filter state is keyed on target index, and **target indices are recycled**
as entities spawn, despawn and you change zones — so without a guard, targeting a
crab on the index a Yagudo just vacated starts the filter at the Yagudo's height
and crawls to the crab's over about a second, which looks like the cursor floating
into place.

Two guards prevent that. It remembers which actor each damped value
belongs to, and independently restarts the filter on any single-frame height jump
larger than `anchorSnapJump` (0.5 world units) — a creature's own animation moves
bone 2 by a fraction of a unit, while a different creature differs by whole units.
A new target snaps to the correct height on the first frame.

---

## Compatibility

Ashita v4. Developed and tested during Phoenix Beta; the memory offsets are from the retail client, so
it should work on retail and other private servers, but that is untested — if `+0x698` moves, cursor
heights will be wrong on scaled creatures.

### What the cursor reads and does

| | |
|---|---|
| Reads | target index and action-target state; the target's position, model scale, hitbox and skeleton; `ROM/119/51.DAT`, once |
| Draws | one sprite over the current target and sub target, while the target frame is hidden |
| Writes | nothing — hideparty's own visibility flags aside |
| Network | none |
| Input | none — it does not send commands, keys or packets |

There is **no memory scanning** for the cursor, and it cannot act on your behalf. Every value it uses is
one the client already computed to draw its own UI.

---

## Credits

targetcursor is a **fork**, not a new addon, and it has two upstream authors.

**Jyouya** wrote `customtarget`
([Ashita-Stuff/addons/customtarget](https://github.com/Jyouya/Ashita-Stuff/tree/master/addons/customtarget)).
**yzyii (Rag)** wrote the v0.6 that this fork actually started from
([xiconfig/extra/customtarget](https://github.com/yzyii/xiconfig/tree/main/extra/customtarget)).

The difference between them is why both are credited:

| | Jyouya, v0.5 | yzyii, v0.6 |
|---|---|---|
| sub cursor | none — one cursor for the active target | `subcursor.png`, drawn separately |
| `getPos` | absent, inlined | factored into a function |
| art | `me.png` | `cursor.png` + `subcursor.png` |
| size | ~180 lines | ~240 lines |

Every sub-cursor feature here descends from yzyii's work. Note that his copy
still carries `addon.author = 'Jyouya'` — he never added himself to it, so
crediting him by name goes beyond what his own file claims.

Still from upstream: the D3D sprite setup, and the structure of the frame's drawing. `getPos` is shared
work — a good part of the original remains inside it. `matrixMultiply` writes into a scratch matrix,
`worldToScreen` does four dot products in locals, and `getBone` became `getBoneOffsetZ`.

Added in targetcursor, by **Hiken**:

| | |
|---|---|
| Anchoring | cursor height from the model's own render scale — correct on every race, mob, NPC and child model without per-model tuning |
| Horizontal tracking | render base rather than bone position, so the cursor no longer drifts as the camera turns |
| Doors | moghouse doors (no entity index) and world doors handled separately |
| Smoothing | filter restarts on a change of target instead of gliding between them |
| Range colors | sub cursor tinted red / yellow / blue by whether the action reaches, derived from the client's own range, hitbox and distance |
| Animation | all six frames of the cursor at the game's own 15fps |
| Tint and opacity | optional main cursor recolor, separate opacity for both cursors |

Changed in hideparty: the cursor is the game's own `anc_l`, read from `51.DAT` through `winxi.cursor`
and laid around its pivot, in place of the PNG sheets; it is drawn only while hideparty hides the target
frame; the `/tc` tuning commands are gone.

---

## License

The target cursor is released under the **MIT License** — see `targetcursor.LICENSE`.

Neither upstream project carries a license file, so both authors were asked
directly and both granted permission:

- **Jyouya** pointed at yzyii's v0.6 and said to use it as a starting point
- **yzyii (Rag)**: *"It has no license / feel free to take it and do whatever
  you want with it."*

Those grants cover the upstream code it is built on. The MIT license covers targetcursor as a whole.
The cursor's art is the game's own, read from the client's files; none is shipped.
