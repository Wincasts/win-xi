# Chatbox — experimental 0.7

A basic **WinXI-styled replacement for the native chat log**, the **size of the game's own
log** when compact (it follows the game's chat size setting), with a native-controlled expanded
view. New messages appear at the bottom; long messages wrap and count as rows. Uses WinXI's shared/local typeface, background and border art, with compact
**12px text** and **3px padding** by default. Text Size is adjustable in `/chatbox`.

This first version is intentionally small:

- The log takes the native primary chat window's place and size: as many rows as fit at Text Size.
- Built-in WinXI input bar, with optional native input positioning/sizing.
- The rows are kept even with an empty log; log and input share one width.
- The log lifts above input when typing opens, without double-applying native movement.
- The clock group follows the top of the log, keeping the game's clock-to-log spacing.
- Match Game Log Size off: a custom Width (640 pixels by default) and ten rows; native input width can be selected instead.
- A WinXI title on the top edge follows `/cm` (`/chatmode`) immediately, with a temporary
  override for a line you are typing with `/p`, `/l`, `/t`, etc. Until a mode command is observed,
  it uses the last channel spoken in (initially Say). Linkshell titles show `Linkshell 1: Name`
  or `Linkshell 2: Name`, using the equipped pearl's name. After loading the addon mid-session,
  re-equip your pearls if names are missing: the game supplies their slots on login/equip updates.
- Native/SimpleLog inline palette colours are always preserved; uncoloured text automatically uses its native chat-mode colour.
- Most recent 256 observed messages kept **in memory only**. No chat is written to disk.
- WinXI input replaces the visible native input; the game's editor still handles typing,
  selected chat mode, commands, submission, history, IME and auto-translate.
- Native Square/window selection lights the box and puts the game's cursor at the newest line; native confirm expands chat.
- Expanded mode uses a WinXI frame and theme-tinted native tabs, selection highlight, cursor and scrollbar at their exact native positions.
- Expanded selection, scrolling, channel tabs, Confirm/Cancel and message-action menus are entirely native.
- Expanded text uses the game's font and row spacing, not the compact WinXI font settings.
- Native split chat is hidden while the single combined replacement is submitted.
- Mouse-wheel scrolling over overflowing **compact** chat: three visual rows per notch, including wrapped messages.
- A compact right-side scrollbar appears only when retained lines overflow: drag its thumb or click the track to page.
- No dragging or mouse resizing. Combat formatting, filters and timestamps are left to the game or SimpleLog.

## Install

Install these together:

```text
addons/chatbox/          this directory
addons/libs/winxi/       WinXI 14 or newer
addons/winxisettings/    shared theme settings (optional)
plugins/uihook.dll       latest build with chat ABI 8 (native content and theme-tinted control artwork)
```

Build uihook from the repository with `plugins/uihook/build.sh`; output is
`plugins/uihook/build/uihook.dll`. Unload the plugin before replacing its DLL.
Do not run FancyChat, hidechatbg or other native-chat visibility writers alongside this.

```text
/load uihook
/addon load chatbox
```

Load any desired chat text formatting/filtering addons **before** chatbox. It observes
`text_in`'s modified text/mode and ignores already-blocked messages, but cannot see changes
made by handlers that run after its own. It does not block or rewrite messages itself,
so native history keeps receiving them and remains available if replacement stops.
Compact history begins collecting when loaded; it does not import earlier messages. Expanded mode displays the game's own history, including messages from before Chatbox loaded.

## Commands

```text
/chatbox          settings, including the WinXI Theme tab
/chatbox on       enable replacement
/chatbox off      immediately restore native logs
/chatbox clear    clear only this addon's retained messages
/chatbox status   bridge status and retained-message/decode-error counts
/chatbox modes    the last ten lines kept and their chat modes (to find a channel's)
/chatbox bytes    last incoming event: original, modified, expanded and UTF-8 bytes (hex, first 256 per stage)
/uihook chat      native recognition and last native/replacement frames
/winxi           shared WinXI appearance, if winxisettings is installed
```

## Input

Open chat just as before: Enter, `/`, Space or your configured game/chat-mode shortcut.
Type in the WinXI input bar below the log. Cursor keys, Home/End, editing, history,
Enter to submit and Escape to cancel are handled by the **same native editor**, not an
ImGui text field. The bar displays the editor's current text and blinking caret and
scrolls horizontally to keep edits visible. Auto-translate previews use the game's
display buffer; otherwise caret placement uses the native raw-byte index.

No keystrokes are intercepted or synthesized, no duplicate Enter/command is
sent, and no second draft buffer is maintained. Expanded browsing also leaves all controls
native; no tell command is synthesized. All keyboard/gamepad input that the game
routes to chat continues controlling this editor. Menus and gameplay retain their normal
input handling. This is a **native-backed input front end**, not an independent ImGui
editor: mouse-click caret placement/selection in our relocated bar is not implemented.
Native completion/IME menus remain the game's, and should be checked in live testing.

Uihook replaces the `menu inline` render boundary with the captured WinXI bar. The native
background, text and caret are not drawn while that replacement succeeds. Input is a
separate slot from the logs: closing input, a decode/API/capture failure, or a missing
input signature releases only the input slot, leaving the native editor visible and usable.
No `+69`/`+6A` flag, chat timer, or native input-buffer writes are used.

### Source formatting and colours

This section describes compact Chatbox rows; expanded rows are drawn directly by the game.

Native and SimpleLog inline colours are **always preserved**, including timestamp colours.
Both FFXI palette banks survive wrapping and paragraph breaks; resets return to the line's
native chat-mode colour. Say, tells, party, linkshells, shout/yell and other native modes are
coloured automatically, even without SimpleLog. There are no channel/timestamp colour controls
or preservation toggle.
The palettes are **standard-palette approximations**, not live reads: custom DAT colours and
user-configured native channel colours are not imported. Text without inline colour codes uses
the native mode's second-palette colour (white for unlisted native slots). An explicitly enabled
Window Colors → Default Text override replaces that base colour, but never inline colours.
Unknown/non-native modes fall back to the WinXI theme. These automatic mode colours also use
the standard-palette approximations; they do not read your live in-game colour configuration.

Chatbox does not compact, group, filter, classify or timestamp combat messages, or apply
custom combat-category colours; their native mode colours and inline spans are preserved.
Older character settings for those removed options are discarded on load.

Named NPC dialogue is labelled `[NPC]` after the speaker name. Only the three letters `NPC`
are yellow; brackets, names and dialogue retain their normal source/native colours. The tag and
its colour survive wrapping, and existing `[npc]`/`[NPC]` tags are not duplicated.

### Window Colors

In `/chatbox` → **Window Colors**, **Chat Log Window** and **Input Text Box** have
independent **Own Color** toggles and RGBA pickers for:

- **Background** (including opacity), keeping the selected WinXI background texture/style.
- **Border / Art Tint** (including opacity): colours a plain border or tints the selected border art.
- **Default Text**: an explicit override for the log's native base text colour, or the input's text, prompt and caret.
- **Title** on the chat log only.

Unchecked colours continue to follow the active shared/local WinXI theme. Each window's
**Follow WinXI Theme** button disables its overrides without discarding the chosen colours.
These preferences are character-saved and do not change the WinXI theme or other addons.
Preserved inline colours (including source timestamps) take precedence over the log's Default Text.
A border override's alpha replaces WinXI Border Opacity for that window; tinted border art
retains the original image's shading/colours rather than becoming a flat solid colour.

Update `addons/libs/winxi/` together with chatbox for border/title colour overrides.

For SimpleLog's packet-based multi-hit/critical tags, aggregation, actor filters, timestamps
and per-job profiles, load SimpleLog **before** chatbox. Chatbox observes its resulting text
and respects blocked messages; there is no second combat formatter or filter.

### Font and Padding

**Font** is the chat's typeface for the log and the input bar: the theme's, or any `.ttf` in
C:\Windows\Fonts. **Text Size** sets its size, and both boxes grow with it. **Left, Right, Top and
Bottom Padding** (0 to 40 pixels each, 3 by default) apply to the log and input bar.
Long log lines wrap between the left and right padding. In the log, as many whole rows
as fit go between the top padding (below half a row kept for the title) and the bottom padding,
centred there: any part of a row left over is shared above and below them. Settings from before,
still at the first default of 4 on every side, become 3 once; log paddings set by hand are kept.

The **input bar** uses the configured left/right padding and a plain `> ` prompt. In compact
sizing its height is Text Size + Top Padding + Bottom Padding. Its text and caret are always
vertically centred in the entire box: space above and below the text is equal even if Top Padding
and Bottom Padding differ, or when matching a taller native input rectangle. Long input still
scrolls horizontally to keep the caret visible.

### Match Game Log Size

In `/chatbox` settings, **Match Game Log Size** is on by default. The compact box takes the
width and height of the game's own chat log, read by uihook after the game lays it out, and
fits as many whole rows as that height holds at Text Size, at the bottom. Make the game's log
bigger or smaller in its settings and the box follows the next frame. Off, the box is **Width**
wide and ten rows tall. Match Game Input Size, when on, still decides the width.

### Match Game Input Size

In `/chatbox` settings, enable **Match Game Input Size** (default **off**).

- **On:** both boxes use the native input width and left edge. Input also follows the
  native bar's height and position, its text centred in it; a Text Size too big for that height
  grows the bar upward from the native bar's foot rather than shrinking the text.
  The last native width ratio is retained while input is closed, following changes to the
  native primary log's UI scale, so the log does not snap back to 640px on closing input.
- **Off:** both boxes use **Width**. The input shares the native chat base, rather than
  floating at an unrelated screen margin.
- **Text Size** applies to both boxes (12px default, 8–24px). The typeface stays WinXI's.
- Compact chat follows the native primary anchor (and its size, with Match Game Log Size).
  Expanded chat keeps the **native full log's exact rectangle**, font and spacing; compact width/input/font settings do not move its content or hit-tests.

This matches the native **outer rectangle**, not its bitmap typeface or exact glyph metrics;
the font is still your WinXI font. Geometry is read by uihook after the native window's
layout update. When input first opens, it can take a frame to acquire the bounds. Missing,
invalid or stale input-height geometry falls back to compact WinXI sizing while retaining
the shared native width when known; `/chatbox status` explains
that fallback. No native geometry or global theme settings are changed.

## Square/window selection and expansion

Use the game's usual **Square/window-selection control**, then its normal **confirm** action
on chat to expand. When chat has native cursor focus, a faint light falls over the box and the
game's own hand cursor points at its newest line. Moving focus to another window or cancelling
removes it. The addon does not bind Square, capture confirm/cancel, synthesize keypresses,
or write the native expanded flag.

Expanded mode is a **WinXI frame around the real native browser**, not a second browser.
Its rectangle is the game's full-log rectangle, including its native width. Uihook replaces the
window decoration, then allows the game's full-log content Draw and subsequent cursor/scrollbar
submissions through unchanged. The game draws the actual visible rows, channel tabs, selection
and scrollbar at the same positions used by its mouse hit-tests.

**Browsing and replying.** Up/Down, d-pad, Square/tab switching, mouse hover, wheel, Confirm and
Cancel all remain native. Confirm invokes the game's normal action for the actual selected row,
including its message-action menus; Chatbox no longer parses player names, injects Escape/Enter,
or creates a `/tell` draft. Older pages use the same frame skin as the newest page. All tabs use
the native filter, so no guessed channel-to-mode mapping is needed. Expanded history includes
whatever the game retained before Chatbox loaded; the addon's 256-message buffer is compact-only.

**Control styling:** the selected tab and row-selection highlight follow WinXI's **Highlight Color**.
Other tabs follow **Title** (or the theme's Title/Text colour); the hand cursor and scrollbar follow
**Border / Art Tint**. The log's existing Window Colors overrides apply, so changing Title or
Border / Art Tint updates these controls without changing the global theme. Native fade/pulse
alpha is retained. Theme colours are captured together with the expanded frame, not read halfway
through a native draw. Missing/ambiguous control signatures leave native artwork untinted while
the frame skin still works.

This is **tinted native artwork**, not replacement WinXI Tab Style textures: native tab labels and
shapes stay together, and no geometry or hit-test is moved. Expanded text still uses the game's
bitmap font, row spacing and message colours. Chatbox's Font, Text Size, paddings, custom width
and Default Text override apply to compact chat and input, not native expanded rows. Expanded
mode uses the log's WinXI background/border, without a second title over the game's tabs.
Native drawing eligibility, menus, input and other
addons' Under Expanded Chat hiding rules remain unchanged. Clock relocation is suspended here.
Nested menus/input hand the complete view back to native drawing.

**Compact scrollbar and wheel.** Overflowing compact chat keeps the slim 2px white scrollbar:
35% opacity normally, 70% hovered/dragged, at least 8px tall. Drag the thumb or click the track to
page; wheel over compact chat moves three visual rows per notch. The viewport clamps to the
retained 256 messages. Only these compact interactions are intercepted. Entering expanded mode
releases compact scrollbar drags and resets its wheel position; expanded mouse input is untouched.

Compact captures are never replayed at the full-log boundary, nor expanded captures at the compact
boundary. Missing content signatures/capabilities, missing geometry, capture failure or stale
submissions leave the full native view visible rather than covering it with stale addon rows.
`/uihook chat` reports focus/expansion flags and native cursor, page, scroll and filter diagnostics.
Live GPU and interaction validation is still required.

### Chat log anchoring

The log follows the native primary chat base. When typing opens it sits **above the
input bar**. Native upward movement is preserved, with only a no-overlap clamp applied;
the input height is not subtracted again from an already-lifted native log. Closing input
returns the log to its native base. Its rows grow upward using Text Size and compact
padding. Both boxes always have the same width and horizontal alignment.

Uihook captures the actual replacement log's bounds and translates the native **clock
text, day icon and weather icons** by the difference between its top-left and the native
log's top-left. This preserves the default UI's clock-to-chat spacing, even though our log
has a different height. It works with the native clock and the optional `clock` addon:
its clock/icon rectangles are published at their translated locations. The compass stays
where it was. Releasing/expiring chat replacement restores ordinary clock placement.

When the primary rectangle is missing/stale or there is not enough room above the native
anchor for the box, the addon leaves the native log visible instead of floating
our log at an unrelated fallback position. The working input bar is independent and stays
available. `/chatbox status` reports whether the native log anchor is available.

**Upgrade both the DLL and WinXI library** for this version; chat ABI 8 is required for
the log/input geometry, clock anchoring, native selection and expansion. Turn replacement off or unload the addon before replacing
its files, and unload uihook before replacing its DLL.

Width (with Match Game Log Size off) and Text Size can be changed in settings. Off, the height
follows Text Size with two pixels between rows and the top and bottom padding. Half a row is kept
clear at the top for the title. Both boxes remain click-through except for wheel events over an overflowing log and its scrollbar. The window is clamped to screen width; if the box cannot fit
above the native anchor, replacement releases its slots and the game's log shows.

## Native behavior and limitations

Uses `winxi.nativechat` to capture the **complete themed window**, after its border is
drawn, and replay it at the native primary log's render boundary. The game controls
native draw eligibility and layering: the replacement does not force a closed log open,
ignore UI hide/show, or draw over native browsing/action-menu views. Zoning suspends replacement.
Turning replacement off, unloading, a failed capture, or stale submissions restores
native drawing. A character/settings swap clears the addon's private message history.

Auto-translate is expanded and CP932 is converted to UTF-8 for ImGui. FFXI `1E`/`1F`
colour escapes are parsed before conversion (including control-valued palette operands),
retained as separate UTF-8 byte-range metadata and never sent to ImGui as text. Slot 1 resets
to the line's default colour. NPC bell separators and CRLF become paragraph breaks.
Native `7F` prompt/end/timing controls are consumed rather than printed or executed;
truncated escapes are safely discarded. Auto-translate brackets are drawn geometrically,
and elemental `EF 1F`–`EF 26` symbols use readable `[fire]`/`[ice]`/etc. labels.
Other special FFXI pictographs, animation/blinking and native timed reveal are not reproduced.
Japanese and other non-Latin text need a font with those glyphs.

No FancyChat parser or renderer is used. Standard-palette RGB observations are credited
in `palette.lua`; those approximations do not track custom game palettes. Native chatdiag
recognition lives in uihook, not in this addon.

## Checks

```sh
luajit tests/chatbox_log_check.lua
luajit tests/chatbox_encoding_check.lua
luajit tests/chatbox_inline_check.lua
luajit tests/chatbox_appearance_check.lua
luajit tests/chatbox_scrollbar_check.lua
luajit tests/chatbox_ui_check.lua
luajit tests/chatbox_input_check.lua
luajit tests/chatbox_layout_check.lua
luajit tests/harness.lua party addons/party/party.lua tests/winxi_capture_check.lua
luajit tests/winxi_version_check.lua
plugins/uihook/tests/run.sh
```

These are offline/mock checks, not proof of live rendering. In-game validation is still
needed for primary/split logs, wrapping, Enter/slash/mode shortcuts, history, editing/caret scrolling,
auto-translate/IME, non-Latin glyphs, input suppression/fallback, expanded
history, Square/window selection and focus changes, confirm/cancel expansion, native history
handoff, menu hiding, shared widths, input lift/close, clock/icon anchoring, menus, zoning, UI hide/show,
theme/font changes, device recovery and addon/plugin
unload/reload. Use `/chatbox off` to return to native chat immediately.
