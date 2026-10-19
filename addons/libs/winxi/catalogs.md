# Shared action, reference and auto-translate catalogs — winxi 29

These are reusable data APIs, not replacements for existing addon windows. Server gameplay
fields, client presentation strings and auto-translate wire tokens remain separate.
Returned definition/index tables are cached and read-only by convention.

## Server catalogs

| Module / set | Definitions |
|---|---|
| `winxi.spells` / `spells` | All spell-list IDs, job levels, magic group/family, element/skill, MP, casting/recast, targeting, range/radius, enmity, content tags; blue-magic set/trait/skillchain data and set modifiers |
| `winxi.abilities` / `abilities` | Job/pet abilities: job/level, recast groups/times, targets/range/AoE, enmity, merits/additional requirements; charge progression by recast group/job/level |
| `winxi.weaponskills` / `weaponskills` | Weapon skill type/threshold, job permission bytes, range/AoE, elemental mask, skillchain properties, main-job restriction and unlock IDs |
| `winxi.traits` / `traits` | Trait IDs with **all** job/level/rank/modifier rows; blue-trait category/point/tier rules kept separate |
| `winxi.jobs` / `jobs` | Server enum IDs, symbols, fallback names and abbreviations; includes NONE and MON reference values |
| `winxi.skills` / `skills` | Server skill IDs, per-job ranks, level/rank cap table; enabled `skills.yaml` module overlays are deep-merged in init order |
| `winxi.elements` / `elements` | Server element IDs/symbols, including NONE |

Initial source: Phoenix live commit `9a4494d5056429d0e75922dc9fa47d419142cf68`.
The initial build contains 893 spells, 616 abilities, 209 weapon skills, 114 trait IDs,
24 job/reference IDs, 49 skills and 9 element values. Rebuilds can change these counts.

### Common API

```lua
local spells = require('winxi.spells');
local definition = spells.Get(1);               -- Cure, or nil for an unknown ID
local whmSpells = spells.ForJob(3, 30);         -- definitions for WHM up to level 30
local healing = spells.ForSkill(33);           -- healing-magic definitions
local found = spells.Search('cure', 20);        -- literal ASCII-case-insensitive search

-- Explicit live-client lookup; ordinary data reads work without Ashita.
local resource = spells.ClientResource(1);
local model = spells.Tooltip(1, resource);
-- Draw model.Name, model.Lines and model.Warnings using the addon's layout.
-- model.Server retains the structured server definition.
-- model.ClientDescription is presentation only, never substituted for server stats.
```

All server catalog modules expose:

- `Get(id)`, `Ids()`, `Index()`, `Clear()`: paged reads, sorted IDs, metadata, cache reset.
- `Search(query, optionalLimit)`: fallback server names; literal substring matching, no patterns.
- `ForJob(jobId, optionalMaxLevel)`: matching definitions, **not** learned/unlocked/usable actions.
  Weapon-skill job bytes are permissions, not levels, so their level argument is ignored.
  Skills match jobs with a rank, independently of level.
- `ForSkill(skillId, optionalMaxSkill)`: spells by magic skill; weapon skills by weapon skill
  type and optional skill threshold. The second argument is not a player/job level.
- `Rows(id, optionalJob, optionalMaxLevel)`: matching raw trait variants; other catalogs return
  an empty list. Multiple tiers/conditions remain separate; this is **not** an effective-stat sum.
- `Tooltip(id, optionalClientResource)`: presentation model with `Name`, `Lines`, `Warnings`,
  `Server`, optional `Variants`, `Charges`, `Blue`, `BlueMods` and `ClientDescription`.
- `ClientResource(id)`: explicit optional Ashita lookup for spells, abilities and weapon skills;
  nil for reference catalogs/traits or unavailable client resources. Job ability server IDs
  map to Ashita's pooled ability index with **+512**; weapon skills use their ID directly.
  Existing default `Name[1]` / `Description[1]` conventions are used when a resource is supplied.
- `Script(path)`: `{Path, SHA256, Text}` for indexed evidence. **Never executed.**
- `EnumName(enum, value)`: uppercase server symbol, or nil. The action indexes contain
  `job`, `skill_type`, `element`, `mod` and `skillchain` maps.

Additional helpers:

```lua
local abilities = require('winxi.abilities');
local rule = abilities.ChargeRule(abilityId, jobId, jobLevel);
-- Highest applicable base charge-rule level; no merit/equipment/recast-state adjustment.

local jobs = require('winxi.jobs');
local related = jobs.Related(3, 30);
-- related.spells / abilities / weaponskills / traits / skills

local skills = require('winxi.skills');
local cap = skills.Cap(skillId, jobId, jobLevel);
-- Base cap for that job's overlaid rank, or nil. Does not add gear/merits.
```

### Record schema and units

Action records have `Id`, fallback `Name`, and `Data` with original SQL column names.
`Data.jobs` is a lossless **44-character hex string** of the 22 binary job bytes, not a bitmask.
`Jobs[jobId]` decodes the nonzero bytes: spell level or weapon-skill permission. For abilities,
`Jobs[jobId]` is the required job level (including level zero where stored).

Trait records use `Rows` instead of `Data` to preserve the composite SQL key and all variants.
Optional blocks are `Blue`, `BlueMods`, `Charges`, `Changed`, `Sources`, and `Overrides`.
`Changed` lists SQL tables whose data differs from the base import for that definition.
`Overrides` are literal callback **declarations**, with unresolved-runtime status.
`Index().RelatedModules` also indexes enabled module files referencing the action family or
shared spell/job/weapon-skill helpers. These references do not prove the module executes.

- Spell `castTime`, `recastTime`, and animation times are milliseconds. The model formats
  base cast/recast as seconds. `spell_range` is stored in tenths of a distance unit; the model
  divides it by ten, matching Phoenix's loader.
- Ability `recastTime` and charge-rule `chargeTime` are seconds. Animation/cast fields retain
  their original SQL representation; do not assume every time column uses the same scale.
- Weapon-skill elemental values are **bit masks**, not `winxi.elements` enum IDs.
- Modifier values retain server units. Trait ranks, blue set/trait rules, merits, unlocks,
  requirements and content tags are not flattened into unconditional stats.
- Client resource text is client-encoded (typically CP932); convert it in the presentation
  layer if your renderer needs UTF-8. Extracted auto-translate text below is already UTF-8.

### Rebuilding

```sh
# Fetch Phoenix live and rebuild every SERVER set (items/mobs/etc. included):
python3 tools/build_winxi_data.py

# Or select sets; --only is repeatable:
python3 tools/build_winxi_data.py --only spells --only abilities --only weaponskills
python3 tools/build_winxi_data.py --only traits --only jobs --only skills --only elements

# Reproduce from the cached revision / use a specified checkout:
python3 tools/build_winxi_data.py --offline --only spells
python3 tools/build_winxi_data.py --server /path/to/Phoenix --only skills
```

`tools/build_action_data.py` reuses the item builder's fail-closed SQL subset. It imports base
tables and replays enabled module SQL in init order, recursively sorted within each entry.
Binary job literals and MySQL's byte-oriented `INSERT(jobs,position,length,replacement)` are
handled explicitly, preserving leading zero bytes. Unknown relevant SQL fails generation.
Each set is generated in a temporary directory before the previous set is replaced.

Every server set has `<page>.lua`, `index.lua`, a portable `{Metadata, Entries}` `catalog.json`,
and upstream licensing notices. Action sets also have batched `script_<page>.lua` evidence.
`Index().Source` identifies that particular set even after a different set updates the shared
manifest. `--set` values are recorded for auditing; this builder does **not** evaluate Lua
conditions or filter definitions by content settings.

## Auto-translate

`winxi.autotranslate` reads a **separate client-derived** catalog. Updating Phoenix does not
regenerate it; update it when the installed client/dictionaries change:

```sh
python3 tools/build_client_data.py --client '/path/to/FINAL FANTASY XI'
# Or FFXI_DIR=/path/to/client python3 tools/build_client_data.py
```

The default inputs are `ROM/168/24.DAT` (Japanese) and `ROM/168/25.DAT` (English). These are
present in the development installation. The parser validates headers, language/category/entry
IDs, category sizes, duplicate IDs and truncation; Japanese reading strings are preserved.
An unsupported or corrupt dictionary fails without replacing the old set.

Explicit inputs can replace the default pair:

```sh
python3 tools/build_client_data.py --dat en=/path/to/25.DAT --client-version 'my-client-label'
```

`--dat` is repeatable; inputs must use the supported dictionary layout and CP932 encoding.
The optional version label is user-supplied. Dictionary **SHA256 hashes and sizes are always
recorded**, so no guessed client-version claim is needed. This set's provenance is in its own
`Index().Source`, independently of the server build's manifest. Output is in `data/autotranslate/`,
including a portable `catalog.json`. No client DAT files are bundled.

The initial extraction contains **2,685 phrases in 42 categories**, in both English and Japanese.
This is the static dictionary, not a list of every item/key-item name the game can translate.

```lua
local auto = require('winxi.autotranslate');
local matches = auto.Search('hello', 'en', nil, 20);
local entry = matches[1];
local display = auto.Text(entry.Id, 'ja');       -- UTF-8 localized phrase
local token = auto.Token(entry.Id, 'en');       -- six encoded bytes, NOT display text
local parsed = auto.Decode(token);             -- Kind, Id, Category, Entry, LanguageByte

local itemToken = auto.ItemToken(itemId, 'en');
local keyItemToken = auto.KeyItemToken(keyItemId, 'en');
local clientText = auto.Expand(token, true);    -- optional live-game expansion, CP932
```

- `Get`, `Ids`, `Index`, `Clear`, `Categories`, `Text`, `Search`, `Token`, `Decode`, `ItemToken`,
  `KeyItemToken`, `Expand` are available. `Search` arguments are query, locale, category, limit.
- Phrase IDs are canonical **category × 256 + entry**. They are neither item IDs nor raw
  four-byte dictionary IDs. Records also retain per-language `RawIds`, `Text`, and Japanese
  `Readings`. Category headers are not sendable phrases.
- Dictionary token layout: `FD 02 <language byte> <category> <entry> FD`. Language bytes come
  from the dictionary, not Ashita language-array indices. No silent missing-language fallback.
- Item/key-item IDs use their separate token kinds. Zero high/low ID bytes are escaped with
  the game's alternate type codes so tokens contain no NUL bytes. Helpers validate ID range
  and encoding, not item existence, obtainability or whether a client can expand that entry.
- Search is literal and ASCII-case-insensitive; Japanese text/readings match exact UTF-8
  substrings. It is not a locale-aware Unicode case-folding or transliteration engine.
- `Decode` accepts a single six-byte token, not a whole chat line. `Expand` calls Ashita's
  `ParseAutoTranslate` only when explicitly requested. It does not send chat or edit input.

No existing addon UI is rewired. A future chat picker should display `Text` but insert the
actual token through the appropriate native editor path, preserving IME/input ownership.

## Validation and limits

```sh
python3 tools/test_build_catalog_data.py
python3 tools/test_build_item_data.py
luajit tests/winxi_catalogs_check.lua
luajit tests/winxi_autotranslate_check.lua
```

Checks cover every generated definition/model/source page, binary job SQL and module edits,
job/level filters, charges, trait variants, skill overlays/caps, client ID namespaces, dictionary
corruption and every phrase/locale. Item/key-item token tests round-trip every ID 1–65535.

A public-source clean import is not the private live database. Local patches/configuration,
Lua runtime gates, dynamic overrides, shared helper chains, C++ rules and player state can
change effective behavior. Catalog presence is not availability. These APIs deliberately do
not claim to compute complete combat formulas or a fully verified natural-language tooltip.

Embedded server sources retain Phoenix's upstream GPL v3 licensing. Extracted game text
belongs to Square Enix. Neither is relicensed under the MIT license of the builders/readers;
see each generated set's notices before redistribution.
