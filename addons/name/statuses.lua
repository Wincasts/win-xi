-- The statuses over a name: a row of icons above it, for the statuses its player has chosen to see.
--
--   statuses.Defaults(defaults)       adds the settings below to an addon's own
--   statuses.HandlePacket(e)          every packet in goes by this: what lands on an enemy is kept count of
--   statuses.Begin(options)           each frame, before any name is set out: whether there is anything
--                                     to draw this frame, the sheet of icons given to the plugin
--   statuses.Write(name, above, height, scale)   between the plugin's BeginName and EndName: the row,
--                                     its foot at above, for a name whose letters are height high
--   statuses.DrawSettings(options, save)         the settings tab
--
-- What is known of who is under what is not the same for everyone. The game keeps the player's own
-- statuses and those of the five others of the player's own party, and they are read as they are. Of
-- anyone else it is told nothing: winxi.debuffs keeps count of the spells seen to land on them, so an
-- enemy has what was cast on it within sight, for as long as such a spell usually lasts. Other
-- players, other parties of an alliance and NPCs have only what was seen cast on them that way.
--
-- The icons are winxi's own (winxi.statusicons), all from the one sheet: the plugin draws from eight
-- pictures and no more, and the others are taken. A status winxi has no icon for is not drawn.
local bit         = require('bit');
local imgui       = require('imgui');
local widgets     = require('winxi.widgets');
local nameplates  = require('winxi.nameplates');
local statusicons = require('winxi.statusicons');
local debuffs     = require('winxi.debuffs');
local controls    = require('controls');

local statuses = {};

statuses.Slot = 7; -- the plugin's number for the sheet: the last, the names' own have the rest

local WHITE        = 0xFFFFFFFF;
local MOST         = 12;   -- icons over one name
local GAP          = 1;    -- pixels between one icon and the next
local RISE         = 3;    -- pixels between the row and what is under it
local PARTY_OTHERS = 5;    -- the others of the player's party, whose statuses the game keeps
local SLOTS        = 32;   -- statuses the game keeps for each
local MEMBER_SIZE  = 0x30; -- one member of the party's statuses, as the game keeps them
local LAST_STATUS  = 671;  -- the highest number the sheet has a place for
local LIST_ROWS    = 14;   -- rows of the settings' list to be seen at once

-- What can be set. The statuses to show are kept as a list of their numbers: to begin with, what
-- ails a character and what winxi.debuffs can tell of an enemy.
local settings = {
    showStatuses = function () return T{ true }; end,
    statusSize   = function () return T{ 125 }; end, -- an icon's height, as a percentage of the height of the names
    statusList   = function ()
        return T{ 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 19, 128, 129, 130, 131, 132, 133, 134, 135, 156, 192, 194, 217 };
    end,
};

function statuses.Defaults(defaults)
    for key, make in pairs(settings) do
        defaults[key] = make();
    end
    return defaults;
end

function statuses.HandlePacket(e)
    debuffs.HandlePacket(e);
end

-- The chosen statuses as a set, made again when the list is another or has changed
local chosen, chosenList, chosenCount = {}, nil, -1;

local function Chosen(options)
    local list = options.statusList;
    if (type(list) ~= 'table') then
        list = settings.statusList();
        options.statusList = list;
    end
    if (list ~= chosenList or #list ~= chosenCount) then
        chosenList, chosenCount = list, #list;
        chosen = {};
        for index = 1, #list do
            chosen[list[index]] = true;
        end
    end
    return chosenCount;
end

local function Choose(options, id, on)
    local list = options.statusList;
    for index = #list, 1, -1 do
        if (list[index] == id) then
            table.remove(list, index);
        end
    end
    if (on) then
        list[#list + 1] = id;
        table.sort(list);
    end
    chosenList = nil;
end

-- The player's own statuses and the party's, read once a frame into lists kept from frame to frame
local own = { count = 0 };
local party = {};
for member = 1, PARTY_OTHERS do
    party[member] = { id = 0, count = 0 };
end
local partyPointer = nil;

local function ReadOwn(memory)
    own.count = 0;
    local player = memory:GetPlayer();
    if (player == nil or player:GetIsZoning() ~= 0) then
        return;
    end
    local ids = player:GetStatusIcons();
    local count = 0;
    for slot = 1, SLOTS do
        local id = ids[slot];
        if (id ~= nil and id > 0 and id ~= 255 and id < 0x400) then
            count = count + 1;
            own[count] = id;
        end
    end
    own.count = count;
end

-- As the game keeps them: who, then two bits of each status's number four to a byte, then the rest
-- of each number a byte each
local function ReadParty()
    for member = 1, PARTY_OTHERS do
        party[member].id, party[member].count = 0, 0;
    end
    if (partyPointer == nil or partyPointer == 0) then
        partyPointer = AshitaCore:GetPointerManager():Get('party.statusicons');
    end
    local base = (partyPointer ~= nil and partyPointer ~= 0) and ashita.memory.read_uint32(partyPointer) or 0;
    if (base == 0) then
        return;
    end
    for member = 1, PARTY_OTHERS do
        local at = base + MEMBER_SIZE * (member - 1);
        local id = ashita.memory.read_uint32(at);
        if (id ~= 0) then
            local list = party[member];
            local count, high = 0, 0;
            for slot = 0, SLOTS - 1 do
                local pair = slot % 4;
                if (pair == 0) then
                    high = ashita.memory.read_uint8(at + 8 + slot / 4);
                end
                local status = bit.band(bit.rshift(high, pair * 2), 0x03) * 256 + ashita.memory.read_uint8(at + 16 + slot);
                if (status > 0 and status ~= 255) then
                    count = count + 1;
                    list[count] = status;
                end
            end
            list.id, list.count = id, count;
        end
    end
end

local sheet = 0;      -- the sheet's address this frame, or 0
local size = 1.25;    -- an icon's height, as a part of the name's
local SELF = nameplates.Category.Self;

-- Whether any name can have a row this frame
function statuses.Begin(options)
    sheet = 0;
    if (options.showStatuses == nil or not options.showStatuses[1] or Chosen(options) == 0) then
        nameplates.SetTexture(statuses.Slot, 0);
        return false;
    end
    sheet = statusicons.Sheet() or 0;
    nameplates.SetTexture(statuses.Slot, sheet);
    if (sheet == 0) then
        return false;
    end
    size = math.max(50, math.min(300, options.statusSize[1])) / 100;
    ReadOwn(AshitaCore:GetMemoryManager());
    ReadParty();
    return true;
end

-- The row for one name: what it is under that is chosen, each status once
local row, rowCount = {}, 0;
local taken, mark = {}, 0;

local function Take(id)
    if (chosen[id] and taken[id] ~= mark and rowCount < MOST) then
        local place = statusicons.SheetPlace(id);
        if (place ~= nil) then
            taken[id] = mark;
            rowCount = rowCount + 1;
            row[rowCount] = place;
        end
    end
end

local function TakeAll(list)
    for index = 1, list.count do
        Take(list[index]);
    end
end

-- What was seen to land on it, the lowest number first so that the row keeps its order
local tracked = {};

local function TakeTracked(serverId)
    local on = debuffs.On(serverId);
    if (on == nil) then
        return;
    end
    local now, count = os.time(), 0;
    for kind, entry in pairs(on) do
        local id = debuffs.StatusIds[kind];
        if (id ~= nil and now < entry.expires) then
            count = count + 1;
            tracked[count] = id;
        end
    end
    for index = #tracked, count + 1, -1 do
        tracked[index] = nil;
    end
    if (count > 1) then
        table.sort(tracked);
    end
    for index = 1, count do
        Take(tracked[index]);
    end
end

local function Gather(name)
    rowCount, mark = 0, mark + 1;
    if (name.Category == SELF) then
        TakeAll(own);
        return;
    end
    local serverId = name.ServerId;
    for member = 1, PARTY_OTHERS do
        if (party[member].id == serverId) then
            TakeAll(party[member]);
            return;
        end
    end
    TakeTracked(serverId);
end

function statuses.Write(name, above, height, scale)
    if (sheet == 0) then
        return;
    end
    Gather(name);
    if (rowCount == 0) then
        return;
    end

    local tall = math.max(1, math.floor(height * size + 0.5));
    local wide = math.max(1, math.floor(tall * statusicons.OwnAspect + 0.5));
    local gap = math.floor(GAP * scale + 0.5);
    local left = math.floor(-(rowCount * wide + (rowCount - 1) * gap) * 0.5);
    local foot = above - math.floor(RISE * scale + 0.5);
    for index = 1, rowCount do
        local place = row[index];
        -- the icons have an edge of their own: none is drawn round them
        nameplates.Quad(left, foot - tall, left + wide, foot, place[1], place[2], place[3], place[4], WHITE, statuses.Slot, false);
        left = left + wide + gap;
    end
end

-- The settings' list: every status winxi has an icon for, by name
local known = nil;
local search = T{ '' };
local chosenOnly = T{ false };
local tick = { false };
local listSize = { 0, 0 };
local previewSize, previewA, previewB = { 36, 48 }, { statusicons.OwnLeft, 0 }, { statusicons.OwnRight, 1 };

local function Known()
    if (known ~= nil) then
        return known;
    end
    known = {};
    local resources = AshitaCore:GetResourceManager();
    for id = 1, LAST_STATUS do
        local name = statusicons.SheetPlace(id) ~= nil and resources:GetString('buffs.names', id) or nil;
        if (type(name) == 'string' and name ~= '') then
            name = name:sub(1, 1):upper() .. name:sub(2);
            known[#known + 1] = { id = id, lower = name:lower(), label = ('%s (%d)##name.status.%d'):format(name, id, id) };
        end
    end
    table.sort(known, function (a, b)
        if (a.lower ~= b.lower) then
            return a.lower < b.lower;
        end
        return a.id < b.id;
    end);
    return known;
end

function statuses.DrawSettings(options, save)
    Chosen(options);
    local changed = false;

    controls.BeginLayout('statuses', 360, 'Show Statuses');
    controls.Section('Status Icons', '##name.statusOptions', true);
    if (controls.Checkbox('Show Statuses', '##name.showStatuses', options.showStatuses,
            'A row of icons above a name, for the statuses ticked below.\nYour own and your party\'s are as the game has them. An enemy\'s are worked out from the spells seen to land on it, each lasting its usual time: one that landed out of sight, or came from anything but a spell, is not known. Other players have only what was seen cast on them the same way.')) then
        changed = true;
    end
    if (options.showStatuses[1]) then
        if (controls.Slider('Scale', '##name.statusSize', options.statusSize, 50, 300, '%d%%',
                'An icon\'s height, as a percentage of the height of the names. The icons are three quarters as wide as they are tall.')) then
            changed = true;
        end
    end
    controls.EndSection();

    controls.Section('Shown Statuses', '##name.statusChoice');
    widgets.Label('Search');
    controls.Width();
    imgui.InputText('##name.statusSearch', search, 64);
    controls.Mark('Part of a status\'s name, or its number. Only a ticked status is drawn over a name; a status with no FFXIV icon is not listed.');
    controls.Checkbox('Chosen Only', '##name.statusChosenOnly', chosenOnly, 'Lists only the statuses that are ticked.');

    local wanted = search[1]:lower();
    listSize[2] = imgui.GetFrameHeightWithSpacing() * LIST_ROWS;
    imgui.BeginChild('##name.statusList', listSize, ImGuiChildFlags_Borders or 1);
    for _, status in ipairs(Known()) do
        local on = chosen[status.id] == true;
        if ((on or not chosenOnly[1]) and (wanted == '' or status.lower:find(wanted, 1, true) ~= nil or tostring(status.id) == wanted)) then
            tick[1] = on;
            if (imgui.Checkbox(status.label, tick)) then
                Choose(options, status.id, tick[1]);
                changed = true;
            end
            if (imgui.IsItemHovered()) then
                local icon = statusicons.Own(status.id);
                if (icon ~= nil) then
                    imgui.BeginTooltip();
                    imgui.Image(icon, previewSize, previewA, previewB);
                    imgui.EndTooltip();
                end
            end
        end
    end
    imgui.EndChild();
    controls.EndSection();
    controls.EndLayout();

    if (changed and save ~= nil) then
        save();
    end
end

return statuses;
