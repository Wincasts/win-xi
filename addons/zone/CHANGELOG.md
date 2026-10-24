# zone changelog

## 2.10

- Each kind of zone announces its features from its own distance: Field Approach Distance (50 yalms to start, from 30), Town Approach Distance (10) and Dungeon Approach Distance (15). A saved Approach Distance is dropped for these.
- Dungeon entrances are announced as you come to them, with the number the zone's map gives them: `Quicksand Caves Entrance 7`. 184 entrances in 55 zones, from the Phoenix server's zone lines; Announce Dungeon Entrances and Entrance Distance (20 yalms) set them.
- Town entrances are announced as you come up to a town's gates from the field or a dungeon: `Southern San d'Oria Entrance`. 38 of them, with Announce Town Entrances and Town Entrance Distance (40 yalms); Jeuno's bridges already name its three.
- Tenshodo H.Q. under Lower Jeuno is announced, as a building and only below the street.
- `/zone approach town 8` and `/zone approach dungeon 12` set the town and dungeon distances; `/zone approach <yalms>` alone is open country's.
- The map browser draws the entrances in blue, and the approach outline at the viewed zone's own distance.

## 2.9 — first release

- A banner as you enter a zone: its name, region, weather and the Vana'diel day and time, each line of it optional.
- A smaller one as you walk into a named part of a zone (833 areas on 494 maps, among them 163 city buildings), and one when the weather changes.
- Eight styles, chosen for zone entry and for sub-zones apart: Classic Text, Title Card, Pennant, Kanji Watermark, Letter Reveal, Classic Window, Elemental Weather and Kind Frames.
- A soft backdrop behind the banner, its opacity and softness yours to set.
- Nation flags behind the banner in a nation's own regions, or a background image of your own.
- An always-on location line, which can be dragged and locked.
- Can keep out of the way while zoning, in cutscenes, with the map or the chat log open, or with the game's interface hidden.
- A map browser and editor for the areas each map announces, and `/zone test [style]` to see a banner now.
- Needs nothing else: it carries its own copy of the parts of winxi it uses.
