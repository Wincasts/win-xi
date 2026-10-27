# Changelog

## 1.70

- `/uihook` help and the lines said on load reread for plain words: each command's line says what it does; the party and HUD lines say what is ready to be drawn in the game's place and what to unload first, instead of naming hooks and signatures. The version resource says 1.70.

## 1.69

- `/uihook skin` (nativeui's theme) no longer reaches the game's own names over heads. The skin knew a texture by its pixels alone, so any draw from the menu font was given the skin's font picture, edged, shadowed and smoothly filtered: the names the game draws from that font too. A font's texture (one the skin's fonts.txt lists) drawn in no game window is now left as the game's; inside a window, and every other texture anywhere, as before. Text the game draws outside its windows from the menu font, such as the chat input line, is left as the game's with them. Without Window::Render's detour, every draw as before.
- `/uihook skin` says how many font draws in no window were left.
- The DLL's version resource says 1.69 (it had said 1.59 since 1.59).
- Tests: a font in no window left; in a window, or nested, skinned; another texture in no window skinned; the windows not heard, every font skinned.

## 1.68

- Every write to the game's code goes through `CodeSite` (`plugins/common/CodePatch.h`, namehook's since 1.40, now shared): the detours' jumps (party and buffs), the target arrows, the clock's text and icons, the chat log's art and text, and the window content call. A site is written over what is there, and given back on unload only while it holds what uihook wrote: one something else has written over since is left as it is. Grouped calls go in together or not at all (both arrows, the three clock icons, every chat art call): where one will not, those written are given back. Where a site has to be left, uihook stays in memory (its DLL pinned) and keeps that detour's trampoline, as the game may still go through them into it, says so as it unloads, and refuses to load again until the game is restarted. A write is checked: before, a failed one was taken as done.
- Tests: a detour's jump written over by another: left, the trampoline kept, stranded; put back by another as found: given back, not stranded; one arrow call written over: the other given back, that one left.

## 1.67

- The target's arrow over the world is drawn where the game puts it again while the game's own target window shows (Party not replacing it). The game draws the arrow from the target window's own drawing, and the native look took it for one of that window's draws: with a menu scale it was moved with the window, scaled from the bottom right corner, far up and left of the target (seen 2026-10-26 with lens on and off alike; with Party's target window it was right, the game's window being replaced). The arrow is now drawn as of no window (`Native.Hold()` round its sprite call). tests/native.cpp: the target window moved, its arrow held out of it not, the window's draws after it moved again.

## 1.66

- Shared blocks frozen at their 1.0 layout until 2.0 (plugins/ABI.md): each grows only at its end, records never, and `tools/abi_check.py` (in tests/run.sh) fails on any other change. lens's block is read by `lens::Live` when it is at least 1.0's size, so a newer lens that adds to it is still read. Nothing in any block's layout changed.

## 1.65

- Party: a party window's replacement can let the game's own drawing away from the window through, for the stamina
  gauge of a hooked fish: the party list's pet bar, named "Fish", which the game moves towards the middle of the
  screen. `capture` 0 or 1 for index 0 to 2 with `PARTY_PASS_OUTSIDE` (4) added asks for it; `SupportedMask`
  bit 4 (`PARTY_PASS_SUPPORTED`) says it can be asked. A draw handed with its vertices that lies wholly further from the window than an eighth
  of the viewport's height on every side (`PARTY_PASS_REACH`; the rectangle read as the window is drawn) is drawn;
  everything else is replaced as before. A real pet's bar, which the game puts against the list, above it or to
  its side, stays hidden: in game, letting through all that was outside the window showed one above it, and all
  that was beside it one to its left. Party ABI 3 unchanged. `DrawOutside` (placement.h); tests/party.cpp: the
  fish's bar mid-screen and far above the list away, a row, a frame piece reaching in, a shadow and the pet bar
  above or beside the list its own, nothing without positions or a viewport. Not yet tried in game.

## 1.64

- Native: with Menu Scale and no Bring Sides In, the top bar's title ("Help") showed only its "p". What ends within
  48 pixels of the bar's right end (and the inset) went with that end, the rest with its left end, scaled from the
  screen's left: "Hel", ending a few pixels short at 3440 wide, went 10% further right at 1.1, off the screen. A piece
  starting in the bar's last quarter goes with its right end too. tests/native.cpp: no inset, "Hel" and "p" both by
  the right end, "Hel" on the screen. Not yet tried in game.

## 1.63

- Buffs: the anchored bar no longer moves a pixel as the buff selector's cursor comes to or leaves the first status.
  The menu hands the item its cursor is on a pixel up and to the left of its place (read from the live game: the first
  icon at 144,50 with the cursor on it, 145,51 with the cursor on the second), and the bar went where the first icon
  was put. It is now kept where the first icon is with the cursor on it, wherever the cursor is: where it already was
  outside the selector (SteadyFirst, game.h). tests/buffs.cpp: the cursor on the first, the second and none.
  Not yet tried in game.

## 1.62

- Keys: a held key's control character is kept whether or not its key down reached the handler. 1.61 kept nothing in
  game (the live keys block: Supported 1, keys named, Kept 0): Ashita's key event sees a key down before the game's
  handler, and the key down chatbox blocked there never reached it, so 1.61, which kept a character only after seeing
  its key down, let Enter's through and the line was sent. Now while Enter, Tab, Escape or Backspace is held, the
  character it types is kept (by the character, not its scan code's key: numpad 8's is Up's), and a held key's key down
  and release are kept too. chatbox names a key it acted on until it is let go, so Enter's character, after the list
  closed at its press, is still kept. tests/keys.cpp: Enter's character, the main and the numpad one, and its release
  kept with no key down seen; another character and Enter's once no longer held, the game's. Not yet tried in game.

## 1.61

- Keys kept from the game's chat editor (independent keys ABI 1, `UIHOOK-KEYS`, `window/keys.h`, 72 bytes). The
  editor reads each key in the game's message loop, in the handler the native look's mouse is taken at, before
  TranslateMessage and DispatchMessage, and sends the line on Enter's WM_CHAR: Ashita's key event, at the window
  procedure, can keep neither from it, which is why chatbox's Auto-Translate list sent the line on Enter. An addon
  names virtual keys in Hold, renewed each frame (HoldFrame; three frames after the last, none); a press begun while
  its key is named is kept from the game whole, its repeats, characters (by scan code) and release too. Ashita, imgui
  and addons still see every message. `winxi.gamekeys` (winxi 53) reads and writes it. The handler was already taken
  for the native look's mouse; nothing else is hooked.
- tests/keys.cpp (in run.sh): a held key's press, character, repeats and release kept, though it is let go of after
  it is held no longer; the next press and a letter typed meanwhile the game's; Up kept and numpad 8 (the same scan
  code, not extended) not; a lost release; the hold expiring three frames after its commit; not supported, never
  committed; the count. Not yet tried in game.

## 1.60

- No blink of the party, alliance and target windows, the clock and compass, or chatbox's logs while imgui makes
  its font texture again (its atlas grown or made afresh: reloading name, which loads its font and writes every
  name size, did it). A capture refused for imgui's texture not being ready keeps the slot's last capture, drawn
  again for up to eight frames in a row (`PARTY_HOLD_FRAMES`, `party/hold.h`), this frame's commands consumed as a
  capture's are, so neither the game's window nor imgui's shows; past eight it is refused as before. A replay no
  longer needs the font texture to be the one it was taken with: its runs hold their textures (AddRef), the old
  atlas among them, so a capture taken before the atlas was made again draws as it was; that check, which left the
  slot to the game for the frame after every rebuild, goes, with `Font()`. Ashita's log has an info line as a hold
  begins and as a capture is taken again after one. Buffs are not covered: their quads are the addon's, of
  whichever atlas it saw.
- tests/party.cpp: kept for the texture alone, eight frames, only a fresh capture; the old atlas held by a capture
  outlives the renderer's reference. tests/run.sh: all pass. Not yet tried in game.

## 1.59

- The group's mirror (mirror ABI 6, `native/mirror.h`; nativeui 0.9's Drawn As Winxi): while an addon asks each
  frame, the windows the game stacks over the chat log are measured, published and left undrawn, the game's own
  working unseen underneath, for the addon to draw them in the winxi look. Revived from the menu mirror (ABI 5,
  retired in 1.58), for the group alone: no names asked for, but those the addon keeps for the game, and its places
  measured where the native look draws the window (its move, its scale), so the native look's mouse works it there.
  Quads to 1024 a frame.
  A window is taken by the native look and the mirror at its first draw (`Settle`: a draw, a text routine, its
  contents or a control), not as `Window::Render` begins: Render updates the window's animation and layout first,
  so its place read before was the last frame's (or nothing, as it opened), and a menu opening over the chat log was
  not yet of the group, and drawn by the game for a frame or more before the mirror hid it. A window is of the group
  too while it is drawn within a layout target (+8C) that is, as one opening grows into its place. tests/native.cpp:
  a window half grown, by its place and within its target; tests/mirror.cpp: held as Render begins, taken at its
  first draw, an inner window that draws nothing leaving the outer mirrored. tests/mirror.cpp: a window of the group measured and hidden, one kept, one moved and
  larger, the textures held two frames, a stale request and no viewport, cleared.
- `/uihook native frames <fill> <border> <rounding> <thickness> | off` (an experiment; nativeui 0.9's Drawn As Winxi
  Frames): the frames of the windows the game stacks over the chat log left undrawn (the draws in a window's frame
  of the frame's art: its corners, edges and striped background, told by their textures' pixels), and a panel
  drawn in their place under the rest of the window, in the colours given (AARRGGBB), its corners rounded and its
  border so many pixels. Their words, pictures, buttons and hand are the game's. While it is on the group is told
  with no move set; `group off` keeps its windows, unmoved. `/uihook native` says what is set and how many draws
  were left undrawn and panels drawn. tests/native.cpp covers the group with frames alone, the panel's place,
  once a frame and with the move, and its triangles.

## 1.58

- The buff selector's hand is put out of sight each frame the game draws its status icons, not once a window: the
  game makes the list again with its hand back at -5, -5, often where the last one was, and the plugin took it for
  the one it had already moved, so the game's hand sometimes showed beside buff's highlight.
- `/uihook native move`, `scale` and `tint`, the first experiment's commands for one window at a time, are taken
  out, and `clear` with them: nothing used them once `group`, `inset` and `size` (nativeui's settings) did it for
  every window. Every entry the native look keeps is now one made as a window is drawn.
- The party module's one file (`partyhook.cpp`, 2,000 lines) is split: the skin (`native/skinmodule.h`), the
  native look (`native/nativemodule.h`) and the diagnostics (`census/diagnostics.h`) are modules of their own, each
  with its state and commands, sharing a `DrawContext` (`drawcontext.h`); `partyhook.cpp` keeps the capture and
  replay and calls each in turn. Nothing it draws or publishes changes.
- The diagnostics (`/uihook census` and `/uihook textures`) are built only by `./build.sh --diagnostics`. Without
  them the census and the texture census are not looked at for each draw, and their commands say how to build
  them.
- The window hooks (the three text routes and the contents' call in Window::Render) are uihook's own, not the
  mirror's and the census's: `src/modules/window/window.h` holds their patterns, the window's fields and the phase
  of a draw (`WindowPhase`, was `MirrorPhase`), which the native look tells a window's frame by.
  tests/check_census_client.py is check_window_client.py.
- `/uihook native mouse on|off` (an experiment, off to begin with; nativeui 0.8's Mouse Follows Menus): the game's
  mouse given each window where the native look draws it. A message on a window drawn moved (the one drawn last on
  top, of those drawn in the last two frames) is given to the game at the same place on its own window, the move
  undone; one where the game puts a window drawn elsewhere, with none drawn there, is kept from the game (a button
  let go always given). The mirror's taking of the game's mouse handler (1.2) is the game's own now
  (`window/mouse.h`).
- The menu mirror is retired (0.96–1.57): mirror ABI 5 (`UIHOOK-MIRROR`) is no longer published, and
  `/uihook mirror`, `/uihook mirror labels`, `watch` and `mark` and the `UihookWatch` export are gone, with the
  menus addon, `winxi.nativemirror` (winxi 43) and tools/uihook_live.py. The skin and the native look change the
  game's own menus instead. Copies are in `archive/`; the history has all of it up to `eae073d`. The window hooks
  stay (the native look needs them) and the census moves to `src/modules/census/`.
- The chat's state, routing, lines and colours are read only while an addon asks for them (a chat submission in
  the last 8 frames; the first after a while reads them all at once): with chatbox not loaded, switched off or
  zoning, nothing of the chat is read each frame. `/uihook chat` says whether they are being read.
- `/uihook` lists its commands a line each, the diagnostics only where they are built in. The plugin's description
  and its DLL's version (it said 0.3 and 0.4) say what it is now; the README no longer says it is experimental or untested.

## 1.57

- A window drawn for the first time (or the first since its entry went to another) is placed at once, by where the
  game draws it (+3A, in pixels): placed only by its draws of the frame before, it showed for a frame where the game
  put it, then moved. A window that drew no frame of its own the frame before is taken for one without, so the
  guess does not move the target's arrow and the like for longer than its first frame.

## 1.56

- Faster. The skin's fonts are drawn a size at a time, the first time a draw is made with that size, not all at
  once: both fonts at every size took 583 ms each time a skin loaded or a font was chosen (nativeui chose two as the
  game started), and at one Menu Scale most sizes are never drawn with. A font's drawing keeps one device context,
  one bitmap and its fonts by size for all its glyphs (each glyph made and let go all three), and a letter's height
  is measured without the averaging: both fonts at every size, were they all drawn, 342 ms.
- A font command as it was (nativeui gives each again as it looks at the theme) draws nothing again; one that
  changes a kind draws only that kind's texture again.
- Each draw asks the device its vertex format once for all that want it (the census, the watch, the native look and
  the skin each asked), the native look reads the screen's size once a frame (three calls of the device's for each
  draw moved), and the skin remembers the last texture it looked up (draws one after another are mostly of one).

## 1.55

- What the bar across the top shows is moved for the whole bar alike: its help text is drawn a letter or a few at a
  time, and 1.50, moving each by where it lay, slid the start of a sentence over its end. All of it goes with the
  left end, what is at the right end (its title) with that end; while the bar showed something over its middle the
  frame before (the loading screen's progress line), what is by the middle stays there.

## 1.54

- A font chosen is drawn smoothed: each glyph four times as large and averaged down, as a font's own hints turn
  Windows' smoothing off at a menu's size and its letters came out two-toned and jagged a pixel wide.
- In winxi's look: its fill, an outline about its letters (`outline=<pixels>`, `outlinecolour=<AARRGGBB>`; a pixel
  in the theme's Text Outline Color as nativeui gives it), outside the letters alone, and no game shadow. The
  game's shadow and edge, laid in the gaps of a font with pixel-wide strokes, made its letters stripy and grey.
- `regular` or `bold` after the file draws it at that weight (the family's bold face where Windows has it).

## 1.53

- The skin's fonts.txt may hold several fonts in one texture, each font line the style of the lines after it:
  30CDD9D4 holds the menus' buttons' small font (Status, Equipment, Magic: what the menu font is chosen for) as well
  as the large one, and 1.52 drew only the large. A style may have a shadow (a colour, moved by texels), drawn
  between its edge and its fill, as the small font's is; a font with no face chosen is left as the skin drew it.

## 1.52

- `/uihook skin font <menu|title> <file|off> [quiet]`: the skin's fonts drawn in a font chosen in game. A skin's
  `fonts.txt` (made by tools/uihook_skin.py) says where each glyph of the game's two font textures goes, on its
  baseline at its height, or fitted to a word's ink; uihook draws each again in the font file (in Windows' Fonts, or a
  path), by Windows' own font drawing, at each size of the skin's picture, on the picture's own pixels (kept as
  loaded), and puts its levels back. The skin's own pictures where none is chosen or it cannot be opened; a font
  chosen before a skin is loaded is drawn as it loads. The font's family and style read from its name table.

## 1.51

- A skin's draw within its texture (its texture places 0 to 1, not tiled across it as the frame's edges are) is
  clamped at the texture's edges, put back after: filtered, a button bar's piece starting at the texture's edge took
  in the far side wrapped round, a clear column where two pieces meet.

## 1.50

- With the sides in, only the bar across the top's frame is pinched by each vertex's side; what it shows is moved
  whole by the end it is near (the help text at its left, its title at its right, within the inset and 48 pixels of
  that end), or left in the middle with the bar: while loading, the game centres "Downloading data..." and a
  progress line there, and the pinch pulled the line's ends in apart from its words and cut the words off.

## 1.49

- A skin's picture may come in sizes, `tex-<hash>@<factor>.png` beside `tex-<hash>.png` (the game's size). Each draw
  is measured (how many pixels a texel covers, as its window is scaled) and drawn with a size whose texels are its
  pixels, unfiltered: crisp, and nothing of a neighbour's blurred into a piece's edge (1.48's filtering drew a
  line where two button bars meet). Where none is, with the smallest about twice as fine, filtered without its
  levels: the menu font, drawn at half its texture, is sharpest so (1.48's levels between blurred it). The levels
  only for one shrunk further than 2.6 times.

## 1.48

- A skin's pictures are made with every level down to a texel (each the one above halved, colours weighted by
  their alpha), and drawn with stage 0's filters linear, its levels between, put back after: a picture made larger
  than it is drawn (for a larger Menu Scale) shrinks smoothly, and the menus stay crisp scaled up to its size.

## 1.47

- `/uihook native size <factor> [quiet]` (0.5 to 3): every window with a frame drawn that much larger or smaller,
  each from its quarter's corner of the screen (one over the middle from the middle), so windows side by side
  keep their places to each other; the bar across the top from its ends, staying with the title and network boxes;
  the group over the chat log from the log's top left, staying on it. The chat log and frameless windows (the
  target's arrow) are left. The native look's moves are now one transform (a corner, a scale, a move; the bar by
  each vertex's side), its viewport moved by the same.

## 1.46

- A window asked for by name (`move`, `scale`, `tint`) is kept: one the inset had given an entry was still taken
  for one made as it was drawn, and given up to another window when long undrawn, its scale lost.
- One asked for by name that is found over the chat log takes the group's offset and keeps its scale; the group
  switched off leaves its scale and tint.

## 1.45

- A window drawn moved (the group, the inset, `move`) is given the skin's colours from skin.txt, as one drawn in
  place is: the moved copy of its vertices kept the game's, so the bottom-left command menu's buttons were the
  game's blue-grey and orange, and its frame faded at the sides.

## 1.44

- The inset brings in only windows with a frame of their own, by that frame: one without (the target's arrow over
  the world) is left where the game puts it, as it was pulled 100 pixels off the name it points at. Only a short
  frame (80 pixels at most) over the middle and wider than half the screen is taken for the bar and pinched; a tall
  one there (the map) is left.

## 1.43

- A window given an entry for the inset before it was found to be one of the group over the chat log (drawn
  before the log was seen) is the group's once it is: it was moved sideways with the inset, not by the group's
  offset.
- 1.41's draws outside any window moved with the window they lie within are gone: the mouse pointer, drawn outside
  any window, jumped with each window it was over. (The title box's words were clipped by a viewport, 1.42.)

## 1.42

- The native look places by the screen's size (the render target's), not the viewport's: the game clips some text
  to its window with a viewport (the title box's words), which taken for the screen made the inset's middle the
  box's, so the words were pinched there. A viewport smaller than the screen is moved with the draw and put back
  after it, so what is moved is not clipped away where the window was (the title box drawn empty).

## 1.41

- A window moved by the inset alone has every draw moved with it: none is kept back for lying outside its frame,
  as the main menu's red arrows beside it were. (The rule is for a window moved alone, the inventory's count up in
  the menu name's bar; with the inset the whole side moves.)
- A draw made outside any window, while the inset or the group is on, that lies within a window moved (drawn this
  frame or the one before) is moved with it, the smallest such: the title box's words, drawn after the box, were
  left behind.

## 1.40

- `/uihook native inset <pixels> [quiet]`: the sides brought in. The bar across the top (a window over the
  middle of the screen and wider than half of it) is drawn that much shorter at each end, every vertex of it
  moved toward the middle, so its frame shortens and what is on it goes with its end; every window wholly on the
  left half is drawn that far right and every one on the right half that far left, at its size, so they keep
  their places to each other. A narrower window over the middle stays; so do the chat log and the windows stacked
  on it (chatbox places the log). Windows are given entries as they are drawn, up to 128.

## 1.39

- The group over the chat log is told by where the game draws each window (+3A), not by its layout target
  (+8C): some have a target over the log while they are drawn elsewhere, and 1.38 moved the Master and
  Automaton menu, beside the main menu at the top right, with the group.

## 1.38

- `/uihook native group <x> <y> | group off`: every window the game stacks in the bottom left over its chat log
  (the command menu, a shop's buy and sell, a yes or no, an item's description, some fifty more) drawn that far
  from where it puts them, together. Told each frame by its layout target: its bottom on the log's top, its left
  within 150 of the log's. `quiet` after it, as an addon sends it, says nothing. The status names them. Up to 64
  windows set (16 before). addons/nativeui keeps it as a setting.

## 1.37

- The texture census hears the glyphs: each print (a text routine) matched to the pieces drawn while it ran, where
  they are as many as its characters (spaces drawn or not) or a whole number of times as many (a shadow or edge
  with each), written to `glyphs.txt` beside `index.txt`: each font texture's glyphs by character, with their
  texels and size on the screen. For a skin's fonts.

## 1.36

- `skin.txt` may give a colour of eight digits, `AARRGGBB`, for the vertices' alpha as well: the game fades its
  frame by its vertices' alpha (its sides near 0, its top and bottom 0x61), so a frame even all round sets one.
- `tools/uihook_skin.py --style winxi`: the frame is the Border Style's art as winxi draws it (a nine-slice, its
  outer 8 of 64 texels in 3 pixels) laid on the game's 3-pixel line, at the game's size (it draws its frame a
  texel to a pixel), and drawn at the theme's Border Opacity all round.

## 1.35

- The texture census keeps up to 48 pieces of each texture as drawn (each quad of a draw: its window, part, place
  and size on the screen, the texture places at its top-left and bottom-right corners, so a mirrored piece shows,
  and its colour), written under the texture in `index.txt`: how the game cuts a texture, for a skin's pictures.

## 1.34

- A skin's `skin.txt` says what colours the game's vertices are drawn in for a picture of its, a line each:
  `<hash> <RRGGBB or *> <RRGGBB>`, alpha the game's. For art the game colours by its vertices, one texture in
  several colours (the button bars). The status counts the draws recoloured.
- `tools/uihook_skin.py --style winxi` follows the winxi theme file and winxi's own images (border, background
  and tab styles, the tab colours), and keeps the census's alpha: the hand and frame are clear about them again.

## 1.33

- `/uihook skin <name>|reload|off`: the game's interface drawn with the pictures in
  `config\uihook\skins\<name>\` (`tex-<hash>.png` or `.bmp`, named as the texture census names the textures
  they stand for, any size) in place of its own textures, every menu at once; layout, input and places the
  game's. `tools/uihook_skin.py` makes a test skin from a census.
- The texture census's hash is shared with the skin (`TextureHash`); buffer draws are left alone while uihook
  makes a draw of its own.

## 1.32

- `/uihook textures on|off|dump|clear`, the texture census: every texture the game's screen-space drawing uses,
  counted by window and part (frame, content, cursor, element, scroll, after, text, outside), with the texture
  places used and its vertex colours, each written once as a picture with an index to `logs\uihook-textures\NN`
  when switched off or dumped. To tell whether the menus are made of few enough pieces to be reskinned once for
  them all. Off until asked.

## 1.31

- The census is off from load again, as before 1.24: `/uihook census on` starts it, each time in a file of its
  own in `logs\uihook-census\`, written as windows are first seen, each minute and as it is switched off or
  uihook is unloaded. Nothing heard and nothing written while it is off.
- The help gives `native` as it is now: drawn moved or scaled, with `scale` listed.

## 1.30

- A draw wholly outside a moved menu's frame is left where the game put it: the inventory's item count is
  drawn by the inventory but up in the menu name's bar, and went with it. A menu is grown from its frame's
  corner, not from everything it draws. The status counts the draws kept back.

## 1.29

- `/uihook native move` moves a menu's drawing, not its layout: every screen-space draw made while the window is
  drawn (frame, elements, contents, text, cursor, scrollbar) is copied, moved and drawn in its place, so the
  menu moves whole. Moving the layout (1.25 to 1.28) moved the frame, and the list's rows once their owner's
  origin was moved too, but the icon boxes, scrollbar and count each keep a place of their own. The game's own
  places are left as they are: the controller works the menu as ever; its mouse hit-tests stay where the game
  put it. `/uihook native scale <name> <factor>` (0.5 to 3) grows it from the corner of the screen it is
  nearest, kept on the screen. Draws from vertex buffers cannot be moved and are counted in the status.
  Nothing of the game's is written any more.

## 1.28

- A moved item list's contents go with it. 1.27 moved the inventory's frame, but its rows stayed: the item
  lists' owner (contents drawn at the client's +1F6A60, as for the inventory, area list, search results,
  linkshell lists and synthesis history) keeps its own origin at +28, +2A, in the target's units, which
  the game sets where it places the window, not in Update. That origin is moved by as much as the target
  and put back with it. An owner of any other kind is left alone, and the status says its contents were
  not moved and which drawer they are (frame only, until its origin is found).

## 1.27

- The tint is a second texture stage after the game's own, multiplying what it made by the colour (the
  texture factor), set for the frame's draws alone and put back after each. 1.25 multiplied the vertices'
  colours, which the game's frames do not take: 2808 draws were tinted and nothing showed. Not where the
  game uses that stage or a pixel shader (counted refused). The status gives the game's first stage too.
- A move past the top or left edge is kept at the edge rather than refused: the inventory's layout starts 48
  down, so a move up 100 was refused as off the range.

## 1.26

- `/uihook native` says, for each menu, when a window of its name was last drawn, why it was not moved
  (chatbox moving it, its layout not writable, no menu manager for its units, off the screen's range), and
  how many of its frame's draws were tinted or refused, with the vertex format of the last.

## 1.25

- `/uihook native`, an experiment in skinning the game's own menus rather than mirroring them: `move <name>
  <x> <y>` moves a menu where the game lays it out (the action menus' layout target, for any menu by
  name), so its cursor, rows and mouse hit-tests go with it; `tint <name> <AARRGGBB>` multiplies the colours
  of its frame's draws, its contents, labels, cursor and text left as they are; `clear [name]` gives them
  back. At most 16 menus; nothing kept between loads. The mirror ABI is as it was.

## 1.24

- The census is on from load: every window drawn while playing is documented without a command, each
  session in a file of its own, `logs\uihook-census\<date>_<time>.txt` (the census's format: each window's
  name, frames, drawer, kind, layout, text routes and the text seen in it). Written a few seconds after a
  window is first seen, each minute while windows are drawn, and as uihook is unloaded. `/uihook census off`
  stops it for the session; `/uihook census dump` still writes `logs\uihook-census.txt`.
- `tools/uihook_live.py` reads the mirror and the watch from the running game, from outside it.

## 1.23

- The watch's block is kept: in 1.22 nothing in the DLL read it back, so the compiler left out every write to
  it and it was never there. It is exported now (`UihookWatch`).

## 1.22

- The watch is always kept, in memory: each frame, every window drawn (its name, kind, whether it was asked
  for, hidden and mirrored, and its draws by kind) in a block of its own, magic `UIHOOK-WATCH`, version 1, for
  reading the running game from outside without a command. No addon uses it; the mirror ABI is as it was.
  `/uihook mirror watch` now only switches the file.

## 1.21

- `/uihook mirror watch`: while on, `logs\uihook-mirror-watch.txt` is written as what is drawn changes (at most
  once a second): every window Window::Render draws, whether an addon asked for it, whether it was mirrored
  (or dropped, past 16 a frame), and how its draws were made: measured (`DrawPrimitiveUP` in screen space),
  not in screen space, or from vertex buffers, which the mirror cannot measure; then each window published,
  with its place or NO PLACE. `/uihook mirror mark <words>` notes a moment in the file. For reading why a
  menu is not mirrored while it is open. Mirror ABI 5 as it was.

## 1.2

- The mouse on a menu the menus addon draws somewhere else, or larger: the game reads each mouse message in
  its own message loop, from the MSG, before Translate and DispatchMessage (0x31c16c0, given the MSG by
  value; its window procedure gives mouse messages to Windows). That call is taken, and a message whose place
  is on a menu drawn elsewhere is given to the game at the same place on its own, so pointing, clicking and
  hit-tests work the menu where it is drawn. Ashita, imgui and addons see the message as it was.
- Mirror ABI 5: `MouseFrame`, `MouseCount` and `Mouse[16][8]` after `Requests`, written by the addon (each
  menu's place as drawn, then the game's own, normalized); `Supported` bit 2 where the handler was found.
  84632 bytes. `/uihook mirror` says whether it was, how many menus are said now and how many messages were
  moved. Needs winxi 41.
- Links user32 (the client area's size).

## 1.1

- Mirror ABI 4: an addon may ask for 128 windows (was 64), `Hide` four words of 32 bits. menus has
  80. Needs winxi 40.

## 1.01

- `/uihook mirror labels` writes the contents' art too (item icons, and letters the game draws one quad
  each in a window's contents, as the top bar's help line), with a phase column: 1 content, 3 element.
- `/uihook mirror labels 5` writes them five seconds on (at most 60), once the chat line the command was
  typed in has closed: typing it changes what the menus show.

## 1.0

- Mirror ABI 3: an addon may ask for 64 windows (was 32), `Hide` two words of 32 bits. With every
  menu of the menus addon on (40) the requests past the 32nd were dropped, and the bit for the 32nd,
  which winxi's LuaJIT wrote as a negative number, left every window watched rather than hidden:
  nothing was replaced. Needs winxi 37.

## 0.99

- `/uihook mirror labels`: every element of the last frame mirrored is cut from its texture as the game
  drew it and written to `logs\uihook-labels\NNN.bmp`, with `labels.txt` naming each one's window, its
  texture's size and format, its place in it (uv and texels) and a hash of its pixels. It is the dump
  the table of the picture labels' words is built from. DXT1–5, A8R8G8B8, X8R8G8B8, R5G6B5, X1R5G5B5,
  A1R5G5B5, A4R4G4B4 and A8 are read; any other format, or a texture that cannot be locked, gets a line
  saying why. Each run goes in a folder of its own (`01`, `02`, …), each texture is also written whole
  once (`sheet-XXXXXXXX.bmp`), and a run with no elements writes nothing.

## 0.98

- The mirror publishes a window's own elements: Window::Render draws, before the contents, each sprite
  of the window's list of elements (a menu's labels where its words are pictures, as the main and
  command menus have them, its buttons and icons) through the one call chat calls the row-selection
  art, in 0x80808080, 0x30808080 greyed, or tinted (0x80805020, 0x40402810) where the element's index is
  the window's cursor's (+3A against +4C, focused +63). Each is now a quad (phase 3, Element, which was
  Selection) with its texture and corners, and the window's Selection is the tinted one's place, the
  element the cursor is on, rather than all of them. The kind-0 elements are the frame's nine-slice
  panels (33F4AB0), still the frame. tests/mirror.cpp: elements as quads, the tinted one the
  selection, apart from the frame. ABI unchanged.

## 0.97

- Mirror ABI 2: an addon names up to 32 windows (`Requests[32]`, a bit of Hide each), 16 are published
  a frame, with up to 512 runs, 512 quads and 32 KB of text; 82564 bytes. ABI 1 bridges are refused.

## 0.96

- The menu mirror (mirror ABI 1, `UIHOOK-MIRROR`): a window of the game's, named by an addon, keeps
  working as it is (its input, cursor and hit-tests the game's) while what it draws is measured and, if
  the addon asks, left undrawn, so the addon draws its own from what the game would have. Window::Render's
  call to a window's contents (`mov edx,[ecx]; call [edx+10]`, five bytes, `MIRROR_CONTENT_PATTERN`) is a
  call to ours making the same call, so each draw is known to be the frame's, the contents' or a
  control's (the cursor, row highlight and scrollbar, from the chat controls' call sites). In the
  contents, each text call is a run (its bytes to the line's end, colour, the place it was asked for and
  the place measured from its glyphs), and every other draw a quad of the game's art with its texture,
  held by a reference until the next frame is published, and its corners in it. Published whole as each
  frame is presented, in viewport-normalized places: up to eight windows, 256 runs, 256 quads and 16 KB
  of text, what does not fit counted as dropped. A request holds four frames, and each texture is held
  for two frames published, as an addon may draw the last frame's after the next is published. The census's three text
  routes are now taken with Window::Render as uihook loads, all four sites or none, each passing on to
  the game's own while nothing is mirrored and the census is off. `/uihook mirror` says what is asked and
  what the last frame published. tests/mirror.cpp: phases, runs (nested calls part of the outer), quads
  and their textures held once and given back, the watched and nested windows, staleness, no viewport,
  overflow, release, world-space draws; tests/nativemirror_check.lua the bridge; check_census_client.py
  the content call unique and in Window::Render.

## 0.95

- The menu census, the first step toward mirroring the game's menus: the real menu stays open and keeps
  its input, and an addon draws its own from what the real one would have drawn. `/uihook census on`
  takes over the game's three text routines, each passing straight on to the game's own (the bitmap
  font's `(x, y, text, colour, sx, sy, centred)`, its scaled sibling and the rendered font's thiscall),
  and keeps, for every window Window::Render draws, its name (+46), its content draw (vtable +10 of its
  owner at +0C), its layout target (+8C), whether it showed a cursor or focus, its text calls on each
  route, its draw calls and up to 24 distinct texts with their places and colours. `/uihook census dump`
  writes it to `logs\uihook-census.txt` with the windows grouped by the content draw they share; `off`
  gives the routines back, `clear` forgets what was seen. Nothing is written to the game. Off until
  asked, and released with the plugin. tests/check_census_client.py: the three routines unique, the
  plain text wrapper calling the bitmap route.
- The census reads each window's name from its header (+4, then +46), as the chat module does, not
  from the window itself; and the bitmap and scaled routes' x and y as the shorts they are, the upper
  halves of their stack words being whatever the caller left.

## 0.94

- Built against lens 0.6's `warp.h`, whose cylindrical mapping finds its edge once a call instead of
  in every step, so moving the target arrows under the cylindrical warp costs a few microseconds
  instead of about fifty. The arrows go where they did.

## 0.93

- The game's own target and subtarget arrows follow the lens plugin's warp. lens draws the world bent
  and the menu layer flat over it, and the game puts each arrow's tip where the flat projection puts
  the target, so near the sides of the screen it pointed beside it. The two arrow calls uihook already
  stands in (`DrawTargetArrow`) now move the tip, in pixels of the menu layer (the menu manager's
  size at `+0x80`), to where the warp shows that point (`WarpArrow`, `target.h`, through lens's own
  `ScreenOf`), before handing it to the game's sprite draw. The warp is read from the block lens.dll
  exports as `LensWarp` (`lens/src/shared.h`); without lens, with its warp off or not live, or with no
  menu size, the arrow is drawn where the game put it. tests/party.cpp: moved out toward the edge to
  ScreenOf's own point, the middle column kept, and left alone for a stale warp, no lens, strength 0
  and no menu size.

## 0.92

- A capture is no longer refused for a texture whose id is a 32-bit pointer sign-extended to 64
  (`TextureAddress`, partyhook.h): the id's low 32 bits are the address, as `Font()` has always taken
  them, where before the whole id was held to `UINT32_MAX` and any ones in its upper half refused the
  capture. A pointer above 2 GB, as imgui's font texture's can be after a while (the renderer makes the
  texture again as the atlas grows), carries them once it has been read as a signed integer. With the
  font texture refused, every window with text in it was refused: the party, alliance and target windows
  and the chat logs drawn by imgui over the game's own, chatbox's second box not drawn at all (it is
  drawn only after the first's capture), and no reload of uihook or of an addon helping, as the texture
  stays; buff's bar, which reads the texture through `Font()`, kept working. The evening of the 19th
  from about 22:50, with nothing said anywhere: the reason is inferred from what was seen and from the
  checks each capture makes, as no command reported them. Hence the next point.
- What a capture was refused for is said. Each slot keeps its last refusal (`PartyRefusal`, slots.h: no
  window or display, a draw command that cannot be replayed, too many draw commands, imgui's texture not
  ready, a texture id that is no 32-bit pointer, a clip rectangle or a vertex that is not a number, a
  vertex index past the buffer, too many vertices, the capture threw), the frame of it and how many in a
  row; `/uihook` lists the slots refused now with the reason, the run and the age, and the count of
  captures refused since loading. Ashita's log gets a warning the first time a slot is refused and when
  its reason changes (`uihook | party list: capture refused at frame N, ...`), and a line when a capture
  is taken again; a slot released on purpose reports nothing. tests/party: `TextureAddress` for a pointer
  below 2 GB, one above zero- and sign-extended, ones over a low pointer, a 33-bit value, the font mark,
  a null and a low address.
- `/uihook`'s first line no longer begins with a stray `0.8.`, left from 0.8's help text.

## 0.91

- What an addon asks for is good for eight frames, as what it hands over has been since 0.9
  (`CHAT_REQUEST_FRAMES`): the action menus' place above chatbox's panel (`MenuFresh`), the expanded log's
  place (`LogFresh`), and the replacement log's place that the clock follows (`ChatClockOffset`, and
  `winxi.nativechat`'s `ClockAnchor`). With two, a few frames the game presented before the addons ran
  again sent the menus and the clock back to the game's places for a frame, as the windows had been at
  more than 60 frames a second. What the game draws itself is still held to two.

## 0.9

- A submission is good for eight frames, not two: the party, alliance and target windows, the clock and
  compass, the chat logs and input (`PARTY_FRESH_FRAMES`) and the buff bar (`BUFF_DRAW_FRAMES`). Under
  TrueFPS the game can present a few frames before the addons are next run, and with two its own windows
  showed for a frame now and then, along with namehook's names. Stopping a replacement still gives the
  game's back at once; an addon that stops without a word gives it back within eight frames (about 90 ms
  at 90 fps).

## 0.8

- Each line given to the game's chat log, recorded for addons as it stands at uihook's turn (the
  independent text ABI 1, magic `UIHOOK-TEXT`; `winxi.nativetext`): Ashita's own incoming-text event
  (PluginFlags::UseText), the bytes the game was given and the bytes it will keep, both modes, and
  whether the line is injected, blocked, indented, changed or cut; a ring of 64, the line with serial s
  at (s - 1) % 64, written whole before its serial. Loaded after `addons`, uihook sees each line after
  every addon, so an addon reading lines here no longer depends on its place in the load order
  (chatbox before SimpleLog). Nothing is read from the game or written to it, no line changed or blocked.
  tests/texttap: untouched, changed, injected, blocked, same bytes, missing pointers, a cut line, round
  the ring.

## 0.7

- Lighter every frame: each guarded read of the client's memory (every window the game draws has its
  name read, a chat window its owner followed, and the chat's state, lines and routing are sampled each
  frame) asked Windows about that memory, a system call. The regions found readable are now kept for
  the frame, a read inside one made at once, and forgotten as the frame is presented.
- The game's chat colours, a few thousand bytes read and compared, are read every fourth frame once they
  have been read, and vouched for as current between: ColorFrame still moves each frame.

## 0.6

- Lighter for every window the game draws: a window's own name is read first, so one that is none of the
  chat's costs two guarded reads, not eight; a chat menu's name still has its owner followed afresh.
- Independent menu ABI 1: chat-owned panel bounds published only with successful compact capture.
  Registered native command/magic/ability/inventory/item-use/control menus can anchor above it.
- Verified Window::Render→Update call and target-field copy signatures; live registry ownership,
  header, writable-field and scaled-coordinate checks. Native layout target is changed before its
  own Update; no render-only offset, mouse remapping, selection or input interception.
- Restore owned positions on expired replay/request, expanded chat, opt-out, zoning and unload;
  never restore a freed/replaced owner or overwrite a newer native-written origin. Oversized menus
  and unknown clients/owners stay native. `/uihook menus` reports readiness/apply/restore counts.
- An event's choices (`query`, an NPC's Yes/No under its message) join the moved family; a unique
  in-module registry global, as the others.
- The first log window over a second stacked above it: the game draws the second after the first, so the
  second's replacement covered the half of the first's title above its top edge. While the second is
  replaced (drawn last frame, with a capture), the first's replay is held back and drawn straight after the
  second's. Side by side, or the second drawn first, nothing changes.
- The full log mirrored: ReplaceControls bit 8 (CHAT_REPLACE_ALL, granted only with tabs and text)
  keeps the full log's GPU submissions blocked through its content Draw and Window::Render's cursor,
  scrollbar and row-selection art, so the marked rows' sprites and anything else it draws are left
  undrawn too; every control and row is still measured and published, and all navigation, hover and
  Confirm stay native. SupportedMask bit 11 (2048) advertises it, with the row site. Menus over the
  log are other windows and stay native.
- `/uihook chat history` and `/uihook menus` reach their reports: the command dispatcher read only two
  words and had no `menus` case, so the first gave `/uihook chat`'s report and the second the help.
- The first log window's history read on request: an independent history ABI 1 (magic UIHOOK-HISTORY,
  16 + 36 + 2400 + 65536 bytes). On an addon's request, uihook reads the window's ring (its owner's +18:
  +14 newest, +16 oldest, +1A count, 100 lines of 2 KB from +20) oldest to newest, each line's 60-byte
  header and words, decoded with the expanded log's decoder, and publishes each line's text, whole mode
  word, serial (+0C), flags (+15) and +38 (cleared, with flags masked to 0xB0, on a message's lines after
  its first); read only, once a request. `/uihook chat history` prints the newest 12 with those fields.
  tests/history: order round the ring's end, decoding, the fields, bad indices, a full ring.
- The full log's row highlight measured: each row-selection art call in a skinned full log (drawn or
  not) is measured from its vertices, and a published row whose middle it covers gets Rows flag 32
  (CHAT_ROW_LIT), so the addon lights what the game highlights. No ABI change.
- The expanded chat log placed where the addon asks: menu ABI 1 grows to 108 bytes (LogRequestFrame,
  LogPlace[2] bottom-left in pixels, LogFrame, LogApplied, LogRestored; unreleased, so still 1). The
  full log's Window target is moved before its own Update, as the menus' are, its size kept, kept on
  the screen; a stale request, release and unload give the game's place back. `/uihook menus` says it.
- Chat ABI stays 13; older addons behave as before. Needs live cursor/mouse/artwork validation.

## 0.5

- Chat ABI 13 (71684 bytes): the game's chat colours as configured (ColorFrame, ColorSerial, InlineColors[17],
  CategoryColors[256], ModeCategory[256]), read each frame from the game's mode table, category colour table
  and inline palette, the serial moving only when they change; the game's components are of 80 as one.
  SupportedMask bit 10. Recognition only, nothing written.
  Each table is copied whole, one memory check for each region it lies in, not one for each entry: about 250
  VirtualQuery calls a frame fewer.
- Chat ABI 12: each log window's lines as the game has them now (LinesFrame, Lines[2][3]:
  its lines, its most and its fewest), read each frame from the window's owner, whose fields are pinned
  by its Update and grow signatures and checked for sense. SupportedMask bit 9. The game grows a window
  a row for each message and shrinks it to its fewest lines while none come; its window rect follows.
- Chat ABI 11: the game's two log windows. The second window's bounds (SplitRect,
  SplitRectFrame, read as the primary's are) and the game's routing between the two, read each frame
  (WindowFrame, WindowFlags bit 1 the second window shown, WindowModes[2][8]: per window, a bit for
  each chat mode its Log Window settings keep). SupportedMask bit 8. Nothing is hooked or written for
  it: the client's keep check is recognised (the first window's, which keeps everything while the
  second is hidden, a mode word with bit 15 set, and otherwise its config words B9/BA by the mode's
  category's bit; the second's, which drops bit-15 words and reads BB/BC) with its mode table, its
  category cases (read from the jump table) and the config manager's value reader, and the decision
  is made again for every mode from the same data, again only when the config or the flag changes.
- `/uihook chat` says whether the routing was read, whether the second window is shown, how many
  modes each window keeps and when the second window's bounds were read.

## 0.4

- Chat ABI 10 (70208 bytes): the game's expanded-log rows of text decoded and measured as it draws
  them and, where the addon asks (ReplaceControls bit 4, copied with a successful expanded capture
  and only with the row site), left undrawn, the addon drawing its own text in their places. Each
  row's screen bounds, normalized to the viewport (a row that drew nothing placed where the game
  would have drawn it), its text as the game was given it (CP932 with its 1E/1F colour codes, the
  7F controls left out), its message's chat mode and its flags (cursor, pressed, marked, cut,
  placed) are published newest first (TextFrame, TextCount, TextSerial, Rows[128], Text[64 KB]);
  the serial moves only when the rows change. SupportedMask bit 7.
- A sixth verified CALL site, the one row-drawing call inside the log drawer the content Draw calls
  at +AA (cdecl, 22 words: the row's text, its 60-byte header by value, x, y, alpha, the cursor
  flag, an out pointer and a zero; the caller's add esp,58 checked), validated on its own and taken
  only with the control group; the drawer and the row draw are not patched, and the compact logs'
  rows pass through it untouched. The rows are decoded from the game's glyph words by the exact
  inverse of the client's encoder (transcribed in glyphs.h; the fixture round-trips every two-byte
  character): a single byte is its glyph and 20, glyph 5F (81 3F, the blank in an enemy's name) a
  space, glyphs 2115–2143 the pictographs EF 1F–EF 4D.
- `/uihook chat` says whether the row site was taken and how many rows were published, at what
  frame and serial, and their bytes.
- A menu open over the live full log (a row's action menu, the input line) no longer hands the
  expanded view back to the game: the log keeps its skin under the menu, and StateFlags bit 4
  (`State().nested`) notes it. Invalid layout, or another menu before the full log is made, still does.

## 0.3

- Chat ABI 9 (564 bytes): the game's expanded-log tab strip and scrollbar measured as it draws them
  and, where the addon asks (ReplaceControls bits 1 tabs, 2 scrollbar, copied with a successful
  expanded capture), left undrawn, the addon drawing its own in their places. Each tab's screen
  bounds, normalized to the viewport, its channel (from the owner's tab sprites) and whether it was
  drawn chosen are published (TabFrame, TabCount, Tabs[12]); the scrollbar's bounds and its page
  rows, row count and rows above the view (ScrollFrame, ScrollRect, ScrollPage/Count/Top), read
  from the fields FullLog::Update writes, never written. SupportedMask bit 6.
- A fifth verified CALL site, the full log's call to its tab strip (thiscall, the filter on the stack,
  ret 4; the content Draw's own fixed bytes keep ecx the owner), in the same all-or-none group as the
  four control sites; the strip's GPU submissions, art and labels alike, are blocked while the addon
  draws its own, with the game's hit-tests and Square selection untouched. Measurement reads
  screen-space vertices only, as the clock's.
- `/uihook chat` says what is replaced, how many tabs were measured and the scrollbar's rows.
- chat.h's helpers are inline, so the controls test builds without unused-function warnings.

## 0.2

- Chat ABI 8 (232 bytes): capture validated theme colours with the expanded frame. Tint native
  tabs, row-selection highlight, cursor and scrollbar via four verified CALL sites, preserving
  positions/scale/flags, native fade alpha and all native input/selection behavior.
- Selected tabs use the actual native sprite; scrollbar colours are changed in a local draw-only
  copy, never in native state. Control hooks are optional/all-or-none; missing signatures leave
  controls native. Add argument-preservation/Wine fixtures and optional private-client verification.
- Expanded capture mode 2 replaces only the frame; a unique full-log content signature
  cross-checked against its vtable lets native tabs, text, cursor and scrollbar draw unchanged.
- Keep native expanded keyboard/controller/mouse selection and message actions; retain the frame
  skin on older pages and all native filters. Reject stale compact/expanded captures across boundaries.
- Expanded typography and exact geometry remain native. Requires the updated nativechat bridge;
  offline tests/build pass, live GPU/interaction validation remains pending.

- Add verified native clock and compass boundaries, sharing the existing capture/replay renderer.
- Add independent HUD ABI 6 (164 bytes), clock/compass capabilities, native weather readback, the game's clock text's place, its map grid and its icons' places, a move and a scale for its weather icons and a preview of all of them.
- Redirect Clock::Draw's three icon calls, measuring each icon and leaving undrawn those the addon draws its own of.
- Redirect Clock::Draw's one text call, so a clock replacement hides only the game's text and keeps its day and weather icons.
- `/uihook` lists the addons handing it something now, and what; `/uihook hud` reports what the clock replacement is drawn into.
- Preserve stock clock during compass replacement and stock compass during clock replacement.
- Honor native radar availability and clock enable/visibility without persistent state writes.
- Keep buff ABI 4 and party ABI 3 unchanged; party and HUD release-all calls are isolated.
- Add basic clock addon and winxi nativehud bridge. No compass addon/UI yet.
- Add C++/Wine fixtures, Lua bridge/presentation checks and optional private-client call-graph verification.
- Live clock/compass validation remains pending.

## 0.1

- Consolidate buffhook and partyhook into one modular plugin without changing their handoff formats.
