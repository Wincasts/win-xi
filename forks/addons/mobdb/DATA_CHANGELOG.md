# MobDB data for Phoenix

Released as a zip of addons/mobdb/data alone, for MobDB 1.26 (ThornyFFXI's) as it is: made with
mobdb/import_phoenix.py from the Phoenix server's own mob data, in the format MobDB already reads.

## 2026.10.28

- The same monsters, made again from Phoenix's live branch, still at 9a4494d (committed 2026-10-18): nothing in the 239 zones changed. Released again with the information brought up to date: the data is winxi's mobs set (addons/libs/winxi/data/phoenix/mobs, made by tools/build_winxi_data.py from the server's source, with the era and Phoenix module overrides applied), which this zip is cut from, and the install text says so; a pre-release of this testing round, as the addons are.

## 2026.10.24

- Every zone's monsters made again from Phoenix's live branch (9a4494d): levels, aggro and link, how they detect you, immunities, respawn, drops, spells and their resistances, with the era and Phoenix module overrides applied.
- Monsters are named as the client shows them, by their index in the zone where the client's own names hold the server's layout: spawns whose name was a guess went from 1406 to 2. Names that differ in Phoenix's era DATs are found, such as Ranguemont Pass's Floating Eyes (Bat Eyes to the server), Giant Grub, Tomb Worm, Lemures, Thousand Eyes, Canal Pugil, Fuligo and Bat Battalion.
