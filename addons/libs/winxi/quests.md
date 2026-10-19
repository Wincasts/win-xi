# Quest catalog — winxi 30

`winxi.quests` is a shared, source-backed Phoenix quest index. It is **not** a walkthrough,
a live progress tracker, or a declaration that every listed quest is implemented/available.
No existing addon UI is changed. Returned data tables are cached and read-only by convention.

## Using it

```lua
local quests = require('winxi.quests');

-- Quest IDs are unique only inside their log/category:
local elder = quests.Get(4, 24); -- Other Areas: Elder Memories
local same = quests.GetBySymbol('otherAreas', 'ELDER_MEMORIES');

local matches = quests.Search('Selbina');
local zoneQuests = quests.ForZone(248);
local npcQuests = quests.ForNpc('Isacio', 248);
local shieldQuests = quests.ForReward(12306); -- literal base reward declarations only
local tip = quests.Tooltip(4, 24);
```

The initial build uses Phoenix live revision
`9a4494d5056429d0e75922dc9fa47d419142cf68` and contains:

| Coverage | Numbered quests |
|---|---:|
| Direct `Quest:new` framework scripts | 512 |
| Recognized factory-backed scripts | 45 |
| References found, but no recognized owning framework script | 130 |
| Enum identities only | 397 |
| **Total numbered definitions** | **1,084** |

There are also **26 hidden interactions**, kept in a separate namespace, and **872 source
files** indexed as evidence. Counts can change on rebuild. An enum-only record is an identity,
not an implemented quest. A reference-only entry might have legacy implementation or merely
be mentioned by another quest; the catalog deliberately does not decide which.

## API

| Function | Result |
|---|---|
| `Get(logId, questId)` | Numbered record, or nil. IDs must be nonnegative integers; ID zero is valid. An ID alone is not accepted. |
| `GetBySymbol(area, symbol)` | Record for a server symbol, e.g. `('sandoria', 'A_KNIGHTS_TEST')`. |
| `GetKey(key)` | Record by canonical `'<log>:<id>'` or hidden key. |
| `Hidden(pathOrKey)` | Hidden interaction, addressed by its full source path **without `.lua`**, or canonical hidden key. |
| `Keys(includeHidden)` | Canonical keys: numbered entries ordered by log/ID, optionally followed by path-sorted hidden entries. |
| `Logs()` | Server log/category metadata keyed by numeric log ID. Names here are source area keys, not localized journal labels. |
| `Index()` | Per-set source revision, counts, coverage, symbols, indexes, source paths, module references and diagnostics. |
| `ForLog(logId, options)` | Records in one quest log. |
| `ForZone(zoneId, options)` | Records with a source reference to that zone—not necessarily started there. |
| `ForNpc(name, optionalZoneId, options)` | Records associated with an NPC name. Exact ASCII-case-insensitive comparison; underscores/spaces are equivalent. |
| `ForReward(itemId, options)` | Records with that item in a literal **base reward declaration**, not incidental item mentions or conditional grant calls. |
| `Search(query, options)` | Literal substring search through source names, symbols, area keys, NPC and zone names. ASCII-case-insensitive; underscores/spaces are equivalent. |
| `Script(path)` | `{Path, SHA256, Text}` source evidence, or nil. Text is never executed by the reader. |
| `Tooltip(logId, questId, presentation)` | Presentation model for a numbered quest. |
| `TooltipKey(key, presentation)` | Presentation model for either namespace. |
| `Clear()` | Drop caches, including missing files. Use after changing `winxi.gamedata.Root` or installing rebuilt data in a running addon. |

Filter `options` is an optional table with `Log`, `Hidden` and `Limit` fields. Hidden interactions
are excluded from searches/filters unless `Hidden = true`. A zero/invalid limit returns no results.
`Hidden = true` includes both numbered and hidden entries; it does not mean hidden-only.

```lua
local found = quests.Search('Bluffnix', { Log = 3, Limit = 20 });
local allKeys = quests.Keys(true);
local hidden = quests.Hidden('scripts/quests/hiddenQuests/New_Character_Cutscenes');
local withHidden = quests.ForZone(235, { Hidden = true });
```

`Tooltip` returns `Key`, optional `Log`/`Id`, `Name`, `Server`, `Lines`, `Warnings`, `NPCs`,
`Zones`, `RewardDeclarations` and `Evidence`. Optional presentation is a table of **strings**:
`{Name = localizedTitle, Description = journalText}`. Its description remains separate as
`ClientDescription`; it never replaces server facts. Warnings must not be dropped when
presenting the result as Phoenix-specific information.

## Record schema: facts versus evidence

Every numbered record has `Key`, `Kind = 'quest'`, `Log`, `Id`, `Area`, `Symbols`, `Name`,
`NameSource` and `Coverage`. Symbol aliases sharing a log/ID share one record.

Names are taken from a source header when possible, otherwise a source filename or humanized
enum symbol. **Localized client journal titles/descriptions have not been extracted.** A consumer
can supply them through the presentation argument. Source names are UTF-8; client-provided
strings may need CP932-to-UTF-8 conversion in the UI layer.

Hidden records have `Kind = 'hidden'`, `Key = 'hidden:scripts/quests/...'` and `HiddenId`,
without numbered `Log`/`Id` fields. A hidden interaction can cover tutorial events, artifact
crafting or other non-journal behavior; it must not be inserted into the numbered quest log.

Optional fields:

- **`Sources`**: owning quest/wrapper files with a recognized literal identity.
- **`HelperSources`, `Factory`**: a recognized Jeuno factory, its literal parameters, source
  line and helper function line range. Gobbiebag/Borghertz parameter identities and the current
  Unlocking a Myth job-ID formula are recognized only while the expected helper patterns exist.
  Factories are not executed. Partial parameters retain unresolved expression markers.
- **`Zones`**: `{Id, Symbol, Source, Line}` references to zone enums. A mention can occur in a
  condition, handler or helper; it is not proof of a starting location.
- **`NPCs`**: `{Name, Zone, ZoneSymbol, Source, Line}` structural zone/NPC table keys, plus
  explicitly labeled legacy NPC-file associations. An NPC can be a starter, later objective,
  completion NPC, or reference; no automatic role is assigned. Dynamic NPC/zone keys can remain
  unresolved. Coordinates in comments are not treated as verified locations.
- **`RewardDeclarations`**: literal `quest.reward = {...}` tables, plus recognized Gobbiebag
  reward parameters. Each has `Source`, `Line`, `Fields`, `Complete`, `Scope`, and, for direct
  declarations, original `Raw` text. `Complete` means the **declaration** was statically resolved,
  not that it describes every effective reward. Unknown expressions remain
  `{Expression = ..., Unresolved = true}`. Item/key-item/title/fame-area symbols resolve to
  server enum IDs. Base gil/experience are not multiplied by server rates.
- **`DeclaredRewardItems`**: item IDs from the literal base reward `item` field only. Nested
  item/quantity tables preserve their original structure in `RewardDeclarations`. Trade items,
  reward choices and conditional `giveItem` branches are not silently added to this index.
- **`Evidence`**: source lines categorized as condition, state, setting, time or reward-call
  references. Conditions might concern later stages, refusals, exclusions, OR branches or
  repeat attempts. **They are not normalized prerequisites.** Read the full source for context.
- **`References`, `RelatedSources`**: incoming quest-ID/path references from other quests,
  legacy NPCs or enabled modules. A file can refer to several quests; its branches are not
  all attributed to each referenced quest.
- **`Modules`**: enabled module files associated through quest IDs, interaction paths or literal
  NPC callback overrides. Reference kinds distinguish direct literal interaction edit declarations,
  path references and NPC-override associations. This is not a confirmed list of applied edits.

Metadata diagnostics include `Unresolved` constructors/symbol references, `UnownedQuestScripts`,
`UnassociatedModules` and `TodoFiles`. `.lua.todo` files are listed but not parsed as implementations.
Shared helpers, numeric-only legacy references, dynamically constructed paths, content gates,
`super` chains and C++ behavior may require manual review.

## Rebuilding and auditing

```sh
python3 tools/build_winxi_data.py --only quests        # fetch Phoenix live
python3 tools/build_winxi_data.py --offline --only quests
python3 tools/build_winxi_data.py --server /path/to/Phoenix --only quests

# Included when rebuilding all server datasets:
python3 tools/build_winxi_data.py
```

The builder is `tools/build_quest_data.py`. It statically tokenizes Lua comments, strings and
balanced tables; reads the quest-log/ID enums; associates literal framework identities and
recognized factory wrappers; indexes quest/NPC references; and inspects **enabled** modules
from `modules/init.txt`. It never executes server Lua. Unknown enum layouts or unbalanced
source delimiters fail generation rather than replacing the previous set with an empty catalog.
Dynamic constructs remain explicit diagnostics/source evidence rather than guessed facts.

`--set` overrides are recorded for audit only. They do not evaluate module conditions or filter
quests by runtime content settings. The public checkout is not the private live server's local
configuration/database. Presence is not obtainability or availability.

Output under `addons/libs/winxi/data/quests/`:

- `<logId>.lua`: numbered definitions, one file per log, indexed by quest ID.
- `hidden.lua`: separately keyed hidden interactions.
- `index.lua`: per-set revision, indexes, diagnostics and source metadata.
- `script_<page>.lua`: lazily loaded batches of UTF-8 source evidence; hashes identify the
  embedded source text. Embedded server scripts retain upstream **GPL v3** licensing.
- **`catalog.json`**: portable `{Metadata, Quests: [...], Hidden: [...]}` list.
- `NOTICE.txt`, `LICENSE-Phoenix`: source attribution/licensing; no MIT relicensing of upstream code.

Generation succeeds in a temporary directory before replacing the old quest set. Each set's
own `Index().Source` is authoritative for its revision, even when another set later updates the
shared manifest. Rebuilding from identical inputs produces byte-identical quest files.

## What remains outside this catalog

There is no player-progress polling, packet-based quest tracker, computed eligibility engine,
repeatability certification, verified starting guide, or complete natural-language walkthrough.
Much server-side quest state is not visible to the client. Module edits are retained as evidence,
not simulated into base reward tables. Optional rewards and unlocks may exist only in source code.

Keep any future human-reviewed guidance **outside** the generated `data/quests/` directory,
keyed by `record.Key`, so ordinary rebuilds cannot overwrite it.

## Validation

```sh
python3 tools/test_build_quest_data.py
luajit tests/winxi_quests_check.lua
```

Tests cover identity collisions/aliases, comments/strings, unresolved expressions, factory
parameters, disabled modules, NPC versus nested table keys, declared versus conditional rewards,
source line accuracy, deterministic fixture rebuilds and preservation of the old set on a failed
shared build. Runtime checks read every generated definition/model/source page, validate source
line references, exercise filters/hidden opt-in and handle missing data without a live client.
