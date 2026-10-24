# uihook

One Ashita v4 plugin that changes the game's own interface. Addons hand it their own **buff**, **party/alliance**,
**target**, **clock**, **compass** and **chat log** drawing to stand in for the game's, each independently; and it
changes the game's **menus** themselves: drawn with a skin's textures and fonts (`/uihook skin`, set by
`addons/nativeui`), moved and scaled (`/uihook native`, nativeui), or left undrawn for `addons/menus` to draw
again (the mirror). Replaces loading `buffhook` and `partyhook`; the addons remain separate. Loading uihook
without any of that asked for leaves the game's drawing unchanged.

## Build and install

```sh
plugins/uihook/build.sh                 # the plugin as it is played with
plugins/uihook/build.sh --diagnostics   # with the census, texture census, label dumps and watch built in
```

Uses the same clang-cl/lld-link, x86 Windows SDK/MSVC and Ashita SDK toolchain as the previous plugins
(default `.toolchain`; overrides: `TOOLCHAIN`, `ASHITA_SDK_PATH`, `MSVC_PATH`). Output:
`plugins/uihook/build/uihook.dll`.

Unload addons and old hooks **before replacing DLLs**:

```text
/addon unload buff
/addon unload party
/addon unload clock
/unload buffhook
/unload partyhook
/unload uihook
```

Copy the built DLL to your Ashita `plugins/` directory, deploy the updated buff/party addons, and
replace old hook load commands in your startup script with:

```text
/load uihook
/addon load buff
/addon load party
```

Buff uses its existing anchored-bar setting. Party replacement stays default-off:

```text
/addon unload hideparty
/pt native on
/pt native target on
/pt native status
```

Party and target opt-ins are independent. **Do not run hideparty with either native Party mode.**
Organize still uses ordinary ImGui windows. Native party positioning remains gated off, as in
partyhook's testing build. Existing styling, positions and saved settings are unchanged.

Updated addons prefer uihook, but can still use their legacy plugins when uihook is absent.
Do not load old and new plugins together. Uihook refuses initialization if either legacy DLL is
present. Rebuilt legacy plugins also reject loading while uihook is present; older binaries do not
have this guard, so remove their startup commands. To revert, unload the addons and uihook first,
then load the legacy plugins and reload the addons.

## Clock and compass

The [clock addon](../../addons/clock/README.md) writes the clock on one line in place of the game's
text, keeps the game's icons and hides the compass through the compass slot. Deploy winxi 5 and
`/addon load clock` after loading uihook. **Unload hidecompass first**: it hides the shared native
object and prevents both clock and compass render boundaries from running. Enable the native clock
in the client. Radar can remain independently on or off. No compass addon/UI is included yet.

`hud.h` discovers the shared native compass object via hidecompass's update-step signature, verifies
its tail jump to `Compass::Draw`, then cross-checks BOTH clock CALLs (radar-on/off branches) against
`Clock::Draw`. Clock detours steal six whole non-relative instruction bytes and preserve `this` plus
two signed stack coordinates (`ret 8`). A separate signature verifies the native radar-visibility
query before compass replacement can be advertised. Optional native weather discovery is bounded to
the clock function and its in-module global; failure leaves weather unavailable, not clock disabled.
No fixed addresses or persistent native visibility/opacity writes are used.

Clock::Draw makes one text call, `Text(x-50, y+26, "%d:%02d  %s", colour)` (cdecl, four arguments),
then draws the day icon at (x-68, y+26) and, for weather 4 to 19, the weather icon at (x-68, y-42),
twice side by side for double weather. `CLOCK_TEXT_PATTERN` finds that call, unique and within
Clock::Draw's first 0x100 bytes, and it is aimed at uihook's own (still a CALL, so the return address
is the game's). With a fresh clock replacement only the text gives way: the game's text call still
runs with its GPU submissions blocked, which is how its screen bounds are measured, and the icons
draw as ever. Without the call found, the whole of Clock::Draw is replaced, icons and all.

The three icon calls, `Sprite::Draw(this=sprite, x, y, colour, 0, 0)` (thiscall, five stack words,
`ret 0x14`), are found the same way, all three or none, each inside Clock::Draw and each calling the
one sprite routine, and aimed at uihook's own. Each icon is measured on the screen, drawn or not
(`IconRect`). The game's day or weather icons (both weather icons for double weather) are left
undrawn only for those the addon names in `HideIcons`, and only while its clock replacement is drawn
in that call: an addon that stops, fails or is unloaded has the game's back at once.

For the preview, Clock::Draw's two calls to the sprite banks' getter (`Bank(n)`, cdecl, `banks[n]`
for n below 18, else 0; a bank's first word its sprites) are found, its day bank (4) and its weather
bank (14), both to the one getter; without them there is no preview, and nothing else is lost.

The dispatcher runs original native logic with GPU submissions suppressed only while a fresh
replacement is being drawn. Nested clock calls temporarily escape compass suppression; with only a
compass replacement, the stock clock still draws, and with only a clock replacement, the stock
compass still draws. Radar-disabled/unsupported-zone checks gate compass replay. Native clock-enable
and shared visibility states gate clock replay. Missing signatures or replay failure leave the
unsupported element native. HUD discovery does not depend on party/window recognition.

### HUD ABI 6

A third, independent block in `uihook.dll`: `UIHOOK-HUD` padded to 16 bytes, **164 bytes** total:

```text
char Magic[16]
u32 Version, Size, SupportedMask, Frame, Submit
u32 DrawnFrame[2], NativeFrame[2], Weather
float ClockRect[4]; u32 ClockRectFrame
char Grid[12]
float IconRect[3][4]; u32 IconFrame[3]
u32 HideIcons            written by the addon
i32 WeatherShift; u32 PreviewWeather; float WeatherScale   written by the addon
```

`SupportedMask`: bit 0 clock, bit 1 compass. `Submit` is `cdecl int(index, capture)` and may only be
called on the render thread while the matching DLL/ABI is loaded. Index 0 clock, 1 compass;
capture 1 synchronously captures/consumes the current ImGui window, 0 renews intentionally empty,
-1 releases that slot. Index -1 releases both HUD slots **only**, never Party's slots. Party's own
release-all likewise cannot release HUD slots. `NativeFrame` records the last eligible native
boundary; `Weather` is a native ID (0xffff unavailable), sampled at `NativeFrame[0]` and expiring
with that timestamp. `ClockRect` is where the game wrote its clock's text (left, top, right, bottom), taken
from the screen-space draws of its text call, replaced or not (all of Clock::Draw's draws without the
call), and turned into ImGui display pixels by the inverse of replay's mapping; current at
`ClockRectFrame`. A replacement drawn below the clock would be covered by what the game draws after
it, the chat log among them. `Grid` is the map grid the game prints after the time, `(H-9)`, copied
from the clock's object (+0x11, eight characters, then zeros) at `ClockRectFrame`. `IconRect` is
the day icon (0), the weather icon (1) and the second weather icon (2), as `ClockRect`, each current
at its `IconFrame`. `HideIcons` is bit 0 the day icon and bit 1 the weather icons; the bridge writes
it each frame and clears it as the clock slot is released. `WeatherShift` moves the game's weather
icons down (up, below 0) by that many of its units, at most 200 either way: added to the `y` their
calls are given. `PreviewWeather` names game weather icons (bit 0 fire, 1 ice, 2 wind, 3 earth,
4 thunder, 5 water, 6 light, 7 dark, its sprites' order) to draw after the day icon, each in its
place in a row from the weather icon's (68 units above the day icon's, shifted), a sprite's width and
two apart; they are not measured and never hidden. `WeatherScale` (0.25 to 4; 0 or 1 as the game
draws them) grows or shrinks the game's weather icons and the preview's: each screen-space draw made
from memory in their calls is drawn again by uihook from a copy, its positions scaled about the
first weather icon's middle as last measured (each preview icon about its own, the row spaced for
them), and the game's draw blocked; anything else is left as the game draws it, and the icons are
measured unscaled. All are honoured as `HideIcons` is, and cleared with it. Geometry limits,
clipping, font validation, texture retention and two-frame
freshness reuse the existing capture/replay implementation. Addons should use the slot-specific
`winxi.nativehud` bridge, which validates ABI, capability, unload/reload and weather, place and grid freshness.

## Chat log and input replacement

`src/modules/chat/chat.h` uses the two-window signature researched in
[chatdiag](../../archive/addons/chatdiag/FINDINGS.md). It re-follows each window's `+08`
menu pointer on every native draw and verifies `menu logwindo`. Primary and split logs
are independent; recognition does not require the party signatures. The existing
`Window::Render` detour and GPU filter are shared, not patched twice.

An addon can hide a whole native log (including its background, text and mode tab), or
write over it with its own captured ImGui window. This does **not** edit messages, chat
mode, input history, input-open state, or the log's open/close timer. Native logic
still runs. The primary slot also serves the verified native `fulllog` boundary, but only
for every page of each channel tab; scrolling, nested menus and the row-action menu stay native, and neither they nor mouse-hover cursor movement release the skin.
A third, independent input slot
replaces `menu inline` using chatdiag's active-menu signature (operand at +16), an
in-module pointer slot and the exact menu header name. Missing or ambiguous input
recognition leaves the input native without disabling the logs. No visibility-byte
writes, keyboard interception or changes to the native input controller are made.
This is not a background-only or label-only hiding control.

Use `require('winxi.nativechat')`, with one bridge per log/input slot (WinXI 12+):

```lua
local nativechat = require('winxi.nativechat')
local chat = nativechat.new(nativechat.Primary) -- Secondary for split chat

-- In your render callback, every frame:
chat.Begin() -- intentionally empty: hides this native log while it is drawn
-- Or build your replacement inside an ImGui Begin/End pair, then call
-- chat.Capture() after drawing, before ImGui End. Only capture if Begin succeeded.

-- On disable/unload:
chat.Stop()
```

`Begin` renews a hidden replacement; `Capture` copies and consumes the current ImGui
window's draw commands. Failed chat captures release the slot. Use `Stop` to restore
it immediately; otherwise submissions expire after two presented frames. Stop on addon
unload, and call Begin only while replacement is enabled. Replacements use the addon's
submitted screen coordinates, not automatic chat anchoring, and follow native draw
eligibility: closing the log or switching to expanded chat does not force it open.
Do not run FancyChat, hidechatbg or other chat-visibility writers alongside replacement:
they can close the native log or change what native restoration looks like.
The [chatbox addon](../../addons/chatbox/README.md) supplies a compact log, native selection highlight,
a WinXI frame, WinXI tabs, scrollbar and rows of text where the game's are (or theme-tinted native controls
and the game's own text) around the actual native expanded browser, and a native-backed WinXI input bar.
The plugin itself does not collect chat messages or own keyboard input.

### Chat ABI 13

Independent `UIHOOK-CHAT` marker padded to 16 bytes, **71684 bytes** total (update DLL and bridge together):

```text
char Magic[16]
u32 Version, Size, SupportedMask, Frame, Submit
u32 DrawnFrame[3], NativeFrame[3]
float InputRect[4]; u32 InputRectFrame
float PrimaryRect[4]; u32 PrimaryRectFrame
float ReplacementRect[4]; u32 ReplacementRectFrame
float ExpandedRect[4]; u32 ExpandedRectFrame
u32 StateFlags, StateFrame
u32 FullScroll, FullCursor, FullPageRows, FullFilter
u32 ControlStyleFrame
float ControlColors[4][4]  // highlight, tab, cursor, scrollbar; RGBA [0,1]
u32 ReplaceControls         // Lua-owned: 1 tabs, 2 scrollbar, 4 text left undrawn, the addon drawing its own; 8 all of it
u32 TabFrame, TabCount
struct { float Rect[4]; u32 Channel, Selected; } Tabs[12]  // the game's tab strip as last drawn
u32 ScrollFrame, ScrollPage, ScrollCount, ScrollTop        // its scrollbar: page rows, rows, rows above the view
float ScrollRect[4]
u32 TextFrame, TextCount, TextSerial                       // its rows of text as last drawn, newest first; the serial moves when they change
struct { float Rect[4]; u32 Offset, Length, Mode, Flags; } Rows[128]  // each row's place, its text's place in Text, its chat mode, flags
char Text[65536]                                           // the rows' text as the game was given it: CP932 with 1E/1F colour codes
float SplitRect[4]; u32 SplitRectFrame                     // the game's second log window's bounds, as PrimaryRect
u32 WindowFrame, WindowFlags                               // the two log windows' routing, read each frame: 1 the second window is shown
u32 WindowModes[2][8]                                      // per window, a bit for each chat mode (its low byte) its filters keep
u32 LinesFrame; u32 Lines[2][3]                            // per window: its lines now, its most and its fewest, read each frame
u32 ColorFrame, ColorSerial; u32 InlineColors[17]          // the game's chat colours, read each frame; the serial moves when they change
u32 CategoryColors[256]; u8 ModeCategory[256]              // each category's colour (components of 80 as one), each mode's category
```

Submission bits/indexes: 0 primary (compact OR expanded), 1 split, 2 input (`nativechat.Input`).
SupportedMask bit 3 advertises verified expansion state/geometry; bit 4 advertises the verified
full-log content Draw hook. Bit 5 advertises the optional verified control-art CALL sites, and
bit 6 that the tab strip and scrollbar are measured and can be left undrawn (the same group of sites);
bit 7 that the rows of text are decoded and measured and can be left undrawn (the row site, taken only
with bit 6); bit 8 that the game's routing between its two log windows is read (which chat modes each
window's Log Window settings keep, and the second window's bounds), nothing of it hooked or written: the
client's keep check is recognised and its decision made again from the config words it reads (B9/BA the
first window's, BB/BC the second's), its mode table and its category cases; a mode word with bit 15 set
goes to the first window alone, and while the second window is hidden the first keeps everything.
`primary.Routes()` gives the sets and `nativechat.Shows(routes, window, mode)` applies them;
`split.Rect(w, h)` the second window's place. Bit 9 that each window's lines are read from its owner
(`Lines()` on the primary and split slots: its lines now, as the game grows a row a message and shrinks
to its fewest while none come, its most and its fewest), the fields pinned by the owner's Update and
grow signatures and checked for sense each frame. Bit 10 that the game's chat colours are read, as
configured: each mode's category, each category's colour (what the game draws a message of that mode
in, and what a 1E code past the palette or a 1F code names) and the inline palette's seventeen colours
(`Colors()`: `Mode(mode)`, `Inline(bank, slot)`). Bit 11 that the full log can be mirrored whole
(`State().nativeMirror`; `replace.all`, ReplaceControls 8, granted only with the tabs and text): its
content and Window::Render's cursor, scrollbar and row-selection art all left undrawn, still measured,
the rows' cursor, pressed and marked flags saying what the addon draws in their place. None is an additional submission slot. `Submit` is render-thread-only
`cdecl int(index, capture)`: 0 renews empty, 1 captures compact/input contents, 2 captures a
**frame-only expanded skin** (primary slot only, requires bit 4), and -1 releases that slot.
`primary.Capture(true, colors, replace)` requests mode 2, optionally publishing the four RGBA control
colours before stamping ControlStyleFrame, and which controls the addon draws itself
(`{ tabs = true, scrollbar = true, text = true }`, ReplaceControls). Missing/invalid colours leave controls native. The
plugin validates and copies the style, and the replace bits, only with a successful current-frame
expanded capture and only where the hooks each needs are; a compact capture or a release clears both.
Older bridges/DLLs are rejected; interpreting a frame-only capture as whole-window replacement
would hide text. Index -1 releases all three **chat slots only**. Party/HUD release-all
cannot release chat slots. Frames use the same clock as Party/HUD; the bridge validates
DLL/ABI/capability and exposes `Ages()` and `Status()`. `/uihook chat` reports recognition
and last native/drawn frames; `/uihook` includes fresh chat replacements, and any slot whose
capture is being refused, with the reason (`PartyRefusal`, `src/slots.h`), how many in a row and how
long ago; the first refusal in a row, and each change of reason, is a warning in Ashita's log, and a
capture taken again after refusals an info line. A refused slot is drawn by the game, with the addon's
window drawn by imgui over it, until a capture is taken; chatbox draws its second box only after the
first's capture, so it is missing while the first is refused.
`InputRect` and `PrimaryRect` are the viewport-normalized native input and primary log
rectangles (left/top/right/bottom), each read after its layout update using the verified
`Window::GetRect` coordinate source. `ExpandedRect` uses the same normalized format and
is recorded only at the verified full-log boundary; `NativeFrame[0]` records either primary boundary.
Menu-manager geometry discovery is independent of party recognition; missing geometry
leaves the rectangle frames unavailable, without disabling capture. The input/primary bridge's
`Rect(displayWidth, displayHeight)` returns its own bounds in ImGui pixels only while fresh
(two frames), or nil. The primary log anchors at its native rectangle's bottom-left,
with its ten compact rows growing up. `primary.Rect(w,h,true)` reads the independent
expanded bounds. No native positioning writes or font-metric guesses are published.

`State()` returns fresh native focus/expansion information. StateFlags bits 0/1 select the
primary/split log only when that window is the active native menu and has cursor enable/focus
bytes +0x62/+0x63 set. Bit 2 is the existing menu-manager +0xF1 > 2 expanded state, found by
the same signature as `winxi.game.IsChatExpanded`. Bit 3 requires full native fallback:
invalid layout data, unsupported full-log discovery or another menu active before the full log is
made. Bit 4 notes a menu open over the live full log (a row's actions, the input line): the log keeps
its skin under it, the menu being the game's own. Nonzero scroll
and cursor movement no longer trigger fallback: all pages retain native contents and behavior.
During opening/closing, no fresh expanded rectangle means no frame skin. Other addons' native
expanded-chat hiding rules remain untouched; no controller input or native expansion flags are rewritten.
`State().nativeContent` reports the bit-4 content-hook capability; `nativeControls` reports bit 5 and
`nativeReplace` bit 6. `primary.Tabs(w, h)` gives the game's tabs as last drawn in a skinned full log,
left to right, each with its bounds in ImGui pixels, its channel (the filter's number, nil where its
sprite is none of the owner's) and whether it was drawn chosen; `primary.Scrollbar(w, h)` the game's
scrollbar's bounds and its page, count and rows above the view. Both only while fresh (two frames),
and nil when the game drew none, so an addon asks for a control to be left undrawn only when it has
a place to draw its own. `State().nativeText` reports bit 7, and `primary.Rows(w, h)` the game's rows
of text as last drawn there, newest first: each its bounds in ImGui pixels (nil where it drew nothing
and its place was not known), its text as the game was given it (CP932 bytes with the game's 1E/1F
colour codes), its chat mode, and whether the game's cursor is on it, whether it is held down, whether the game marks it and
whether it was cut; the same table again while the rows are what they were.

Full-log discovery cross-checks the three adjacent logwindo/logwin2/fulllog registry entries
against the primary/split pointer signature. A unique constructor identifies the full-log
owner vtable; unique Open/Update field-access patterns validate cursor (+0x1C), scroll (+0x20),
filter (+0x54, the tab's channel number, 0 to 15 accepted and published as FullFilter) and page rows (+0x58) against that class's Update method (vtable +0x28) before any such reads are used.
Unknown layouts stay native. All live object pointers are re-followed through guarded reads.
A unique content Draw prologue is additionally cross-checked against full-log vtable +0x10
before its five whole instruction bytes are detoured. The dispatcher replays mode-2 captures
**only at the full-log window**, blocking its stock decoration. At the verified content Draw,
GPU blocking is disabled, and remains disabled for Window::Render's subsequent native cursor
and scrollbar. The outer render scope restores the previous blocking state. Thus the game's
actual rows, tabs, positions, colours and row actions are preserved without approximating native
row offsets. The expanded skin has no custom title.
Compact and expanded captures cannot replay across boundaries; empty mode-2 submissions cannot
suppress a full log. Missing content hooks leave native expanded drawing intact, while compact
replacement remains available. Expanded spacing is native; the text is the game's own unless the
addon asks for its own, drawn row for row where the game's rows are.
Optional control styling redirects **six CALL sites only**: the full-log tab sprite call,
Window::Render's row-selection sprite call, cursor sprite call, scrollbar Draw call, the full
log's call to its whole tab strip (its content Draw's first call: thiscall with the filter on the
stack, ret 4; the pattern's own bytes keep ecx the owner up to the call), and the one row-drawing
call inside the log drawer the content Draw calls at +AA (cdecl: the row's text, its 60-byte header
by value, x, y, alpha, the cursor flag, an out pointer and a zero, 22 words the caller takes back).
Each unique site is checked against its parent function and native callee; the five control sites
are verified before any is patched, and the row site on its own, taken only with them. Shared
sprite/scrollbar/tab-strip/drawer/row-draw routines are never patched. The native five-word tab and
eight-word window-sprite ABIs retain all geometry, float bits and flags; only colour changes.
Selected tabs are identified by the native owner's selected-tab sprite, not guessed tab ordering.
The row-selection draw alone bypasses frame suppression, then restores it. Scrollbar Draw reads
its first 40 bytes, so it receives a temporary copy with only the two colour words changed; native
range/page/offset/scale and mouse state are untouched. Sprite colour unity is 128; alpha retains
native pulse/fades. Theme changes never recolour message text or other windows' controls.
Native artwork is tinted where it is drawn. Where the addon draws its own tabs or scrollbar, the
strip's or the scrollbar's GPU submissions are blocked for that call alone (labels and art alike),
while each tab sprite call and the scrollbar Draw are measured from their screen-space vertices,
drawn or not, and published normalized to the viewport they were drawn in; whose tab a sprite is
comes from the owner's tab sprite table (+0x80 plain, +0x84 chosen, by channel), and the
scrollbar's page/count/rows-above from the fields the verified Update pattern writes (+0x0C, +0x10,
+0x14), read only. Hit-tests, Square selection, the wheel and the native objects are untouched. Where the addon draws its
own text, each row-draw call's submissions are blocked the same way (its glyphs and the cursor's mark),
while the row is measured from its glyphs' vertices, its header read from the by-value copy and its glyph
words read, guarded, from the history ring and decoded by the exact inverse of the client's encoder
(`glyphs.h`: a single byte is its glyph and 20, a two-byte character the lowest SJIS code encoding to its
glyph, glyph 5F a space, glyphs 2115–2143 the pictographs EF 1F–EF 4D; 1E/1F colour words become their
codes, 7F controls nothing). The game's marker sprites under rows, its row highlight, cursor and every
hit-test are untouched, and the compact logs' rows pass through the same site as the game's.
Missing control signatures leave controls native while frame/content support remains independent.
See [discovery notes](src/modules/chat/FINDINGS.md) for static-client evidence and live checks.
Optional private-client verification: `python3 plugins/uihook/tests/check_chat_client.py /path/to/ffximain.bin /path/to/ffximain.txt`.

`ReplacementRect` is the actual captured primary ImGui window rectangle in **ImGui pixels**,
not native normalized coordinates, sampled by the plugin on a successful nonempty capture.
Empty, released or failed primary submissions invalidate it. With fresh capture, native
boundary, native rectangle and successful primary replay timestamps, Clock::Draw's GPU
submissions are translated by the difference between replacement and native log top-lefts.
This moves the native clock **and its icons** as one group while retaining native spacing
above chat. It never moves the compass, never changes native positions and stops when the
log is released, expires or is expanded. Only copied screen-space UP vertices are changed (indexed UP
requires minimum vertex 0); unsupported draw paths/shaders are left native. HUD clock/icon
rectangles include the translation, so the clock addon's replay/custom icons follow too;
its already-positioned replay is not translated again. Weather scaling and translation
compose on the copy, leaving the game's original vertices untouched.

Offline fixtures check chat discovery ambiguity, invalid/aliased globals, menu-name
validation, null/recreated children, bad pointers, native focus, verified full-log layouts,
compact/expanded capture isolation, content-hook signature/vtable checks, native GPU pass-through,
scroll/filter continuity and menu handoff; Lua fixtures check ABI,
slot isolation, capture failure and unload/reload. **Live GPU validation is still needed**:
primary/split, expand/collapse, input/mode changes, zoning, UI hide/show, resolution/font
changes, device recovery, stale submissions and addon/plugin unload/reload.

## Chat-owned panel / native action-menu anchor (0.6)

Chatbox 0.11.1 / Winxi 22 optionally publishes its completed panel bounds after a successful compact
chat capture. `winxi.nativemenus` uses the independent **menu ABI 1**, magic `UIHOOK-MENUS`:
108 bytes: Magic[16], Version, Size, Frame, Supported, RequestFrame, HostSlot, Panel[4] in pixels,
MenuFrame, Applied, Restored, LastName[16], LogRequestFrame, LogPlace[2] in pixels, LogFrame,
LogApplied, LogRestored. Chat ABI remains 13. No publisher means no menu changes.

The **expanded chat log** (`fulllog`, the owner global the chat module recognises) is placed the same
way: while LogRequestFrame is fresh (eight frames), its target is moved before its own Update so its
bottom-left is at LogPlace, its size the game's; moved left or down as far as keeps it on the screen,
and left where the game puts it when taller than the screen. Its rows, tabs, scrollbar, cursor and
hit-tests are laid out there by the game. It has its own request and restore, independent of the
menus' (expanded chat does not stop it); a stale request, release or unload gives the game's place back
to a still-live matching window. `PlaceLog(left, bottom)` and `StopLog()` in `winxi.nativemenus`.

The plugin verifies Window::Render's first CALL is the unique Window::Update and pins its four
short target fields (+8C/+8E origin, +90/+92 size) against native shape writes. It discovers only the
registered command (`playermo`), magic, ability, inventory/item-use, associated control and event-choice (`query`) owners;
no fixed process addresses. Live owner→Window (+8), header identity/prefix, writable fields, bounds,
scale mode and menu-manager dimensions are checked. Before the native renderer, it changes the
native origin target to align left with the panel and end 2px above it. Native Update rebuilds the
frame, sprites and row origins, so native cursor/hit geometry uses the same coordinates. No GPU
translation, mouse remapping, selection writes or fake input. Positional animations may snap.

Requests expire after eight frames (`CHAT_REQUEST_FRAMES`), and the host log's replay after two; expanded chat also disallows them.
Opt-out, zoning, disabled/failed chat replacement and plugin unload restore only owned origins in
still-live matching windows and rebuild native geometry. Newer game-written targets are preserved.
Unknown client signatures/owners, invalid bounds and menus too tall to fit above the panel remain
native. `/uihook menus` reports support, source frame/host, apply/restore counts and the last owner,
and the expanded log's request, place and apply/restore counts.

This is experimental. Static client-signature checks and fixture tests do not replace in-game
mouse/controller, action selection, open/close, scale, cutscene and unload checks. Unload uihook
before copying the rebuilt DLL; never overwrite a loaded plugin.

## The game's chat history (0.6)

`winxi.nativehistory` uses the independent **history ABI 1**, magic `UIHOOK-HISTORY`: Magic[16],
Version, Size, Frame, Supported, RequestFrame (Lua's), Serial and ReadFrame (moved with each read),
Count, Used, Lines[100] (Offset, Length, Mode, Serial, Flags, Extra) and Text[65536]. Asked, uihook reads
the first log window's ring once (its owner's +18; +14 newest, +16 oldest, +1A count, 100 lines of 2 KB
from +20) oldest to newest, each line decoded with the expanded log's decoder to the bytes the game was
given (CP932 with its 1E/1F colour codes), with its whole mode word, serial (+0C), flags (+15) and +38 (on a
message's lines after its first the game clears +38 and masks the flags to 0xB0). Nothing is called or
written. `/uihook chat history` prints the newest 12 lines with those fields.

## Each chat line after every addon (0.8)

`winxi.nativetext` uses the independent **text ABI 1**, magic `UIHOOK-TEXT`: Magic[16], Version, Size,
Frame, Serial and Events[64], each Serial, Mode, FinalMode, Flags (1 injected, 2 blocked, 4 indent, 8
modified, 16 cut), OriginalLength, FinalLength, Original[4096] and Final[4096]. uihook takes Ashita's
own incoming-text event (PluginFlags::UseText) and records each line given to the game's chat log as
it stands at its turn: the bytes the game was given and the bytes it will keep, with both modes. Ashita
hands plugins the event in load order and the Addons plugin runs the Lua addons inside its own turn,
so a uihook loaded after `addons` sees each line after every addon, whatever their order. An addon
whose own `text_in` handler runs before a formatter's (chatbox loaded before SimpleLog) reads the line
here instead. The line with serial s is at Events[(s - 1) % 64], written whole before its serial is;
a reader keeps the last serial it read and takes the ones after, at most a ring's worth. The block is
zero in the DLL's file, its magic written as the plugin initializes, so the half-megabyte ring costs
the file nothing. Nothing is read from the game or written to it, and no line is changed or blocked.

## Diagnostics: built with `--diagnostics` (1.58)

The menu census, the texture census, `/uihook mirror labels` and `/uihook mirror watch`, and the watch block
`tools/uihook_live.py` reads, are the tools the mirror and the skin were found with. They are built in only by
`./build.sh --diagnostics` (`src/modules/mirror/diagnostics.h`); the plugin as built by `./build.sh` answers
their commands with how to build them, and exports no watch. A skin is made from a texture census, so
`tools/uihook_skin.py`'s input needs a diagnostics build to take; the skin it makes loads in either.

## Menu census (0.95)

The first step toward mirroring the game's menus. The game registers about 370 menus, all drawn by
Window::Render: the frame first, then the menu's own content through its owner's vtable +10, then the
cursor and scrollbar. A mirror keeps the real menu open, its input and controller handling the game's,
blocks its drawing as the chat log's is, and hands an addon what it would have drawn: its rect, the text
it prints and where, its icons, and where its cursor is. The census finds how many ways the menus print
their contents, so the mirror is built for those rather than menu by menu.

```text
/uihook census on      start hearing the windows, written to logs\uihook-census\<date>_<time>.txt as menus are opened
/uihook census dump    write logs\uihook-census.txt
/uihook census off     stop, writing the session's file a last time (what was seen is kept)
/uihook census clear   forget what was seen
```

Text reaches the screen through three routines, each found by a unique prologue (`src/modules/mirror/census.h`):
the bitmap font's `(x, y, text, colour, sx, sy, centred)`, cdecl, each glyph a Sprite::Draw, behind
the plain `(x, y, text, colour)` wrapper with about 150 callers; its scaled sibling `(x, y, text, colour,
flag, sx, sy)` with about 130; and the rendered font's thiscall `(x, y, text, ?, colour, flags, sx, sy)`,
`ret 20`, reached through two thunks that load the font object. For each window the file gives its name,
frames drawn, content draw and vtable (offsets into the client), its kind (+10), whether it showed a
cursor (+62) or focus (+63), its layout target (+8C, four shorts), its text calls on each route, text
calls made inside others, draw calls and those made inside text calls; then the windows grouped by the
content draw they share; then up to 24 distinct texts for each, with route, place and colour. Off until
asked, nothing written to the game, released with the plugin. The census shares the one Window::Render
detour, taking it only if nothing else has.
`python3 plugins/uihook/tests/check_census_client.py /path/to/ffximain.bin /path/to/ffximain.txt`
checks the routines against a private dump.

## Texture census (1.32)

Whether the menus could be reskinned once for them all, by the pieces they are made of (frame, title bar,
highlight, hand, scrollbar, font), rather than each one drawn again. While on, every screen-space draw's
texture (stage 0) is read the first time it is seen and counted with the window drawing it and the part of
the window it is drawn in.

```text
/uihook textures on      start counting; open the menus to be counted
/uihook textures off     stop, writing logs\uihook-textures\NN (what was seen is kept)
/uihook textures dump    write logs\uihook-textures\NN now
/uihook textures clear   forget what was seen
```

Each run is a folder of its own: `index.txt` and each texture read once as `tex-<hash>.bmp`. The index gives
the textures by how many windows draw them, each with its size, format and pool, its draws by part (frame,
content, cursor, element, scroll, after, text: drawn in a text routine; outside: in no window), how many of
them came from a vertex buffer, the texture places used (all draws together, so an atlas shows how much of it
the menus take), up to eight vertex colours and the windows drawing it; then each window with the textures it
draws. Under each texture, up to 48 of its pieces as drawn (1.35): window, part, place and size on the screen,
the texture places at the piece's top-left and bottom-right corners, colour, and how many were alike.
`glyphs.txt` (1.37): each print matched to the pieces it drew, where they are as many as its characters (spaces
drawn or not) or a whole number of times as many, gives each font texture's glyphs by character, with their
texels and size on the screen. Textures with the same pixels are one, wherever the game keeps them; a pointer unseen for 120 frames is
read again, as the game may have made another there. One that cannot be locked (the default pool) is
counted by its size and format. At most 128 MB of pixels are kept. Off until asked, nothing written to the
game (`src/modules/mirror/textures.h`).

## Skin (1.33)

The game's own interface drawn with other pictures in place of its textures: every menu at once, its layout,
input and places the game's own. A skin is a folder, `config\uihook\skins\<name>\`, of pictures named for
the game textures they stand for as the texture census names them, `tex-<hash>.png` (or `.bmp`, 24 or 32 bits,
alpha kept), any size: a draw's texture places are a share of its texture, so a picture twice the size is drawn
twice as fine in the same place. The edge and background textures are tiled (texture places past 1), so their
pictures must tile.

```text
/uihook skin <name>     load config\uihook\skins\<name>\ and draw with it
/uihook skin reload     load the same again, as its pictures are changed
/uihook skin off        the game's own textures
/uihook skin            what is loaded, how many of its pictures the game has drawn, and those not drawn yet
/uihook skin font <menu|title> <file|off>   the skin's menu or title font drawn in a font of Windows' Fonts, or its own
```

Some of the game's art is coloured by its vertices, one texture in several colours (the button bars blue-grey or
orange). A skin may say what those are drawn as in `skin.txt` beside its pictures, a line each:
`<hash> <RRGGBB or *> <RRGGBB>` (`9E2854A3 616180 3C3C52`): a draw with that texture, its vertices of the game's
colour (any, for `*`) drawn in the other, their alpha the game's; the first line that fits is used. A colour of eight
digits, `AARRGGBB`, sets their alpha too (1.36): the game fades its frame by its vertices' alpha, its sides near 0
and its top and bottom 0x61, so a frame even all round sets one. Only for
draws from memory; the status counts the draws recoloured.

A picture may come in sizes (1.49): `tex-<hash>@<factor>.png` beside `tex-<hash>.png`, the game's size. Each draw is
measured (how many pixels a texel covers, as its window is scaled) and drawn with a size a texel to a pixel,
unfiltered; where none is, the smallest about twice as fine, filtered without its levels; its levels only for one
shrunk further than 2.6 times.

A game texture is known by its pixels (the census's hash), read the first time its pointer is seen in a
screen-space draw, and again where it has not been seen for 120 frames. For a draw whose texture the skin has a
picture for, stage 0 is given the picture, the draw made, and the game's texture put back; the census and the
mirror see the game's own. A skin is loaded by command, each time uihook is loaded (an Ashita script can do it).
`python3 tools/uihook_skin.py <census folder>` makes a test skin by recolouring the chrome the first census
found (gold frame, red background, green hand, amber buttons) into `plugins/uihook/build/skins/test`, to be
copied to `config\uihook\skins\test\`; `--style winxi` makes `skins/winxi` from the winxi theme file
(`config\addons\winxi\theme.lua`, or `--theme`) and winxi's own images: the frame the Border Style's art as winxi
draws it (a nine-slice, its outer 8 of 64 texels in 3 pixels) laid on the game's 3-pixel line 1 pixel in from
the edge, as wide as `--frame-width` (1 pixel by default, 3 the game's whole line), at the game's size, its alpha
`--frame-alpha` (20 hex by default, `theme` for the Border Opacity), at the Border Opacity all round; the Background Style (the Background Color with
`lines.png` over it for FFXI-inspired, a tinted tile for the others); the buttons in the Tab Style's art, and a
`skin.txt` colouring the game's blue-grey bars as a tab not chosen and its orange ones as the chosen tab; the hand
and item boxes in the border's steel; the menu font (`30CDD9D4`'s large font, the menus' labels
and lists) in the theme's Font (`--font` for another, from the game's `C:\Windows\Fonts`), each glyph drawn where the
game's was, on its baseline at its height with the game's dark edge, the game placing and spacing them as ever. The title font (`5218C635`: the windows' titles, the jobs' and races'
names) in the theme's Title Font the same way, each letter on its row's baseline, each word fitted to the game's.
Every picture is made at several sizes, `tex-<hash>@<factor>.png` (0.5 to 2 times the game's); uihook 1.49 draws
each draw with a size whose texels are its pixels, unfiltered, or else the smallest about twice as fine, filtered,
so the menus stay crisp at any Menu Scale up to 2. The game's art stays out of the repository (`src/modules/native/skin.h`).

## Menu mirror (0.96, ABI 2 in 0.97, ABI 3 in 1.0, ABI 4 in 1.1, ABI 5 in 1.2)

The real menu stays open and keeps its input; an addon draws its own from what it would have drawn.
`winxi.nativemirror` uses the independent **mirror ABI 5**, magic `UIHOOK-MIRROR`, 84632 bytes
(`src/modules/mirror/mirror.h`): the addon writes up to 128 window names (`menu    inventor`) into
`Requests`, a bit of `Hide` (four words of 32) for each the game is to leave undrawn, then `RequestFrame` as the commit,
every frame; four frames after the last the game draws them all again. As each frame is presented,
uihook publishes what the requested windows drew in it (`Published`): for each window its name, flags
(cursor shown, focused, hidden, contents drawn), its frame's place, the cursor's, the row highlight's
and the scrollbar's where drawn (and the scrollbar's rows shown, rows and rows above, read), the game's
layout target; the element the cursor is on (0.98: Window::Render draws a window's list of elements,
its labels, buttons and icons, before the contents, the cursor's tinted, each published as a quad of
phase Element); its runs of text (the bytes the game was given, to the line's end, its colour, the
place it was asked for in the game's units and the place measured from its glyphs) and its quads (each
draw of the game's art in the contents: its place, its corners in its texture, its colour, and the
texture, an `IDirect3DBaseTexture8*` held by uihook until the next frame is published). Places are
normalized to the viewport, as the chat rectangles are. Up to 16 windows, 512 runs, 512 quads and 32 KB
of text a frame; what does not fit is counted in `Dropped`.

Window::Render's one call to a window's contents, `mov edx,[ecx]; call [edx+10]` (five bytes), is made
a call to uihook's, which makes the same call (the return address the game's, the owner in ecx), so
each draw is known to be the frame's (before), the contents' (in it) or a control's (after: the cursor,
row highlight and scrollbar, told apart by the chat controls' call sites where those were found). The
three text routines the census found say what is printed. A hidden window's draws are blocked through
the same GPU filter the other replacements use, after being measured. No cursor, selection or layout is
touched.

The mouse (1.2): the addon also writes, each frame, where up to 16 menus are drawn other than where the game
puts them (`Mouse`, each the drawn place then the game's own, normalized; `MouseCount`, then `MouseFrame` as
the commit, holding four frames as a request does). The game reads mouse messages in its own message loop,
from the MSG, before Translate and DispatchMessage (its window procedure gives them to Windows); uihook takes
that handler (`MIRROR_INPUT_PATTERN`, `src/modules/mirror/mouse.h`) and gives it a move, press, release or
double click on a drawn menu at the same place on the game's own, `lParam` and `pt` moved. The wheel's place
is the screen's and is left as it is (the game scrolls where its cursor is). Ashita, imgui and addons see the
message as it was. `Supported` bit 2 says the handler was found. `/uihook mirror` reports what is asked and the last frame published; `/uihook mirror labels` writes
its elements, cut from their textures, to `logs\uihook-labels`. Only
screen-space `DrawPrimitiveUP` draws are measured. The census is off until `/uihook census on`, each time written to `logs\uihook-census\<date>_<time>.txt` as windows
are seen. `/uihook mirror watch` (again to stop) writes
`logs\uihook-mirror-watch.txt` as it changes: each window drawn, whether it was asked for and mirrored, how its
draws were made, and what was published; `/uihook mirror mark <words>` notes a moment in it. The `menus` addon draws the item lists and the item
description box in the winxi look.

## The native look (1.25; drawn moved in 1.29)

The game's own menus drawn moved and scaled rather than drawn again: the menu stays the game's whole (its
controller input, cursor and text). `addons/nativeui` gives it its settings.

```
/uihook native                         what is set, and how much of each was drawn so
/uihook native group <x> <y> [quiet]   every window the game stacks over the chat log drawn x, y from its place, together
/uihook native group off [quiet]       those as the game draws them again
/uihook native inset <pixels> [quiet]  the top bar that much shorter at each end, every window either side moved in with it
/uihook native size <factor> [quiet]   every framed window that much larger, from its corner of the screen
```

The group (1.38) is told each frame by where the game draws each window (+3A; 1.38 read its layout target, +8C,
which for some is over the log while they are drawn elsewhere): its bottom on the chat log's top (within 8),
its left within 150 of the log's, the log itself and the input line not of it. That is the command menu, a shop's
buy and sell, yes-or-no questions, an item's description and some fifty more; a window of the same name placed
elsewhere (the main menu on the right) is left. `addons/nativeui` keeps the offset as a setting.

Only the drawing moves: every screen-space draw made while the window is drawn, its frame, elements,
contents, text, cursor and scrollbar alike, is copied, moved about the window's last frame's bounds and drawn
in its place, so it moves whole without knowing where its parts keep their places. A draw wholly outside the
window's frame (the inventory's count, up in the menu name's bar) is left where it is, and the frame is what
the window is grown from. Nothing of the game's is
written: its mouse hit-tests stay where it put the menu, and the controller works it as ever. A draw from a
vertex buffer cannot be moved, and is counted. Nothing is kept between loads.

The first experiment's commands for one window at a time (`move`, `scale` and `tint`, 1.25–1.27) were taken out
in 1.58: nothing used them once the group, the inset and the size did it for every window.

## Architecture

- `src/uihook.cpp`: sole exported plugin entry point, lifecycle dispatch and scoped GPU-filter routing.
- `src/modules/chat/`: primary/split/input recognition and independent chat ABI; uses the shared renderer.
- `src/modules/buffs/`: icon/time detours, native origin and selector cursor, textured quad replay.
- `src/modules/party/`: party/alliance/target identification, ImGui capture/clipping/replay,
  scoped stock-HUD suppression and native target-arrow exceptions. `hud.h` adds clock/compass
  discovery and scope helpers, sharing the same renderer/filter rather than installing another.
  Under the [lens](../lens) plugin's warp (0.93), each native target/subtarget arrow's tip is moved
  to where the warp shows the target (`WarpArrow` in `target.h`, from the block lens.dll exports as
  `LensWarp`, in menu-layer pixels); without lens, or with its warp off, the arrows are untouched.
  `partyhook.cpp` is the one place the game's draws and `Window::Render` come in: it does the capture and replay
  itself and calls each of the parts below in turn.
- `src/modules/native/`: the game's own menus changed as they are drawn. `skinmodule.h` (`/uihook skin`) swaps
  their textures and fonts for a skin's; `nativemodule.h` (`/uihook native`) draws them moved and scaled. Their
  logic, checked offline, is in `skin.h`, `skinfile.h`, `skinfont.h` and `native.h`.
- `src/modules/mirror/`: the menu mirror (`mirror.h`, `mouse.h`), which leaves a menu undrawn and publishes what
  it would have drawn for `addons/menus`, and `diagnostics.h`: the menu and texture censuses, the label dumps and
  the watch, the tools the mirror and the skin were found with.
- `src/drawcontext.h`: what those parts share for each draw (the device, the frame, the draw's vertex format, the
  screen's size, and whether a draw of uihook's own is under way).

This is a behavior-preserving consolidation, not a rewrite of both renderers into one abstraction.
Each module retains its own frame clock, D3D state/texture ownership, signature validation and cleanup.
One GPU filter handles party/target and clock/compass scopes; buffs intercepts separate native icon callbacks.
A missing signature disables only the affected capability. No additional global UI suppression is added.

The two existing shared blocks are now located in **uihook.dll**: `BUFFHOOK-SHARED` (buff ABI 4) and
`PARTYHOOK` (party ABI 3, 168 bytes). Marker names and layouts intentionally remain unchanged.
Each addon validates its own block; there is no new combined ABI or hard dependency between addons.
Missing/stale submissions restore native drawing after two presented frames. Fresh empty submissions
mean intentionally hidden replacement. Module-specific native behavior is not generalized away.

Implementation background and inherited limitations:
[buff protocol](../buffhook/README.md#for-the-addon),
[party capture/target arrows](../partyhook/README.md#rendering-implementation).
Future UI modules should own their recognition and native semantics; any additional use of
`Window::Render` must share the existing detour/dispatch rather than patch that boundary twice.

## Checks

```sh
plugins/uihook/build.sh
plugins/uihook/build.sh --diagnostics   # the diagnostics built in as well; both must build
plugins/uihook/tests/run.sh
luajit tests/nativehud_check.lua
luajit tests/nativechat_check.lua
luajit tests/harness.lua clock tests/clock_stand_in.lua tests/clock_check.lua
python3 plugins/uihook/tests/check_hud_client.py /path/to/ffximain.bin /path/to/ffximain.txt
python3 plugins/uihook/tests/check_census_client.py /path/to/ffximain.bin /path/to/ffximain.txt
luajit tests/party_hook_performance_check.lua
luajit tests/harness.lua party addons/party/party.lua tests/party_hook_integration_check.lua
luajit tests/harness.lua party addons/party/party.lua tests/party_native_positioning_check.lua
```

The Wine fixtures compile against the migrated modules' headers, checking signatures, detours,
restoration, clipping, arrow forwarding and party ABI. Lua bridge checks run against both legacy
DLL names and uihook. HUD fixtures cover discovery ambiguity/call-target/global rejection,
clock calling convention/trampoline/restoration, radar/clock filter independence, optional weather and
ABI. Lua checks cover slot isolation, reloads, weather expiry, clock presentation and capture timing.
These are offline checks, **not proof of live GPU output**.

In game, `/uihook` (or `/uihook addons`) lists the addons handing uihook something now, and what:
buff's bar, party's party, alliance and target windows, clock's line and its hidden compass, each
marked "(hidden)" where the addon hands over an intentionally empty replacement. A plugin cannot see
which Lua addon calls it, so this is read from the slots, each filled by one addon only, while the
last submission is fresh (eight frames). It also says which parts this client was not recognised for.

`/uihook hud` prints what the clock replacement was drawn into: Clock::Draw's calls and
position, the replayed vertices' bounds, the viewport, the render target against the back buffer,
whether a scene was open, a few of the game's render states, and the game's own clock draws (their
count, vertex format and, for drawing from memory, their screen bounds), where its text is, whether its
text call was taken and the grid. It only reads.

Live validation is required for combined buff/party/target use: menu overlap, buff selection/cursor
restoration, target/subtarget arrows, independent toggles, Organize, addon/plugin unload/reload,
cutscenes, zoning, UI hide/show, resolution/font changes and device recovery. Existing partyhook
validation gaps carry over. Clock/compass additionally
need native clock/radar toggle checks, radar-disabled zones and hidecompass removal validation.

MIT; see `LICENSE.md`.
