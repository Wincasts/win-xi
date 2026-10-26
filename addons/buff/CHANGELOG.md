# Changelog

## Unreleased

- uihook alone: the retired buffhook plugin is no longer looked for.
- The plugin's block is let go of when uihook (or buffhook) has been unloaded and loaded again at another address since it was found, even between two looks, so the old DLL's memory is never read or written (the plugin's base is compared each look, as winxi's uihook readers do).
- The controller's confirm in the buff selector removes the status the cursor is on again (the game's own confirm did not, with a DirectInput pad). The press is not taken from the game: buff asks the server to remove the status only if the game has not a quarter of a second later, so it is never asked twice. Controller Navigation, Controller Sounds and Controller Type are back under Controller; an XInput controller's A is always heard, and with XInput chosen a DirectInput pad's cross is read as PlayStation's.
- In the buff selector the game's hand points at the status the cursor is on, at its left as the game's menus have it: the game's animated hand from its menu DAT (winxi.cursor's anc_s), Cursor Size of an icon's height (60% to begin with, 25% to 100%), handed to the plugin anchored and over the window dragged. winxi's highlight is drawn instead only where the hand cannot be read.
- The anchored bar is dragged from anywhere on it, the gaps between its icons too, not just from an icon.
- Grow From: Left, Right or Middle, where a row's icons sit as statuses come and go. Anchored, across a full row of Icons Per Row from where the bar is placed (the mouse finds them there); dragged, the window keeps that side where it is.
- Show Backdrop: off, the dragged window has no backdrop, border or shadow.
- The anchored bar is dragged with the left button to move it, still anchored: dragging sets Anchor Adjustment (not in the buff selector, where a click removes a status). Lock Position stops it, for the dragged window too. Anchor Adjustment and Position are X and Y sliders across the screen in place of number boxes.
- In the selector, the game's hand no longer comes back beside the highlight now and then (uihook 1.58).
- The controller is the game's again: its confirm in the selector removes the status the cursor is on, as it always has, so buff no longer takes A, and its Controller section (Controller Navigation, Controller Sounds, Controller Type) is gone.
- Font and Font Size are winxi's own controls (widgets.FontFile, FontSize), as every addon's; every tooltip, the statuses' included, is drawn by winxi.tooltip, so winxisettings' Tooltips tab applies to them.
- The anchored bar's plugin is uihook, which holds buffhook's module, or the legacy buffhook where uihook is not loaded. The plugin in use is asked after once a frame, and the other only once that one is gone.
- With the new `buffhook` plugin, which comes with buff, the anchored bar is drawn where and when the game draws its own status icons, in their place: the game's menus are drawn over it as over its icons, a menu covering part of it covers just that part, and it goes when they would. Without the plugin it is drawn over everything, as before, and the settings say how to load it.
- In the game's buff selector, with the plugin, the game's hand (which points at where the game's icons would be) is put out of sight and the status its cursor is on has winxi's highlight round it, anchored or dragged; a click on an icon removes it. Dragged with the game's icons hidden, the plugin keeps them and the hand away in place of changing the game's code.
- The anchored bar handed to the plugin is written only when something of it changes, about once a second as the times go down, and drawn from winxi's sheet of icons in a texture or two; the plugin keeps the vertices it made of it.
- The times' letters are drawn from imgui's font texture as the plugin reads it (buffhook 1.1), and buff no longer asks imgui for it: once the texture was above 2 GB, as it can be after a while on Windows, Ashita could not hand it to Lua at all, and the times could not be drawn. Needs winxi 4.
- The timers handed to the plugin read the font's texture through winxi's fonts.Texture (the data first, then the reference, each apart), so an exception from the reference no longer leaves them out. Needs winxi 2.
- The Covering Menus list, `/buff covers` and Hide Anchored Buffs Under Menus are gone: the plugin does what they stood in for.

## 1.0 — first release

- The statuses you are under, in a window, in place of the game's own row: winxi's custom icons (FFXIV's to start) and the time each has left.
- Hover an icon for its name, number and description; right-click to remove it where the game allows.
- Sits where the game's row was, or anywhere you put it; Icon Size, Icons Per Row, Show Time Left, Font and Font Size.
