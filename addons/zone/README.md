# Zone: all-map boundary editor

## Renamed from zoneinfo

Unload `zoneinfo` before installing this addon as `addons/zone`, then load it with
`/addon load zone`. Use `/zone` to open settings and `/zone test` to preview the zone banner.
While both addons are unloaded, copy your character settings and boundary overrides from
`config/addons/zoneinfo/` to `config/addons/zone/` to preserve them. Copy any custom
background images into `addons/zone/assets/backgrounds/` as well. The saved boundary
file format is unchanged; do not run both addons together.

Ashita v4 winxi-styled zone/region/weather banners with nation flags, a popup
when the weather changes, an always-on location line, experimental same-zone
area detection, and an offline-capable map browser with draggable polygon
vertices.

## Coverage and what is guessed

All **494 unique zone-map rasters across 204 zones** in the supplied
`XICombinedMaps-2048` pack have independently editable area data.
Duplicate copies of the same raster are represented once; different raster
variants and floors have separate save identities.

The browser draws each map from the game's own files, read by `winxi.mapdat`
the way pivot turns towards its overlays: with XICombinedMaps-2048 installed as
an overlay they are its pictures, and without it the game's own. 22 of the 494
are other pictures of a map that only the pack has; without it they are blank.

The dataset contains **833 polygons**:

- **417 named features** on 81 maps. Every one has been placed by eye on its
  map's artwork, traced from it, or is a player's own edit:
  - 163 are **buildings** in 24 cities and towns: shops, guilds, auction
    houses, consulates, manors and rooms. See "City buildings" below.
  - 27 are the player's saved edits, kept exactly.
  - 152 were drawn on the feature the map names: the square, bridge, pond or
    stretch of river its label or leader line points at.
  - 55 on past-era and Abyssea maps take the present-day map's shape, where the
    two maps' artwork was compared and found to be the same layout.
  - 13 are copied between two rasters that are the same picture (Windurst
    Waters North, Aht Urhgan Whitegate), so the one the client uses has them.
  - 7 are unchanged: the four original POC shapes, Lake Mechieume, and two
    (Colkhab's Hive, Hurkan's Roost) whose first placement already sat on
    the feature.
  - 408 are announced. The 9 that are off are city moats and rivers that
    cannot be walked into.
- **416 unnamed editor-only drafts**, one for each raster without reviewed
  names. These do not announce invented sub-zone names. Rename/reposition them
  or add named areas as you review the map.

Ten of the named features were not in the label review and were added from the
maps: eight outposts (named for their region, as the player named Ronfaure
Outpost), Giddeus's second spring and the Metalworks' second cannonry.

These shapes are judged from the map artwork, **not walked or terrain-traced in
game**. See [`research/boundary_authoring_style.md`](research/boundary_authoring_style.md)
for how the player's edits were read and applied. The map art writes Port
Bastok's river as "Dalba River"; the name used is the game's, Dalha River.

The pack does not include maps for 90 other resource-registry zones. Those
cannot be displayed from this pack; this is not a claim of complete FFXI map or
named-sub-region coverage.

**Sub-zone popups are enabled by default; debugging starts OFF.** Use
`/zone` to adjust sub-zone popup settings. The POC command is retained
for compatibility.

## City buildings

A building is an **exact** area: it is announced when you step inside its
outline, not on approach, and is taken about a third of a second after you
cross (open-country features wait a full second). Inside a shop that stands in
a named square you are in the shop; step out and you are in the square again.

The outlines come from the map artwork. Most buildings are painted a darker
colour than the street, and `tools/trace_zoneinfo_buildings.py` follows that
paint out to the building's wall line. Where the artwork only outlines a
building, its polygon was drawn by hand on the outline. Names are the maps'
own labels. The source is `research/building_seeds.json`; add a building there
(a box round it, or a polygon) and run:

```sh
python3 tools/trace_zoneinfo_buildings.py references/XICombinedMaps-2048 --preview /tmp/buildings
python3 tools/build_zoneinfo_maps.py references/XICombinedMaps-2048 --defaults-only
```

`--preview` writes each map with its buildings drawn on it, to check by eye.

What this cannot know: the map shows a building's footprint, not where its
door is or how thick its walls are. The outline is the outer wall, so the name
appears as you pass through it, wherever the door is. A building whose inside
is a separate zone or an upper floor is announced when you walk over its
footprint. Buildings a map labels but does not draw were left out (Mhaura's
guild salesrooms and Governor's House) or drawn small where the label's line
ends (the shops along Lower Jeuno's bridge). Past-era cities have none. In the editor, **Exact Boundary (No
Approach)** switches any area between the two kinds.

## Deploy and open

From a terminal, if needed:

```sh
./deploy.sh push zone
```

In Ashita:

```text
/addon load zone
/zone debug on
```

Use `/addon reload zone` if already loaded. This update includes about 41 MB
of new preview assets; deploy the entire addon, not just the Lua entrypoint.

## Display settings (winxi)

```text
/zone
/zone test
/zone reload
```

The presentation is inspired by `references/Zonename`, but uses the shared
**winxi** ImGui renderer/theme instead of a separate GDI font engine or font DLL.
The `/zone test` command shows the current zone immediately;
`config` / `settings` opens or closes the settings window, and `reload` / `rl`
reloads character settings and shows the current zone again.

**Settings** controls banner/chat visibility, the zone-entry and **Sub-zone**
popup content, banner X/Y position and alignment, opacity, timing, and winxi's
game-UI hiding rules. Zone-entry popups never include a sub-zone line. Sub-zone
popups show the area's name as the title, without a separate category label.
**Show Sub-zone Popups** is enabled by default; no POC command is needed.

**Approach Distance** (under Sub-zone Popup) is how near a feature is announced,
0 to 100 yalms from its outline. It is saved per character, as is the map chosen
for live detection in each zone; `/zone approach` and `/zone livemap`
change the same settings.

### Weather popup

**Show Weather Popups** (on by default) shows a popup when the weather changes
while you are in a zone: `Weather: Rain` as the title, with the zone under it
when **Show Zone Context** is on. It uses the sub-zone popup's fonts, sizes and
per-line timing, and writes a line to the chat log if **Chat Announcements** is
on. The weather is read once a second. A change while another banner is up
updates that banner's weather line and the popup follows once it has gone. A
change in the ten seconds after zoning only corrects the banner, since the
client can still hold the last zone's weather then. **Preview Weather Once**
shows the popup with the current weather.

### Location line

**Show Location Line** (off by default) keeps a small outlined line on screen
with the zone you are in, and the sub-zone after it when you are in one:
`West Ronfaure - Knightwell`. Drag it into place, or type its **Position**;
**Lock Position** then fixes it there and lets clicks pass through it. **Text
Size** is 10 to 40 pixels. It follows the banner's hiding rules. Naming the
sub-zone uses the same detection as the popups, and works with **Show Sub-zone
Popups** off.

Enable **Use Per-Line Timing** for independent start delay, hold, fade-in and
fade-out controls for zone region/title/weather and sub-zone title/zone-context/
weather. Otherwise the shared timing controls apply. Fade-in is part of the
hold interval; start delay is measured from popup creation. Each popup lasts
until its last enabled line expires. Hidden lines do not extend its lifetime,
and expired/delayed lines keep their layout space so other text does not jump.
Timing is captured when a popup starts; changes apply to the next popup.

**Appearance** offers:

- **Floating Text** (default): large outlined title, smaller region above and
  optional context/weather below; no background and no interception of clicks.
- **Themed Panel**: the same text with winxi background, border, padding and
  optional shadow. Shared-theme or addon-specific theme controls work normally.
- Independent zone-entry and sub-zone title/detail font selectors and pixel
  sizes. Choose Default or an installed `.ttf` file from `C:\\Windows\\Fonts`.
  Font choices are cached, with Default used when a font cannot be loaded.
  Line spacing and theme or title/detail colors are shared; the outline is Winxi Theme's Text Outline.
  No separate GDI engine is required.
- Left/center/right alignment. With **Centered On Screen** enabled, X is an
  offset from screen center and Y is measured from the top; otherwise X/Y are
  absolute screen pixels. Alignment also anchors the whole banner at that point.

### Region flags

**Use Region Flags** (Appearance → Background Image, on by default) shows a
nation's flag behind every banner in that nation's own regions:

| Flag | Regions |
| --- | --- |
| San d'Oria | Kingdom of San d'Oria, Ronfaure, Ronfaure Front |
| Bastok | Republic of Bastok, Gustaberg, Gustaberg Front |
| Windurst | Federation of Windurst, Sarutabaruta, Sarutabaruta Front |
| Jeuno | Grand Duchy of Jeuno |
| Aht Urhgan | West Aht Urhgan, Western Aradjiah |

Other regions show no flag. The table is `data/region_flags.lua`: a region ID
and the name of a PNG in `assets/backgrounds/flags/`. A flag keeps its
proportions, as large as **Image Size** allows and in the middle of it, and uses
**Image Offset** and **Image Opacity**. Where there is a flag it takes the place
of the background image below; elsewhere that image is shown as before. The
flags are opaque squares, so lower the opacity or move the offset if the text
is hard to read over one. The PNGs were made from the `.webp` files in
`assets/flags/`, which the client cannot load.

### Optional background image

Place a PNG, JPG/JPEG or BMP in `addons/zone/assets/backgrounds/` (or the
same folder in the deployed addon). Open **Appearance → Background Image**,
enable **Show Background Image** and enter its filename, such as `banner.png`.
Absolute paths and subdirectories are not accepted. Only the flags above are bundled.

Set **Image Size**, **Image Offset** and **Image Opacity** and use the banner
preview. The image stretches to the specified size; transparent PNGs work well.
Its horizontal anchor follows banner alignment, and its offset is relative to
the banner position. Image dimensions do not change text layout. The image fades
with the banner and works with ImGui floating/panel text and experimental GDI.
With a themed panel it is drawn above the panel fill and behind the text.

The image is loaded lazily and cached; replacing the filename refreshes it.
**Reload Background Image** refreshes an edited file with the same name. Missing
or unreadable images fall back to text-only, retry at most every five seconds
while visible, and report an error in Appearance. Image settings save with the
other per-character display settings. Native texture loading, transparency,
layering and device-reset behavior require in-game validation.

Defaults are centered, Y=110, zone and sub-zone title/detail sizes 32/16, a
5-second hold, 0.2-second fade-in and 1-second fade-out. Fade-in occurs within the hold; the
full lifetime is hold plus fade-out. Timing changes apply to the next banner;
position, text style and opacity can be adjusted live. Zone-entry priority uses
that banner's configured lifetime instead of a fixed six-second display.

Enable **Preview While Configuring** to keep the last banner visible while
adjusting its appearance (a sample is used before any banner has been shown).
**Preview Zone Once** runs the zone display with configured timing and chat
behavior. **Preview Sub-zone Once** previews the current sub-zone or an example
name. Preview never enables area detection or changes map selection.

Display settings are saved by Ashita's per-character `settings` library under
`config/addons/zone/`, separately from polygon overrides. Display changes
save on completed interaction/config close/unload. Approach distance and each
zone's live map are saved with them. The debug toggle, manual transforms and
editor browsing remain session-only. The map editor window also
follows the selected winxi theme; map overlays keep their diagnostic colors.

Shared `addons/libs/winxi/` modules must be installed alongside the addon.
Visual placement, font scaling and fading still need confirmation in Ashita;
offline tests only exercise mocked renderer behavior.

## Experimental GDI banner renderer

Open `/zone`, select **Appearance → Text Renderer → GDI Fonts
(Experimental)**, then use **Preview Zone Once** or **Preview Sub-zone Once**.
ImGui remains the default; select **ImGui (Default)** to switch back.

This uses Thorny's `gdifonts` full-string textures and Direct3D sprite rendering,
as Zonename did. The banner's text does **not** load or bake ImGui fonts. The
settings/editor UI still uses ImGui. Zone/sub-zone detection, visibility rules,
position/alignment, sizes, colors, outlines and per-line timing are retained.
GDI currently renders **floating text only**; the Themed Panel option is ignored.

Appearance provides separate GDI family dropdowns for zone and sub-zone titles
and details, plus **Bold Titles** and **Bold Details**. Dropdowns list installed
Windows family names, sorted and deduplicated, rather than `.ttf` filenames.
Vertical `@Family` variants are excluded. Enumeration is cached and independent
of the texture DLL. If enumeration fails, saved selections are retained and an
error is shown; missing rendering families fall back to Arial. Each enabled line is rendered as a full-string
texture, cached until its text/font/size/colors/outline change. Fade opacity is
applied by the sprite without rebuilding textures.

The addon includes its own `gdifonts/` Lua files, `gdifonttexture.dll` and MIT
license. It uses a private manager and explicit rendering instead of sharing
`name`'s GDI module or an automatic render tick. The texture-pointer lifetime fix
from `name` is retained. Deploy the **whole zone addon**, not just the Lua
entrypoint, and reload it before testing.

**Experimental native code:** the DLL requires Windows/Ashita's Direct3D 8
client. Lua error handling cannot recover from a native access violation or
prove device-loss compatibility. Offline tests use a mocked renderer; native
font quality, placement and simultaneous use with `name` require in-game
validation. `gdi-diagnostic.txt` records initialization and texture-build
checkpoints to help investigate a native failure; cached frames do not log.

Thorny's MIT license is in [`gdifonts/LICENSE`](gdifonts/LICENSE). The reference
implementation is `references/Zonename`; zone's private library disables
automatic rendering, uses a unique event ID, reports manager/sprite creation
failures and ends sprite rendering before propagating a Lua drawing error.

## Browse and edit any map

You **do not need to travel to a zone to edit its maps**.

1. Choose a **Zone** from the dropdown, then choose a **Map / floor / variant**.
   Selecting either turns off **Follow player zone/map**. Re-enable Follow to
   return to the player's live map.
2. Check **Edit vertices**, then choose the **Area** to edit.
3. Drag numbered **yellow handles** with the left mouse button. The feature
   polygon and rounded approach outline update as you move. Release to apply.
4. Click a handle to select a vertex. **Insert vertex after selected** adds a
   midpoint on the following edge; **Remove selected vertex** removes it.
   Polygons support 3–64 vertices, including concave outlines.
5. Edit **Area name** and **Announce this area**, then click **Apply name /
   detection**. Disabled/unlocalized drafts remain non-announcing until you
   explicitly enable them. Only enable meaningful, localized names.
   **Minimum Height** and **Maximum Height** limit the area to a band of
   elevation, for a place above or below another. Tick a side, type its height
   or press **My Height** to take the Z you are standing at, then **Apply Height
   Limits**. An unticked side is open. Heights are the Z shown as the live
   position. The area you are in keeps one yalm of slack, so a jump does not
   leave it.
6. Use **New area name → Add Area** for additional features. A four-vertex
   polygon appears in the center of the viewed map; drag it into place and add
   vertices as needed. Disable an area if you no longer want it announced.
7. **Undo** reverses the last operation for the selected area, including vertex,
   name and enable changes (up to 50 operations). **Restore Default** restores
   that area's built-in shape/name/enable setting. Custom areas have no built-in
   geography: their reset baseline is their initial session shape or loaded
   saved shape.
8. **Save Boundaries** saves all modified areas across all maps—not just the
   currently viewed map. The window shows unsaved changes and save errors.

Browsing does not change live map selection, pause live detection, or place
the player marker on another map. Dragging a boundary on the actual live map
pauses announcements until release and then seeds membership silently.
Editing another map does not reset live membership. Changing the viewed map,
closing/collapsing the window or disabling edit mode cancels an unfinished drag.
Invalid moves that cross/collapse edges are rejected; vertices are clamped to
512-reference map bounds.

### Zoom for precise vertex placement

Use the **Map zoom** slider to enlarge the canvas from **1x to 6x**. Scrollbars
and the mouse wheel let you navigate the enlarged map. **Center selected
vertex** brings the current handle into view; **Reset view** returns to 1x and
clears scrolling. Zoom is session-only and never changes saved coordinates.

The map, polygons, approach outlines and player marker scale together. Vertex
handles keep a fixed screen size. Dragging converts screen movement back to
512-reference coordinates, including scrolling, so zoom allows finer fractional
pixel adjustments. Changing zoom cancels an unfinished drag rather than moving
its vertex accidentally. Zoom enlarges the map's picture; it does not add
new raster detail.

### Feature boundary versus approach boundary

The yellow handles edit the **feature polygon**. The approach buffer is added
outside it, by default **30 yalms**. Gray outlines mark the feature; orange/green
outlines show the approach envelope; purple marks disabled drafts. Cyan marks
the player **only on the live map**.

```text
/zone approach 45
/zone approach 0
```

The first widens the buffer; the second makes the draggable polygon the exact
detection boundary. Approach distance is saved per character (default 30) and
is also a slider in the settings. It is straight-line horizontal proximity, not walking-path length or
line of sight. Terrain barriers and elevation-specific sub-area volumes are
not modelled.

When browsing, the client transform is read for the **viewed map**, not copied
from the player's zone. If unavailable, you can still edit feature vertices,
but the UI says the approach outline cannot be calibrated.

## Persistence and existing edits

Overrides are saved inside the deployed addon at:

```text
data/boundary_overrides.txt
```

The new **v2 format** records source-raster identity, area ID, name, enable flag
and vertices. After the name come two optional fields: `h:<min>:<max>` for an
area with height limits (`~` for an open side), and `e:1` or `e:0` where an
area's kind (exact or with approach) is not its built-in one. A file with
neither is written as before. It is validated text, never executable Lua. Map identity includes
zone, texture and raster hash, so variants do not inherit each other's edits.
The previous saved file is retained as `.bak`. Saving uses a temporary file and
attempts to restore the old file if installation fails.

Your existing **v1 three-zone POC file imports automatically** into those zones'
primary POC rasters. The next explicit Save migrates to v2 and keeps the original
file as the backup. No automatic save occurs on upgrade.

Unsaved edits are discarded on reload/unload. Saved names, shapes and height
limits persist; the debug toggle, browsing state and manual transform settings
are session-only. Share the `.txt` file to incorporate your authored
boundaries into the default dataset later. Saved edits remain experimental.

Regenerating defaults does not overwrite this local override file. A changed
source raster has a new identity; mismatched/unknown saved maps are rejected
rather than silently applying geometry to the wrong artwork.

## Live map selection and alignment

469 rasters have a matching zone/floor index in the Boussole reference metadata.
The remaining 25 are marked **editor only** unless manually calibrated.
Metadata matches alone do not establish client compatibility or alignment.
Every live transform read still checks the actual client zone ID, floor ID,
nonzero scale and sane offsets before allowing classification.

The already-tested three outdoor POC zones retain their direct floor-zero path.
Other genuinely single-floor zones use their single floor. Other zones with
more than one reference client floor—even if the pack only includes one—use
Boussole's signature-based native floor selection, including its X/Z/Y call
convention. Missing signatures/pointers or an unmapped returned floor disable
classification rather than guessing. This native path needs validation against
your client; offline tests cannot validate native addresses/calling conventions.
The debug browser itself does not call the native floor function.

Multiple artwork variants for one floor are separately editable. Automatic
selection prefers the existing POC or the variant with more located reviewed
names. It cannot prove which replacement artwork matches your client. In the
current player zone, use **Use this map for live detection** to explicitly test
an alternate raster. **Automatic live floor** removes the override. The choice is saved for that zone.
Merely choosing a map in the dropdown never sets a live override.

Before trusting any new map's detection:

1. Check the cyan marker at several separated landmarks.
2. Run `/zone sample` at each checkpoint to record world position, raster
   key, client transform, floor and map pixels.
3. Correct draft vertices and unlocalized names, then Save.
4. Enable POC detection, start outside the **expanded** boundary, wait briefly
   and approach the area. Initial samples/enabling inside an area seed silently.

Player position uses `Movement.LocalPosition`: X/Y horizontal, Z elevation.
Standard image conversion in 512-reference coordinates is:

```text
map_x = world_x * abs(scale) / 5 - offset_x
map_y = -world_y * abs(scale) / 5 - offset_y
```

Preview resize does not alter this coordinate space. No arbitrary clamp is
applied to position before testing polygons.

## Commands and detection behavior

| Command | Effect |
| --- | --- |
| `/zone` | Open/close display settings and Appearance tab |
| `/zone test` | Show zone/region/weather now |
| `/zone reload` or `rl` | Reload character display settings and show current zone |
| `/zone poc [on\|off]` | Toggle experimental area announcements |
| `/zone debug [on\|off]` | Open/close the all-map browser/editor |
| `/zone approach <0..100>` | Approach buffer in yalms (default 30), saved |
| `/zone sample` or `status` | Print live coordinate/map report |
| `/zone livemap auto` | Remove this zone's saved live-map choice |
| `/zone livemap <map-key>` | Use a raster in the current zone, saved for that zone |
| `/zone transform <scale> <offset_x> <offset_y>` | Session-only transform for the current live raster |
| `/zone transform reset` | Clear that raster override and retry client metadata |
| `/zone help` | Command syntax |

Polling is every 0.25 seconds while debug or detection is active. A transition
must remain stable for one second. Current membership has three map pixels of
exit hysteresis beyond the approach boundary. Actual feature containment wins
over neighbouring approach buffers; otherwise current membership is retained
in overlaps, or the closest feature within range is chosen. Beyond finite
buffers, terrain remains unlabelled.

Stable exits clear membership without announcing an invented name. Reentry
can announce again. Load, enable, zone/floor changes, geometry edits to the live
map and position recovery seed silently. Zone entry does not show a sub-zone name;
with **Show Sub-zone Popups** enabled, later stable transitions into named areas
use a separate sub-zone popup. Zone entry retains priority over queued area
banners. Missing position/map selection clears stale area state. Ordinary
zone/region/weather banners remain available independently.

## Files, generation and tests

- `data/all_maps.lua`: generated all-raster identities and polygons.
- `research/boundary_refinements.json`: canonical player examples/visual drafts.
- `data/boundary_refinements.lua`: generated raster-specific refinement layer.
- `map_catalog.lua`: groups zones/floors/variants and preserves POC defaults.
- `data/poc_areas.lua`: original seven POC shapes.
- `data/region_flags.lua`: which flag each nation's regions show.
- `research/building_seeds.json`: where each city building is, for the tracer.
- `presentation.lua`, `banner_layout.lua`: winxi display settings, text layout
  and timed fades, independent of geometry/editor persistence.
- `map_browser.lua`, `debug_view.lua`: independent browsing, maps and editing.
- `boundary_editor.lua`: validation, undo, names/flags and v1/v2 persistence.
- `map_position.lua`, `area_tracking.lua`, `area_geometry.lua`: live mapping and
  membership logic.
- Exported map previews in `assets/maps/` are obsolete and no longer bundled.
  The browser reads map textures directly from the game's DAT files.
- `research/map_subregions.md`: reviewed-name provenance and research limits.
- `research/performance_audit.md`: optimization findings, offline measurements
  and remaining native/client validation needs.

Rebuild all draft defaults/previews (requires Pillow):

```sh
python3 tools/build_zoneinfo_maps.py references/XICombinedMaps-2048
# Or refresh defaults only, keeping already prepared previews:
python3 tools/build_zoneinfo_maps.py references/XICombinedMaps-2048 --defaults-only
```

The previews retain supplied community artwork/labels and attribution. No
additional ownership or licensing claim is made here.

Focused offline checks, also included in `tests/run.sh`:

```sh
luajit tests/zone_math_check.lua
luajit tests/zone_banner_check.lua
luajit tests/zone_editor_check.lua
luajit tests/zone_catalog_check.lua
luajit tests/zone_geometry_regression_check.lua
luajit tests/harness.lua zone tests/zone_fixture.lua tests/zone_check.lua
luajit tests/harness.lua zone-presentation tests/zone_fixture.lua tests/zone_presentation_ui_check.lua
luajit tests/harness.lua zone-subzone tests/zone_fixture.lua tests/zone_subzone_check.lua
luajit tests/harness.lua zone-gdi tests/zone_fixture.lua tests/zone_gdi_check.lua
luajit tests/harness.lua zone-background tests/zone_background_fixture.lua tests/zone_background_check.lua
luajit tests/zone_gdi_families_check.lua
luajit tests/zone_height_check.lua
luajit tests/zone_exact_check.lua
luajit tests/harness.lua zone-features tests/zone_background_fixture.lua tests/zone_features_check.lua
luajit tests/harness.lua zone-editor tests/zone_fixture.lua tests/zone_editor_ui_check.lua
luajit tests/harness.lua zone-browser tests/zone_fixture.lua tests/zone_browser_ui_check.lua
luajit tests/harness.lua zone-zoom tests/zone_fixture.lua tests/zone_zoom_ui_check.lua
luajit tests/harness.lua zone-performance tests/zone_fixture.lua tests/zone_performance_ui_check.lua
luajit tools/benchmark_zone.lua
python3 -m unittest discover -s tools -p 'test_*.py'
```

Synthetic tests cover coverage accounting, geometry, editing, dropdowns,
map/floor isolation, persistence/migration, mocked floor-selection behavior,
fade timing, text visibility, settings reloads and winxi renderer cleanup.
They do **not** establish real-client native compatibility, map alignment,
physical terrain boundaries or visual appearance.
