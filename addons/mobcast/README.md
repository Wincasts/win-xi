# mobcast

Shows the actions of nearby enemies in a compact on-screen window. Each spell, weaponskill and
ability appears as it begins, worded as in the chat log and colour-coded by type.

## Highlights

- Follow enemy spells, weaponskills and abilities without reading the chat log.
- Each entry updates as the action progresses: cast, used or interrupted.
- Show only your current target, and only the kinds of action you choose.

It needs only the `winxi` library (`addons/libs/winxi`).

Example lines:

    Mad Sheep readies Sheep Song on Tester.
    Goblin Smithy starts casting Fire on Tester.
    Orcish Fighter uses Mighty Strikes.

## Commands

- `/mobcast` opens or closes the settings.
- `/mobcast test` shows one line of each kind, so you can see how the box looks.

## What it shows

mobcast takes trigger's indicator further. trigger shows a line only for the spells and moves you have
made triggers for. mobcast shows a line for everything an enemy does.

A line changes as the action goes on:

| The line starts as | It can become |
|---|---|
| `starts casting` (a spell) | `casts` when the spell lands; `'s casting is interrupted` when it is broken off; `is paralyzed and stops casting` (or `is intimidated`) when that stops it at the end |
| `readies` (a weaponskill) | `uses`, or `is interrupted` |

An ability is used at once, with no warning first, so its line stands alone. If the same line comes
again while it is still on screen, it stays up longer instead of showing twice.

An enemy here is a monster that is nobody's pet. Players, NPCs and pets are left out.

When a spell or weaponskill is aimed at someone else, the line names them as the chat log does. A
party member is named from the party list. Anyone else is named from the people and monsters in the
area.

## Settings

Type `/mobcast` to open them. Each setting is a row: its name, a sentence saying what it does, and its
control on the right. The sections fold open and shut with their [-] and [+]. While the settings are
open and nothing is happening, the box shows a sample line of each kind. This lets you drag it where
you want it.

### Settings tab

**Window**

- **Lock Window** holds the box in place and lets the mouse click through it to the game. When it is
  off, you can drag the box.
- **Position** is where the top of the box is on the screen, on the side it grows from. Dragging the
  box sets it too.
- **Grow From** is the side that stays in place as lines get longer or shorter: Left, Center or Right.
  The lines line up on that side too.
- **Font Size** is the size of the lines in pixels. Theme Size uses the size set in Winxi Theme.

**Enemies**

- **Show Spells**, **Show Weaponskills** and **Show Abilities** turn each kind of line on and off.
- **Show Targets** names who a spell or weaponskill is aimed at. When it is off, the lines say only
  what is coming.
- **Only My Target** shows only the enemy you have targeted. When it is off, it shows every enemy near
  you.

**Lines**

- **Duration** is how long a line stays: 1 to 30 seconds. A line that comes again starts its time
  over.
- **Max Lines** is how many lines the box holds at once: 1 to 10. Past that, the oldest line goes.
- **Newest Line** is where a new line goes:
  - **Bottom**: lines are in the order they came, the oldest at the top.
  - **Top**: the newest line is always at the top, just under the box's edge, and older ones move down.

  A line that changes (for example `starts casting` becoming `casts`) keeps its place.
- **Spell Color**, **Weaponskill Color** and **Ability Color** are the colours of each kind of line.
- **Test** shows a line of each kind, as `/mobcast test` does.

### Visibility tab

- **Fade In And Out** fades the box in as it appears and out as it goes.
- The hiding rules every winxi addon has: hide while the map is open, while the chat log is opened
  out, while changing area, during events (cutscenes), and while the game's interface is hidden.

### Look

The box uses the game-window look set in wxi: theme, border, background, frame title and font. Its
lines use the theme's Text Outline (the dark edge round the text). The settings window uses winxi's
settings-window look.

## Limits

mobcast reads the same messages from the server that trigger reads: the ones the game gets about each
action.

- A spell or move the game does not announce (no message when it begins) is not shown here either.
- An attack, an ability or an item stopped by paralysis or intimidation names nothing, so it is not
  shown.
- The name of a move is the game's own name for it. Where the game has no name, the line says
  `Spell 999`, `Weaponskill 999` or `Ability 999`.
