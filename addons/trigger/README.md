# trigger

Plays an audio alert when something notable happens, such as a tell, a party invite, low HP or a
wanted item dropping. Custom triggers can alert you when a chosen monster begins a specific spell or
ability, and an optional on-screen notification, the toast, can accompany each alert.

## Highlights

- Hear tells, invites, trade requests and other events even when you are not watching the screen.
- Warnings when your HP or MP runs low, when your TP is ready, or when a party member is knocked
  out.
- An alert, and an on-screen line, when a monster begins a spell or ability you care about.

It needs only the `winxi` library (`addons/libs/winxi`).

## Commands

- `/trigger` opens or closes the settings.
- `/trigger test` plays every event's sound in turn.

## Install, and renamed from twister

Install `addons/trigger` and `addons/libs/winxi`, then type `/addon load trigger`.

This addon used to be called `twister`.

- Unload the old addon, and change `twister` to `trigger` in any load scripts.
- To keep your settings: while both addons are unloaded, copy each character's settings from
  `config/addons/twister` to the same place in `config/addons/trigger`.
- Copy your own WAV files, and their `high`/`low` versions, into the new `sounds` folder too.
- The settings format has not changed.
- The optional "Twister" voice clips keep their old file names and spoken words.

## The settings window

The settings have three tabs:

| Tab | What it holds |
|---|---|
| **Notifications** | The standard events, and how sounds play. |
| **Triggers** | Your own triggers for monster actions. |
| **Toast** | The small on-screen window that shows triggers. |

Each setting is a row: its name, a sentence under it saying what it does, and its control on the
right. There are no help marks or tooltips. You can resize the window. The sentences wrap to fit, and
rows that still need more room scroll.

The look is set for every addon at once, in the **wxi** addon. trigger always follows the shared theme.
It has no Winxi Theme tab and no theme of its own. Its settings window uses winxi's settings-window
look.

## Notifications

An event's row is its on/off switch. Its sound and its **Test** button are in the row under it. A
threshold, or the item names, come under that. These rows are greyed out while the event is off.

| Event | Sounds when |
|---|---|
| Tell Received | someone sends you a tell |
| Name Mentioned | someone else says your character's name in party or linkshell chat |
| Party Invite | you are invited to a party or an alliance |
| Trade Request | someone asks to trade with you |
| Examined | someone examines you |
| TP Ready | your TP reaches 1000 |
| Low HP | your HP falls to the threshold (25% unless you change it). It sounds again only after your HP has been 5 points above the threshold. |
| Low MP | the same for MP (20%). Never on a job with no MP. |
| Party Member KO | someone else in your party is knocked out in your area: they have had no HP for a second, and had been in the area for five seconds or more |
| Skill Up | one of your skills, or one of your pet's, goes up or reaches a new level. Crafts count too. |
| Item Drop | an item you have named drops: it lands in the treasure pool, for you alone or for the party |

### Item Drop

Item Drop listens for the items you name in its settings, under its row. Put a comma between one name
and the next, for example `Kindred's Seal, Beastmen's Seal`. Each must be the item's whole name as the
game shows it. Capital letters do not matter. Items already in the pool when you arrive in an area do
not sound.

### Sounds

Each event has its own switch, its own sound and a Test button. The sounds are the WAV files in the
addon's `sounds` folder. Put your own there and they appear in every event's list. Four sounds come
with it for each event:

- a spoken one in a woman's voice: `voicef-tell.wav` and so on ("Tell", "Mentioned", "Invite",
  "Trade", "Examined", "TP ready", "Low HP", "Low MP", "Member down", "Skill up", "Item drop"). This
  is what each event starts with;
- the same in a man's voice: `voicem-tell.wav` and so on;
- a tone of plain notes: `tone-tell1.wav` and so on;
- a second tone, on bells: `tone-tell2.wav` and so on.

There is also one spoken clip in each voice that belongs to no event, `voicef-twister.wav` and
`voicem-twister.wav` ("Twister"). Use them for whatever you like.

### Volume

**Playback → Volume**, at the bottom of Notifications, sets the volume of every sound trigger plays:
notifications, triggers, Test buttons, previews when you choose a sound, and `/trigger test`.

- **Medium** (the default): the WAV files as they are.
- **High**: a little louder, up to +3 dB. It is only raised as far as the file allows without
  distortion.
- **Low**: quieter, −6 dB (about half as loud).

The High and Low copies are kept in `sounds/high/` and `sounds/low/`, so they do not fill up the sound
lists. The setting is saved. A sound waiting in line uses the volume chosen when it starts playing. A
sound of your own with no High or Low copy plays the original file.

### Overlap Sounds

**Playback → Overlap Sounds** is experimental and off by default. Turn it on to play up to **eight
sounds at the same time**: events, triggers, previews and tests.

- Windows plays these sounds itself, so a sound from another addon does not cut them off.
- The one-second repeat limit still applies (see [How sounds play](#how-sounds-play)).
- When all eight are playing, any more sounds are dropped.
- Turning it off stops the overlapping sounds and goes back to the normal queue.

What Overlap Sounds can play:

- mono or stereo WAV files in standard integer PCM format (8, 16, 24 or 32-bit), up to 16 MiB each;
- all the sounds that come with trigger.

If it cannot play a file, or playback fails, it says so in the chat (once for each reason). To play
such a file of your own, turn Overlap Sounds off, and Ashita plays it instead. If Windows sound
cannot start, trigger says so and uses the normal queue. The High and Low copies work in both modes.
How well it works with real sound devices in Ashita still needs testing.

## Triggers (experimental)

The **Triggers** tab lets you make sounds of your own for what monsters do.

1. Choose a kind of monster (Sheep, Crab, Quadav…).
2. Choose something its monsters do.
3. Press **Create Trigger**.
4. Choose a sound for it in the list of triggers below.

What a monster does is a spell, a weaponskill or an ability:

- a spell or a weaponskill sounds when a monster of that kind begins it (starts casting, or readies
  it). It does not sound when one is interrupted;
- an ability is something a monster uses at once, with nothing readied first. A job's special
  ability, such as Mighty Strikes, is one. It sounds as it is used.

Each trigger has an on/off switch, its sound, a **Test** button and a **Remove** button. Triggers are
saved with the rest of the settings. A new trigger starts with `voicef-trigger.wav` ("Heads up").
`voicem-trigger.wav` is the same in the other voice. `tone-trigger1.wav` and `tone-trigger2.wav` are
tones for it.

### How the lists work

- A trigger is for every monster of the kind, in any area.
- The kinds of the area you are in are listed first, under the area's name. The rest are under
  **Elsewhere**.
- Once you choose a kind, the line at the bottom of the tab names its monsters in the area you are in.
- What a kind can do is everything its monsters do between them, wherever they are. That is more than
  any one of them does.

Notorious monsters (NMs) have their own lists:

- What only a kind's NMs do comes after the rest, under each NM's name and level. So a beetle is not
  said to cast what one notorious beetle casts.
- NMs in the area you are in come first. The rest follow, from the lowest level up.
- An NM found in two areas is listed twice if its level or its moves differ there, and once if they
  are the same.
- Under each NM is everything it does that the kind's other monsters do not, whether or not another NM
  does it too. So you can look an NM up and find all of its own moves under it.
- The exception: what three or more of a kind's NMs do is listed once, under **Notorious Monsters**,
  straight after what the kind's other monsters do. So fifty goblins are not each listed for the dice
  they all throw.
- An NM is one the server marks as one, or a monster with a name of its own.
- The ordinary monsters of Dynamis (the Vanguards and the like) are not counted as NMs, even though
  the server's Dynamis code marks them all. What they do is listed with their kind's other monsters.

The game has some moves under more than one number (a weaponskill, and the same again for Dynamis
monsters). A name is listed once, and a trigger for it covers every number it goes by.

### Where the monster data comes from

What each kind can do, and which kind each area's monsters are, comes from the server data that
winxi carries (its `triggermobs` set). It holds only the monsters that do something.

- A kind is the server's family for a monster.
- A monster's weaponskills and abilities are the ones on its skill list, the ones its own script
  names, and its main job's special ability where its script uses one without naming it.
- Moves a monster gets some other way are not included.
- A monster that is not in the data is not known as one of its kind.

## Toast

The **Toast** tab lets you see triggers as well as hear them. The toast is a small window in the
theme's look.

- **Enable Toast** turns it on. The other Toast settings are greyed out while it is off.
- It says what the monster does in the chat log's words: `Mad Sheep readies Sheep Song.`, `starts
  casting` for a spell, `uses` for an ability. It shows one line for each thing going on.
- **Duration**: how long a line stays.
- **Fade In And Out**: fades the window in as it appears and out as it goes (on by default).
- **Grow From**: the side of the window that stays in place as its text gets longer or shorter: Left,
  Center or Right.
- The hiding rules: by default it hides while the chat log is opened out, while the map is open,
  while loading, during an event (cutscene) and while the interface is hidden. These rules hide only
  the toast. Notifications still sound.

While the Toast tab is open and Enable Toast is on, the window shows a sample line, so you can drag it
where you want it. A trigger's Test button shows its line too, under the kind's name.

The toast uses the game-window look: border, background, frame title and font, with outlined text so
it is easy to read.

## How sounds play

With Overlap Sounds off, Ashita plays one sound at a time, at the volume of the chosen file copy.

- A new sound would cut off the one before it. So a sound asked for while another is playing waits
  for it to finish. If that takes more than three seconds, the new sound is dropped.
- A sound played by another addon still cuts trigger's sound short.
- One event does not sound twice within one second.
- Nothing based on the game's numbers (TP, HP, MP, the party) sounds for the first three seconds in
  an area.
