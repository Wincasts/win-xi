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
| Skillchain | a skillchain is made by someone in your party or alliance, or on your target |
| TP Ready | your TP reaches 1000 |
| Low HP | your HP falls to the threshold (25% unless changed); again only after it has been 5 points over |
| Low MP | the same for MP (20%); never on a job with no MP |
| Party Member KO | someone else in your party is knocked out, in your area |

Each event has its own switch, its own sound and a Test button. The sounds are the wav files in the
addon's `sounds` folder: put your own there and they appear in every event's list. The ones that come
with it are plain tones made by `sounds/generate.py`.

Ashita plays one sound at a time, at the volume of the file: a sound cuts short the one before it, and
there is no volume setting. One event does not sound twice within a second. Nothing read from the
game's numbers (TP, HP, MP, the party) sounds for the first three seconds in an area.
