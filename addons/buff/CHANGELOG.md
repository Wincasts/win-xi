# Changelog

## Unreleased

- With the new `buffhook` plugin, which comes with buff, the anchored bar is drawn where and when the game draws its own status icons, in their place: the game's menus are drawn over it as over its icons, a menu covering part of it covers just that part, and it goes when they would. Without the plugin it is drawn over everything, as before, and the settings say how to load it.
- In the game's buff selector, with the plugin, the game's hand (which points at where the game's icons would be) is put out of sight and the status its cursor is on has winxi's highlight round it, anchored or dragged; a click on an icon removes it. Dragged with the game's icons hidden, the plugin keeps them and the hand away in place of changing the game's code.
- In the selector, a controller's A removes the status the cursor is on (the game's own does not): Controller Navigation, with Controller Sounds and Controller Type, in a Controller section of the settings.
- The anchored bar handed to the plugin is written only when something of it changes, about once a second as the times go down, and drawn from winxi's sheet of icons in a texture or two; the plugin keeps the vertices it made of it.
- The timers handed to the plugin read the font's texture through winxi's fonts.Texture (the data first, then the reference, each apart), so an exception from the reference no longer leaves them out. Needs winxi 2.
- The Covering Menus list, `/buff covers` and Hide Anchored Buffs Under Menus are gone: the plugin does what they stood in for.

## 1.0 — first release

- The statuses you are under, in a window, in place of the game's own row: winxi's custom icons (FFXIV's to start) and the time each has left.
- Hover an icon for its name, number and description; right-click to remove it where the game allows.
- Sits where the game's row was, or anywhere you put it; Icon Size, Icons Per Row, Show Time Left, Font and Font Size.
