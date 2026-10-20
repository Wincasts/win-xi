# mobcast

Says, in a small window in the theme, what the enemies about you are doing: a spell begun, a
weaponskill readied, an ability used, each line in the chat log's own words and in a colour of its
kind, up for a few seconds. It is for seeing what is coming where you are looking, rather than finding
it in the log. It needs only the `winxi` library (`addons/libs/winxi`).

    Mad Sheep readies Sheep Song on Tester.
    Goblin Smithy starts casting Fire on Tester.
    Orcish Fighter uses Mighty Strikes.

- `/mobcast` opens or closes the settings
- `/mobcast test` says a line of each kind, to see the box by

The box is trigger's indicator taken further. Trigger says a line only for the spells and moves you
have made triggers for; mobcast says one for everything an enemy does, and a line follows what it is
about: a mob's `starts casting` becomes `casts` as the spell lands, or `'s casting is interrupted`
when it is broken off, and its `readies` becomes `uses`, or `is interrupted`. An ability is used at
once, with no warning sent, so its line stands by itself. A line said again while it is up stays up
longer rather than being said twice.

An enemy is a monster that is nobody's pet: players, NPCs and pets are left alone. Whom the
spell or weaponskill is aimed at is named as the log names them, when they are someone else: a party
member by the party list, anyone else by the area's entities.

## Settings

Every section collapses with its [-]/[+].

**Enemies**

- **Show Spells**, **Show Weaponskills**, **Show Abilities** switch each kind of line on and off.
- **Show Targets** says whom a spell or weaponskill is aimed at. Off, the lines say only what is coming.
- **Only My Target** keeps the box to the enemy you have targeted. Off, every enemy about you.

**Box**

- **Duration** is how long a line stays, 1 to 30 seconds. A line said again starts its time over.
- **Max Lines** is how many the box holds at once, 1 to 10; past that the oldest goes.
- **Grow From** is the side that stays where it is as the lines get longer or shorter, Left, Center or
  Right. The lines are set to that side too.
- **Lock Window** holds the box where it is and lets the mouse through it to the game. Off, it can be
  dragged.
- **Font Size** is the lines' size in pixels; Theme Size (0) follows Winxi Theme.
- **Spell Color**, **Weaponskill Color** and **Ability Color** are the colours of each kind of line.
- **Test** says a line of each kind, as `/mobcast test` does.

While the settings are open the box shows a sample line of each kind when it has nothing to say, so
that it can be dragged where it is wanted.

**Visibility**

- **Fade In And Out** fades the box in as it appears and out as it goes.
- The hiding rules every winxi addon has: while the map is open, the chat log opened out, changing
  area, during events, and with the game's interface hidden.

The box uses the game-window theme, border, background, frame title and font set in winxisettings,
and the lines have the theme's Text Outline. The settings window uses winxi's settings appearance.

## What it reads

Everything comes from the action packet (0x028), as trigger reads it. A spell beginning and a
weaponskill readied are two kinds of action whose first result numbers the spell or move; one broken
off is the same kind with the action's four letters beginning `sp` rather than `ca`, as the Phoenix
server writes them. A spell cast, a mob's move done and an ability used name the spell or move as the
action itself. A spell or move the game keeps quiet about (no message with its beginning) is left
alone here too.

A move's name is the game's: a monster's moves are numbered from 256 up and named in the game's list
of monsters' abilities; a weaponskill of the players' own, or an ability, in its list of abilities.
Where the game has no name, the line says `Spell 999`, `Weaponskill 999` or `Ability 999`.

`reader.lua` reads the packets and makes the lines, `box.lua` draws the window, and
`tests/mobcast_check.lua` works them through: spells begun, cast and broken off; weaponskills
readied, used and broken off; abilities; targets by the party list and by id; players, NPCs, pets
and unknowns left alone; each switch; the box's lines, time, lock and size; the sample; hiding and
fading; bad settings made good.
