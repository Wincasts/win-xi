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

The settings' Triggers tab makes sounds of your own: a mob of the area you are in, a spell or a
weaponskill of that mob's, and a sound. It sounds as a mob of that name begins it (starts casting, or
readies the weaponskill), in that area, and not when one is broken off. Each trigger has a switch, its
sound, a Test button and a Remove button; they are kept with the rest of the settings, for every area.
A trigger starts on `voice-trigger.wav` ("Heads up"), and `trigger.wav` is a tone for the same.

What each area's mobs can do is in the `mobs` folder, one file to an area, with only the mobs that cast
or ready something. It is made from a checkout of the server by `mobs/generate.py` (which uses MobDB's
importer, from `addons/mobdb`), and wants making again when the server's mobs change. A spell or a
weaponskill the server gives a mob from a script, and not from its lists, is not among them.

Ashita plays one sound at a time, at the volume of the file, and there is no volume setting. A sound
would cut short the one before it, so one asked for while another is playing waits for it to finish (and
is dropped if that takes more than three seconds). A sound played by another addon still cuts chime's
short. One event does not sound twice within a second. Nothing read from the
game's numbers (TP, HP, MP, the party) sounds for the first three seconds in an area.
