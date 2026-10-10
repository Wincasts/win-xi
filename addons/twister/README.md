# twister

Plays a sound when something happens that is worth hearing about. It has no window, only settings,
and needs only the `winxi` library (`addons/libs/winxi`).

- `/twister` opens or closes the settings
- `/twister test` plays every event's sound in turn

| Event | Sounds when |
|---|---|
| Tell Received | someone sends you a tell |
| Name Mentioned | someone else says your character's name in party or linkshell chat |
| Party Invite | you are invited to a party or an alliance |
| Trade Request | someone asks to trade with you |
| Examined | someone examines you |
| TP Ready | your TP reaches 1000 |
| Low HP | your HP falls to the threshold (25% unless changed); again only after it has been 5 points over |
| Low MP | the same for MP (20%); never on a job with no MP |
| Party Member KO | someone else in your party is knocked out, in your area: they have had no HP for a second, and had been in the area five seconds or more |
| Skill Up | one of your skills, or one of your pet's, rises or reaches a new level, crafts included |
| Item Drop | an item you have named drops: it lands in the treasure pool, yours alone or the party's |

Each event has its own switch, its own sound and a Test button. The sounds are the wav files in the
addon's `sounds` folder: put your own there and they appear in every event's list. Four come with it
for each event:

- a spoken one in a woman's voice, `voicef-tell.wav` and so on ("Tell", "Mentioned", "Invite", "Trade",
  "Examined", "TP ready", "Low HP", "Low MP", "Member down", "Skill up", "Item drop"), which is what an
  event starts on;
- the same in a man's voice, `voicem-tell.wav` and so on.
  The spoken ones were made with the Piper text-to-speech program and its voices en_US-amy-medium and
  en_US-ryan-high, by `sounds/generate_voices.sh`. There is one more of each that is no event's,
  `voicef-twister.wav` and `voicem-twister.wav` ("Twister"), to choose for whatever you like;
- a tone of plain notes, `tone-tell1.wav` and so on;
- a second tone, on bells, `tone-tell2.wav` and so on.

Both tones are made by `sounds/generate.py`.

Item Drop listens for the items named in its settings, under its line: their names with a comma between
one and the next (`Kindred's Seal, Beastmen's Seal`), each the whole of the item's name as the game shows
it, in capitals or not. Items already in the pool when you arrive in an area do not sound.

## Triggers (experimental)

The settings' Triggers tab makes sounds of your own: a kind of mob (Sheep, Crab, Quadav) and something
its mobs do, made with Create Trigger, and then a sound, chosen in the list of triggers under it. What a mob does is a spell, a weaponskill or an ability:

- a spell or a weaponskill sounds as a mob of the kind begins it (starts casting, or readies it), and
  not when one is broken off;
- an ability is what a mob uses at once, with nothing readied first (a job's special, such as Mighty
  Strikes, among them), and sounds as it is used.

A trigger is for every mob of the kind, in any area. The kinds are listed with those of the area you are
in first, under its name, and the rest under Elsewhere; the `(?)` beside a kind once chosen names its
mobs in the area. What a kind can do is everything its mobs do between them, wherever they are, which
is more than any one of them does. What only a kind's notorious monsters do comes after that, in lists
of its own, each under the monster's name and level, so that a beetle is not said to cast what one
notorious beetle casts. The monsters of the area you are in come first, then the rest from the lowest
level up; one that is in two areas is listed as two where it is of another level there or does other
things, and once where it is the same. Each monster has everything it
does that the kind's other mobs do not, whether or not another monster does it too, so a monster can be
looked up and all of its own found under it. What three or more of a kind's notorious monsters do is
the exception: it is listed once, under Notorious Monsters, straight after what the kind's other mobs
do, and not under each of them, so that fifty goblins are not each listed for the dice they all throw. A notorious
monster is one the server marks as one, or a mob with a name of its own. The rank and file of Dynamis
(the Vanguards and the like), which the server's Dynamis module marks one and all, are not: what they do
is with what their kind's other mobs do. The game has some things under more than one number (a weaponskill,
and the same again for the mobs of Dynamis): what has one name is listed once, and a trigger for it is
for every number it goes by.

The tab's Indicator section makes triggers seen as well as heard. With Show Indicator on, a small
window in the theme, like recast's, says what the mob does as the chat log does (`Mad Sheep readies
Sheep Song.`, `starts casting` for a spell, `uses` for an ability) for as long as Indicator Duration
says, a line for each thing going on. It is shown with a sample line while the Triggers tab is open, to
be dragged to where you want it, and like recast's window it is not drawn over the opened-out chat log,
the map, an event or a hidden interface. A trigger's Test button shows its line too, under the kind's name.

Each trigger has a switch, its sound, a Test button and a Remove button; they are kept with the rest of
the settings. A trigger starts on `voicef-trigger.wav` ("Heads up"); `voicem-trigger.wav` is
the same in the other voice, and `tone-trigger1.wav` and `tone-trigger2.wav` are tones for it.

What the kinds can do, and which kind each area's mobs are, is in `mobs.lua`, with only the mobs that do
something. It is made from a checkout of the server by `generate_mobs.py` (which uses MobDB's importer,
from `addons/mobdb`, and says how the file is laid out), and wants making again when the server's mobs
change. A kind is the server's family for a mob. A mob's weaponskills and abilities are those of its
skill list, those its own script names, and its main job's special where its script takes one and
names none: what a mob is given some other way is not among them, and a mob the file does not have is
not known for one of its kind.

The file costs nothing until it is wanted, and is never kept. The Triggers tab reads it when first
drawn and lets go of it when the settings are closed. Hearing for triggers reads it once in an area,
the first time a mob there does what a trigger is for, to find out which kind each of the area's mobs
is: that much is kept, a few dozen names, and the file let go of at once.

Ashita plays one sound at a time, at the volume of the file, and there is no volume setting. A sound
would cut short the one before it, so one asked for while another is playing waits for it to finish (and
is dropped if that takes more than three seconds). A sound played by another addon still cuts twister's
short. One event does not sound twice within a second. Nothing read from the
game's numbers (TP, HP, MP, the party) sounds for the first three seconds in an area.
