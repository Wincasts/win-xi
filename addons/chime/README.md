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

Each event has its own switch, its own sound and a Test button. The sounds are the wav files in the
addon's `sounds` folder: put your own there and they appear in every event's list. The ones that come
with it are plain tones made by `sounds/generate.py`, which every event but Trade Request and Examined starts on, and a spoken one for
each event, `voice-tell.wav` and so on ("Tell", "Mentioned", "Invite", "Trade", "Examined", "TP ready",
"Low HP", "Low MP", "Member down", "Skill up"), to choose in its place. The spoken ones were made with the Piper
text-to-speech program and its voice en_US-amy-medium, by `sounds/generate_voices.sh`.

Ashita plays one sound at a time, at the volume of the file, and there is no volume setting. A sound
would cut short the one before it, so one asked for while another is playing waits for it to finish (and
is dropped if that takes more than three seconds). A sound played by another addon still cuts chime's
short. One event does not sound twice within a second. Nothing read from the
game's numbers (TP, HP, MP, the party) sounds for the first three seconds in an area.
