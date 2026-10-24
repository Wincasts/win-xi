# Changelog

## Unreleased

- In the selector, the game's hand no longer comes back beside the highlight now and then (uihook 1.58).
- With a Controller Type of the other kind than the controller pressing buttons (a DualSense on DirectInput, XInput chosen), A could not remove a status: the Controller settings now say so, and buff says it once in the chat the first time it happens in the selector. Needs winxi 44.
- Font and Font Size are winxi's own controls (widgets.FontFile, FontSize), as every addon's; every tooltip, the statuses' included, is drawn by winxi.tooltip, so winxisettings' Tooltips tab applies to them.
- The anchored bar's plugin is uihook, which holds buffhook's module, or the legacy buffhook where uihook is not loaded. The plugin in use is asked after once a frame, and the other only once that one is gone.
- With the new `buffhook` plugin, which comes with buff, the anchored bar is drawn where and when the game draws its own status icons, in their place: the game's menus are drawn over it as over its icons, a menu covering part of it covers just that part, and it goes when they would. Without the plugin it is drawn over everything, as before, and the settings say how to load it.
- In the game's buff selector, with the plugin, the game's hand (which points at where the game's icons would be) is put out of sight and the status its cursor is on has winxi's highlight round it, anchored or dragged; a click on an icon removes it. Dragged with the game's icons hidden, the plugin keeps them and the hand away in place of changing the game's code.
- In the selector, a controller's A removes the status the cursor is on (the game's own does not): Controller Navigation, with Controller Sounds and Controller Type, in a Controller section of the settings.
- The anchored bar handed to the plugin is written only when something of it changes, about once a second as the times go down, and drawn from winxi's sheet of icons in a texture or two; the plugin keeps the vertices it made of it.
- The times' letters are drawn from imgui's font texture as the plugin reads it (buffhook 1.1), and buff no longer asks imgui for it: once the texture was above 2 GB, as it can be after a while on Windows, Ashita could not hand it to Lua at all, and the times could not be drawn. Needs winxi 4.
- The timers handed to the plugin read the font's texture through winxi's fonts.Texture (the data first, then the reference, each apart), so an exception from the reference no longer leaves them out. Needs winxi 2.
- The Covering Menus list, `/buff covers` and Hide Anchored Buffs Under Menus are gone: the plugin does what they stood in for.

## 1.0 — first release

- The statuses you are under, in a window, in place of the game's own row: winxi's custom icons (FFXIV's to start) and the time each has left.
- Hover an icon for its name, number and description; right-click to remove it where the game allows.
- Sits where the game's row was, or anywhere you put it; Icon Size, Icons Per Row, Show Time Left, Font and Font Size.
