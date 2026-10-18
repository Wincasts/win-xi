# Shared info panel (Winxi 22)

`chat` supplies defaults/validation, chooses the owning compact chat window and samples/draws its
panel. `source` supplies time/zone/EXP and weather without requiring native clock rendering;
only the optional map grid uses a fresh native HUD read. It never claims or stops a HUD slot.
`panel`, `fields`, `exp`, `icons` and `panel_settings` are also used by the legacy clock addon
through compatibility imports. Each addon still has its own Lua state, settings and EXP tracker.

The attachment is drawn on its host's existing draw list before the host border/title; it uses
`winxi.frame` for an explicit-rectangle background/border/shadow and sits flush against chat by
default. It does not change the host's position, size, layout cursor, scroll hit regions or native
published bounds. Only a successful completed host capture can publish its native menu anchor.
`winxi.nativemenus` / uihook 0.6 (menu ABI 1) move the registered action-menu family through native
layout targets; unsupported clients/menus remain unchanged. Stopping or losing the panel restores
owned native targets. No GPU-only translation, selection/controller or mouse-position writes.

Custom icon sets live in `icons/<set>/days` and `icons/<set>/weather`, using the filenames in the
bundled `gems` set. They can follow the same format as clock's existing icon sets. The legacy clock
keeps searching `addons/clock/icons`; chatbox does not require that folder or the clock addon.

Bundled gems are repository-generated MIT artwork. Regenerate this shared copy with:

```sh
python3 tools/generate_clock_icons.py --output addons/libs/winxi/infopanel/icons/gems
```

See [chatbox](../../../chatbox/README.md#optional-info-panel) for controls, data fields and migration.
