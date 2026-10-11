# Changelog

## namehook 1.21 - 2026-10-11

- `target on` no longer shows your own name: with own names hidden, your name stays hidden while you have yourself targeted.

## namehook 1.20 - 2026-10-11

- Renamed from nameplatehook to `namehook`: the DLL, the `/namehook` command and the `config\namehook` folder all carry the new name, and `/nh` is short for the command where `/nph` was.
- Until `config\namehook\defaults.ini` exists, the settings and the whitelist kept in `config\nameplatehook` are read, and failing those nameplatew's as before.
- The block is found by `NAMEHOOK` and eight 0s, where it was `NAMEPLATEHOOK` and three: an addon written for nameplatehook does not find it.

## nameplatehook 1.11 - 2026-10-11

Does what 1.10 does, with less work each frame:

- The names are made ready for addons once a frame, in the scene they were drawn in, and again only if more are drawn. The client ends a scene a dozen times a frame, and they were made ready each time, the camera asked after and every name copied.
- Everybody's pets are looked for once in 16 frames, not every frame: it is a look at every player and every pet there is. A pet that appears is taken for an NPC or a monster for a quarter of a second at most. The local player's own pet is still found every frame.
- A player's name is looked for on the whitelist by a number made from it, and compared only with the names that have the same number.
- The device's states for drawing an addon's names are made when the frame's first such name is drawn, not at the frame's first name of any kind; the device is asked for once a frame, not once a name; and a name drawn from one texture has it set once, not twice.

## nameplatehook 1.10 - 2026-10-11

- An addon can have the plugin draw names for it. It leaves each name set out as quads (a rectangle of a texture for each letter and icon) in `HookDraw`, found through the block's new `Draw`, and claims the name's category; the plugin draws the quads in the client's own picture where the client was about to draw the name, as deep in the picture as the name is, so that whatever is in front of the name hides it. `README.md` describes it.
- The block says how large the picture the client draws the world on is (`TargetWidth`, `TargetHeight`), which may be larger than its window. They and `Draw` are where `Reserved` was, and the block's `Version` is 2: an addon written for 1 does not read it.
- A name drawn that way is listed with a new flag, custom (0x100).
- Added `/nameplatehook probe`, which says what the client is drawing on as it draws a name. It is for finding out how a client draws, and is not in the help.
- The plugin answers Ashita's `Direct3DInitialize`, without which 1.00 was not loaded.

## nameplatehook 1.00 - 2026-10-11

Forked from nameplatew 0.60 as `nameplatehook`: the DLL, the `/nameplatehook` command (`/nph` for short) and the `config\nameplatehook` folder all carry the new name. nameplatew was itself forked from Nameplate-AshitaV4 0.1.0, of Nameplate 0.51; their changes are listed in nameplatew's `CHANGELOG.md`.

- Every name is sorted into one of eight categories (self, party, alliance, players, mypet, pets, npcs, monsters), and each category's names are shown or hidden with `/nameplatehook show|hide|toggle <category>...`. These take the place of nameplatew's `mode` and `alliance` commands, which are gone.
- Added `/nameplatehook target on|off`: the target's name is shown whatever its category.
- Added `/nameplatehook status`.
- The names the client was about to draw each frame are listed for addons, hidden ones among them: whose each is, its category, where it is in the world and on screen, its colours, what the client writes for it, and whether it is drawn. The list, and the settings beside it that an addon may write, are described in `README.md`.
- An addon can show or hide the name of one entity, and can claim categories whose names it draws itself in place of the client.
- The client's two calls that draw a name's lines are pointed at the plugin, when both are found where they are expected; they are put back on unload. On a client where they are not, names are shown and hidden all the same, and none are listed.
- Which categories are hidden, and the target setting, are kept in `defaults.ini` as `Hidden` and `AlwaysTarget`. Until that file exists, settings are read from nameplatew's `config\nameplatew\defaults.ini`, its `NameMode` becoming the categories it hid, and the whitelist from its `whitelist.txt`.
- The whitelist is as it was, and is of players only.
- Removed the Windower 4 entry points, which nameplatew did not build.
