# Changelog

## 1.34

- Subtarget Scale, under Name Appearance: the name under the sub-target cursor (`<st>`, `<stpc>` and the like) can be drawn from 50% to 200% of the size of the others while you choose. 100% to begin with, as before.

## 1.33

- The names' letters are drawn from imgui's font texture as the namehook plugin reads it, and Name no longer asks imgui for it. Its id is 64 bits and a Lua integer in this game 32: once the texture was above 2 GB, as it can be after a while on Windows, Ashita could not hand it to Name at all, and the names were the game's for the rest of the session. Needs namehook 1.25, which comes with it, and winxi 4.
- Letters for monsters of the same name cut their badges from the font's texture the plugin drew from, which it holds while it draws; until it has drawn, the letters are plain. Never anything that is not a texture's address is given to Direct3D to read.
- Diagnostics say whether imgui has the font texture ready and what it says of it, and the log the texture the plugin drew from; the history notes each time imgui makes the texture again.

## 1.32 — first release

- Shows and hides the names over characters' heads by what they are (self, party, alliance, other players, pets, NPCs, monsters), through the namehook plugin, which comes with it.
- Draws the names in winxi's style: font, size near and far, outline, player icons, and monsters' level and aggro signs, written by a format of your own.
- What a check shows under a checked monster's name, and the statuses over a name.
- Experimental: a tracked notorious monster, and letters for monsters of the same name.
