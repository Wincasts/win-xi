# Changelog

## 2.2

- `/vis terrain` is off by default: drawing the terrain the zone would hide costs frames in big zones, and with the fog at stock most of it is fogged out. A terrain on saved before 2.2 (when on was the default) is turned off once, and vis says so at load; `/vis terrain on` brings it back.
- The kind of each zone (city, outdoors, dungeon), for the presets, is read from the server's data as winxi keeps it, so the release carries its own copy of the parts of winxi it uses (addons/vis/winxi). It still needs nothing else.

## 2.1 — first release

- Draw distance for the world and for entities (`/vis world`, `/vis entity`), with the fog kept where you want it (`/vis fog`), objects drawn as far as the terrain (`/vis objects`) and keeping their detail (`/vis detail`), and distant terrain the zone would hide (`/vis terrain`). It replaces the stock drawdistance addon.
- A preset each for cities, the outdoors and dungeons, and values for a zone of its own, applied as you arrive. Everything is saved per character.
- vis was called drawscale until 2.1. The first time it loads for a character it copies their drawscale settings and says so; take `/addon load drawscale` out of your startup script, and don't load both.
- The field of view and true proportions are the lens plugin's (`/lens fov`, `/lens middle`, `/lens square`) since drawscale 2.0; settings saved before then are said once as the lens commands that set them.
