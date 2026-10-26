# The plugins' shared blocks: the 1.0 promise

namehook, uihook and lens share what they do with addons through blocks of memory in their DLLs: each found
by a magic, or reached through a pointer in one that is. From 1.0 until 2.0 the promise is:

**An addon made for 1.0, or any later 1.x, keeps working with every newer 1.x plugin, without an update.**

An addon newer than the plugin it finds may need something the plugin does not have yet; it finds out and
says so, or goes without (see *Addons* below). It never misreads the plugin.

This file is the contract. `tools/abi_check.py` enforces the layouts: it runs in `tests/run.sh` and fails the
moment a plugin or a Lua copy breaks them.

## The blocks at 1.0

The 1.0 layout of each, and of every struct inside it, is frozen in `plugins/abi/layout-1.0.json`, made from the
plugins' own compiled sources (`tools/abi_check.py --freeze`, once, for 1.0; never again before 2.0).

| Plugin | Found by | Version | C++ struct | 1.0 size (bytes) | Records in it | Read by |
|---|---|---|---|---|---|---|
| namehook | `NAMEHOOK` | 3 | `HookShared` | 35,168 | `HookName` | `addons/libs/winxi/nameplates.lua` |
| namehook | `NAMEHOOKCAPS` | 1 | `HookCapabilities` | 32 | — | `addons/libs/winxi/nameplates.lua` |
| namehook | `HookShared.Draw`, `HookClaims` slots | — | `HookDraw` | 841,872 | `HookDrawing`, `HookQuad` | `addons/libs/winxi/nameplates.lua` |
| namehook | `NAMEBUBBLES` | 2 | `HookBubbles` | 851,116 | — | `addons/chatbubbles/world.lua` |
| namehook | `NAMEHOOKPOPUPS` | 1 | `HookPopups` | 5,432 | `HookPopup` | `addons/libs/winxi/popups.lua` |
| namehook | `HookPopups.Draw` | — | `HookPopupDraw` | 198,808 | `HookPopupDrawing`, `HookQuad` | `addons/libs/winxi/popups.lua` |
| namehook | `NAMEHOOKCAMERA` | 1 | `HookCamera` | 268 | — | `addons/libs/winxi/camera.lua` |
| namehook | `NAMEHOOKCLAIMS` | 1 | `HookClaims` | 144 | `HookClaimSlot` | `addons/libs/winxi/nameplates.lua` |
| namehook | `NAMEHOOKLAYERS` | 1 | `HookLayers` | 176 | `HookLayerSlot` | `addons/libs/winxi/layers.lua` |
| namehook | `HookLayers` slots | — | `HookLayerDraw` | 417,944 | `HookLayerDrawing`, `HookQuad` | `addons/libs/winxi/layers.lua` |
| uihook | `BUFFHOOK-SHARED` | 4 | `BuffShared` | 41,228 | `BuffQuad` | `addons/buff/hook.lua` |
| uihook | `PARTYHOOK` | 3 | `PartyShared` | 168 | `NativeRect` | `addons/party/hook.lua` |
| uihook | `UIHOOK-CHAT` | 13 | `ChatShared` | 71,684 | `ChatTab`, `ChatTextRow` | `addons/libs/winxi/nativechat.lua` |
| uihook | `UIHOOK-HUD` | 6 | `HudShared` | 164 | — | `addons/libs/winxi/nativehud.lua` |
| uihook | `UIHOOK-MENUS` | 1 | `MenuShared` | 108 | — | `addons/libs/winxi/nativemenus.lua` |
| uihook | `UIHOOK-TEXT` | 1 | `TextTapShared` | 525,856 | `TextTapEvent` | `addons/libs/winxi/nativetext.lua` |
| uihook | `UIHOOK-HISTORY` | 1 | `ChatHistoryShared` | 67,988 | `ChatHistoryLine` | `addons/libs/winxi/nativehistory.lua` |
| uihook | `UIHOOK-KEYS` | 1 | `KeysShared` | 72 | — | `addons/libs/winxi/gamekeys.lua` |
| uihook | `UIHOOK-MIRROR` | 6 | `MirrorShared` | 106,880 | `MirrorFrameData` | `addons/nativeui/groupmirror.lua` |
| lens | `LENS-WARP` (exported `LensWarp`) | 1 | `lens::Shared` | 48 | — | `addons/libs/winxi/lens.lua`; namehook and uihook in C++ (`lens::Live`) |

A record is a struct a block holds a list of (a name, a popup, a quad, a party window's rectangle): fixed in
size, as the list it is in is part of the block.

## Plugins

1. **The 1.0 layout never changes.** No field of a block or a record is moved, removed, resized, retyped or
   given another meaning. A list's length (`HookName Names[...]`) is part of the layout too.
2. **The magic and the Version stay as they are.** Changing either is what 2.0 is.
3. **A block grows only at its end.** A new field goes after the last, and the block's `Size` is what it now
   is. Older addons read the block as far as they know it and never look further.
4. **A record never grows.** It sits in a list inside its block, and growing it would move all that comes
   after. More for each entry goes in a new list appended to the block, by the same index (`NamesExtra[i]`
   beside `Names[i]`). The same goes for more entries: a second list, not a longer one.
5. **New behaviour is asked for.** A field an addon writes is 0 in an older addon's hands, so 0 means as it
   was. A change in what the plugin does is turned on by the addon (a flag, as party's `PARTY_PASS_OUTSIDE`)
   and offered in a mask the plugin sets (`SupportedMask`), never on for everyone.
6. **A function an addon calls keeps its signature and its meaning.** Another goes in a new pointer field.
7. **A block reached through a pointer (`HookDraw`, `HookPopupDraw`) has no Size of its own.** What it gains
   is announced where an addon can see it: a feature bit (`HookCapabilities.Features` for namehook) or the
   `Size` of the block that points to it.
8. **A new plugin still fills every 1.0 field as 1.0 did**, so an old addon sees what it always saw.

## Addons

Every read goes through `winxi.abi` (winxi 57):

```lua
local abi = require('winxi.abi')
if not abi.Accepts(block, 'uihook_keys_t', 1) then ... end      -- this Version, and at least the addon's size
if abi.Has(block, 'uihook_keys_t', 'SomeLaterField') then ... end -- the plugin is new enough for the field
```

- **Accept a block** when its Version is the addon's and its `Size` reaches as far as the addon needs: its
  `ffi.sizeof`, or, where its copy has fields a plugin added after 1.0, the first of them
  (`abi.Accepts(block, 'namehook_t', 3, 'LoadId')`), so an older plugin is still read. Never ask for an
  exact size: that refuses every newer plugin.
- **A record's size is exact** (`NameSize`, `PopupSize`): records never change, so any other size is not this
  plugin's.
- **A field the plugin's 1.0 layout did not have** is read only after `abi.Has` (or the plugin's feature bit)
  says it is there; otherwise the addon goes without, or says what plugin it needs.
- **The Lua copy is the C++ struct's** to the byte, as far as it goes: `tools/abi_check.py` checks each field
  it shares, and that it is no larger.

The addons released before 1.0 (buff 1.0, name 1.32, party 0.2, chatbox 0.15) asked for exact sizes: the first
plugin that grows a block needs them updated once. From 1.0 on, never again.

## Adding to a block, step by step

1. Add the field at the end of the C++ struct (or a new parallel list, for records). Nothing before it moves.
2. Fill it in the plugin; if addons write it, 0 must mean the old behaviour.
3. Add it at the end of the Lua copy, and read it only behind `abi.Has` (or a feature bit).
4. `python3 tools/abi_check.py`: it must still pass. The baseline is not refrozen.
5. Say in the plugin's CHANGELOG which field, from which version, so an addon can name what it needs.

## 2.0

A change these rules do not allow — a field moved or gone, a record grown, a Version changed — is 2.0: every
addon that reads that block is updated with it, and the baseline is frozen again as `layout-2.0.json`.
