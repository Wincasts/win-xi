# Boundary style inferred from the player's saved edits

## Evidence

Compared all 14 records in the live `data/boundary_overrides.txt` with their
original drafts and decoded map artwork. Examples cover East Ronfaure,
La Theine Plateau, Valkurm Dunes, Jugner Forest and Batallia Downs. The exact
snapshot polygons, names and enabled flags are preserved in
`boundary_refinements.json` as `player_authored_example`. The SHA256 there
identifies the saved-file snapshot, not an official boundary revision.

No live override file was modified or imported into a live deployment.

## Decision-making patterns

1. **Trace the geographic feature, not its annotation.** Bridge names and text
   leaders may sit far from the actual crossing. Aged Arbor was relocated into
   the wooded area rather than kept over the label.
2. **Long features are route-shaped.** Cheval River, Tisaret River and Vadout
   Brook became bent corridors with meaningful ends. They are neither nearest-
   label circles nor arbitrary horizontal ovals. Surrounding banks belong in
   the envelope; unrelated side terrain does not.
3. **Scale follows semantics and local terrain.** Crag of Holla includes its
   surrounding field, while The Ephemere remains a relatively compact water
   feature. Beaches follow coast/access geography and have different extents.
4. **Shrinking and relocation matter as much as expansion.** Spore Hollow got
   smaller. Maiden's Spring was shifted to the western water feature. Bridge
   corridors were moved and reoriented rather than uniformly inflated.
5. **Exclude annotation-driven geography.** Quest symbols and monster spawn
   ellipses are not physical boundaries. Do not snap a marsh to an NM ellipse
   when the actual wetland shape is visible nearby.
6. **Keep explicit decisions explicit.** Coveffe Barrows remains disabled. The
   reason for disabling it is unknown; this is not generalized to every barrow.
7. **Keep approach distance separate.** These are feature/landscape envelopes;
   the runtime's 30-yalm approach buffer is not baked into the vertices again.

### Examples (bounding-box width × height, 512-reference pixels)

These show shape changes, not a universal scale multiplier:

| Feature | Original draft | Player edit |
| --- | --- | --- |
| Cheval River | 120 × 28 | 73.5 × 231.1 |
| Tisaret River | 120 × 28 | 46 × 171.6 |
| Vadout Brook | 120 × 28 | 30 × 108.1 |
| Crag of Holla | 52 × 44 | 99 × 93 |
| The Ephemere | 36 × 28 | 46 × 29 |
| Spore Hollow | 52 × 44 | 36 × 32.7 |
| Whitebone Sands | 41 × 44 | 69 × 57 |
| Lord Bolicevre Bridge | 84 × 68 | 38.3 × 94.1 |

The old bridge footprint exposed a classifier bug: substring matching treated
**bridge** as **ridge**. Category selection now uses whole words, with bridges
handled separately from hills/ridges. Crag defaults include a broader field;
dune/beach defaults have a more substantial shore/access envelope. These
category templates remain unverified when no physical trace is available.

## Application

The initial refinement pass contains **42 raster-specific polygons**:

- 14 exact player examples, including the disabled flag.
- 28 new assistant drafts, traced using terrain/feature cues on eight maps:
  North Gustaberg (4), Konschtat Highlands (2), Pashhow Marshlands (5),
  Rolanberry Fields (7), Tahrongi Canyon (2), Buburimu Peninsula (3),
  Meriphataud Mountains (2), Sauromugue Champaign (3).

Examples include Zeikt Creek's bent channel, Obere Creek's north/south course,
Rolanberry/Sauromugue bridges at the crossings rather than their labels,
Pashhow wetland outlines, compact fountain pools, and Drogaroga's Spine's long
ridge rather than its text box. Broader pass/valley/mountain outlines are still
interpretations, not verified elevation-aware regions.

New assistant drafts are marked `visually_traced_player_style_draft`; they are
**not** represented as player-approved. Shapes are keyed to exact zone/texture/
raster hash. They are not inherited by past zones, alternate variants or floors.

The generator consumes the canonical JSON and emits both all-map defaults and
`data/boundary_refinements.lua`. The latter reapplies the selected shapes after
the original POC merge. Regeneration therefore preserves these decisions.
Existing player override files continue to take priority on load. Unedited
maps still contain heuristic templates; this pass is not an exhaustive visual
review or automatic terrain segmentation of all 494 rasters.

```sh
python3 tools/build_zoneinfo_maps.py references/XICombinedMaps-2048 --defaults-only
```

This refreshes polygon defaults and the manifest without re-encoding previews.
Omit `--defaults-only` if preparing missing previews.

## Second pass: every named feature placed (2026-10-13)

The player's next 17 saved records (Southern San d'Oria, Lower Jeuno, East
Sarutabaruta, West Ronfaure, South Gustaberg, Batallia Downs) were read the
same way. What they showed:

1. **The label is not the place.** Every OCR-placed shape sat on the feature's
   printed name, often off the walkable map altogether. The player moved each
   to what the name or its leader line points at.
2. **Small marks are enough.** A gate, a stable or an alley is a triangle or
   box a few pixels across at the spot; the approach distance does the rest.
3. **Rivers lie along their water**, bent where it bends.
4. **Outposts count**, named for their region ("Ronfaure Outpost").
5. **Some names were turned off** (Cavalry Way, Westgate), and one that was off
   was turned on (Coveffe Barrows). The player later asked for the two to be
   on again, so they are on in the defaults, with the player's shapes.

Applied to all 78 maps with reviewed names:

- 14 of those records replace the defaults as `player_authored_example` (the
  three areas the player added by hand stay in their own file, so they are not
  doubled).
- 156 features were redrawn on what the map names, and 10 added (8 outposts,
  Giddeus's second spring, the Metalworks' second cannonry), as
  `visually_traced_player_style_draft`.
- 55 features on 14 past-era and Abyssea maps take the present-day shape, as
  `inherited_from_present_day_raster`. Each pair of maps was overlaid first;
  all 14 have the same layout. Outposts were not carried into the past.
- City moats and rivers (Northern San d'Oria and Al Zahbi moats, Blackash,
  Dalha and Blacktea rivers) are drawn but off: they cannot be entered, and
  with the approach distance would be announced from every bank.
- Names were checked against each map's lettering. One differs: the artwork
  prints "Dalba River" in Port Bastok; the game's name, Dalha River, is kept.

Refinements may now add an area (`"add": true` with a name) as well as reshape
one. None of this has been walked in game.
