-- winxi's art is found beside the module that draws it: in libs\winxi, or in the copy of winxi an
-- addon released on its own carries in its folder (tools/package_release.py, zone's release).
local checks = 0;
local function check(label, ok) H.print(label, ok); assert(ok, label); checks = checks + 1; end

local backgrounds = require('winxi.backgrounds');
local borders = require('winxi.borders');
check('backgrounds: beside libs/winxi/backgrounds.lua', backgrounds.Folder():find('addons/libs/winxi/assets\\backgrounds\\', 1, true) ~= nil);
check('borders: beside libs/winxi/borders.lua', borders.Folder():find('addons/libs/winxi/assets\\borders\\', 1, true) ~= nil);

-- The same file somewhere else (an addon's own copy) finds the art beside itself there.
local function copied(name)
    local source = io.open('addons/libs/winxi/' .. name .. '.lua'):read('*a');
    local chunk = assert(loadstring(source, '@C:\\Ashita\\addons\\zone\\winxi\\' .. name .. '.lua'));
    package.loaded['winxi.' .. name] = nil;
    return chunk('winxi.' .. name);
end
check('an addon\'s copy of backgrounds: its own art', copied('backgrounds').Folder() == 'C:\\Ashita\\addons\\zone\\winxi\\assets\\backgrounds\\');
check('an addon\'s copy of borders: its own art', copied('borders').Folder() == 'C:\\Ashita\\addons\\zone\\winxi\\assets\\borders\\');

-- Loaded with no place known: the addon's own copy if it has one, or libs\winxi's.
local function unplaced(name)
    local source = io.open('addons/libs/winxi/' .. name .. '.lua'):read('*a');
    return assert(loadstring(source, '=' .. name))('winxi.' .. name);
end
local realexists = ashita.fs.exists;
ashita.fs.exists = function(path) return path == addon.path .. 'winxi\\assets\\borders\\'; end;
check('no place known, the addon\'s copy there: its art', unplaced('borders').Folder() == addon.path .. 'winxi\\assets\\borders\\');
ashita.fs.exists = function() return false; end;
check('no place known, no copy: libs\\winxi\'s', unplaced('borders').Folder():find('\\addons\\libs\\winxi\\assets\\borders\\', 1, true) ~= nil);
ashita.fs.exists = realexists;

H.print(('winxi assets: %d assertions passed'):format(checks));
