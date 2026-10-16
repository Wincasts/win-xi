# Changelog

## 1.33

- The font's texture is read through winxi's fonts.Texture: from the fields of the atlas's texture data and its reference first, then their methods, each asked apart. On Windows the methods could both throw an exception (imgui's assertion, as Ashita reports it) once the game had been running a while, and the names were the game's for the rest of the session; a field is only read and cannot trip it.
- Diagnostics say what imgui answered when the font's texture cannot be had, in the history, the chat and the log. The log reads everything imgui holds of the texture apart (the texture data, every id each way, every texture in the atlas's list), and the history notes each change of the texture's id. The reason no longer says the id was 0 when it was an exception. Needs winxi 3.

## 1.32 — first release

- Shows and hides the names over characters' heads by what they are (self, party, alliance, other players, pets, NPCs, monsters), through the namehook plugin, which comes with it.
- Draws the names in winxi's style: font, size near and far, outline, player icons, and monsters' level and aggro signs, written by a format of your own.
- What a check shows under a checked monster's name, and the statuses over a name.
- Experimental: a tracked notorious monster, and letters for monsters of the same name.
