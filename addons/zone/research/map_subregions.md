# Raster-derived sub-region research

## Full-pack expansion

The extraction now covers **all 583 supplied DATs**: **582 zone-map DATs**
produce **494 unique rasters across 204 zones**, with **88 byte-identical
copies**, **zero decode errors**, and one excluded `conquest` texture.
The available Boussole resource registry contains 294 zone records; the
90 records with no map in this pack are explicitly listed, not silently
omitted or treated as zones with no geographical names.

Some textures are 512×512 originals rather than 2048×2048 HD replacements.
The original DXT-only decoder could not read 80 indexed BITMAP textures;
`tools/scan_combined_maps.py` now also decodes their 256-entry BGRA palette
and bottom-up indices. They have all been included in OCR.

**Full extraction does not mean exhaustive visual review.** There are now
102 selected-label raster reviews, with **273 reviewed zone/name pairs in
78 zones**. This expands the initial outdoor sample to city streets,
squares, rooms, expansion landmarks and past-area maps. The remaining OCR
is explicitly pending review; no inferred inheritance from present-day
zones to past/Abyssea/Dynamis variants is applied.

Current files:

- [`map_subregions_reviewed.md`](map_subregions_reviewed.md): concise list
  of all reviewed names by zone.
- [`map_label_catalog.md`](map_label_catalog.md): all-zone coverage table
  and per-raster candidate text for continued review.
- `map_label_catalog.json`: machine-readable all-zone inventory, including
  review states, provenance, reviewed labels and unreviewed OCR candidates.
- `combined_maps_ocr.json`: full raw output, including both OCR passes and
  native text boxes/word confidence. Stored compactly, one map per line.
- `map_label_reviews.json`: editable, canonical visual-review source.
  Reviews are tied to individual DAT rasters, not automatically every map
  in a zone. “No selected names seen” applies only to that reviewed raster
  and the stated label scope, not to the entire zone or every possible POI.
- `../data/map_subregions.lua`: generated reviewed-only data for **all 494
  rasters**, with empty landmark lists and explicit pending states where
  appropriate. The original 33 feature anchors are preserved; most new
  names are transcriptions without feature anchors yet.

OCR confidence filtering and geographical-word hints aid discovery only.
They do not approve names, join fragmented labels, locate leader endpoints,
or supply area extents. Missing/blurred names remain unresolved instead of
being guessed. Vunkerl Inlet's selected raster is marked uncertain.

Reproduce the full pass (the output directory also retains PNGs and
per-map resumable checkpoints):

```sh
python3 tools/ocr_combined_maps.py references/XICombinedMaps-2048 /tmp/zone-all-ocr \
  --jobs 8 --resume --tessdata-dir /tmp/zone-tessdata
python3 tools/build_map_label_catalog.py /tmp/zone-all-ocr/ocr_manifest.json \
  addons/zone/research --lua-output addons/zone/data/map_subregions.lua
python3 -m unittest discover -s tools -p 'test_*.py'
```

`--tessdata-dir` is optional if English language data is installed normally.
PNG/model/checkpoint files remain outside the repository. `--resume` reuses
completed OCR only when the DAT hash and texture match; after changing OCR
settings or language data, omit it to force recognition again.

The addon does not directly load these research tables. The separate runtime
`data/all_maps.lua` dataset now covers all 494 rasters with editable heuristic
polygons, using these reviewed names and explicit localization provenance.
Unlocalized/unnamed drafts are disabled until authored. The original three-zone
POC shapes are preserved; the user has reported that POC working in game.
The expanded dataset and native multi-floor path still need map-by-map client
validation. See [`../README.md`](../README.md) for the zone/map browser,
persistence migration, generation process and alignment checks.

## Initial sample (historical)

## Existing addon work at the initial research pass (historical)

`../zone.lua` shows a six-second zone/region/weather banner and chat message
when the party-memory zone ID changes; `/zone` forces the same display.
It registers packet `0x00A`, but the recorded `zone_in_seen_at` timestamp is
currently unused: the frame-based zone-ID poll actually triggers the banner.
There is no player-coordinate reader, map/floor selection, sub-region lookup,
or same-zone movement trigger yet.

Two previous King Ranperre's Tomb experiments are not loaded by the addon:

- `../data/king_ranperres_tomb_poi.lua`: generated Phoenix spawn sectors,
  bounding boxes/centroids and mob/exit POIs, not raster geographical names.
- `../data/king_ranperres_tomb_map_labels.lua`: visually reviewed map text and
  ten **proposed** descriptive areas, e.g. “Vrtra Chamber.” Those descriptors
  are deliberately not claimed to be official sub-zone names. The endpoints
  are in 512-space, not world coordinates, and the radii are unverified.

## Initial extraction pass

Scanned the 583 DATs in `references/XICombinedMaps-2048`, selecting zones
100, 101, 102, 103, 104, 106, 107, 108, 109, 110 and 190. Decoded 14 matching
DATs into 13 unique 2048×2048 rasters; KRT `ROM/18/13.DAT` is byte-identical
to `ROM/18/11.DAT`. No selected maps failed decoding. **This is a sample,
not a completed inventory of the entire pack.**

`tools/ocr_combined_maps.py` runs Tesseract English sparse-text recognition
(PSM 11) on both the original raster and an autocontrasted grayscale copy.
The OCR manifest retains DAT paths, texture IDs, SHA256 hashes,
duplicate paths, and both OCR passes with line/word boxes and confidence.
The hashes match the existing KRT manifest. No decoded PNGs or downloaded
OCR model files are added to the repository.

Then the decoded maps were visually reviewed to distinguish geography from
zone exits, map titles, mobs, quest annotations, and legends. The reviewed
result originally contained **33 named geographical landmarks
across ten outdoor zones** (now included in the expanded generated table). These names occur on the map; no “Grotto,”
“Chamber,” or other suffix was invented. Community-map text alone does not
prove official naming.

| Zone | Reviewed geographical names |
| --- | --- |
| West Ronfaure (100) | Knightwell |
| East Ronfaure (101) | Cheval River |
| La Theine Plateau (102) | The Ephemere; Crag of Holla |
| Valkurm Dunes (103) | Secret Sands; Whitebone Sands; Siren Sands |
| Jugner Forest (104) | Lake Mechieume; Maiden's Spring; Spore Hollow; Tisaret River; Vadout Brook |
| North Gustaberg (106) | Drachenfall; Zeikt Creek; Zegham Hill; Obere Creek |
| South Gustaberg (107) | The Fumaroles; Vomp Hill; Morhen Lighthouse |
| Konschtat Highlands (108) | Crag of Dem; Aulgung Pass |
| Pashhow Marshlands (109) | Hoaxmarsh; Aughtmarsh; Luremarsh; Rotmarsh; Hexmarsh |
| Rolanberry Fields (110) | Lord Bolicevre Bridge; Market Bridge; Great Jeuno Bridge; Fountain of Promises; Fountain of Partings; Brutus's Field; Dietmund's Field |

### Important classification decisions

- Valkurm's “Lufaise Meadows” is a destination label pointing to the zone
  connection, not a fourth beach or an area inside Valkurm.
- “Ghelsba Outpost,” “Carpenter's Landing,” “Dangruf Wadi,” etc. are also
  destinations. They should not silently become same-zone sub-regions.
- Generic “Outpost,” “Stone Monument,” “Goblin Camp,” and quest markers may
  be useful POIs, but are not included in this geographical-name pass.
- Names such as “King Arthro,” “Stray Mary,” “Maighdean Uaine,” and “Haty”
  are mobs, not geographical features.
- KRT has no additional clearly geographical area names in these rasters.
  Its existing Tomb Stone / Strange Apparatus and mob-landmark candidates
  remain useful, but need a different display category from named geography.
- Offshore water-body labels (e.g. Bhefhel Gulf) are not included as
  traversable same-zone areas.

### OCR limitations

Sparse OCR works well enough for discovery, but is not safe for automatic
runtime data generation. The faint italic geographical text competes with
grid lines, terrain, and leader lines. Examples in the retained output:

- Knightwell is found in the grayscale pass but not the original pass.
- “Lake Mechieume” and “Tisaret River” are legible, while “Spore Hollow”
  is fragmented and “Vadout Brook” gets an extra initial character.
- “Zegham Hill” is badly fragmented/missed despite being visually readable.
- “The Fumaroles” and “Vomp Hill” are split by map lines.
- “Aulgung Pass” loses letters and its second line.
- “Brutus's Field” and “Dietmund's Field” are not reliably recovered.

Both passes include noise. Confidence is diagnostic, not proof of a correct
name. Exact name deduplication alone cannot fix split lines or OCR mistakes.

## Coordinates and runtime follow-up

The reviewed table stores approximate **feature anchors**, manually read
from the rasters, normalized to 0..512 image space (native pixels divided
by four). These are not OCR text centers. Text can be far outside the zone
geometry, with a leader line pointing to the actual feature. The Cheval
River is labelled twice; one anchor is only a reference point on its course.

No area extents or radii have been guessed. A marsh, river, or beach should
not be implemented as an arbitrary nearest-label Voronoi cell: that would
assign a named area to unrelated corridors and terrain between landmarks.

Before enabling same-zone banners:

1. Confirm the world-to-map transform for each map. The repository's
   `references/boussole/src/map.lua` / map metadata already provide a useful
   transform/floor-selection implementation to investigate, but alignment
   to this HD pack still needs in-game validation.
2. Trace appropriate feature polygons/corridors (or validate small POI
   proximity areas). Preserve unlabelled terrain rather than inventing a
   named region everywhere.
3. For multi-floor maps, select the correct floor using world position and
   height; XY overlap alone is insufficient.
4. Poll player position at a modest rate, classify membership, and add
   hysteresis/debounce so boundary movement does not repeatedly announce.
5. On zone entry show the zone banner first; on a stable same-zone area
   change show the geographical name or explicitly descriptive POI label.

The new dataset intentionally remains research-only; no runtime behavior
has been changed or claimed to be calibrated.

## Reproduce

Requires Python 3, Pillow, Tesseract and English `eng.traineddata`:

```sh
python3 tools/ocr_combined_maps.py references/XICombinedMaps-2048 /tmp/zone-ocr \
  --zones 100 101 102 103 104 106 107 108 109 110 190
```

Use `--tessdata-dir PATH` if English data is outside Tesseract's default
location. During this pass the installed Tesseract 5.5.3 had only `afr` and
`osd`; `tessdata_fast/eng.traineddata` was downloaded to
`/tmp/zone-tessdata`, leaving the system install unchanged. Pillow was
12.3.0. Omit `--zones` to attempt the entire pack (potentially slow).

Each raster is saved under a DAT-derived filename; `ocr_manifest.json`
records the association. To recreate the checked-in compact manifest,
retain the top-level fields and serialize each map record on one line.

Tests (no language model download required):

```sh
python3 -m unittest discover -s tools -p 'test_ocr_combined_maps.py'
lua -e 'local d=dofile("addons/zone/data/map_subregions.lua"); local n=0; for _,m in ipairs(d.maps) do n=n+#m.landmarks end; assert(#d.maps==494 and n==273)'
```
