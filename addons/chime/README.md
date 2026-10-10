# chime

Plays a sound when something happens that is worth hearing about. It has no window, only settings,
and needs only the `winxi` library (`addons/libs/winxi`).

- `/chime` opens or closes the settings
- `/chime test` plays every event's sound in turn

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
| Skill Up | one of your skills rises or reaches a new level, crafts included |
| Item Drop | an item you have named drops: it lands in the treasure pool, yours alone or the party's |

Each event has its own switch, its own sound and a Test button. The sounds are the wav files in the
addon's `sounds` folder: put your own there and they appear in every event's list. The ones that come
with it are plain tones made by `sounds/generate.py`, which every event but Trade Request, Examined and Item Drop starts on, and a spoken one for
each event, `voice-tell.wav` and so on ("Tell", "Mentioned", "Invite", "Trade", "Examined", "TP ready",
"Low HP", "Low MP", "Member down", "Skill up", "Item drop"), to choose in its place. The spoken ones were made with the Piper
text-to-speech program and its voice en_US-amy-medium, by `sounds/generate_voices.sh`.

Item Drop listens for the items named in its settings, under its line: their names with a comma between
one and the next (`Kindred's Seal, Beastmen's Seal`), each the whole of the item's name as the game shows
it, in capitals or not. Items already in the pool when you arrive in an area do not sound.

## Triggers (experimental)

The settings' Triggers tab makes sounds of your own: a mob of the area you are in, something that mob
does, and a sound. What a mob does is a spell, a weaponskill or an ability:

- a spell or a weaponskill sounds as a mob of that name begins it (starts casting, or readies it), and
  not when one is broken off;
- an ability is what a mob uses at once, with nothing readied first (a job's special, such as Mighty
  Strikes, among them), and sounds as it is used.

A trigger is for the area it was made in. Each has a switch, its sound, a Test button and a Remove
button; they are kept with the rest of the settings, for every area. A trigger starts on
`voice-trigger.wav` ("Heads up"), and `trigger.wav` is a tone for the same.

What each area's mobs can do is in `mobs.lua`, with only the mobs that do something. It is made from a
checkout of the server by `generate_mobs.py` (which uses MobDB's importer, from `addons/mobdb`, and says
how the file is laid out), and wants making again when the server's mobs change. A mob's weaponskills
and abilities are those of its skill list, those its own script names, and its main job's special where
its script takes one and names none: what a mob is given some other way is not among them.

The file costs nothing until it is wanted. It is read when the Triggers tab is first drawn, an area is
taken apart only when its mobs are listed, and all of it is let go of when the settings are closed. A
trigger keeps what it needs, so hearing for one reads nothing.

Ashita plays one sound at a time, at the volume of the file, and there is no volume setting. A sound
would cut short the one before it, so one asked for while another is playing waits for it to finish (and
is dropped if that takes more than three seconds). A sound played by another addon still cuts chime's
short. One event does not sound twice within a second. Nothing read from the
game's numbers (TP, HP, MP, the party) sounds for the first three seconds in an area.
