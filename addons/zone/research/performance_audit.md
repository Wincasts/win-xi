# Zoneinfo optimization audit

Scope: the current 494-map / 689-area dataset, live tracking and the browser,
zoom, drag editor and persistence paths. No live files were changed/deployed.

## Findings and changes

### 1. Outline cache invalidation was too broad — fixed

Previously every global editor revision or drag-preview revision invalidated
**every** buffered polygon on the viewed map. This included rename/enable
changes, even though geometry was unchanged. On a 12-area map a one-vertex drag
could rebuild all 12 outlines per frame.

The cache now keys each area by **polygon table identity and approach radius**.
Editor operations replace polygon tables, so geometry edits invalidate exactly
that area's outline. Metadata changes, zooming and idle frames do not rebuild
map-space outlines. Offscreen areas wait until visible before generating them.

### 2. Offscreen rendering still incurred Lua/native work — fixed

ImGui clipping prevented pixels being rendered outside the zoomed viewport,
but Lua still transformed every segment, allocated its two coordinate tables
and called AddLine. Conservative feature bounds and segment bounds now skip
invisible work before allocating vectors or crossing the Lua/ImGui boundary.
ImGui retains responsibility for exact clipping. Crossing segments are not
incorrectly hidden just because both endpoints are offscreen.

Color conversion is now nine calls per visible canvas frame, rather than a
conversion per edge/feature. Handle size, picking, scrolling, zoom transforms
and saved coordinates are unchanged.

### 3. Geometry repeatedly computed unnecessary square roots — fixed

Segment distances use squared values internally. Edge distance takes one
square root after finding the closest segment instead of one per edge.
Polygon boundary tolerance remains equivalent. Broad-phase bounding boxes
reject distant polygons before detailed ray/segment tests; disabled drafts
are skipped before distance work. Circle-arc trigonometry for preview buffers
is precomputed once, and two-side edge loops no longer allocate small tables.

Bounding boxes use weak polygon keys. All editor operations use immutable
polygon snapshots/replacement tables, so edits obtain fresh bounds and obsolete
drag tables can be collected. Independent callers must likewise replace a
polygon table rather than mutate cached vertices in place.

### 4. Texture eviction was FIFO — improved to LRU

Preview loading was already lazy and limited to four textures. Cache hits now
touch recency, so frequently revisited maps are not evicted simply because they
were originally loaded first. Texture references remain GC-safe and the limit
is unchanged. Closed debug windows do no texture loading. Closing the window
retains the bounded cache for quick reopening; unload releases references.

Map dropdown labels are cached too. Area names remain editable and are not
statically cached as map labels.

## Banner renderer follow-up

The banner renderer now returns before visibility checks or row construction
when expired and not previewing. Switching away from GDI still releases its
private backend even on an idle frame.

A single bounded cache retains current banner rows, invalidated by text and
line-content settings. ImGui text dimensions are cached per row by resolved
font and rounded size. Position, alignment, spacing, colors and opacity remain
live; delayed/expired rows keep their measured layout space but skip font pushes,
color conversion and glyph submission on warmed frames. Failed measurements
are not committed to the cache, and existing stack cleanup remains intact.

GDI applies text/style setters only when their values change, and packs shared
colors once per draw. Position, visibility and opacity remain dynamic. Texture
rebuilds still use the library's dirty flag, including native device-reset
invalidation; this does not introduce a separate texture/rectangle cache.

Offline structural checks verify unchanged frames perform zero measurements
and row rebuilds, size edits remeasure only the affected line, invisible lines
skip drawing work, GDI fades perform zero style updates/texture rebuilds, and
text/size edits rebuild only their line. Presentation checks: 44 assertions;
GDI checks: 18 assertions. These are operation-count improvements, not measured
in-game FPS gains. The five-pass ImGui outline and native renderer are unchanged.

The legacy `tests/zone_check.lua` still expects the obsolete default-off POC
behavior; it is not green. The current default-on behavior is covered by the
passing sub-zone integration checks. This follow-up does not change detection
settings or update that legacy test.

## Measurements

Host Linux LuaJIT, three runs per version, median CPU timings. Same dataset,
100 warm-up iterations (or fewer for shorter tasks), explicit garbage
collection between tasks. These are **not in-game FPS or GPU measurements**.

| Task | Before | After | Change |
| --- | --- | --- | --- |
| 100,000 classifications across all maps | 22.42 ms | 11.77 ms | ~47% less CPU time |
| 100 full outline rebuilds of the busiest map (12 areas) | 231.92 ms | 130.88 ms | ~44% less CPU time |

Those timings measure the geometry algorithms. The outline-cache improvement
is additional: an isolated vertex edit rebuilds **1 instead of 12** outlines
on that map, while metadata changes rebuild **0 instead of 12**.

Startup including registry/editor snapshots was approximately 8 ms with about
2.35 MiB of Lua heap after collection. Cached bounds/JIT traces add a small
retained cost after exercising geometry; they are not a memory reduction.
Outline stress tests retained approximately 0–1.2 KiB after collection beyond
the already warmed baseline. Transient heap readings vary with GC timing and
must not be interpreted as total allocation counts or native/GPU memory.

Checksums were identical: 1,418 matches and 364,800 emitted outline segments in
the benchmark workload (including warm-up). An additional 93,768 comparisons
against an uncached reference cover all maps, membership/hysteresis, vertices,
approach limits and edge tolerances. A pre-change snapshot comparison also
matched all 59,280 sampled map positions.

Reproduce the current benchmark:

```sh
luajit tools/benchmark_zone.lua
```

An optional first argument loads a prior `area_geometry.lua` snapshot for
algorithm comparison with the same dataset. Timing results are informational,
not pass/fail thresholds; host load and JIT trace behavior vary.

## Existing design that was already appropriate

- Live position/membership polling at 4 Hz, not once per render frame.
- Classification only considers areas on the active map, not all 689 areas.
- Transform entries cached; failed map/floor signatures backed off five seconds.
- Disabled debug path returns without building the window or previews.
- Unsaved-change results cached by revisions instead of scanning all maps on
  every unchanged frame.
- Undo snapshots taken on completed operations, not on every drag sample, and
  capped at 50 per area.
- Disk parsing/serialization and save backup rotation occur on explicit
  load/save, not in ordinary frame processing.
- Map assets are lazy; the ~54 MB addon directory is not all loaded into Lua or
  VRAM. Four textures is a count limit, not a measured GPU-byte budget.

No stationary-position shortcut was added: the debounce timer must keep
advancing even when coordinates are unchanged. No nearest-area semantics,
polygon vertices, enable flags, save format or approach distances changed.

## Remaining costs / validation

Cold image decoding and D3D texture upload are synchronous on first view and
can still cause a one-time navigation hitch. Cached frames still submit visible
polylines through ImGui, and native floor selection is client-specific. Real
GPU memory, frame-time impact, device-reset behavior and native floor-call cost
need measurement in the running Ashita client; offline stubs cannot establish
them. More invasive asynchronous loading or geometry simplification should
wait for evidence of a real client bottleneck.

Regression tests include UI assertions for per-area invalidation, palette reuse,
offscreen line suppression and the closed-debug fast path, plus all existing
zone-entry, editing, zoom, map isolation, persistence and migration checks.

## Frame cost audit, 2.6.3 (banner styles)

`tools/benchmark_zone_frames.lua` runs the addon in the test stand-in for
Ashita and measures each kind of frame: Lua time, Lua memory allocated and
imgui calls a frame, 2,000 frames after 200 to warm up, GC stopped while
measuring. imgui and the game are stand-ins, so this is the addon's own Lua
work, not the game's frame time. The stand-ins' own allocations (game objects,
winxi's hide checks, the harness's events) are in the bytes; about 320 bytes a
frame of them are left in every row. The addon's own were found with a line
hook on the GC count.

```sh
luajit tests/harness.lua zone tests/zoneinfo_fixture.lua tools/benchmark_zone_frames.lua
```

Median of three runs, before → after:

| Frame | µs/frame | bytes/frame | imgui calls |
| --- | --- | --- | --- |
| idle: nothing up | 0.91 → 0.72 | 449 → 320 | 0 |
| location line | 4.27 → 3.74 | 1841 → 1304 | 25 |
| banner: Classic Text | 3.84 → 3.47 | 2134 → 1403 | 53 |
| banner: Title Card | 5.86 → 5.53 | 1533 → 1404 | 125 |
| banner: Pennant | 8.00 → 7.24 | 1532 → 1403 | 136 |
| banner: Kanji Watermark | 4.51 → 3.91 | 1733 → 1403 | 43 |
| Title Card entrance | 7.06 → 6.47 | 1692 → 1563 | 136 |
| Pennant entrance | 7.38 → 7.88 | 1692 → 1562 | 146 |
| Kanji Watermark entrance | 5.25 → 4.55 | 1917 → 1563 | 44 |

Times move by a microsecond between runs; the bytes are steady.

Changed:

- Every frame, nothing up or not, made two functions: the zone ID read
  (`pcall(function() ... end)`) and the banner draw inside `xpcall`. Both are
  made once now. Idle frames make no garbage of the addon's own.
- Classic Text made two functions, colour tables for every line, a spacing
  table and a Dummy size table a line, each frame it was up; the location line
  a function and a Dummy table each frame. Their window bodies are made once
  and given what to draw in a table; colours and sizes reuse tables.
- The Kanji Watermark made a function each frame for its rising lines.
- The player's position read (4 times a second) made a function each time.
- **Every styled banner loaded the Japanese font** (IPA Mincho, some 4 MB) into
  ImGui the first time it showed, Title Card and Pennant included, though only
  the Kanji Watermark writes Japanese. It is loaded only for that style now.
  `tests/zoneinfo_styles_check` checks Title Card loads no font.

Left as they are:

- Title Card and Pennant make 125 to 146 imgui calls a frame while up, nearly
  all AddText: each letter is drawn by itself (the spacing animation, the
  letters down the pennant) and winxi's outline is five passes. That is a few
  hundred glyphs, little for ImGui, and only for the banner's few seconds.
- The zone ID is read from the game every frame (three API calls), so the
  banner comes up the frame the zone changes. The objects Ashita hands back
  for those calls, `imgui.GetIO()` and winxi's hide checks are the remaining
  per-frame allocations; they are the API's, not the addon's.
- Caches added with the styles are bounded or small: letters split for at most
  64 strings; letter widths per font, size and character (the pennant's
  letter size changes with the name's length, so a few sizes a zone).

## 2026-10-22: zone 2.8.2, the four new styles and the backdrop

Measured as before (median of three runs, `tools/benchmark_zone_frames.lua`),
with Kind Frames now measured in each of its looks (the harness's West Ronfaure,
Southern San d'Oria, Davoi) and `BENCH_CALLS=1` listing each style's imgui calls
in a settled frame by name. The Backdrop (on to start) is in every figure: ten
`AddRectFilled` a frame, its colour packed once.

| Frame | Time (µs) | Bytes | imgui calls |
| --- | --- | --- | --- |
| Nothing on screen | 0.74 → 0.72 | 320 → 320 | 0 → 0 |
| Classic Text | 3.77 → 3.43 | 1403 → 1403 | 63.6 → 63.6 |
| Title Card | 9.43 → 8.83 | 1423 → 1404 | 134.5 → 127.3 |
| Pennant | 9.70 → 9.32 | 1438 → 1403 | 146.1 → 139.0 |
| Kanji Watermark | 6.99 → 6.83 | 1404 → 1406 | 52.9 → 44.8 |
| Letter Reveal | 9.64 → 6.59 | 1404 → 1403 | 87.0 → 68.1 |
| Classic Window | 8.62 → 7.93 | 1403 → 1403 | 61.0 → 52.9 |
| Elemental Weather | 9.28 → 6.99 | 1404 → 1403 | 109.4 → 96.8 |
| Kind Frames, open country | 6.13 → 6.19 | 1403 → 1403 | 51.1 → 43.0 |
| Kind Frames, city | 6.35 | 1405 | 44.8 |
| Kind Frames, dungeon | 7.38 | 1421 | 103.1 |

The bytes are the harness's stand-ins, as before; no style allocates of its own.

Changed:

- Every style measured its words afresh each frame, a font pushed, the size asked
  and the font popped for each line: half of Elemental Weather's ten font pushes
  a frame were for measuring. Measurements are kept for each font and size
  (`measure`, beside the letter widths, a size's words let go past 64), and a
  letter's width pushes its font itself the once it is measured, so a font is
  pushed only to draw.
- Letter Reveal packed its colour twice for every letter every frame, the same
  colour once all had settled; a settled letter takes the banner's own, packed
  once (21 `GetColorU32` a frame to 5).

Left as they are:

- Kind Frames' dungeon carving draws its name seven times (four for the torch's
  glow, the cut, the lip, the stone with its outline), about 100 calls for a
  name of 15 letters. Two glow passes in place of four would save some 30, but
  it would look different; it is a few seconds a dungeon.
- The backdrop's ten rounded rectangles are ten calls; ImGui makes their corners'
  vertices, a few hundred, which is little for it.
