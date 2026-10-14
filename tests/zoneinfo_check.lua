-- Integration check: synthetic coordinate movement, commands and banners, not real alignment.
local game = H.zoneinfo_game;
local function check(label, value)
    H.print(label, value);
    assert(value, label);
end
local function count(text)
    local n = 0;
    for _, line in ipairs(H.printed) do if line:find(text, 1, true) then n = n + 1; end end
    return n;
end
local function move(map_x, map_y)
    game.x, game.y = map_x - 256, 256 - map_y;
end
H.load();
H.frames(50);
check('addon load does not pop a zone banner', count('Zone 100 - Unknown') == 0);
check('area POC starts off', count('Area POC is OFF') == 1);
check('unrelated command not blocked', not H.command('/somethingelse'));
check('debug command blocked', H.command('/zoneinfo debug on'));
H.frames(10);
check('debug overlay draws map boundaries', (H.calls['draw.AddLine'] or 0) > 0);
check('sample command reports map coordinates', H.command('/zoneinfo sample') and count('pixel512=') == 1);
move(238, 337); H.frames(60);
check('debug-only mode has no area announcements', count('Experimental area: Knightwell -') == 0);
H.command('/zoneinfo poc on'); H.frames(10);
check('enabling inside an area seeds silently', count('Experimental area: Knightwell -') == 0);
move(200, 300); H.frames(60);
move(238, 337); H.frames(15); move(200, 300); H.frames(60);
check('brief area entry does not announce', count('Experimental area: Knightwell -') == 0);
move(238, 337); H.frames(70);
check('stable same-zone entry announces once', count('Experimental area: Knightwell -') == 1);
H.frames(90);
check('remaining inside area does not spam', count('Experimental area: Knightwell -') == 1);
move(252, 339); H.frames(60); move(248, 338); H.frames(60);
check('small boundary excursion does not reannounce', count('Experimental area: Knightwell -') == 1);
move(200, 300); H.frames(60); move(238, 337); H.frames(70);
check('stable exit permits later reentry', count('Experimental area: Knightwell -') == 2);
game.present = false; H.frames(30); game.present = true; H.frames(50);
check('position recovery does not announce stale transition', count('Experimental area: Knightwell -') == 2);
H.packet(0x00A); H.frames(60);
check('same-zone zone-in packet reseeds without duplicate area banner', count('Experimental area: Knightwell -') == 2);
H.command('/zoneinfo poc off'); move(200, 300); H.frames(60); move(238, 337); H.frames(60);
check('poc off suppresses movement banners', count('Experimental area: Knightwell -') == 2);
H.command('/zoneinfo');
check('manual zone banner still works', count('Zone 100 - Unknown') == 1);
H.command('/zoneinfo poc on');
game.zone = 103; move(200, 200); H.packet(0x00A); H.frames(230);
check('zone-change banner still works', count('Zone 103 - Unknown') == 1);
move(57, 225); H.frames(70);
check('second POC zone detects beach', count('Experimental area: Secret Sands -') == 1);
game.zone = 107; move(220, 200); H.packet(0x00A); H.frames(230);
move(403, 310); H.frames(70);
check('third POC zone detects lighthouse', count('Experimental area: Morhen Lighthouse -') == 1);
game.zone = 999; H.frames(70); H.command('/zoneinfo sample');
check('unsupported zone explicitly reported', count('No supplied maps for this zone') > 0);
game.zone = 100; game.valid_table = false; move(200, 300); H.frames(230);
H.command('/zoneinfo transform reset'); H.frames(20); H.command('/zoneinfo sample');
check('mismatched client entry fails closed', count('refusing transform') > 0);
H.command('/zoneinfo transform 5 -256 -256'); H.frames(20);
move(238, 337); H.frames(70);
check('session-only transform fallback works', count('Experimental area: Knightwell -') == 3);
H.command('/zoneinfo transform 0 0 0');
check('invalid transform refused', count('Usage in a mapped zone') > 0);
H.command('/zoneinfo debug nonsense');
check('invalid debug mode refused', count('Usage: /zoneinfo debug') > 0);
move(200, 300); H.frames(60); move(264, 337); H.frames(70);
check('approaching object announces before entering feature polygon', count('Experimental area: Knightwell -') == 4);
H.command('/zoneinfo approach 0'); H.frames(20);
move(238, 337); H.frames(70);
check('zero approach restores feature-only entry', count('Experimental area: Knightwell -') == 5);
H.command('/zoneinfo approach 101');
check('out-of-range approach distance refused', count('Usage: /zoneinfo approach') > 0);
H.command('/zoneinfo approach 30');
check('approach distance adjustable in session', count('Approach buffer: 30 yalms around each feature') == 1);
H.command('/zoneinfo debug off');
local drawn = H.calls['draw.AddLine'] or 0;
H.frames(10);
check('debug off stops map rendering', (H.calls['draw.AddLine'] or 0) == drawn);
game.zone = 0; game.present = false; H.frames(20);
check('logout does not crash', true);
H.unload();
