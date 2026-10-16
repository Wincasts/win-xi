# Changelog

## 0.2

- Add verified native clock and compass boundaries, sharing the existing capture/replay renderer.
- Add independent HUD ABI 1 (56 bytes), clock/compass capabilities and native weather readback.
- Preserve stock clock during compass replacement and stock compass during clock replacement.
- Honor native radar availability and clock enable/visibility without persistent state writes.
- Keep buff ABI 4 and party ABI 3 unchanged; party and HUD release-all calls are isolated.
- Add basic clock addon and winxi nativehud bridge. No compass addon/UI yet.
- Add C++/Wine fixtures, Lua bridge/presentation checks and optional private-client call-graph verification.
- Live clock/compass validation remains pending.

## 0.1

- Consolidate buffhook and partyhook into one modular plugin without changing their handoff formats.
