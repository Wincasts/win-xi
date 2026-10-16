# Changelog

## 1.1

- A texture of `1` (`BUFF_TEXTURE_FONT`) is imgui's font texture, which the plugin reads itself as it draws the bar, and the bar's vertices are made again when imgui makes that texture again. Its id is 64 bits and a Lua integer in this game 32: once the texture is above 2 GB, as it can be after a while on Windows, Ashita could not hand it to the addon at all. `FontTexture` says which texture it drew from. The block is version 4, so that buff does not give `1` to an older plugin, which would take it for an address.

## 1.0 — first release

- Draws the buff addon's bar where and when the game draws its row of status icons, in their place: the game's menus are drawn over it as over its icons, and it goes when they would.
- Puts the buff selector's hand out of sight while it draws the bar, and says which status the game's cursor is on; quads of colour alone, for the addon's highlight.
- Keeps the vertices it made of the bar, and the textures it holds, while the addon hands over the same one (its Sequence) in the same place.
- Without a bar from the addon, the game draws its own icons; with functions it does not recognise, it says so and changes nothing.
