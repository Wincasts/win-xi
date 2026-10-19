-- Which kinds of name a feature is drawn for: a mask of winxi.nameplates' categories, kept as T{ mask }.
--
--   types.Settle(value)               the mask made good: a number of the categories, all where it is not
--   types.Draw(prefix, value, help)   a checkbox for each, under Players, Pets and NPCs & Monsters;
--                                     returns whether any changed
local bit = require('bit');
local imgui = require('imgui');
local nameplates = require('winxi.nameplates');
local controls = require('controls');

local Category = nameplates.Category;

local types = {};

types.List = {
    { key = 'self',     category = Category.Self,     label = 'Yourself',         group = 'Players' },
    { key = 'party',    category = Category.Party,    label = 'Party Members' },
    { key = 'alliance', category = Category.Alliance, label = 'Alliance Members' },
    { key = 'players',  category = Category.Player,   label = 'Other Players' },
    { key = 'myPet',    category = Category.MyPet,    label = 'My Pet',           group = 'Pets' },
    { key = 'pets',     category = Category.Pet,      label = 'Other Pets' },
    { key = 'npcs',     category = Category.Npc,      label = 'NPCs',             group = 'NPCs & Monsters' },
    { key = 'monsters', category = Category.Monster,  label = 'Monsters' },
};

function types.Settle(value)
    if (type(value) ~= 'table') then
        return T{ Category.All };
    end
    local mask = tonumber(value[1]);
    value[1] = mask ~= nil and mask == mask and bit.band(math.floor(mask), Category.All) or Category.All;
    return value;
end

local tick = { false };

function types.Draw(prefix, value, help)
    local changed = false;
    for _, entry in ipairs(types.List) do
        if (entry.group ~= nil) then
            imgui.TextDisabled(entry.group);
        end
        tick[1] = bit.band(value[1], entry.category) ~= 0;
        if (controls.Checkbox(entry.label, '##name.' .. prefix .. '.' .. entry.key, tick, help)) then
            value[1] = tick[1] and bit.bor(value[1], entry.category) or bit.band(value[1], bit.bnot(entry.category));
            changed = true;
        end
    end
    return changed;
end

return types;
