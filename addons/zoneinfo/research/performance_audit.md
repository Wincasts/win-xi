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

The legacy `tests/zoneinfo_check.lua` still expects the obsolete default-off POC
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
luajit tools/benchmark_zoneinfo.lua
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
