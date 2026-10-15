package.path = 'addons/zone/?.lua;' .. package.path;
local background = require('banner_background');
local original = background.new;
H.background_loads = 0;
background.new = function()
    local cache = original(function(file)
        H.background_loads = H.background_loads + 1;
        if file == 'missing.png' then error('missing image'); end
        return { handle = 42, width = 320, height = 70 };
    end);
    H.background_cache = cache;
    return cache;
end;
dofile('tests/zoneinfo_fixture.lua');
