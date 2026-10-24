-- Sub-zone popups work without enabling the legacy POC command.
local p = require('presentation');
local game = H.zoneinfo_game;
local checks = 0;
local function check(label, ok) H.print(label, ok); assert(ok, label); checks = checks + 1; end
local function count()
    local total = 0;
    for _, line in ipairs(H.printed) do
        if line:find('Sub-zone: Knightwell -', 1, true) then total = total + 1; end
    end
    return total;
end
local function move(x, y) game.x, game.y = x - 256, 256 - y; end
H.load();
p.app.options.display.fieldApproach[1] = 30; -- The places below were laid out for a 30-yalm buffer.
p.app.options.display.reannounceSeconds[1] = 0; -- Returns below come quickly; each is to be announced.
H.frames(230);
check('sub-zone popups enabled by default', p.area_enabled());
check('load seeds silently', count() == 0);
move(238, 337); H.frames(70);
check('entering sub-zone announces without POC command', count() == 1);
local discovered = 0;
for key in pairs(p.app.options.display.discovered) do if key:find(':knightwell', 1, true) then discovered = discovered + 1; end end
check('the first time, it is discovered and kept', discovered == 1);
H.frames(70);
check('remaining inside does not spam', count() == 1);
move(200, 300); H.frames(60); move(238, 337); H.frames(70);
check('reentry produces another popup', count() == 2);
local kept = 0;
for _ in pairs(p.app.options.display.discovered) do kept = kept + 1; end
check('come to again, nothing more is discovered', kept == 1);
H.packet(0x00A); H.frames(70);
check('zone-in inside sub-zone remains silent', count() == 2);
p.app.options.display.areaEnabled[1] = false;
move(200, 300); H.frames(60); move(238, 337); H.frames(70);
check('settings can suppress sub-zone popups', count() == 2);
p.on_area_preview(); H.frames(1);
check('sub-zone preview works without enabling popups', not p.area_enabled());
H.print(('zoneinfo sub-zone integration: %d assertions passed'):format(checks));
