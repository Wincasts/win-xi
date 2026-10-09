# xiframes
party, target and pet frames in winxi's themed windows, with bars and a layout after the Windower
addon [XivParty](https://github.com/Tylas11/XivParty)'s compact one.

- **Party**: your party and the other two alliance parties. A member is a line: the name, an HP bar
  and a smaller MP bar with their values, and TP as a value. The member targeted has `>>` before
  their name, in blue; a leader has a circle before theirs. Your own party's list grows upwards, and
  has its buffs running leftwards from the window. A circle beside the window marks a party or
  alliance invite waiting for an answer, and a brown one ringed in gold marks anything in the treasure pool.
- **Target**: your target, sub-target and target of target, each a line of the same kind: the name,
  the HP bar, the distance and the HP percentage, with the enemy's debuffs under it if wanted.
- **Pets**: your pet, and your party members' pets, listed under your party below a line.

## usage
`/xiframes` (or `/xif`) opens the settings. Its Style tab sets how every frame is drawn (sizes,
where the values sit, the outline, the bookends); Party, Target and Pets have what is each one's
own. Organize, at the foot of the window, fills the frames with sample data to drag into place.

## the code
| file | what it does |
|---|---|
| `xiframes.lua` | puts the rest together: what goes in which window each frame, which packets go where |
| `party.lua`, `pets.lua`, `target.lua` | read the game, and hand back lists of lines |
| `frames.lua` | draws a list of lines: the bars, names and values |
| `notices.lua` | invitations and treasure waiting, and their icons |
| `debuffs.lua` | what is on each enemy, from the actions the server reports |
| `windows.lua` | the windows the lists are drawn in: themed, arranged, fading, held by a corner |
| `options.lua` | the settings, each an entry in a list: defaults and the settings tabs come from it |
| `config.lua` | the settings window |
| `draw.lua`, `colors.lua`, `game.lua`, `packets.lua` | drawing on a draw list, the colours that mean something, small things asked of the game, and the packets read |

`tests/run.sh` loads the addon against a stand-in for Ashita, and compares what it draws, call for
call, with a kept copy.

The bar images are XivParty's, cut down to the bars themselves, in `assets/bars` with its licence.
Needs `libs/winxi`.
