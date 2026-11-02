-- The statuses over a name: a row of icons above it or below it, for the statuses its player has chosen to see.
--
--   statuses.Defaults(defaults)       adds the settings below to an addon's own
--   statuses.Settle(options)          the settings have been loaded: a new character's statuses chosen
--   statuses.HandlePacket(e)          every packet in goes by this: what lands on an enemy is kept count of
--   statuses.Begin(options)           each frame, before any name is set out: whether there is anything
--                                     to draw this frame, the sheet of icons given to the plugin
--   statuses.Write(name, left, right, above, below, height, scale, set, fit)   between the plugin's
--                                     BeginName and EndName: the row, for a name whose letters are height
--                                     high, drawn from left to right, with nothing yet above above or below
--                                     below, moved by the X and Y offsets; set and fit the name's letters,
--                                     for the durations under the icons
--   statuses.SetWords(width, write, own)   how the names' letters are measured and written, from custom:
--                                     width(set, words, fit) and write(set, words, pen, top, fit, color); own(height),
--                                     the durations' own font's letters at a name's height, or nil for the name's
--   statuses.DrawSettings(options, save)         the settings tab
--
-- What is known of who is under what is not the same for everyone. The game keeps the player's own
-- statuses and those of the five others of the player's own party, and they are read as they are
-- (winxi.partystatus). Of anyone else it is told nothing: winxi.debuffs keeps count of every status
-- the server is seen to say took hold on them, by spell, ability, weapon skill, monster's move or
-- additional effect, for as long as the server's scripts say it usually lasts, or until the server
-- says it wore off.
--
-- With Show Durations on, how long each has left is written under its icon (winxi.statustimes): the
-- player's own to the second; anyone else's an estimate, in Estimate Colour, or - where it cannot be known.
-- One the player cast is in Your Colour, whether exact or estimated, until anyone else's is seen to
-- land over it. One with less than Low Time Warning left fades out and in.
-- Only Yours On Enemies leaves a monster's row the statuses the player put there. Removable Marks puts
-- a dot on the corner of each icon a spell can take off: debuffs Erase, a -na spell or a waltz removes,
-- buffs Dispel does (winxi.statuses' Removable, the server's flags).
--
-- The icons are as party and buff draw them (winxi.statusicons): with Custom Icons on in wxi,
-- the chosen set's where it has one and the game's where it has not; off, the game's. All are from
-- the one sheet: the plugin draws from eight pictures and no more, and the others are taken.
local bit         = require('bit');
local imgui       = require('imgui');
local widgets     = require('winxi.widgets');
local nameplates  = require('winxi.nameplates');
local statusicons = require('winxi.statusicons');
local debuffs     = require('winxi.debuffs');
local partystatus = require('winxi.partystatus');
local statustimes = require('winxi.statustimes');
local theme       = require('winxi.theme');
local controls    = require('controls');
local entityTypes = require('entity_types');
local statusFlags = require('winxi.statuses');
local healthbar   = require('healthbar');

local statuses = {};

statuses.Slot = 7; -- the plugin's number for the sheet: the last, the names' own have the rest

local WHITE        = 0xFFFFFFFF;
local MOST         = 12;   -- icons over one name
local GAP          = 1;    -- pixels between one icon and the next
local RISE         = 3;    -- pixels between the row and what is under it
local PARTY_OTHERS = 5;    -- the others of the player's party, whose statuses the game keeps
local LAST_STATUS  = 1023; -- the highest a status's number can be, for when the server's list is not to be had
local LIST_ROWS    = 14;   -- rows of the settings' list to be seen at once
local PREVIEW_MOST = 4;    -- icons over each name while previewing
local MOST_OFFSET  = 200;  -- screen pixels the row can be moved each way
-- the durations written under the icons of a preview, and whether each is an estimate
local PREVIEW_TEXT = { '8', '2m', statustimes.Unknown, '1h' };
local PREVIEW_ESTIMATE = { false, true, true, false };
local PREVIEW_MINE = { false, true, false, false }; -- and whether each is one the player cast
local PREVIEW_SECONDS = { 8, 120, nil, 3600 };      -- and its seconds left: the first running out, blinking

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
    statusDurations = function () return T{ false }; end, -- how long each has left, written under its icon
    statusDurationSize = function () return T{ 50 }; end, -- those letters' height, as a percentage of an icon's
    statusDurationFont = function () return T{ '' }; end, -- and their font: '' the names', 'default' the usual one, or a file
    statusEstimateColor = function () return T{ 1.0, 0.82, 0.35, 1.0 }; end, -- an estimate's colour
    statusMineColor = function () return T{ 0.45, 1.0, 0.55, 1.0 }; end, -- the colour of one the player cast
    statusLowTime = function () return T{ 10 }; end, -- seconds left under which a time is low; 0 for no warning
    statusOnlyMine = function () return T{ false }; end, -- a monster's row: only what the player put there
    statusRemovableMarks = function () return T{ false }; end, -- a dot on what a spell can take off
    statusCureMarkColor = function () return T{ 0.35, 0.85, 1.0, 1.0 }; end, -- on debuffs Erase, -na or a waltz removes
    statusDispelMarkColor = function () return T{ 1.0, 0.75, 0.2, 1.0 }; end, -- on buffs Dispel removes
    -- Empty here, and the chosen statuses given by Settle: Ashita fills each place a saved list lacks
    -- from the default list, so a list saved shorter than this came back with this one's tail, and
    -- statuses taken off came back on
    statusList   = function () return T{ }; end,
    statusListVersion = function () return 0; end,
};

-- The statuses ticked to begin with: what ails a character, and what can be told of an enemy
local function Preset()
    return T{ 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 19, 132, 133, 134, 135, 156, 192, 194, 217 };
end

function statuses.Defaults(defaults)
    for key, make in pairs(settings) do
        defaults[key] = make();
    end
    return defaults;
end

-- A new character's list is the preset. A list saved before has each status once, in order: the
-- merge had added the default list's tail to it, some statuses more than once.
function statuses.Settle(options)
    local list = options.statusList;
    if (type(list) ~= 'table') then
        list = T{ };
    end
    if (options.statusListVersion ~= 1) then
        if (#list == 0) then
            list = Preset();
        else
            local seen, kept = {}, T{ };
            for _, id in ipairs(list) do
                if (type(id) == 'number' and not seen[id]) then
                    seen[id] = true;
                    kept[#kept + 1] = id;
                end
            end
            table.sort(kept);
            list = kept;
        end
        options.statusListVersion = 1;
    end
    options.statusList = list;
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
local durations = false;          -- the time left written under each icon
local durationSize = 0.5;         -- its letters' height, as a part of an icon's
local estimateColor = 0xFFFFD159; -- an estimate's colour, 0xAARRGGBB
local mineColor = 0xFF73FF8C;     -- the colour of one the player cast
local lowTime = 10;               -- seconds left under which a time is low, 0 for none
local onlyMine = false;           -- a monster's row: only what the player put there
local marks = false;              -- a dot on what a spell can take off
local cureColor, dispelColor = 0xFF59D9FF, 0xFFFFBF33;
local me = 0;                     -- the player's server id, this frame
local MONSTER = nameplates.Category.Monster;

-- A channel, 0 to 1, as a byte
local function Byte(value)
    return math.max(0, math.min(255, math.floor((tonumber(value) or 1) * 255 + 0.5)));
end

-- A colour as the settings keep it, { r, g, b, a } from 0 to 1, as the plugin takes it
local function Packed(color, otherwise)
    if (type(color) ~= 'table') then
        return otherwise;
    end
    return Byte(color[4]) * 0x1000000 + Byte(color[1]) * 0x10000 + Byte(color[2]) * 0x100 + Byte(color[3]);
end

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
    onlyMine = options.statusOnlyMine ~= nil and options.statusOnlyMine[1] == true;
    marks = options.statusRemovableMarks ~= nil and options.statusRemovableMarks[1] == true;
    if (marks) then
        cureColor = Packed(options.statusCureMarkColor, 0xFF59D9FF);
        dispelColor = Packed(options.statusDispelMarkColor, 0xFFFFBF33);
    end
    me = 0;
    if (onlyMine) then
        local partyNow = AshitaCore:GetMemoryManager():GetParty();
        me = partyNow ~= nil and partyNow:GetMemberServerId(0) or 0;
    end
    durations = options.statusDurations ~= nil and options.statusDurations[1] == true;
    if (durations) then
        durationSize = math.max(30, math.min(100, tonumber(options.statusDurationSize ~= nil and options.statusDurationSize[1]) or 50)) / 100;
        estimateColor = Packed(options.statusEstimateColor, 0xFFFFD159);
        mineColor = Packed(options.statusMineColor, 0xFF73FF8C);
        lowTime = math.max(0, tonumber(options.statusLowTime ~= nil and options.statusLowTime[1]) or 0);
        statustimes.Begin();
        -- the party is watched every frame, whether or not their names are drawn, so that what appears
        -- on them is seen to begin when it does
        partyRead = true;
        partystatus.Party(party);
        for member = 1, PARTY_OTHERS do
            statustimes.Watch(party[member].id, party[member]);
        end
    end
    return true;
end

-- The row for one name: what it is under that is chosen, each status once, and whether each icon is
-- one of the set's
-- one, and each one's status, for its duration
local row, rowOwn, rowIds, rowCount = {}, {}, {}, 0;
local taken, mark = {}, 0;

local function Take(id)
    if (chosen[id] and taken[id] ~= mark and rowCount < MOST) then
        local place, own = placeOf(id);
        if (place ~= nil) then
            taken[id] = mark;
            rowCount = rowCount + 1;
            row[rowCount], rowOwn[rowCount], rowIds[rowCount] = place, own == true, id;
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

-- mine: only what the player put there
local function TakeTracked(serverId, mine)
    local on = debuffs.Statuses(serverId);
    if (on == nil) then
        return;
    end
    local count = 0;
    for id, entry in pairs(on) do
        if (seconds < entry.expires and (not mine or (me ~= 0 and entry.by == me))) then
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
            partystatus.Own(own);
        end
        TakeAll(own);
        return;
    end
    if (not partyRead) then
        partyRead = true;
        partystatus.Party(party);
    end
    local serverId = name.ServerId;
    for member = 1, PARTY_OTHERS do
        if (party[member].id == serverId) then
            TakeAll(party[member]);
            return;
        end
    end
    TakeTracked(serverId, onlyMine and name.Category == MONSTER);
end

-- How the names' letters are measured and written: custom's, handed over as it is loaded
local wordsWidth, writeWords, ownWords = nil, nil, nil;

function statuses.SetWords(width, write, own)
    wordsWidth, writeWords, ownWords = width, write, own;
end

-- each icon's duration, false for none, its colour, and whether it is running out
local rowText, rowColor, rowLow = {}, {}, {};

function statuses.Write(name, nameLeft, nameRight, above, under, height, scale, set, fit)
    if (sheet == 0 or bit.band(categories, name.Category or 0) == 0) then
        return;
    end
    Gather(name, shownWith);
    if (rowCount == 0) then
        return;
    end

    -- the durations under the icons, where any is written: the row is raised to make room for them
    local timed = false;
    for index = 1, rowCount do
        rowLow[index] = false;
    end
    if (durations and set ~= nil and fit ~= nil and writeWords ~= nil) then
        for index = 1, rowCount do
            local text, estimate, mine, left;
            if (preview[1]) then
                text, estimate, mine, left = PREVIEW_TEXT[index], PREVIEW_ESTIMATE[index], PREVIEW_MINE[index], PREVIEW_SECONDS[index];
            else
                text, estimate, mine, left = statustimes.Text(name.ServerId, rowIds[index]);
            end
            -- the player's own cast in Your Colour, then an estimate in Estimate Colour
            rowText[index] = text or false;
            rowLow[index] = left ~= nil and lowTime > 0 and left <= lowTime;
            rowColor[index] = (mine and mineColor) or (estimate and estimateColor) or WHITE;
            timed = timed or text ~= nil;
        end
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
    local textTall = timed and math.max(1, math.floor(tall * durationSize + 0.5)) or 0;
    local textFit = timed and fit * textTall / height or 0;
    -- in Duration Font, where one is chosen: its letters at the name's height, fitted the same way
    local textSet = set;
    if (timed and ownWords ~= nil) then
        textSet = ownWords(set.height) or set;
    end
    local top = below and (under + rise) or (above - rise - textTall - tall);
    -- the offsets are the screen's pixels, as the gap is
    left = left + math.floor(offsetX * scale + 0.5);
    top = top + math.floor(offsetY * scale + 0.5);
    for index = 1, rowCount do
        local place = row[index];
        -- the set's icons are narrower than the game's, which are square, as party draws them
        local width = rowOwn[index] and wide or tall;
        -- the icons have an edge of their own: none is drawn round them
        -- running out: the icon fades out and in
        local tint = rowLow[index] and (math.floor(statustimes.Blink() * 255 + 0.5) * 0x1000000 + 0xFFFFFF) or WHITE;
        nameplates.Quad(left, top, left + width, top + tall, place[1], place[2], place[3], place[4], tint, statuses.Slot, false);
        -- what can take it off: a small square in its top right corner, of the kind's colour in a dark
        -- border, the whole of it inside the icon
        if (marks) then
            local kind = statusFlags.Removable(rowIds[index]);
            local color = ((kind == 'erase' or kind == 'waltz') and cureColor) or (kind == 'dispel' and dispelColor) or nil;
            local u, v = nil, nil;
            if (color ~= nil) then u, v = healthbar.WhitePixel(); end
            if (u ~= nil) then
                local border = math.max(1, math.floor(tall * 0.04 + 0.5));
                local side = math.max(2, math.floor(tall * 0.14 + 0.5));
                local inset = math.max(1, math.floor(tall * 0.06 + 0.5));
                local right, high = left + width - inset, top + inset;
                nameplates.Quad(right - side - 2 * border, high, right, high + side + 2 * border, u, v, u, v, 0xFF101010, 0, false, nil, true);
                nameplates.Quad(right - side - border, high + border, right - border, high + border + side, u, v, u, v, color, 0, false, nil, true);
            end
        end
        -- the duration under it, its middle under the icon's, outlined as the names' letters are
        local text = timed and rowText[index];
        if (text) then
            local textWidth = wordsWidth(textSet, text, textFit);
            writeWords(textSet, text, math.floor(left + (width - textWidth) * 0.5 + 0.5), top + tall, textFit,
                rowColor[index]);
        end
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

-- The numbers of the statuses the server has (winxi.statuses, made from its data), or nil where
-- winxi's data is not installed: then every number the game names is offered, but these
local function ServerStatuses()
    local ok, found = pcall(require, 'winxi.statuses');
    local ids = ok and found and found.Ids() or nil;
    return (ids ~= nil and #ids > 0) and ids or nil;
end

-- Numbers the server has no status for, which the game still names: no name is ever under them
local UNUSED = { [24] = true, [25] = true, [26] = true, [27] = true, [224] = true, [225] = true, [226] = true,
    [372] = true, [373] = true, [374] = true, [514] = true, [520] = true, [521] = true };

-- The statuses the list offers, by name: not the numbers above, nor the game's stand-ins, whose
-- names are wholly in brackets, (None), (N/A) and (Imagery)
local function Known()
    if (known ~= nil) then
        return known;
    end
    known = {};
    local resources = AshitaCore:GetResourceManager();
    local ids, unused = ServerStatuses(), {};
    if (ids == nil) then
        ids, unused = {}, UNUSED;
        for id = 1, LAST_STATUS do ids[id] = id; end
    end
    for _, id in ipairs(ids) do
        local name = id > 0 and resources:GetString('buffs.names', id) or nil;
        if (type(name) == 'string' and name ~= '' and not unused[id] and name:match('^%(.*%)$') == nil) then
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

local showSpec = {}; -- the rows that wait for Enabled
local durationSpec = {}; -- and those that wait for Show Durations
local markSpec = {};     -- and those that wait for Removable Marks

function statuses.DrawSettings(options, save)
    Chosen(options);
    local changed = false;

    if (controls.Section('Display', true)) then
        if (controls.Checkbox('Enabled', '##name.showStatuses', options.showStatuses,
                'Shows the ticked statuses over the names. Yours and your party\'s are the game\'s, and everyone else\'s are worked out from the battle messages.')) then
            changed = true;
        end
        showSpec.parent = options.showStatuses;
        if (controls.Choice('Icons', '##name.statusIcons', options.statusIcons, ICONS,
                'Which icons the statuses are drawn with: Winxi Theme as its Custom Icons setting says, Game Icons, or Custom Icons with the game\'s where the set has none.', showSpec)) then
            changed = true;
        end
        if (controls.Slider('Size', '##name.statusSize', options.statusSize, 50, 300, '%d%%',
                'How tall the status icons are, compared with the name.', showSpec)) then
            changed = true;
        end
        if (controls.Choice('Position', '##name.statusPlace', options.statusPlace, PLACES,
                'Above the name, over any mastery stars, or below it, under a checked monster\'s details.', showSpec)) then
            changed = true;
        end
        if (controls.Choice('Alignment', '##name.statusAlign', options.statusAlign, ALIGNMENTS,
                'Which side of the name the row lines up with: Left, Center or Right.', showSpec)) then
            changed = true;
        end
        if (controls.Input('X Offset', '##name.statusOffsetX', options.statusOffsetX, -MOST_OFFSET, MOST_OFFSET, '%d px',
                'Moves the row right. Below 0, left.', showSpec)) then
            changed = true;
        end
        if (controls.Input('Y Offset', '##name.statusOffsetY', options.statusOffsetY, -MOST_OFFSET, MOST_OFFSET, '%d px',
                'Moves the row down. Below 0, up.', showSpec)) then
            changed = true;
        end
        if (controls.Checkbox('Show Durations', '##name.statusDurations', options.statusDurations,
                'Writes the time left under each icon. Others\' times are estimates, or - if unknown.', showSpec)) then
            changed = true;
        end
        -- greyed while either Enabled or Show Durations is off
        durationSpec.parent = (options.showStatuses[1] and options.statusDurations[1]) == true;
        if (controls.Slider('Duration Size', '##name.statusDurationSize', options.statusDurationSize, 30, 100, '%d%%',
                'How tall the durations are, compared with the icon.', durationSpec)) then
            changed = true;
        end
        if (controls.Choice('Duration Font', '##name.statusDurationFont', options.statusDurationFont, require('custom_settings').TextFonts(),
                'The font the durations are written in. Same as Names is the names\' font, Default the font everything else is written in.', durationSpec)) then
            changed = true;
        end
        if (controls.Color('Estimate Colour', '##name.statusEstimateColor', options.statusEstimateColor,
                'The colour of estimated durations and -.', durationSpec)) then
            changed = true;
        end
        if (controls.Color('Your Colour', '##name.statusMineColor', options.statusMineColor,
                'The colour of durations of statuses you cast, so you can see when someone else\'s replaces yours.', durationSpec)) then
            changed = true;
        end
        if (controls.Slider('Low Time Warning', '##name.statusLowTime', options.statusLowTime, 0, 60, '%d s',
                'Below this many seconds left, the icon fades in and out. At 0 there is no warning.', durationSpec)) then
            changed = true;
        end
        if (controls.Checkbox('Only Yours On Enemies', '##name.statusOnlyMine', options.statusOnlyMine,
                'On monsters, shows only the statuses you put there.', showSpec)) then
            changed = true;
        end
        if (controls.Checkbox('Removable Marks', '##name.statusRemovableMarks', options.statusRemovableMarks,
                'Puts a dot on the corner of each status a spell can take off.', showSpec)) then
            changed = true;
        end
        markSpec.parent = (options.showStatuses[1] and options.statusRemovableMarks[1]) == true;
        if (controls.Color('Curable Mark Colour', '##name.statusCureMarkColor', options.statusCureMarkColor,
                'The dot on debuffs that Erase, a -na spell or a waltz removes.', markSpec)) then
            changed = true;
        end
        if (controls.Color('Dispellable Mark Colour', '##name.statusDispelMarkColor', options.statusDispelMarkColor,
                'The dot on buffs that Dispel removes.', markSpec)) then
            changed = true;
        end
        controls.Checkbox('Preview', '##name.statusPreview', preview,
            'Shows the first few ticked statuses over every name, to see how the row looks. Not saved.', showSpec);
    end

    if (controls.Section('Entity Types')) then
        showSpec.parent = options.showStatuses;
        if (entityTypes.Draw('statusTypes', options.statusCategories, 'A row of statuses', showSpec)) then
            changed = true;
        end
    end

    if (controls.Section('Selected Statuses')) then
        controls.Text('Search', '##name.statusSearch', search, 64,
            'Part of a status\'s name, or its number, to find it in the list. Only a ticked status is drawn.');
        controls.Checkbox('Selected Only', '##name.statusChosenOnly', chosenOnly, 'Lists only the ticked statuses.');

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
                -- the icon itself, as the mouse rests on a status: a picture, not help
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

    if (changed and save ~= nil) then
        save();
    end
end

return statuses;
