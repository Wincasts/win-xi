# luashitacast

Gear-swap profiles for [LuAshitacast](https://github.com/ThornyFFXI/LuAshitacast) (2.14, as installed),
one file a job, in `<Name>_<Id>/<JOB>.lua` as LuAshitacast looks for them.

| Profile | Job |
|---|---|
| [Win_4458/PUP.lua](Win_4458/PUP.lua) | Puppetmaster: master idle, TP and weapon skills, and the automaton's weapon skills and spells |

## Installing

Copy `Win_4458` into `config/addons/luashitacast/` in the Ashita folder, then in game
`/addon load luashitacast`. The profile for your job loads by itself; `/lac load` loads it by hand
and `/lac reload` picks up a change.

## Filling the sets

Every set starts empty. Put the gear on and save what you are wearing into a set:

```
/lac addset Idle
/lac addset "Asuran Fists"
```

A set named for a weapon skill, an ability or a spell (one that the profile doesn't already list) is
worn over the general one when you use it. The list of sets is at the top of each profile.

`/lac addset` writes the profile in the live folder, and keeps the old one in
`config/addons/luashitacast/Win_4458/backups`. Copy the profile back here before changing it here,
or the sets saved in game are lost.

## Commands

| Command | What it does |
|---|---|
| `/lac fwd tp` | PUP: cycles the TP mode, Normal and Acc (Engaged_Acc over Engaged) |
| `/lac set <Set>` | wears a set, to check it |
| `/lac disable <slot>` / `/lac enable <slot>` | stops and starts swaps in a slot (`all` for every slot) |

`tests/lac_pup_check.lua` runs the PUP profile against a stand-in for LuAshitacast:
`luajit tests/lac_pup_check.lua`.
