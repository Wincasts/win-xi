# Changelog

## 0.5.0 — first release

- A combat parser of its own for Ashita v4, read from the action packets: damage by actor and by kind (melee, ranged, weapon skills, spells, abilities, skillchains, additional effects), observed hit and critical rates, and DPS over an encounter you start and pause yourself (`/parse clear`, `/parse pause`, `/parse resume`). Zoning pauses the encounter.
- The full view, with columns of your choosing, and `/parse minimal`, a quiet overlay of the top actors with no window round it.
- `/parse report` and `/parse report detail` print the totals to your own chat log.
- `/parse test` previews the overlay with up to 18 made-up people.
- Ashita 4.3 or newer is recommended: its packet chunks let parse leave out retransmitted packets, which would otherwise count twice.
