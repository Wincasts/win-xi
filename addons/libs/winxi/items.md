# Shared item data — winxi 28

`winxi.items` gives suite addons one ID-based Phoenix catalog, independently of inventory,
treasure pool or equipment windows. It does not change existing addon tooltips automatically.
The reader has no ImGui or live-client dependency. Tables are shared and read-only by convention.

## Using it

```lua
local items = require('winxi.items');
local definition = items.Get(12306); -- Kite Shield, or nil for an unknown ID
local resource = AshitaCore:GetResourceManager():GetItemById(12306);
local tip = items.Tooltip(12306, resource);
-- Draw tip.Name and tip.Lines with winxi.tooltip or the addon's own layout.
-- tip.Server contains structured server data; tip.Warnings must not be discarded
-- when claiming that this is a complete, Phoenix-accurate tooltip.
-- tip.ClientDescription is deliberately NOT merged into the authoritative stat lines.
```

- `Get(id)` lazily loads a 256-ID page; invalid/noninteger IDs return nil.
- `Ids()` returns all catalog IDs, sorted (explicitly loads all definition pages).
- `Index()` returns schema, count, revision, applied item SQL files, enum maps,
  script path index, item override declarations and coverage limitations.
- `Script(path)` returns `{Path, SHA256, Text}` evidence for an indexed script/module.
  **Text is data, never executed.** Lua runtime gates have not been evaluated.
- `ModName(id)` returns the server modifier symbol or `MOD_<id>`.
- `Clear()` releases cached definitions/evidence/index, including missing pages. Call it after
  changing `winxi.gamedata.Root` or installing a rebuilt catalog during development.

`Tooltip` returns a presentation model, not an ImGui widget:
`Id`, `Name`, `Server`, `Lines`, `Warnings`, `Latents`, `PetMods`, optional `Food`, and optional
`ClientDescription`. With no client resource, `Name` is a server sort-name fallback, not a
localized retail display name. With a client resource, `Name[1]` and `Description[1]` are used
only for presentation. Obtain icons/localized names from Ashita's client resources as before.

## Structured definitions

Each record has `Id`, fallback `Name`, and `Basic`. Optional blocks use original SQL column
names and values so consumers don't have to reverse-engineer a formatted description:

| Block | Data |
|---|---|
| `Basic` | `itemid`, `subid`, internal `name`, `sortname`, `name_jp`, server `type`, `stackSize`, `flags`, auction category `aH`, `BaseSell` |
| `Equipment` | level/item level, jobs bitmask, model, shield size, script type, slot/restricted-slot masks, superior level |
| `Weapon` | skill/subskill, item-level skill bonuses, damage type, hit count, **raw server delay**, damage, unlock points |
| `Usable` | target mask, activation, animation/time, max charges, equip-to-use delay, reuse delay, AoE |
| `Furnishing` | storage, moghancement, element/aura, placement, dimensions/height |
| `Puppet` | head/frame/attachment slot and packed elemental capacities/costs |
| `Mods` | array of `{itemId, modId, value}` |
| `PetMods` | array of `{itemId, modId, value, petType}` |
| `Latents` | array of `{itemId, modId, value, latentId, latentParam}` |
| `Food` | conservatively extracted straight-line food definition: duration in seconds, named modifier/value pairs and source path |
| `Changed` | blocks differing from the base SQL after enabled module SQL is replayed |
| `Script` | base item script path, if implemented |
| `Overrides` | literal item callback declarations in enabled Lua files: path, callback and explicit unresolved-runtime status |

`Index().Enums` contains server `mod`, `latent`, `job`, `skill_type`, and `element` maps
(symbol to value). Jobs use bit `jobId - 1`. Server item types/flags are not necessarily the
same masks as Ashita resource types/flags. Do not copy them into an Ashita resource object.

### Units and conditional data

Modifiers retain **server units**, not universal percent values. Haste and damage-taken mods,
for example, may use different scales. The generic model labels them as server units instead
of guessing. A consumer wanting polished stat lines should implement explicit per-mod formatting.
Weapon delay is not converted to retail DAT display delay (especially hand-to-hand).
`BaseSell` is the server base value, not a guaranteed final NPC payout.

Latents and pet bonuses remain separate; never sum them into unconditional player stats.
Food percentage modifiers and their cap modifiers are separate as in the server implementation.
Only a literal, straight-line `onEffectGain` list of `effect:addMod` calls with a literal food
duration is extracted. A declared item override invalidates that extraction for the item.
The remaining behavior is available as source evidence, not an automatically invented tooltip.
Instance augments, signatures, remaining charges, quality and other extdata still belong to
the inventory instance and are not part of these ID-based definitions.

## Rebuilding and auditing

```sh
python3 tools/build_winxi_data.py --only items       # fetch Phoenix live; replace items set on success
python3 tools/build_winxi_data.py --offline --only items
python3 tools/build_winxi_data.py --server /path/to/Phoenix --only items
python3 tools/test_build_item_data.py
luajit tests/winxi_items_check.lua
```

The builder is `tools/build_item_data.py`. It imports all nine `sql/item_*.sql` tables into an
in-memory SQLite database, translating the used MySQL subset (quoted strings, session variables,
bitwise expressions and item DML). It then replays enabled module SQL in `modules/init.txt`
order, recursively sorted inside each listed directory, as Phoenix dbtool does. Unsupported
item SQL fails rather than being silently ignored. Disabled module folders are not scanned.
No MySQL service or execution of untrusted server Lua is needed.

The `--set` arguments of the shared builder are recorded for audit only: item SQL is not gated
by runtime content settings. They do **not** evaluate Lua conditions or filter the item catalog.
The item index's own `Source` revision identifies this set even when the shared manifest was
subsequently updated by rebuilding a different set.

Output under `data/items/`:

- `<page>.lua`: paged definitions used at runtime.
- `index.lua`: metadata, enum maps, SQL provenance and source index.
- `script_<page>.lua`: lazily loaded batches of source evidence.
- **`catalog.json`**: the complete portable list, `{Metadata, Items: [...]}`, for search/export,
  audits or another addon/toolchain. Script text itself is in the Lua evidence pages.
- `NOTICE.txt`, `LICENSE-Phoenix`: upstream source attribution/licensing.

### What this does not certify

All `item_basic` IDs are included, including later-era, dummy and unavailable items. Presence
is **not** proof of obtainability. A clean import of public source is not a dump of the private
live database: local SQL patches and a locally modified `modules/init.txt` cannot be inferred.

Lua source indexing records **declarations**, not effective execution. Module-level conditions,
`addOverrideByEra`, `super` chains, dynamic targets, shared globals, C++ behavior, and runtime
settings may change item effects. A declaration is not presented as an applied override. The
catalog does not promise a complete natural-language description of every scripted item.
Client descriptions may also be stale or retail-specific, even where SQL has not changed.

The initial checked-in build uses Phoenix live commit
`9a4494d50` (see `Index().Source.Commit` for the full revision): 23,537 IDs, 6,181 SQL-changed
items, 761 simple food definitions, 2,492 source files and 10 literal item override declarations.
Future builds may change these counts.

Embedded server script texts remain under Phoenix's upstream GPL v3 license, not the MIT
license of the reader/builder. See the generated notice and license before redistribution.
