# tempo

Two bars in a small window in the theme: one fills to your next auto attack while you fight, the
other to your next resting tick while you `/heal`, with about what that tick restores and about when
your HP and MP are full. The window shows only while one of them has something to show, or the
settings are open. It needs only the `winxi` library (`addons/libs/winxi`).

    Attack  ~3.73s                 1.2
    +14 HP  +16 MP                 6.2
    Full in ~1:05

- `/tempo` opens or closes the settings
- `/tempo toggle` shows or hides the window

It is a basic take on Kipling's [cadence](https://github.com/KiplingFFXI/cadence): the same server
rules (LandSandBoat's, which Phoenix runs unchanged here), without cadence's gear modifier tables,
enemy timers, TP or sounds. Like cadence it only reads: the packets the server sends you and what the
game holds in memory.

## The attack timer

The delay is worked out from your weapons (two for dual wield, fists for hand-to-hand), Martial Arts
and Dual Wield from your jobs, and the haste and slow buffs the client can see (Haste, March, Slow,
Elegy, Weakness, Spirit Surge, Hasso, Hundred Fists), to Phoenix's 93% cap. Gear haste and delay
changes are not known, so the delay is marked `~` until three clean gaps between your own rounds have
shown the real one; from then the bar uses that. What is learned is kept for each set of weapons,
jobs and buffs, through zoning, but not for March, Slow or Elegy, whose strength changes cast to cast.

The first round comes 2.8 s after you engage. A job ability or weapon skill holds the timer 2 s; a
spell, item or ranged attack holds it while it runs, then 2 s, 0.4 s or 0.8 s more. Sleep, stun,
petrification, terror and Lullaby stop the bar where it is, and the bar says so; so does the server's
"too far" or "not facing". Any one gap can be 0.4 s off the delay, as the server counts in 0.4 s ticks.

## The resting ticks

Resting ticks every 10 s from when you sit, and tick k restores 10 + (k − 2) HP and 12 + (k − 2) MP;
the first restores nothing, so the first that does lands 20 to 23 s after you sit. The ticks run on
the zone's 3 s effect pass, so the gaps between them go 9, 9, 12. Until one is seen it is put at about
21.4 s; once one is seen the passes are known, and each tick after is put on the first pass after its
10 s mark. What a seen tick restored over the formula is taken for gear (Clear Mind, HP and MP
recovered while healing) and added to the ones after. At full HP and MP nothing shows, and the ticks
are counted on all the same. Loaded mid-rest, it waits for the first tick and tells which it was by
how much MP it restored.

Regen, Refresh or a cure landing just as a tick is due can be taken for the tick, and moves the
estimate a little; the next real tick puts it right.

## Settings

Every section collapses with its [-]/[+].

**Timers**

- **Show Attack Timer**, **Show Resting Ticks** switch each bar.
- **Show Time To Full** says under the resting bar about how long until HP and MP are full.

**Window**

- **Bar Width** is how wide the bars are, 120 to 400 pixels.
- **Attack Color** and **Rest Color** are what each bar fills with.
- **Lock Window** keeps it where it is, and lets the mouse through. Off, it is dragged.

Below them are the rules for hiding the window (the map, an event, the chat log opened out) and
whether it fades in and out.
