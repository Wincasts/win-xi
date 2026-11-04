# uihook

An Ashita v4 plugin that lets addons draw parts of the game's own interface. Addons can give it their
own **buff**, **party/alliance**, **target** and **chat log** windows to show in place of the game's,
each one separately. Then those windows behave like the game's own: for example, the game's menus are
drawn over them. If no addon asks it for anything, uihook leaves the game's drawing unchanged.

## Why you need it

- An addon you use needs it: [winbuff](../../addons/winbuff/README.md),
  [winchat](../../addons/winchat/README.md) and [winparty](../../addons/winparty/README.md) use it to
  work with the game's own windows. Their downloads include it.
- It replaces the older `buffhook` and `partyhook` plugins with one plugin. The addons stay separate.

Load it before those addons: `/load uihook`, then the addon.

## Install and update

uihook comes in the downloads of winbuff, winchat and winparty.

**Before you replace the plugin file (DLL)**, unload the addons and the old plugins:

```text
/addon unload winbuff
/addon unload winparty
/addon unload clock
/unload buffhook
/unload partyhook
/unload uihook
```

Never copy over a plugin that is loaded. Unload uihook first.

Then copy the new `uihook.dll` into your Ashita `plugins/` folder, and install the updated winbuff and
winparty addons. In your startup script, replace the old plugin load commands with:

```text
/load uihook
/addon load winbuff
/addon load winparty
```

### Turning it on in the addons

- **winbuff** uses its existing **Anchor To Default Location** setting.
- **winparty**'s use of uihook stays off until you turn it on:

  ```text
  /addon unload hideparty
  /winparty native on
  /winparty native target on
  /winparty native status
  ```

  The party and target windows are turned on separately. **Do not run hideparty with either of them.**

### Fishing

While a fish is on the line, the game draws its stamina gauge as part of the party list: the list's
pet bar, named "Fish", moved up towards the middle of the screen. From 1.65, uihook lets through the
game's drawing outside winparty's replaced windows, so the gauge shows. Your styles, positions and
saved settings do not change.

## Moving from buffhook and partyhook

- Updated addons use uihook if it is there. If it is not, they can still use the old plugins.
- Do not load the old and new plugins together. uihook refuses to start if either old plugin is
  loaded.
- Rebuilt versions of the old plugins also refuse to load while uihook is loaded. Older copies do not
  check this, so remove their lines from your startup script.
- To go back to the old plugins: unload the addons and uihook first, then load the old plugins and
  load the addons again.

## Clock and compass

The clock addon that used uihook is retired. It wrote the clock on one line in place of the game's
text, kept the game's icons, and hid the compass. winchat's Info Panel now reads the same game clock.

**Unload hidecompass first.** It hides the game's clock and compass object, which uihook shares, and
that stops uihook's clock and compass drawing from running.

## Chat

winchat gives uihook its chat log and input bar to draw in place of the game's.

- uihook itself does not collect chat messages, and does not take over keyboard input.
- It does not change messages, the chat mode, the input history or the timer that opens and closes
  the log.
- Do not run FancyChat, hidechatbg or other addons that change whether the chat shows, at the same
  time. They can close the game's own log, or change how it looks when it is given back.

## Commands

| Command | What it does |
|---|---|
| `/uihook` (or `/uihook addons`) | Lists the addons that are giving uihook something now, and what: winbuff's bar, and winparty's party, alliance and target windows. Each is marked "(hidden)" where the addon gives an empty window on purpose. It also says which parts of the game it did not recognise in your game version, and any part it is refusing, with the reason. |
| `/uihook chat` | Reports whether the chat log was recognised, and the last frames drawn by the game and by uihook. |
| `/uihook chat history` | Prints the newest 12 lines of the game's chat history. |
| `/uihook menus` | Reports where the action menus are placed beside winchat's panel: whether this is supported, how many times they were moved and put back, the last menu, and where the opened-out log is. |
| `/uihook hud` | Prints what the clock replacement was drawn into. It only reads, and changes nothing. |

## Building

```sh
plugins/uihook/build.sh                 # the plugin as it is played with
plugins/uihook/build.sh --diagnostics   # with the menu and texture censuses built in
```

It uses the same clang-cl/lld-link, x86 Windows SDK/MSVC and Ashita SDK toolchain as the other plugins
(default `.toolchain`; overrides: `TOOLCHAIN`, `ASHITA_SDK_PATH`, `MSVC_PATH`). Output:
`plugins/uihook/build/uihook.dll`.

The `--diagnostics` build adds the menu and texture censuses (lists of the game's menus and textures,
for checking). The plugin as it is played with does not have them.

## Compatibility with addons

The data this plugin shares with addons keeps its 1.0 layout until 2.0. So an addon made for uihook 1.0
keeps working with every newer 1.x version.

## License

MIT; see [LICENSE.md](LICENSE.md).
