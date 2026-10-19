-- The statuses over a name: a row of icons above it or below it, for the statuses its player has chosen to see.
--
--   statuses.Defaults(defaults)       adds the settings below to an addon's own
--   statuses.HandlePacket(e)          every packet in goes by this: what lands on an enemy is kept count of
--   statuses.Begin(options)           each frame, before any name is set out: whether there is anything
--                                     to draw this frame, the sheet of icons given to the plugin
--   statuses.Write(name, left, right, above, below, height, scale)   between the plugin's
--                                     BeginName and EndName: the row, for a name whose letters are height
--                                     high, drawn from left to right, with nothing yet above above or below
--                                     below, moved by the X and Y offsets
--   statuses.DrawSettings(options, save)         the settings tab
--
-- What is known of who is under what is not the same for everyone. The game keeps the player's own
-- statuses and those of the five others of the player's own party, and they are read as they are. Of
-- anyone else it is told nothing: winxi.debuffs keeps count of every status the server is seen to say
-- took hold on them, by spell, ability, weapon skill, monster's move or additional effect, for as long
-- as the server's scripts say it usually lasts, or until the server says it wore off.
--
-- The icons are as party and buff draw them (winxi.statusicons): with Custom Icons on in winxisettings,
-- the chosen set's where it has one and the game's where it has not; off, the game's. All are from
-- the one sheet: the plugin draws from eight pictures and no more, and the others are taken.
local bit         = require('bit');
local imgui       = require('imgui');
local widgets     = require('winxi.widgets');
local nameplates  = require('winxi.nameplates');
local statusicons = require('winxi.statusicons');
local debuffs     = require('winxi.debuffs');
local theme       = require('winxi.theme');
local controls    = require('controls');
local entityTypes = require('entity_types');

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
local PREVIEW_MOST = 4;    -- icons over each name while previewing
local MOST_OFFSET  = 200;  -- screen pixels the row can be moved each way

-- Preview: every shown name has a few of the chosen statuses over it, whatever it is under, to see
-- how the row looks. Not kept: it is off again when the addon is loaded.
local preview = T{ false };

-- What can be set. The statuses to show are kept as a list of their numbers: to begin with, what
-- ails a character and what winxi.debuffs can tell of an enemy.
local settings = {
    showStatuses = function () return T{ true }; end,
    statusSize   = function () return T{ 125 }; end, -- an icon's height, as a percentage of the height of the names
    statusPlace  = function () return T{ 'above' }; end,  -- the row above the name or below it
    statusAlign  = function () return T{ 'center' }; end, -- and level with its left, its middle or its right
    statusOffsetX = function () return T{ 0 }; end, -- then moved right (or left, below 0), in screen pixels
    statusOffsetY = function () return T{ 0 }; end, -- and down (or up, below 0)
    statusCategories = function () return T{ 0xFF }; end, -- which kinds of name have a row: entity_types
    statusIcons  = function () return T{ 'theme' }; end,  -- the icons: as the winxi theme has them, the game's, or the custom set's
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

-- Whether the custom set's icons are drawn: as Icons says, or as the winxi theme's Custom Icons does
local function UseOwn(options)
    local icons = options.statusIcons ~= nil and options.statusIcons[1] or 'theme';
    if (icons == 'game') then return false; end
    if (icons == 'custom') then return true; end
    return theme.Get().StatusIcons == true;
end

local sheet = 0;      -- the sheet's address this frame, or 0
local placeOf = statusicons.MixedPlace; -- where a status's icon is in it, and whether it is the set's
local aspect = statusicons.OwnAspect;    -- how wide one of the set's is, for how tall: the game's are square
local shownWith = nil; -- the settings of this frame
local size = 1.25;    -- an icon's height, as a part of the name's
local below = false;  -- the row under the name, not over it
local align = 'center';
local offsetX, offsetY = 0, 0; -- screen pixels the row is moved by
local categories = 0xFF; -- the kinds of name that have a row
local SELF = nameplates.Category.Self;
-- The player's and the party's statuses are read the first time a name this frame wants them, and
-- not at all in a frame with no name that does; and the time, for what is tracked, once a frame
local ownRead, partyRead = false, false;
local seconds = 0;

-- Whether any name can have a row this frame
function statuses.Begin(options)
    sheet = 0;
    if (options.showStatuses == nil or not options.showStatuses[1] or Chosen(options) == 0) then
        nameplates.SetTexture(statuses.Slot, 0);
        return false;
    end
    if (UseOwn(options)) then
        sheet, placeOf, aspect = statusicons.MixedSheet() or 0, statusicons.MixedPlace, statusicons.OwnAspect;
    else
        sheet, placeOf, aspect = statusicons.GameSheet() or 0, statusicons.GameSheetPlace, 1;
    end
    nameplates.SetTexture(statuses.Slot, sheet);
    if (sheet == 0) then
        return false;
    end
    size = math.max(50, math.min(300, options.statusSize[1])) / 100;
    below = options.statusPlace ~= nil and options.statusPlace[1] == 'below';
    align = options.statusAlign ~= nil and options.statusAlign[1] or 'center';
    offsetX = math.max(-MOST_OFFSET, math.min(MOST_OFFSET, tonumber(options.statusOffsetX ~= nil and options.statusOffsetX[1]) or 0));
    categories = options.statusCategories ~= nil and tonumber(options.statusCategories[1]) or 0xFF;
    offsetY = math.max(-MOST_OFFSET, math.min(MOST_OFFSET, tonumber(options.statusOffsetY ~= nil and options.statusOffsetY[1]) or 0));
    shownWith = options;
    ownRead, partyRead, seconds = false, false, os.time();
    return true;
end

-- The row for one name: what it is under that is chosen, each status once, and whether each icon is
-- one of the set's
local row, rowOwn, rowCount = {}, {}, 0;
local taken, mark = {}, 0;

local function Take(id)
    if (chosen[id] and taken[id] ~= mark and rowCount < MOST) then
        local place, own = placeOf(id);
        if (place ~= nil) then
            taken[id] = mark;
            rowCount = rowCount + 1;
            row[rowCount], rowOwn[rowCount] = place, own == true;
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
    local on = debuffs.Statuses(serverId);
    if (on == nil) then
        return;
    end
    local count = 0;
    for id, entry in pairs(on) do
        if (seconds < entry.expires) then
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

-- The first few chosen statuses, for a preview, the same few over every name
local function TakePreview(options)
    local list = options.statusList;
    for index = 1, #list do
        if (rowCount >= PREVIEW_MOST) then
            return;
        end
        Take(list[index]);
    end
end

local function Gather(name, options)
    rowCount, mark = 0, mark + 1;
    if (preview[1]) then
        TakePreview(options);
        return;
    end
    if (name.Category == SELF) then
        if (not ownRead) then
            ownRead = true;
            ReadOwn(AshitaCore:GetMemoryManager());
        end
        TakeAll(own);
        return;
    end
    if (not partyRead) then
        partyRead = true;
        ReadParty();
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

function statuses.Write(name, nameLeft, nameRight, above, under, height, scale)
    if (sheet == 0 or bit.band(categories, name.Category or 0) == 0) then
        return;
    end
    Gather(name, shownWith);
    if (rowCount == 0) then
        return;
    end

    local tall = math.max(1, math.floor(height * size + 0.5));
    local wide = math.max(1, math.floor(tall * aspect + 0.5));
    local gap = math.floor(GAP * scale + 0.5);
    local across = (rowCount - 1) * gap;
    for index = 1, rowCount do
        across = across + (rowOwn[index] and wide or tall);
    end
    local left;
    if (align == 'left') then
        left = nameLeft;
    elseif (align == 'right') then
        left = nameRight - across;
    else
        left = math.floor((nameLeft + nameRight - across) * 0.5);
    end
    local rise = math.floor(RISE * scale + 0.5);
    local top = below and (under + rise) or (above - rise - tall);
    -- the offsets are the screen's pixels, as the gap is
    left = left + math.floor(offsetX * scale + 0.5);
    top = top + math.floor(offsetY * scale + 0.5);
    for index = 1, rowCount do
        local place = row[index];
        -- the set's icons are narrower than the game's, which are square, as party draws them
        local width = rowOwn[index] and wide or tall;
        -- the icons have an edge of their own: none is drawn round them
        nameplates.Quad(left, top, left + width, top + tall, place[1], place[2], place[3], place[4], WHITE, statuses.Slot, false);
        left = left + width + gap;
    end
end

-- The settings' list: every status the game has a name for
local known = nil;
local search = T{ '' };
local chosenOnly = T{ false };
local tick = { false };
local listSize = { 0, 0 };
local previewSize, previewA, previewB = { 36, 48 }, { 0, 0 }, { 1, 1 }; -- filled in from the set as it is drawn
local gameSize, gameA, gameB = { 48, 48 }, { 0, 0 }, { 1, 1 };

local function Known()
    if (known ~= nil) then
        return known;
    end
    known = {};
    local resources = AshitaCore:GetResourceManager();
    for id = 1, LAST_STATUS do
        local name = resources:GetString('buffs.names', id);
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

local PLACES = { { key = 'above', label = 'Above' }, { key = 'below', label = 'Below' } };
local ICONS = { { key = 'theme', label = 'Winxi Theme' }, { key = 'game', label = 'Game Icons' }, { key = 'custom', label = 'Custom Icons' } };
local ALIGNMENTS = { { key = 'left', label = 'Left' }, { key = 'center', label = 'Center' }, { key = 'right', label = 'Right' } };

function statuses.DrawSettings(options, save)
    Chosen(options);
    local changed = false;

    controls.BeginLayout('statuses', 360, 'Y Offset (px)');
    if (controls.Section('Display', '##name.statusOptions', true)) then
        if (controls.Checkbox('Enabled', '##name.showStatuses', options.showStatuses,
                'Show the statuses selected below on visible nameplates.')) then
            changed = true;
        end
        if (options.showStatuses[1]) then
            if (controls.Choice('Icons', '##name.statusIcons', options.statusIcons, ICONS,
                    'Which icons the statuses are drawn with. Winxi Theme follows Custom Icons in /wxi; Game Icons are the game\'s own; Custom Icons are the custom set\'s (the one chosen in /wxi, FFXIV to begin with), and the game\'s for a status the set has none for.')) then
                changed = true;
            end
            if (controls.Slider('Size (%)', '##name.statusSize', options.statusSize, 50, 300, '%d%%',
                    'An icon\'s height, as a percentage of the height of the names. With custom icons, each is as wide as the set\'s icons are for that height; the game\'s are square.')) then
                changed = true;
            end
            if (controls.Choice('Position', '##name.statusPlace', options.statusPlace, PLACES,
                    'Above the name, over the mastery stars where it has them, or below it, under the line a checked monster\'s details are written on while they are shown.')) then
                changed = true;
            end
            if (controls.Choice('Alignment', '##name.statusAlign', options.statusAlign, ALIGNMENTS,
                    'Which side of the name the row is level with: its left, where its icons begin, its middle, or its right.')) then
                changed = true;
            end
            if (controls.Input('X Offset (px)', '##name.statusOffsetX', options.statusOffsetX, -MOST_OFFSET, MOST_OFFSET,
                    'Moves the row right from where Position and Alignment put it, in screen pixels; below 0, left.')) then
                changed = true;
            end
            if (controls.Input('Y Offset (px)', '##name.statusOffsetY', options.statusOffsetY, -MOST_OFFSET, MOST_OFFSET,
                    'Moves the row down from where Position and Alignment put it, in screen pixels; below 0, up.')) then
                changed = true;
            end
            controls.Checkbox('Preview', '##name.statusPreview', preview,
                'Puts the first few ticked statuses over every name that is shown, whatever it is really under, to see how the row looks. Not kept: it is off again when the addon is loaded.');
        end
    end
    controls.EndSection();

    if (controls.Section('Entity Types', '##name.statusTypes')) then
        imgui.BeginDisabled(not options.showStatuses[1]);
        if (entityTypes.Draw('statusTypes', options.statusCategories, 'Whether names of this kind have a row of statuses.')) then
            changed = true;
        end
        imgui.EndDisabled();
    end
    controls.EndSection();

    if (controls.Section('Selected Statuses', '##name.statusChoice')) then
        widgets.Label('Search');
        controls.Width();
        imgui.InputText('##name.statusSearch', search, 64);
        controls.Mark('Part of a status\'s name, or its number. Only a ticked status is drawn over a name.');
        controls.Checkbox('Selected Only', '##name.statusChosenOnly', chosenOnly, 'Lists only the statuses that are ticked.');

        local wanted = search[1]:lower();
        listSize[2] = imgui.GetFrameHeightWithSpacing() * LIST_ROWS;
        imgui.BeginChild('##name.statusList', listSize, ImGuiChildFlags_Borders or 1);
        local useOwn = UseOwn(options);
        for _, status in ipairs(Known()) do
            local on = chosen[status.id] == true;
            if ((on or not chosenOnly[1]) and (wanted == '' or status.lower:find(wanted, 1, true) ~= nil or tostring(status.id) == wanted)) then
                tick[1] = on;
                if (imgui.Checkbox(status.label, tick)) then
                    Choose(options, status.id, tick[1]);
                    changed = true;
                end
                if (imgui.IsItemHovered()) then
                    local icon, own = statusicons.Get(status.id, useOwn);
                    if (icon ~= nil) then
                        imgui.BeginTooltip();
                        if (own) then
                            previewSize[1] = previewSize[2] * statusicons.OwnAspect;
                            previewA[1], previewB[1] = statusicons.OwnLeft, statusicons.OwnRight;
                            imgui.Image(icon, previewSize, previewA, previewB);
                        else
                            imgui.Image(icon, gameSize, gameA, gameB);
                        end
                        imgui.EndTooltip();
                    end
                end
            end
        end
        imgui.EndChild();
    end
    controls.EndSection();
    controls.EndLayout();
    controls.Help('Help / Examples', '##name.statusHelp',
        'Your own and party statuses come from the game. Everyone else\'s come from effects observed in server messages; effects applied out of sight or before entering the area may be unknown.\nCustom Icons in /wxi selects the icon set, with game icons as fallback.');

    if (changed and save ~= nil) then
        save();
    end
end

return statuses;
