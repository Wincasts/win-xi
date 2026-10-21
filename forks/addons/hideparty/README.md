# hideparty (winxi's changes)

atom0s's hideparty, which hides the game's own party and target frames (`/hideparty`, `/hideparty hide`,
`/hideparty show`), with these changes.

The frames are hidden as soon as hideparty loads, with no `/hideparty hide` needed; `/hideparty show`
brings them back. Unloading it shows them again, where atom0s's left them as they were.

While the game's party cursor is out (a member is being picked from the party list, in the party menu or
as a sub-target) the party frames are shown again, and hidden once it has gone. The game's cursor cannot
move freely between party frames that are hidden: it is thrown out of the one it enters and on to the
next, so that it was trapped in the alliance and could not return to the party. The target frame stays
hidden throughout.

While the frames are hidden, hideparty draws the target cursor itself. The game's target box and the arrow
over what you have targeted are one primitive, so hiding the box hides the arrow with it. The cursor is the
game's own: the animated `anc_l` sprites in `ROM/119/51.DAT`, read through `winxi.cursor` (so the winxi
library must be installed), anchored over the target and the sub target. While a spell or ability is
being aimed, the sub cursor is tinted blue, yellow or red by whether the action reaches, as the game does.
Its size, opacity and colours are set at the top of `targetcursor.lua`; how each was measured is in
[TARGETCURSOR.md](TARGETCURSOR.md). Under the [lens](../../../plugins/lens) plugin's warp the cursor is
placed where the warp shows the target, through `winxi.lens`.

The target cursor is **targetcursor** by Hiken, a fork of Jyouya's `customtarget` as extended by yzyii
(Rag), under the MIT licence in [targetcursor.LICENSE](targetcursor.LICENSE). Only its drawing has changed
here: it draws the game's sprites from the DAT in place of the PNG sheets it shipped with.
