# Approach distance audit (2026-10-24)

Every announced area measured in yalms, with each map's scale read from the client's
own map table (the running game, read only), to set an approach distance for each kind
of zone. Zone kinds are `data/zone_kinds.lua`.

| Kind | Areas (non-exact) | Zones | Size across, median (p10–p90) | Gap to nearest, median (p10, p25) |
| --- | --- | --- | --- | --- |
| Open country | 137 | 48 | 188 y (102–336) | 117 y (10, 40) |
| City | 97, and 163 buildings | 25 | 58 y (19–89) | 24 y (5, 8) |
| Dungeon | 6 | 2 | 45 y | 324 y |

Size across is the square root of the polygon's area. The old single distance, 30
yalms, reached past the next square in most cities (half are 24 yalms apart or less)
while open country's features, three times as wide and far apart, were announced
late. The distances became 50 (open country), 10 (city) and 15 (dungeon).

Found along the way:

- Two areas touch a neighbour: Oceaneade (Lufaise Meadows) and the Drawbridge
  (Northern San d'Oria). Being inside picks the smaller, so both still work.
- Open country's largest, over 400 yalms across: Emfea Waterway, Vozold Island,
  Dvucca Isle, Coveffe Barrows (both eras), Galesmouth (both eras), Gausebit
  Mountains (both eras), Ahopahgo Pass. With 50 yalms these are announced well
  before their middle; that is their size, not a fault.
- The city squares over 100 yalms across: Parade Ground, Airship Docks (Port San
  d'Oria), Gold Street (both eras), Mithra Groves, Coronal Esplanade.
- Dungeons have almost no named areas (Giddeus Spring, Davoi's four ponds); the
  entrances below are most of what a dungeon-goer will see announced.
- Five Windurst Waters buildings sit on a raster with no client table index; the
  copies on the raster the client uses are the ones announced.

## Dungeon entrances

184 entrances, from the server's zone lines (`tools/build_zone_entrances.py`). Each
was drawn on its zone's map and the map's number beside it read by eye; they are in
`dungeon_entrances.json`. The numbers are colour-coded by destination on the newer
maps (Halvung yellow, Mamook green, Aydeewa and Alzadaal white) and are per
destination: Western Altepa's Quicksand Caves entrances are 4 to 15 (1 to 3 are
presumably Eastern Altepa's, whose map is too coarse to show them). Where the line
sat between two markers the nearer was taken: Wajaom's z1fe (4), Western Altepa's z3hm (12), Yahse's z786 (1). Ru'Aun Gardens' gates are
numbered 1 to 7 for the Shrine (green) and 1 to 10 for Ve'Lugannon (white);
z3mw's number is under a teleport icon and is read as 2 from the sequence.
