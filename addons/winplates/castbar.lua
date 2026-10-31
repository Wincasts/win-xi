-- name's cast bars: winxi.castbar's observed casts, switched on by Show Cast Bar (while names are
-- drawn) and Show Weaponskills. Everything else is winxi.castbar's own.
local casts = require('winxi.castbar');
local castbar = setmetatable({}, { __index = casts });
local function wanted(options)
    return options.showCastBar and options.showCastBar[1] and (not options.drawNames or options.drawNames[1]) or false,
        options.castBarWeaponskills and options.castBarWeaponskills[1] or false;
end
function castbar.Configure(options) return casts.Configure(wanted(options)); end
function castbar.Begin(options, now)
    local on, withSkills = wanted(options);
    casts.Begin(on, withSkills, now);
end
function castbar.HandlePacket(e, options)
    if e.id ~= 0x00A then castbar.Configure(options); end
    casts.HandlePacket(e);
end
return castbar;
