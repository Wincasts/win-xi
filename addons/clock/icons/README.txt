Icon sets for the clock's day and weather icons.

Each folder here is a set, chosen under Icon Set in /clock. gems comes with the addon: round cut
gemstones for the days, and weather icons after the game's own, with a sun for a clear sky, a pair of
clouds and a bank of fog. It is made by tools/generate_clock_icons.py.

A set holds any of these, as .png:

    days\firesday.png  earthsday  watersday  windsday  iceday  lightningday  lightsday  darksday
    weather\fire.png   ice  wind  earth  thunder  water  light  dark
    weather\clear.png  clouds  fog

Each picture is drawn where the game draws that icon, at the size it draws it, so square pictures
suit best. Weather is by element: rain and squalls are water, dust and sand storms earth, and so on;
double weather is its picture twice, side by side, as the game draws it. Where a set has no picture
for the day or the weather, the game's own icon is drawn.

The game draws no icon for no weather, sunshine, clouds or fog. clear (for no weather and sunshine),
clouds and fog are drawn where its weather icon would be.
