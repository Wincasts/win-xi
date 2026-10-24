-- Integration check: synthetic coordinate movement, commands and banners, not real alignment.
-- Sub-zone popups are a display setting (Show Sub-zone Popups, on to begin with), and each banner
-- is written to chat as well while Chat is on: a sub-zone's as "Sub-zone: <area> - <zone> - ...",
-- a zone's as "<region> - <zone> - <weather>". /zone poc and /zone debug are the experiment's own
-- switches: debug samples and draws the map without announcing anything.
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
-- the sub-zone banners for an area so far, and the zone banners for a zone
local function areas(name) return count('Sub-zone: ' .. name .. ' - '); end
local function zones(id)
    local n = 0;
    for _, line in ipairs(H.printed) do
        if line:find(' - Zone ' .. id .. ' - ', 1, true) and not line:find('Sub-zone: ', 1, true) then n = n + 1; end
    end
    return n;
end
local function move(map_x, map_y)
    game.x, game.y = map_x - 256, 256 - map_y;
end
H.load();
local display = H.options().display;
display.fieldApproach[1] = 30; -- The places below were laid out for a 30-yalm buffer.
H.frames(50);
check('addon load does not pop a zone banner', zones(100) == 0);
check('sub-zone popups and chat lines on to begin with', display.areaEnabled[1] == true and display.chat[1] == true);
-- /zone poc alone turns it the other way: from off, on; then off again for what follows
H.command('/zone poc');
check('area POC starts off', count('poc: ON') == 1);
H.command('/zone poc off');
check('unrelated command not blocked', not H.command('/somethingelse'));

-- with popups off, debug samples and draws, and announces nothing
display.areaEnabled[1] = false;
check('debug command blocked', H.command('/zone debug on'));
H.frames(10);
check('debug overlay draws map boundaries', (H.calls['draw.AddLine'] or 0) > 0);
check('sample command reports map coordinates', H.command('/zone sample') and count('pixel512=') == 1);
move(238, 337); H.frames(60);
check('popups off: debug announces nothing', areas('Knightwell') == 0);
H.command('/zone debug off');
move(200, 300); H.frames(60); move(238, 337); H.frames(70);
check('popups off: movement announces nothing', areas('Knightwell') == 0);
move(200, 300); H.frames(60);
display.areaEnabled[1] = true;

-- popups on: an area is announced once it is stood in for a while, and only once
move(238, 337); H.frames(15); move(200, 300); H.frames(60);
check('brief area entry does not announce', areas('Knightwell') == 0);
move(238, 337); H.frames(70);
check('stable same-zone entry announces once', areas('Knightwell') == 1);
H.frames(90);
check('remaining inside area does not spam', areas('Knightwell') == 1);
move(252, 339); H.frames(60); move(248, 338); H.frames(60);
check('small boundary excursion does not reannounce', areas('Knightwell') == 1);
move(200, 300); H.frames(60); move(238, 337); H.frames(70);
check('stable exit permits later reentry', areas('Knightwell') == 2);
game.present = false; H.frames(30); game.present = true; H.frames(50);
check('position recovery does not announce stale transition', areas('Knightwell') == 2);
H.packet(0x00A); H.frames(60);
check('same-zone zone-in packet reseeds without duplicate area banner', areas('Knightwell') == 2);
display.areaEnabled[1] = false; move(200, 300); H.frames(60); move(238, 337); H.frames(60);
check('popups switched off stop movement banners', areas('Knightwell') == 2);
display.areaEnabled[1] = true;

H.command('/zone test');
check('manual zone banner still works', zones(100) == 1);
game.zone = 103; move(200, 200); H.packet(0x00A); H.frames(230);
check('zone-change banner still works', zones(103) == 1);
move(57, 225); H.frames(70);
check('second POC zone detects beach', areas('Secret Sands') == 1);
game.zone = 107; move(220, 200); H.packet(0x00A); H.frames(230);
move(403, 310); H.frames(70);
check('third POC zone detects lighthouse', areas('Morhen Lighthouse') == 1);
game.zone = 999; H.frames(70); H.command('/zone sample');
check('unsupported zone explicitly reported', count('No supplied maps for this zone') > 0);
game.zone = 100; game.valid_table = false; move(200, 300); H.frames(230);
H.command('/zone transform reset'); H.frames(20); H.command('/zone sample');
check('mismatched client entry fails closed', count('refusing transform') > 0);
local before = areas('Knightwell');
H.command('/zone transform 5 -256 -256'); H.frames(20);
move(238, 337); H.frames(70);
check('session-only transform fallback works', areas('Knightwell') == before + 1);
H.command('/zone transform 0 0 0');
check('invalid transform refused', count('Usage in a mapped zone') > 0);
H.command('/zone debug nonsense');
check('invalid debug mode refused', count('Usage: /zone debug') > 0);
move(200, 300); H.frames(60); move(264, 337); H.frames(70);
check('approaching object announces before entering feature polygon', areas('Knightwell') == before + 2);
H.command('/zone approach 0'); H.frames(20);
move(238, 337); H.frames(70);
check('zero approach restores feature-only entry', areas('Knightwell') == before + 3);
H.command('/zone approach 101');
check('out-of-range approach distance refused', count('Usage: /zone approach') > 0);
H.command('/zone approach 30');
check('approach distance adjustable in session', count('Approach buffer in open country: 30 yalms around each feature') == 1);
H.command('/zone debug on'); H.frames(10);
H.command('/zone debug off');
local drawn = H.calls['draw.AddLine'] or 0;
H.frames(10);
check('debug off stops map rendering', (H.calls['draw.AddLine'] or 0) == drawn);
game.zone = 0; game.present = false; H.frames(20);
check('logout does not crash', true);
H.unload();
