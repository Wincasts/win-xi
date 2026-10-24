# Changelog

## 2.1 — first release

- Draw distance for the world and for entities (`/vis world`, `/vis entity`), with the fog kept where you want it (`/vis fog`), objects drawn as far as the terrain (`/vis objects`) and keeping their detail (`/vis detail`), and distant terrain the zone would hide (`/vis terrain`). It replaces the stock drawdistance addon.
- A preset each for cities, the outdoors and dungeons, and values for a zone of its own, applied as you arrive. Everything is saved per character.
- vis was called drawscale until 2.1. The first time it loads for a character it copies their drawscale settings and says so; take `/addon load drawscale` out of your startup script, and don't load both.
- The field of view and true proportions are the lens plugin's (`/lens fov`, `/lens middle`, `/lens square`) since drawscale 2.0; settings saved before then are said once as the lens commands that set them.
