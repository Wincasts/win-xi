# Editing addon tooltips

This folder is the editable source for tooltip wording. Start with **[name.md](name.md)**.
Open it in any text editor (VS Code, Notepad, etc.). You do not need to edit Lua.

## Try it

1. Open `tooltips/name.md`.
2. Find `## name.appearance.bold` (or search for the setting's label).
3. Change the paragraph below its Label/Location block. Save the file.
4. Ask the coding assistant **“build my tooltip edits”**, or run from the project root:

   ```sh
   python3 tools/build_tooltips.py
   ```

5. Install/sync the updated addon and shared WinXI files as usual, then reload Name
   (`/addon reload name`) to see the new text. If editing the live installation,
   building there and reloading is enough. Text is cached until the addon reloads.

There is no in-game editor or automatic hot reload. Generated Lua is committed and
shipped with the addons: players do not need Python or these Markdown files.

## File format

```markdown
## name.appearance.bold
Label: Bold
Location: Names → General Name Appearance

Makes name text heavier.

Icons and outline thickness are unchanged.
```

- **Keep the `##` ID unchanged.** Code uses it to find the tooltip. IDs are permanent,
  even when a control is renamed or moved.
- Label and Location are notes to help you find the control. They do **not** change
  its in-game label or placement. Both must be present and nonempty.
- Everything after the blank line is tooltip text, until the next `## ID` heading.
- Text is **plain text**, not rendered Markdown. Paragraphs and line breaks are
  preserved; quotes, backslashes, `%`, and format tokens like `[name]` need no escaping.
  Markdown styling such as `**bold**` would appear literally in the tooltip.
- Do not put a line beginning `## ` inside the tooltip: it starts a new entry.
- Do not leave an entry empty. Remove a tooltip through a code change instead.
- Keep named placeholders such as `{default_format}` when you want the current value
  inserted. The format editors share an Options entry; their individual help text
  and that shared entry are joined at runtime.
- Use UTF-8 when saving. Actual display of non-ASCII characters depends on the font.

The first pilot covers Name's **settings text tooltips and expandable help**, not
chat messages, warning banners, icon-only previews, or tooltips provided by shared
WinXI theme controls. Those shared controls can be migrated to `winxi.md` later.
No settings layout or tooltip rendering behaviour is changed by the catalogue.

## Validation

```sh
python3 tools/build_tooltips.py --check
```

Checks all catalogues and code references, writes nothing, and exits unsuccessfully
if an entry is invalid, an ID is missing, or generated Lua needs rebuilding. Normal
builds validate first, then write only changed generated files. Unused entries are
reported as warnings (useful while migrating another addon). Duplicate IDs, empty
text, invalid namespaces, and malformed metadata are errors.

## Extending to another WinXI addon

1. Add `tooltips/<addon>.md`; it is discovered automatically. Use IDs beginning with
   `<addon>.`, e.g. `party.appearance.lock`. Shared controls can use `winxi.`.
2. In the code, use the standard local name **`tips`**:

   ```lua
   local tips = require('winxi.tips');
   local tooltip = require('winxi.tooltip');
   -- After drawing a control:
   tooltip.Hover(tips.Get('party.appearance.lock'));
   ```

   Existing help functions can receive `tips.Get(...)` wherever they expect text.
   The content lookup does not depend on imgui or on a particular control helper.
3. Use literal IDs in `tips.Get`, not concatenated/dynamically constructed IDs. A
   table of literal lookups works for data-driven controls. The build tool scans
   `addons/**/*.lua` for these references, ignoring comments and string contents.
   Keep the `tips` alias so validation can find the calls.
4. For variable text, pass named values:

   ```lua
   tips.Get('party.example.help', { seconds = 5 })
   ```

   `{seconds}` in the entry becomes `5`. Values are inserted literally, without
   interpreting `%` or any Lua code. Unknown placeholders remain visible as written.
5. Run the build and tests. Commit both the Markdown and generated Lua. Ship
   `addons/libs/winxi/tips.lua` and `addons/libs/winxi/data/tooltips/<addon>.lua`
   with the shared library alongside the updated addon.

Generated files live under `addons/libs/winxi/data/tooltips/`. **Do not edit them**:
the next build overwrites them from Markdown. The builder never rewrites addon code;
connecting a new control to an ID is an explicit coding change.
