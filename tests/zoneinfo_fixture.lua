-- Loads zoneinfo with a synthetic client-map table for the shared Ashita harness.
package.path = 'addons/libs/?.lua;' .. package.path; require('winxi.gamedata').Root('addons/libs/winxi/data/') -- the server's sets, from the repository's data
package.path = 'addons/zone/?.lua;' .. package.path;
package.preload['chat'] = function()
    return {
        header = function(name) return { append = function(_, text) return '[' .. name .. '] ' .. text; end }; end,
        message = function(text) return text; end,
        error = function(text) return text; end,
    };
end;
local game = { zone = 100, x = -56, y = -44, z = 10, present = true, valid_table = true };
H.zoneinfo_game = game;
function GetPlayerEntity()
    return game.present and { Movement = { LocalPosition = { X = game.x, Y = game.y, Z = game.z } } } or nil;
end
local party = { GetMemberZone = function() return game.zone; end };
local core = AshitaCore;
local base_memory = core:GetMemoryManager();
AshitaCore = setmetatable({
    GetMemoryManager = function() return setmetatable({ GetParty = function() return party; end }, { __index = base_memory }); end,
    GetResourceManager = function() return { GetString = function(_, kind, id) return kind == 'zones.names' and ('Zone ' .. id) or 'Clear'; end }; end,
}, { __index = core });
local defs = require('data.poc_areas');
ashita.memory.find = function(_, _, sig) return sig:sub(1, 4) == '8A0D' and 1000 or 0; end;
ashita.memory.read_uint32 = function(address) return address == 1028 and 2000 or 0; end;
local function at(address)
    for zone, def in pairs(defs) do
        local offset = address - (2000 + def.table_index * 14);
        if offset >= 0 and offset < 14 then return zone, offset; end
    end
end
ashita.memory.read_uint16 = function(address)
    local zone, offset = at(address);
    if offset == 0 then return game.valid_table and zone or 999; end
    if offset == 10 or offset == 12 then return 65536 - 256; end
    return 0;
end;
ashita.memory.read_uint8 = function(address)
    local _, offset = at(address);
    return offset == 5 and 5 or 0;
end;
dofile('addons/zone/zone.lua');
