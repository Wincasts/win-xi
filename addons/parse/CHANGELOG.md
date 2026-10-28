# Changelog

## 0.6.0

- The minimal view shows the stats you choose: besides Share, Damage and DPS, the Minimal tab can show Melee and Ranged hit rates, Magic Damage, WS Count, WS Hit % (TP), WS TP Unknown, Magic Land % and Magic Resists, each on or off on its own and saved apart from the full view's columns. They are the full view's figures with its formatting; Compact K/M applies to magic damage too.
- The weapon skill TP inference takes the server's rules through winxi.rules (the TP each extra hit returns before Store TP) and leaves out every job the server's traits give Double Attack, Triple Attack or Conserve TP, and BLU; its own figures stay where winxi's data is not installed.

## 0.5.0 — first release

- A combat parser of its own for Ashita v4, read from the action packets: damage by actor and by kind (melee, ranged, weapon skills, spells, abilities, skillchains, additional effects), observed hit and critical rates, and DPS over an encounter you start and pause yourself (`/parse clear`, `/parse pause`, `/parse resume`). Zoning pauses the encounter.
- The full view, with columns of your choosing, and `/parse minimal`, a quiet overlay of the top actors with no window round it.
- `/parse report` and `/parse report detail` print the totals to your own chat log.
- `/parse test` previews the overlay with up to 18 made-up people.
- Ashita 4.3 or newer is recommended: its packet chunks let parse leave out retransmitted packets, which would otherwise count twice.
