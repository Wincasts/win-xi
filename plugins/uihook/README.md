# uihook

One Ashita v4 plugin that changes the game's own interface. Addons hand it their own **buff**, **party/alliance**,
**target** and **chat log** drawing to stand in for the game's, each independently. It replaces loading `buffhook`
and `partyhook`; the addons remain separate. Loading uihook without any of that asked for leaves the game's drawing
unchanged.

## Who needs it

[winbuff](../../addons/winbuff/README.md), [winchat](../../addons/winchat/README.md) and
[winparty](../../addons/winparty/README.md) use it to work with the game's own windows, and their zips carry it.
Load it before them: `/load uihook`, then the addon.

## Build and install

```sh
plugins/uihook/build.sh                 # the plugin as it is played with
plugins/uihook/build.sh --diagnostics   # with the menu and texture censuses built in
```

Uses the same clang-cl/lld-link, x86 Windows SDK/MSVC and Ashita SDK toolchain as the previous plugins
(default `.toolchain`; overrides: `TOOLCHAIN`, `ASHITA_SDK_PATH`, `MSVC_PATH`). Output:
`plugins/uihook/build/uihook.dll`.

Unload addons and old hooks **before replacing DLLs**:

```text
/addon unload winbuff
/addon unload winparty
/addon unload clock
/unload buffhook
/unload partyhook
/unload uihook
```

Copy the built DLL to your Ashita `plugins/` directory, deploy the updated winbuff/winparty addons, and
replace old hook load commands in your startup script with:

```text
/load uihook
/addon load winbuff
/addon load winparty
```

winbuff uses its existing anchored-bar setting. winparty's replacement stays off until you turn it on:

```text
/addon unload hideparty
/winparty native on
/winparty native target on
/winparty native status
```

The party and target replacements are turned on separately. **Do not run hideparty with either of them.**

While a fish is on the line the game draws its stamina gauge with the party list: the list's pet bar, named "Fish",
moved up towards the middle of the screen. From 1.65 uihook lets the game's drawing outside Party's replaced
windows through, so the gauge shows. Existing styling, positions and saved settings are unchanged.

Unload uihook before copying a rebuilt DLL; never overwrite a loaded plugin.

The `--diagnostics` build adds the menu and texture censuses; the plugin as it is played with does not have them.

## Moving from buffhook and partyhook

Updated addons prefer uihook, but can still use their legacy plugins when uihook is absent.
Do not load old and new plugins together. Uihook refuses initialization if either legacy DLL is
present. Rebuilt legacy plugins also reject loading while uihook is present; older binaries do not
have this guard, so remove their startup commands. To revert, unload the addons and uihook first,
then load the legacy plugins and reload the addons.

## Clock and compass

The clock addon that used this (writing the clock on one line in place of the game's text, keeping
the game's icons and hiding the compass through the compass slot) is retired; winchat's Info Panel
reads the same native clock. **Unload hidecompass first**: it hides the shared native object and
prevents both clock and compass render boundaries from running.

## Chat

winchat hands uihook its chat log and input bar to draw in the game's place. The plugin itself does not
collect chat messages or own keyboard input, and does not edit messages, chat mode, input history or the
log's open/close timer. Do not run FancyChat, hidechatbg or other chat-visibility writers alongside
replacement: they can close the native log or change what native restoration looks like.

## Commands

| Command | What it does |
|---|---|
| `/uihook` (or `/uihook addons`) | Lists the addons handing uihook something now, and what: winbuff's bar, winparty's party, alliance and target windows, each marked "(hidden)" where the addon hands over an intentionally empty replacement. It also says which parts this client was not recognised for, and any slot whose capture is being refused, with the reason. |
| `/uihook chat` | Reports chat recognition and the last native and drawn frames. |
| `/uihook chat history` | Prints the newest 12 lines of the game's chat history. |
| `/uihook menus` | Reports the action-menu placement beside winchat's panel: support, apply and restore counts and the last menu, and the expanded log's placement. |
| `/uihook hud` | Prints what the clock replacement was drawn into. It only reads. |

## Stability

The blocks this plugin shares with addons are frozen at their 1.0 layout until 2.0: an addon made for 1.0 keeps
working with every newer 1.x uihook.

## License

MIT; see [LICENSE.md](LICENSE.md).
