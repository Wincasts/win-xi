# trigger

Plays a sound when something happens that is worth hearing about. It has settings and an optional
trigger indicator. It needs only the `winxi` library (`addons/libs/winxi`).

- `/trigger` opens or closes the settings
- `/trigger test` plays every event's sound in turn

## Installation And Rename

Install `addons/trigger` and `addons/libs/winxi`, then `/addon load trigger`.
This addon used to be called `twister`. Unload the old addon and change any load scripts to
`trigger`. To keep your settings, copy each character's settings from `config/addons/twister` to the
same place in `config/addons/trigger`, while both addons are unloaded. Copy custom WAVs and their
`high`/`low` variants into the new `sounds` folder too. The settings format has not changed. The
optional "Twister" voice clips keep their original filenames and spoken words.

## WinXI Appearance

The look is set for every addon at once, through the **winxisettings** addon. Trigger always follows
the shared theme. It has no Winxi Theme tab and no theme of its own.
The settings have three tabs: **Notifications** for the standard events and playback, **Triggers**
for your own mob-action triggers, and **Toast** for the on-screen notification window. Every setting
is a described row, as winxi lays them out: its name, a sentence under the name saying what it does,
and its control at the right. There are no help marks or tooltips. An event's row is its switch. Its
sound and Test button are in the row under it, and a threshold or the items named come under that.
Those rows are greyed out while the event is off. Toast holds **Enable Toast**, then **Duration**,
**Fade In And Out**, **Grow From** and the hiding rules under it, greyed out while it is off.
Settings windows use WinXI's separate settings appearance, and you can resize them. The sentences
wrap to fit, and rows that still need more room scroll. The indicator uses the game-window theme:
border, background, frame title and font, with outlined text so it is easy to read.
The Toast tab's hiding rules apply to the toast only. Notifications still sound.

| Event | Sounds when |
|---|---|
| Tell Received | someone sends you a tell |
| Name Mentioned | someone else says your character's name in party or linkshell chat |
| Party Invite | you are invited to a party or an alliance |
| Trade Request | someone asks to trade with you |
| Examined | someone examines you |
| TP Ready | your TP reaches 1000 |
| Low HP | your HP falls to the threshold (25% unless changed); it sounds again only after your HP has been 5 points over the threshold |
| Low MP | the same for MP (20%); never on a job with no MP |
| Party Member KO | someone else in your party is knocked out in your area: they have had no HP for a second, and had been in the area five seconds or more |
| Skill Up | one of your skills, or one of your pet's, rises or reaches a new level; crafts count too |
| Item Drop | an item you have named drops: it lands in the treasure pool, for you alone or for the party |

Each event has its own switch, its own sound and a Test button. The sounds are the wav files in the
addon's `sounds` folder. Put your own there and they appear in every event's list. Four come with it
for each event:

- a spoken one in a woman's voice, `voicef-tell.wav` and so on ("Tell", "Mentioned", "Invite", "Trade",
  "Examined", "TP ready", "Low HP", "Low MP", "Member down", "Skill up", "Item drop"). This is what an
  event starts on;
- the same in a man's voice, `voicem-tell.wav` and so on.
  The spoken ones were made with the Piper text-to-speech program and its voices en_US-amy-medium and
  en_US-ryan-high, by `sounds/generate_voices.sh`. There is one more of each that belongs to no event,
  `voicef-twister.wav` and `voicem-twister.wav` ("Twister"), to choose for whatever you like;
- a tone of plain notes, `tone-tell1.wav` and so on;
- a second tone, on bells, `tone-tell2.wav` and so on.

Both tones are made by `sounds/generate.py`.

### Playback

**Playback → Overlap Sounds** is experimental and off by default. Turn it on to play up to
**eight sounds at the same time**: events, triggers, previews and tests. Windows mixes
separate `waveOut` voices, and another addon's Ashita sound does not replace those voices.
The one-second repeat limit still applies. When all eight voices are busy, more sounds are dropped.
Turning it off stops the overlapping voices and goes back to the normal queue.

The overlap backend takes mono or stereo integer PCM WAVs (8, 16, 24 or 32-bit), up to 16 MiB
per file. All the bundled sounds work. A file it cannot play, or a playback failure, gives a
chat message (once per reason). Turn overlap off to play such custom files with Ashita instead.
If the Windows backend cannot start, Trigger says so and uses the normal queue.
Volume copies are used in either mode. Buffers in use are released when they finish or when the
addon unloads. There is no Lua-side mixing and no background Lua callback. Audio is read only when
it is asked for, and at most eight buffers are held. How well it works with real devices in Ashita
still needs testing.

### Volume

The **Playback → Volume** selector at the bottom of Notifications applies to every sound Trigger
plays: notifications, triggers, Test buttons, previews when you choose a sound, and `/trigger test`.

- **Medium** (default): the existing WAVs, unchanged.
- **High**: a little louder, up to +3 dB, limited to the headroom the file has so it does not clip.
- **Low**: quieter, −6 dB (about half the sample amplitude).

The High and Low copies live in `sounds/high/` and `sounds/low/`, so they do not clutter the sound
lists. The setting is saved. A queued sound uses the level chosen when it starts playing.
After you regenerate the bundled sounds or add PCM WAVs of your own, run
`python3 addons/trigger/sounds/generate_volumes.py` from the repository root to make their copies.
A custom sound with no matching volume copy plays the original WAV.

Item Drop listens for the items named in its settings, under its line. Write their names with a comma
between one and the next (`Kindred's Seal, Beastmen's Seal`). Each must be the whole of the item's
name as the game shows it, in capitals or not. Items already in the pool when you arrive in an area
do not sound.

## Triggers (experimental)

The Triggers tab in the settings makes sounds of your own. Choose a kind of mob (Sheep, Crab, Quadav)
and something its mobs do, press Create Trigger, and then choose a sound in the list of triggers
under it. What a mob does is a spell, a weaponskill or an ability:

- a spell or a weaponskill sounds as a mob of the kind begins it (starts casting, or readies it), and
  not when one is broken off;
- an ability is what a mob uses at once, with nothing readied first (a job's special, such as Mighty
  Strikes, is one). It sounds as it is used.

A trigger is for every mob of the kind, in any area. The kinds are listed with those of the area you
are in first, under its name, and the rest under Elsewhere. Once you choose a kind, the line at the
foot of the tab names its mobs in the area. What a kind can do is everything its mobs do between
them, wherever they are. That is more than any one of them does. What only a kind's notorious
monsters do comes after that, in lists of its own, each under the monster's name and level, so that
a beetle is not said to cast what one notorious beetle casts. The monsters of the area you are in
come first, then the rest from the lowest level up. One that is in two areas is listed twice where it
is of another level there or does other things, and once where it is the same. Each monster has
everything it does that the kind's other mobs do not, whether or not another monster does it too. So
you can look a monster up and find all of its own under it. What three or more of a kind's notorious
monsters do is the exception: it is listed once, under Notorious Monsters, straight after what the
kind's other mobs do, and not under each of them, so that fifty goblins are not each listed for the
dice they all throw. A notorious monster is one the server marks as one, or a mob with a name of its
own. The rank and file of Dynamis (the Vanguards and the like), which the server's Dynamis module
marks one and all, are not notorious: what they do goes with what their kind's other mobs do. The
game has some things under more than one number (a weaponskill, and the same again for the mobs of
Dynamis). What has one name is listed once, and a trigger for it is for every number it goes by.

The Toast tab makes triggers seen as well as heard. With Enable Toast on, a small window in the
theme, like recast's, says what the mob does as the chat log does (`Mad Sheep readies Sheep Song.`,
`starts casting` for a spell, `uses` for an ability). It stays for as long as Duration says, with a
line for each thing going on. By default it fades in as it appears and fades out as it goes. In
Toast, Grow From is the side of the window that stays where it is as what it says gets longer or
shorter: Left, Center or Right. While the Toast tab is open and Enable Toast is on, the window shows
a sample line, so you can drag it to where you want it. It follows the hiding rules set in the Toast
tab (by default: the opened-out chat log, the map, loading, an event or a hidden interface). A
trigger's Test button shows its line too, under the kind's name.

Each trigger has a switch, its sound, a Test button and a Remove button. They are kept with the rest
of the settings. A trigger starts on `voicef-trigger.wav` ("Heads up"). `voicem-trigger.wav` is the
same in the other voice, and `tone-trigger1.wav` and `tone-trigger2.wav` are tones for it.

What the kinds can do, and which kind each area's mobs are, is in the server's `triggermobs` set
(winxi's data). It holds only the mobs that do something. It is made from the server's live branch
by `tools/build_trigger_mobs.py` (which uses MobDB's importer through `tools/phoenix`, reads the
server as its modules leave it, and says how the file is laid out). It needs making again when the
server's mobs change. A kind is the server's family for a mob. A mob's weaponskills and abilities are
those of its skill list, those its own script names, and its main job's special where its script
takes one and names none. What a mob is given some other way is not among them. A mob the file does
not have is not known as one of its kind.

The file costs nothing until it is wanted, and it is never kept. The Triggers tab reads it when first
drawn, and lets go of it when the settings are closed. Listening for triggers reads it once in an
area, the first time a mob there does what a trigger is for, to find out which kind each of the
area's mobs is. That much is kept, a few dozen names, and the file is let go of at once.

With Overlap Sounds off, Ashita plays one sound at a time, at the volume of the chosen file copy. A
new sound would cut short the one before it, so one asked for while another is playing waits for it
to finish (and is dropped if that takes more than three seconds). A sound played by another addon
still cuts trigger's short. One event does not sound twice within a second. Nothing read from the
game's numbers (TP, HP, MP, the party) sounds for the first three seconds in an area.
