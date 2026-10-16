# Changelog

## Unreleased

- The font's texture is read through winxi's fonts.Texture: from the atlas's texture data first, then its reference, each asked apart. Asked of the reference first, an exception there (imgui's assertion, as Ashita reports it, which it can make once the atlas has been made again) kept the data from being asked, and the names were the game's for the whole session.
- Diagnostics say what imgui answered when the font's texture cannot be had, in the history, the chat and the log, and the log reads its texture data, data id and reference id apart; the reason no longer says the id was 0 when it was an exception. Needs winxi 2.

## 1.32 — first release

- Shows and hides the names over characters' heads by what they are (self, party, alliance, other players, pets, NPCs, monsters), through the namehook plugin, which comes with it.
- Draws the names in winxi's style: font, size near and far, outline, player icons, and monsters' level and aggro signs, written by a format of your own.
- What a check shows under a checked monster's name, and the statuses over a name.
- Experimental: a tracked notorious monster, and letters for monsters of the same name.
