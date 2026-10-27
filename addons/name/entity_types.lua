-- Which kinds of name a feature is drawn for: a mask of winxi.nameplates' categories, kept as T{ mask }.
--
--   types.Settle(value)               the mask made good: a number of the categories, all where it is not
--   types.Draw(prefix, value, what, spec)   a checkbox for each, a row with a sentence saying what is
--                                     drawn over that kind ('A health bar'); returns whether any changed
local bit = require('bit');
local nameplates = require('winxi.nameplates');
local controls = require('controls');

local Category = nameplates.Category;

local types = {};

-- Each kind, with what it is: the sentence of a row is what is drawn, over that
types.List = {
    { key = 'self',     category = Category.Self,     label = 'Yourself',         over = 'your own name' },
    { key = 'party',    category = Category.Party,    label = 'Party Members',    over = 'the others of your party, trusts among them' },
    { key = 'alliance', category = Category.Alliance, label = 'Alliance Members', over = 'the other parties of your alliance' },
    { key = 'players',  category = Category.Player,   label = 'Other Players',    over = 'every player outside your party and alliance' },
    { key = 'myPet',    category = Category.MyPet,    label = 'My Pet',           over = 'your own pet' },
    { key = 'pets',     category = Category.Pet,      label = 'Other Pets',       over = 'anyone else\'s pet, trust or adventuring fellow' },
    { key = 'npcs',     category = Category.Npc,      label = 'NPCs',             over = 'what cannot be fought: townspeople, doors, and the rest' },
    { key = 'monsters', category = Category.Monster,  label = 'Monsters',         over = 'what can be fought, charmed players among them' },
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
local ids = {};       -- prefix -> the id of each kind's checkbox
local sentences = {}; -- what -> the sentence of each kind's row, made once

local function Rows(prefix, what)
    local rowIds, rowSentences = ids[prefix], sentences[what];
    if (rowIds == nil) then
        rowIds = {};
        for index, entry in ipairs(types.List) do
            rowIds[index] = ('##name.%s.%s'):format(prefix, entry.key);
        end
        ids[prefix] = rowIds;
    end
    if (rowSentences == nil) then
        rowSentences = {};
        for index, entry in ipairs(types.List) do
            rowSentences[index] = ('%s over %s.'):format(what, entry.over);
        end
        sentences[what] = rowSentences;
    end
    return rowIds, rowSentences;
end

function types.Draw(prefix, value, what, spec)
    local changed = false;
    local rowIds, rowSentences = Rows(prefix, what or 'This');
    for index, entry in ipairs(types.List) do
        tick[1] = bit.band(value[1], entry.category) ~= 0;
        if (controls.Checkbox(entry.label, rowIds[index], tick, rowSentences[index], spec)) then
            value[1] = tick[1] and bit.bor(value[1], entry.category) or bit.band(value[1], bit.bnot(entry.category));
            changed = true;
        end
    end
    return changed;
end

return types;
