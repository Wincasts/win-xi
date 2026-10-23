# menus

Draws the game's menus in the winxi look. The game's own menus stay open and do everything they
do: the controller moves their cursor, Confirm and Cancel are theirs, and what they list is what the
game lists. The `uihook` plugin leaves them undrawn and says what they would have drawn, and menus
draws them again in the theme, each piece where the game put it: the window as a winxi panel, its
text in the theme's font (an item's name in the colour the game gives it), its icons from the game's
own textures, the row the cursor is on lit in the Highlight Color, the game's hand where the game put
it, and the scrollbar.

Needs `uihook` 0.98 or newer (its menu mirror) and winxi 35.

- `/menus` opens or closes the settings

It mirrors the menus that print their words (the item lists, the ability, spell, emote and mount
lists, currencies, missions, quests and the friend list among them); the game's other menus, whose
labels are pictures (the main menu, the command menu, config), are drawn by the game unless the
experimental Picture Label Menus are on.
Everything is placed where the game placed it, so its hit-tests line up with what is seen. With Mouse
Follows Menus on, a menu can be moved and scaled and the mouse still works it where it is drawn.

## Settings

Every section collapses with its [-]/[+]. Mirror and Mouse come first and start open; the groups of menus
start collapsed.

Which of the game's windows are mirrored, in eleven groups; off, the game draws its own. In each group the
menus sit three to a row, each a checkbox with its name, under an All checkbox that switches the whole
group (on where every one of them is):

- **Items** (on to start): Inventory, Item Info, Mog Safe, Shop.
- **Lists** (on): Abilities, Emotes, Mounts, Currencies, Missions, Quests, Quest Pages,
  Friend List, Area List, Search Results, Help Desk.
- **Status** (off): Status, Level And EXP, Profile, Job Levels, Combat Skills, Crafting Skills, Gil.
- **[Experimental] Picture Label Menus** (off): Main Menu, Command Menu, Magic Categories, Ability
  Categories, Status Menu, Config Menu, Mog House Menu, Mog House Options, Item Sort, Macro Menu,
  Mission Menu, Friend List Menu, Communication Menu, Unity Menu, Bazaar Menu, Menu Name, Top Bar. The game spells their
  words one letter at a time from its menu font; each is drawn as a winxi panel with those words read
  back and drawn in the theme's font, the row the cursor is on lit and the hand. What is not a letter
  of that font (button bars) is the game's own art. A menu's title, in the game's serif letters, is set
  on the panel's top edge as a winxi title (every mirrored menu that has one). In Outline their elements are outlined in
  purple.
- **Config** (off): Chat Filters, Battle Message Filters, Chat Colors.
- **[Experimental] Equipment And Items** (on): Equipment, Item Quantity, Gil Amount, Use Item, Item
  Sort Options.
- **[Experimental] Auction House** (on): Auction House, Categories, Weapons, Armor, Scrolls, Materials,
  Food, Ammunition, Items, Item List, Price History.
- **[Experimental] Shops And Prompts** (on): Shop Menu, Sell, Yes Or No, Sort Yes Or No, Question,
  Party Invitation.
- **[Experimental] Mog House And Delivery** (on): Mog House Exit, Storage, Delivery Menu, Delivery
  Box, Send Box, Job Change Menu, Job Select.
- **[Experimental] Jobs** (on): Ability Menu, Ability Sort, Automaton, Automaton Status, Automaton
  Menu, Blue Magic Spells, Blue Magic Info.
- **[Experimental] Magic** (on): Spells, Magic Menu, Magic Sort, Blue Magic Sort.
- **[Experimental] Other Menus** (on): Map Menu, Social Menu.

The experimental groups were found in play with `/uihook census` and have not yet been looked at
mirrored: try them in Outline first. Menus added in a release start on, for every character, so they are
seen; one switched off stays off. Their names are best guesses from the game's own; the HUD and
chat windows (the party list, target, chat log, network) are left to the addons that draw them.

The Status and Config windows also draw some of their labels as pictures. Those drawn with a window's
contents come through as the game's art; any drawn with its frame would be lost. Look at them in
Outline (each label should have a blue box) before replacing them.

**Mouse**
- Mouse Follows Menus [Experimental]: the mouse works each menu where it is drawn here, moved or at any
  scale. uihook 1.2 gives the game each mouse message on a drawn menu (moves, presses, releases) at the
  same place on the game's own, so pointing at an entry moves the game's cursor to it and a click
  chooses it; the wheel scrolls the menu the game's cursor is on. Where the game's own menu is but
  nothing is drawn, the game is given no mouse. A press on a menu's edge (its outer 8 pixels) drags it,
  kept from the game with its release. Ashita, imgui and other addons see the mouse where it really is.
  With an older uihook the mouse is kept from the menus instead, and a press anywhere on one drags it.
  Off, the menus are drawn where the game puts them and the mouse is the game's. Replace only.
- Lock Menu Positions: menus cannot be dragged (a press on an edge is the game's). Each menu's place is
  kept as an offset from where the game puts it, kept on the screen, and saved as it is let go.
- Reset Positions: every menu back where the game puts it.

**Mirror**
- Mirror Mode: Replace leaves the game's menus undrawn and draws them again. Outline leaves them as
  the game draws them, and outlines over them what uihook measured: the window (yellow), each piece of
  text (green), each icon (blue), the cursor (red), the row highlight (pink) and the scrollbar
  (white). For checking what is measured before replacing.
- Menu Scale (0.75x to 2x): how large the menus are drawn in Replace, each grown from the corner of the
  screen it is nearest (the item lists from the top left, the item box from the bottom left), so it
  stays on the screen. Its text is drawn larger, not stretched. The controller works as ever; with Mouse
  Follows Menus on, so does the mouse.
- Status: what uihook says of the mirror, and any menu given back to the game, and why.

## When the game's own comes back

Whatever goes wrong, the menu is never left unseen: a window whose place could not be measured is the
game's to draw for two seconds, an error in drawing gives every menu back to the game for ten (said
once in the chat log), and uihook draws a window itself again four frames after menus last asked,
so unloading menus or uihook gives the game's menus back.
