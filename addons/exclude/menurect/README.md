# menurect — native menu rectangle discovery POC

A **read-only, opt-in diagnostic**, not a replacement UI. It explores the focused native menu's
memory and lets you overlay plausible rectangle fields. Nothing is treated as a verified bound,
and this addon does not change buff visibility, intercept controller input, or write game memory.

## Running it

Install `addons/menurect` alongside the other addons and the updated `addons/libs/winxi` library.

1. `/addon load menurect`
2. `/menurect` opens the probe; opening it enables guarded reads.
3. Open a native menu such as Items or Equipment. Watch **Focused** to confirm the menu detected.
4. Enter the menu's approximate on-screen bounds in **Approximate screen L/T/R/B**, then use
   **Find closest snapshot candidate**. This only helps search; it does **not** validate anything.
5. Enable **Overlay selected candidate**. The amber outline is drawn above everything for
   inspection. Compare all four edges against the real menu, not just its position.
6. Use **Candidate**, **Previous**, and **Next** to try other interpretations. **Preview scale**
   and **Preview offset** help investigate logical UI coordinates versus display pixels. They are
   manual diagnostic transforms, not automatically determined native UI scaling.
7. Use **Capture snapshot** to write `addons/menurect/menu-rect-probe.txt`. Copy/rename each capture
   before taking another; the file is overwritten. Include a screenshot of the native menu and
   candidate outline, the candidate index/label, and any preview transform.
8. `/menurect off` stops all probe reads and removes the overlay; closing its window does too.

The window can be dragged away from the menu. Preview selection resets on a change of focused
menu or node/header identity. The selected candidate is reread at 10 Hz; closing a menu drops the
preview on the next poll. **Rescan** refreshes candidate snapshots, resetting preview selection.

## What to validate

A matching outline in one screenshot is insufficient. A useful field should:

- Match menu bounds across several openings, without depending on a particular heap address.
- Track movement/resizing if available; otherwise test different UI resolutions/scales.
- Change appropriately between differently sized menus and between parent/submenus.
- Not be an icon cell, text box, cursor position, static DAT geometry or animation target instead
  of the actual visible window.

Try Items, Equipment, the main menu, a dialog submenu, expanded chat, and the native buff selector.
Capture both successful candidates and menus where no candidate matches. There may be no match:
geometry might live deeper than this bounded scan or be computed from separate fields.

## Known chain versus hypotheses

The existing Ashita `menu` pointer (also used by Ashita's `autologin` addon) and the signature used
by `winxi.game.MenuName` locate:

```
slot -> holder -> focused node
                     +04 -> header
                               +46 -> 16-byte menu name
```

The name chain is established; **rectangle fields are not**. The probe reads the node/header and
up to ten additional readable blocks referenced by aligned pointers in their `+08..+3C` fields.
It follows at most one hop, reads 256 bytes per block, and never walks a guessed menu linked list.
It tests signed 16-bit, signed 32-bit, and float32 quadruples as either L/T/R/B or X/Y/width/height.
Screen-relative sanity checks reject tiny, inverted, non-finite and wildly off-screen values.
Many false positives are still expected.

The capture contains scan-time candidate values and block hex dumps, plus the selected live
rectangle if valid. It does not contain a complete client memory dump. It can still contain
unrelated nearby menu data; review it before sharing publicly.

Reads use `VirtualQuery` to reject uncommitted, guarded, no-access and execute-only pages before
copying bytes. There are no writes or page-protection changes. A replaced child pointer invalidates
the preview until rescanned. The range checks reduce risk; this remains experimental client-memory
inspection and should be tested cautiously.

## Next steps after verification

The focused menu alone is **not** enough for full occlusion: parent windows and non-focused UI can
remain visible above buffs. We need the active draw-window list, each window's current rectangle,
visibility and ordering. Verified screen rectangles can then drive clipping (including partial
icon/timer coverage) and exclude covered regions from tooltip/cancellation/controller hit-testing.
Controller navigation additionally needs cursor/selection state and input routing; a window
rectangle by itself does not provide those.

## Tests

```
luajit tests/harness.lua menurect addons/menurect/menurect.lua tests/menurect_check.lua
```

Synthetic tests cover the pointer chain, bounded scan, rectangle layouts, live updates, rejection
of stale pointers/invalid values, and opt-in/off behaviour. Actual Windows page checks and native
menu geometry still require in-game validation.
