# Changelog

## 1.0 — first release

- Draws the buff addon's bar where and when the game draws its row of status icons, in their place: the game's menus are drawn over it as over its icons, and it goes when they would.
- Puts the buff selector's hand out of sight while it draws the bar, and says which status the game's cursor is on; quads of colour alone, for the addon's highlight.
- Keeps the vertices it made of the bar, and the textures it holds, while the addon hands over the same one (its Sequence) in the same place.
- Without a bar from the addon, the game draws its own icons; with functions it does not recognise, it says so and changes nothing.
