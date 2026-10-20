addon.name    = 'sct';
addon.author  = 'win';
addon.version = '0.8';
addon.desc    = 'Scrolling text for statuses, received items and key items.';
addon.link    = 'https://github.com/Wincasts/win-xi';

-- Scrolling combat text for the player's own statuses: as one is gained, "+ [icon] Name" starts at
-- the top of a box and moves down it, fading out just before it reaches the bottom; as one is lost,
-- "- [icon] Name" does the same. A buff gained is blue, an enfeeble gained purple (enfeebles.lua),
-- anything lost grey. The icons are winxi's choice (winxi.statusicons): the theme's set where Custom
-- Icons is on and the set has one, the game's own (from its DATs, as pivot has them) otherwise.
--
--   /sct            shows or hides the text
--   /sct config     opens or closes the settings
--   /sct test       sends a buff, an enfeeble and a loss down the box, to see where it is
--
-- What the player is under is read from the game each frame and set beside the last frame's. On
-- coming into an area, or logging in, the game fills the list again: what it holds for the first
-- moments there is taken as it is, not as gained.

-- The winxi this addon was made with, or a newer one (winxi.version)
local winxiNeeded = 25; -- widgets.FontFile, FontSize
do
    local ok, found = pcall(require, 'winxi.version');
    local number = ok and type(found) == 'table' and found.Number or 0;
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number);
        print(('\30\68[%s]\30\01 %s'):format(addon.name, text));
        error(text, 0);
    end
end

require('common');
local bit = require('bit');
local imgui = require('imgui');
local widgets = require('winxi.widgets');
local shell = require('winxi.shell');
local theme = require('winxi.theme');
local text = require('winxi.text');
local fonts = require('winxi.fonts');
local icons = require('winxi.statusicons');
local itemicons = require('winxi.itemicons');
local window = require('winxi.window');
local fade = require('winxi.fade');
local style = require('winxi.style');
local enfeebles = require('enfeebles');

local windowName = 'winxi.sct';
local SETTLE = 2;      -- seconds after coming into an area in which statuses are taken as they are
local MOST_LINES = 40; -- lines waiting or moving at once: past this the oldest waiting are dropped
local FADE_FROM = 0.8; -- how far down the box a line begins to fade
local iconGap = 4;     -- between the sign, the icon and the name

local defaults = T{
    isVisible = T{ true },
    pos = T{ 100, 300 },
    locked = T{ false },
    boxStyle = 'text',     -- 'text': the lines alone; 'background': the theme's window behind them
    showOutline = T{ true }, -- the box's edge, while it is unlocked
    width = T{ 260 },
    height = T{ 300 },
    speed = T{ 90 },       -- pixels a second a line moves down the box
    spacing = T{ 2 },      -- pixels between one line and the next
    iconSize = T{ 24 },
    align = 'left',        -- 'left', 'center' or 'right'
    fontFile = '',         -- empty inherits the Winxi theme font
    fontSize = T{ 0 },     -- zero inherits the theme size
    showGained = T{ true },
    showLost = T{ true },
    showDrops = T{ true },
    dropsSeparate = T{ false },
    dropsPos = T{ 380, 300 },
    dropsLocked = T{ false },
    dropColor = T{ 1.00, 0.82, 0.35, 1.00 },
    buffColor = T{ 0.40, 0.68, 1.00, 1.00 },
    enfeebleColor = T{ 0.76, 0.50, 1.00, 1.00 },
    lostColor = T{ 0.62, 0.62, 0.62, 1.00 },
};

local boxStyles = { { key = 'text', label = 'Text Only' }, { key = 'background', label = 'Full Background' } };
local aligns = { { key = 'left', label = 'Left' }, { key = 'center', label = 'Center' }, { key = 'right', label = 'Right' } };

-- What the player was under last frame, by status: how many of each (some can be on twice)
local last = {};
local counts = {};
local ready = false;     -- whether there is a player, out of the way between areas
local settleUntil = nil; -- until when what is read is taken as it is

-- The lines: each { id, gained, words, start }, start when it leaves the top (later than now while
-- it waits for the line before it to move out of the way), oldest first
local lines = {};
local statusStream = { lines = lines, nextStart = 0 };
local dropStream = { lines = {}, nextStart = 0 };

local names = {}; -- status -> its name, looked up once
local function Name(id)
    local name = names[id];
    if name == nil then
        name = AshitaCore:GetResourceManager():GetString('buffs.names', id);
        if name == nil or name == '' then
            return ('Status %d'):format(id);
        end
        names[id] = name;
    end
    return name;
end

local app;

-- How far a line moves, from the top of the box until its foot reaches the bottom
local lineHeight = 24;
local function Travel(options)
    return math.max(1, options.height[1] - lineHeight);
end

-- The seconds a line takes from the top to the bottom, at the speed set
local function Duration(options)
    return Travel(options) / math.max(1, options.speed[1]);
end

-- The seconds a line waits behind the one before it: as long as the line before takes to move a
-- line's height, and the spacing, down the box
local function Spacing(options)
    return (lineHeight + options.spacing[1]) / math.max(1, options.speed[1]);
end

local function Enqueue(stream, line)
    local start = math.max(os.clock(), stream.nextStart);
    stream.nextStart = start + Spacing(app.options);
    line.start = start;
    stream.lines[#stream.lines + 1] = line;
    while #stream.lines > MOST_LINES do table.remove(stream.lines, 1); end
end

local function AddDrop(id, quantity, keyItem)
    local options = app.options;
    if not options.showDrops[1] or (id == 0 and not keyItem) then return; end
    local resources = AshitaCore:GetResourceManager();
    local name;
    if keyItem then
        name = resources:GetString('keyitems.names', id);
    else
        local item = resources:GetItemById(id);
        name = item and item.Name and item.Name[1];
    end
    if type(name) ~= 'string' or name == '' then name = ('%s %d'):format(keyItem and 'Key Item' or 'Item', id); end
    local words = quantity > 1 and ('%s x%d'):format(name, quantity) or name;
    if keyItem then words = 'Key Item: ' .. words; end
    Enqueue(options.dropsSeparate[1] and dropStream or statusStream,
        { id = id, gained = true, drop = true, keyItem = keyItem, words = words });
end

local acquisitions = require('acquisitions').New(AddDrop);

local function Add(id, gained)
    local options = app.options;
    if (gained and not options.showGained[1]) or (not gained and not options.showLost[1]) then
        return;
    end
    Enqueue(statusStream, { id = id, gained = gained, words = Name(id) });
end

-- Reads what the player is under into counts; false while there is no player, or between areas
local function Read()
    for id in pairs(counts) do counts[id] = nil; end
    local memory = AshitaCore:GetMemoryManager();
    local party, player = memory:GetParty(), memory:GetPlayer();
    if party == nil or player == nil or party:GetMemberServerId(0) == 0 or player:GetIsZoning() ~= 0 then
        return false;
    end
    local ids = player:GetStatusIcons();
    for slot = 1, 32 do
        local id = ids[slot];
        if id ~= nil and id > 0 and id ~= 255 and id < 0x400 then
            counts[id] = (counts[id] or 0) + 1;
        end
    end
    return true;
end

-- Sets what the player is under beside last frame's, and sends a line down for each change
local function Track()
    if not Read() then
        ready = false;
        for id in pairs(last) do last[id] = nil; end
        return;
    end
    local now = os.clock();
    if not ready then
        ready, settleUntil = true, now + SETTLE;
    end
    local settling = settleUntil ~= nil and now < settleUntil;
    if not settling then
        settleUntil = nil;
        for id, count in pairs(last) do
            for _ = (counts[id] or 0) + 1, count do Add(id, false); end
        end
        for id, count in pairs(counts) do
            for _ = (last[id] or 0) + 1, count do Add(id, true); end
        end
    end
    for id in pairs(last) do last[id] = nil; end
    for id, count in pairs(counts) do last[id] = count; end
end

-- Drawing

local boxSize = { 0, 0 };
local cornerA, cornerB = { 0, 0 }, { 0, 0 };
local uvA, uvB = { 0, 0 }, { 1, 1 };
local tint = { 1, 1, 1, 1 };
local shade = { 0, 0, 0, 0 };
local outlineMin, outlineMax = { 0, 0 }, { 0, 0 };
local signWidths, measuredFont, measuredSize = {}, nil, nil;
local itemSheet, itemFramed;

local function Color(line, options)
    if line.drop then return options.dropColor; end
    if not line.gained then return options.lostColor; end
    return enfeebles[line.id] and options.enfeebleColor or options.buffColor;
end

local function DrawLines(options, x, y, now, stream)
    local lines = stream.lines;
    local drawList = imgui.GetWindowDrawList();
    local width, height = options.width[1], options.height[1];
    local iconHeight = options.iconSize[1];
    local edge = text.Edge(); -- the theme's Text Outline
    local useOwn = theme.Get().StatusIcons;

    local font, size = imgui.GetFont(), imgui.GetFontSize();
    if font ~= measuredFont or size ~= measuredSize then
        measuredFont, measuredSize = font, size;
        signWidths['+'], signWidths['-'] = imgui.CalcTextSize('+'), imgui.CalcTextSize('-');
        for _, source in ipairs({ statusStream, dropStream }) do
            for _, line in ipairs(source.lines) do line.width = nil; end
        end
    end
    local _, textHeight = imgui.CalcTextSize('A');
    lineHeight = math.max(iconHeight, textHeight);
    local travel = Travel(options);
    local duration = Duration(options);

    for _, line in ipairs(lines) do
        local progress = (now - line.start) / duration;
        if progress >= 0 and progress < 1 and (not line.drop or options.showDrops[1]) then
            local alpha = progress < FADE_FROM and 1 or (1 - progress) / (1 - FADE_FROM);
            local top = y + travel * progress;
            local sign = line.gained and '+' or '-';

            local handle, own, itemUV;
            if not line.drop then
                handle, own = icons.Get(line.id, useOwn);
            elseif not line.keyItem then
                if not itemFramed then
                    itemSheet, itemFramed = itemicons.Frame(), true;
                end
                if itemSheet ~= nil then itemUV = itemicons.Place(line.id); end
                if itemUV ~= nil then handle = itemSheet; end
            end
            local iconWidth = handle == nil and 0 or (own and math.floor(iconHeight * icons.OwnAspect + 0.5) or iconHeight);
            if line.width == nil then
                line.width = imgui.CalcTextSize(line.words);
            end
            local whole = signWidths[sign] + iconGap + (iconWidth > 0 and iconWidth + iconGap or 0) + line.width;
            local left = x;
            if options.align == 'center' then
                left = x + (width - whole) / 2;
            elseif options.align == 'right' then
                left = x + width - whole;
            end

            local color = Color(line, options);
            tint[1], tint[2], tint[3], tint[4] = color[1], color[2], color[3], color[4] * alpha;
            local edgeColor = text.EdgeColor();
            shade[1], shade[2], shade[3], shade[4] = edgeColor[1], edgeColor[2], edgeColor[3], edgeColor[4] * alpha;
            local packed, dark = imgui.GetColorU32(tint), imgui.GetColorU32(shade);
            local textTop = top + (lineHeight - textHeight) / 2;

            text.Packed(drawList, left, textTop, packed, sign, edge, dark);
            left = left + signWidths[sign] + iconGap;
            if handle ~= nil then
                local iconTop = top + (lineHeight - iconHeight) / 2;
                cornerA[1], cornerA[2], cornerB[1], cornerB[2] = left, iconTop, left + iconWidth, iconTop + iconHeight;
                if itemUV ~= nil then
                    uvA[1], uvA[2], uvB[1], uvB[2] = itemUV[1], itemUV[2], itemUV[3], itemUV[4];
                elseif own then
                    uvA[1], uvA[2], uvB[1], uvB[2] = icons.OwnLeft, 0, icons.OwnRight, 1;
                else
                    uvA[1], uvA[2], uvB[1], uvB[2] = 0, 0, 1, 1;
                end
                tint[1], tint[2], tint[3], tint[4] = 1, 1, 1, alpha;
                drawList:AddImage(handle, cornerA, cornerB, uvA, uvB, imgui.GetColorU32(tint));
                left = left + iconWidth + iconGap;
            end
            text.Packed(drawList, left, textTop, packed, line.words, edge, dark);
        end
    end
end

local function DrawBox(options, now, stream)
    local x, y = imgui.GetCursorScreenPos();
    boxSize[1], boxSize[2] = options.width[1], options.height[1];
    imgui.Dummy(boxSize);
    -- unlocked with no box to see, its edge shows where it is, to be dragged
    if not options.locked[1] and options.boxStyle ~= 'background' and options.showOutline[1] then
        outlineMin[1], outlineMin[2], outlineMax[1], outlineMax[2] = x, y, x + boxSize[1], y + boxSize[2];
        imgui.GetWindowDrawList():AddRect(outlineMin, outlineMax, imgui.GetColorU32(theme.Get().TextColor), 0, 0, 1);
    end

    local face, size = fonts.Get(options.fontFile), options.fontSize[1];
    local pushed = face ~= nil or size > 0;
    if pushed then imgui.PushFont(face, size > 0 and size or imgui.GetFontSize()); end
    local ok, err = pcall(DrawLines, options, x, y, now, stream);
    if pushed then imgui.PopFont(); end
    if not ok then error(err, 0); end

    if not options.locked[1] then
        local wx, wy = imgui.GetWindowPos();
        options.pos[1], options.pos[2] = math.floor(wx + 0.5), math.floor(wy + 0.5);
    end
end

local place = true; -- the windows are put where the settings say, next frame
local windowOptions = { alpha = 1 };
local transparent = { 0, 0, 0, 0 };
local open = { true };

local function Draw(options, now, stream, name)
    local wanted = options.isVisible[1];
    local alpha = wanted and 1 or 0;
    if options.fadeInOut[1] then alpha = fade.Presence(name, wanted); end
    if alpha <= 0.01 then return; end

    -- nothing to show: no window, unless it is there to be placed or set
    local placing = not options.locked[1] or app.showConfig[1];
    if #stream.lines == 0 and not placing then return; end

    local flags = bit.bor(style.TitlelessFlags(), ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse);
    local box = options.boxStyle == 'background';
    if not box then flags = bit.bor(flags, ImGuiWindowFlags_NoBackground); end
    windowOptions.alpha = alpha;
    windowOptions.locked, windowOptions.clickThrough = options.locked[1], options.locked[1]; -- Lock Window
    windowOptions.background = not box and transparent or nil;
    windowOptions.border = not box and transparent or nil;
    windowOptions.padding = not box and 0 or nil;
    if box then windowOptions.shadow = nil; else windowOptions.shadow = false; end

    imgui.SetNextWindowPos(options.pos, (options.locked[1] or place) and ImGuiCond_Always or ImGuiCond_FirstUseEver);
    window.Plain(name, open, flags, function() DrawBox(options, now, stream); end, windowOptions);
end

-- Lines that have reached the bottom are let go
local function Prune(options, now, stream)
    local lines = stream.lines;
    local duration = Duration(options);
    local kept = 0;
    for index = 1, #lines do
        local line = lines[index];
        lines[index] = nil;
        if now - line.start < duration then
            kept = kept + 1;
            lines[kept] = line;
        end
    end
    if kept == 0 then stream.nextStart = 0; end
end

-- Settings

local function Combo(id, value, choices)
    local shown = choices[1].label;
    for _, choice in ipairs(choices) do
        if choice.key == value then shown = choice.label; end
    end
    local chosen = value;
    if imgui.BeginCombo(id, shown) then
        for _, choice in ipairs(choices) do
            if imgui.Selectable(choice.label .. id, choice.key == value) then chosen = choice.key; end
        end
        imgui.EndCombo();
    end
    return chosen;
end

local Tip = require('winxi.tooltip').Hover;

local function DrawSettings(options)
    if widgets.Header('Box', true) then
        widgets.Label('Visible');
        imgui.Checkbox('##sct.visible', options.isVisible);
        Tip('Whether the text shows. /sct switches this.');
        widgets.Lock(options.locked, '##sct.locked', { tooltip = 'Unlocked, the box can be dragged (its edge drawn, with Text Only and Show Outline). Locked, clicks go through it.' });
        widgets.Label('Position');
        if imgui.InputInt2('##sct.position', options.pos) then place = true; end
        widgets.Label('Box Style');
        options.boxStyle = Combo('##sct.boxStyle', options.boxStyle, boxStyles);
        Tip('Text Only: the scrolling lines and nothing else, no background, border or shadow.\nFull Background: the theme\'s window behind the lines while they are moving.');
        if options.boxStyle ~= 'background' then
            widgets.Label('Show Outline');
            imgui.Checkbox('##sct.showOutline', options.showOutline);
            Tip('Draws the box\'s edge while it is unlocked, to see where it is. Locked, the edge is never drawn.\nOff, the box can still be dragged where it is while unlocked.');
        end
        widgets.PushControlWidth();
        widgets.Label('Box Width');
        imgui.SliderInt('##sct.width', options.width, 80, 800);
        widgets.Label('Box Height');
        imgui.SliderInt('##sct.height', options.height, 60, 1000);
        widgets.Label('Scroll Speed');
        imgui.SliderInt('##sct.speed', options.speed, 10, 600, '%d px/s');
        Tip('How fast a line moves down the box, in pixels a second.');
        widgets.Label('Line Spacing');
        imgui.SliderInt('##sct.spacing', options.spacing, 0, 40, '%d px');
        Tip('The gap between one line and the next, in pixels, when they come close together.');
        widgets.PopControlWidth();
        widgets.Label('Align');
        options.align = Combo('##sct.align', options.align, aligns);
    end

    if widgets.Header('Received Items') then
        widgets.Label('Show Received Items');
        imgui.Checkbox('##sct.showDrops', options.showDrops);
        Tip('Shows newly received items added to your main Inventory and key items you gain. Wardrobe/storage updates, treasure-pool entries and transfers from your other bags do not count.');
        widgets.Label('Separate Popup');
        if imgui.Checkbox('##sct.dropsSeparate', options.dropsSeparate) then place = true; end
        Tip('Off: received items scroll with statuses. On: they have their own movable area, which disappears when empty while locked. New notifications use the selected area.');
        if options.dropsSeparate[1] then
            widgets.Lock(options.dropsLocked, '##sct.dropsLocked', { tooltip = 'Unlock to move the item-drop area; lock to hide it when empty and let clicks through.' });
            widgets.Label('Drop Position');
            if imgui.InputInt2('##sct.dropsPos', options.dropsPos) then place = true; end
        end
        widgets.Label('Drop Color');
        imgui.ColorEdit4('##sct.dropColor', options.dropColor, ImGuiColorEditFlags_NoInputs);
        if imgui.Button('Test Drop##sct.testDrop') then AddDrop(4096, 2); end
        Tip('/sct testdrop also sends a sample drop. Both areas share size, speed, font and box style.');
    end

    if widgets.Header('Lines') then
        widgets.Label('Show Gained');
        imgui.Checkbox('##sct.showGained', options.showGained);
        widgets.Label('Show Lost');
        imgui.Checkbox('##sct.showLost', options.showLost);
        widgets.Label('Buff Color');
        imgui.ColorEdit4('##sct.buffColor', options.buffColor, ImGuiColorEditFlags_NoInputs);
        widgets.Label('Enfeeble Color');
        imgui.ColorEdit4('##sct.enfeebleColor', options.enfeebleColor, ImGuiColorEditFlags_NoInputs);
        widgets.Label('Lost Color');
        imgui.ColorEdit4('##sct.lostColor', options.lostColor, ImGuiColorEditFlags_NoInputs);
        widgets.PushControlWidth();
        widgets.Label('Icon Size');
        imgui.SliderInt('##sct.iconSize', options.iconSize, 12, 64);
        Tip('How tall an icon is, in pixels. Custom Icons (Winxi Theme) says whose icons they are.');
        widgets.PopControlWidth();
        widgets.FontFile(options, 'fontFile', '##sct.fontFile', { tooltip = 'The lines\' font: Theme Font follows Winxi Theme, or one of C:\\Windows\\Fonts.' });
        widgets.PushControlWidth();
        widgets.FontSize(options, 'fontSize', '##sct.fontSize', { tooltip = 'How large the lines are, in pixels; Theme Size (0) follows Winxi Theme.' });
        widgets.PopControlWidth();
        if imgui.Button('Test##sct.test') then
            Add(33, true); Add(4, true); Add(33, false);
        end
        Tip('Sends a buff gained, an enfeeble gained and a buff lost down the box. /sct test does the same.');
    end
end

app = shell.New({
    defaults = defaults,
    window = windowName,
    configTitle = 'SCT Settings',
    command = '/sct',
    help = '/sct shows or hides the text; /sct config opens or closes the settings; /sct test sends status lines; /sct testdrop sends a sample item drop.',
    drawSettings = DrawSettings,
    commands = {
        test = function() Add(33, true); Add(4, true); Add(33, false); end,
        testdrop = function() AddDrop(4096, 2); end,
    },
    onSettings = function(options)
        place = true;
        -- Show Box, before Box Style
        if options.showBox ~= nil then
            local shown = type(options.showBox) == 'table' and options.showBox[1];
            options.boxStyle = shown and 'background' or 'text';
            options.showBox = nil;
        end
        -- Scroll Time, before Scroll Speed: the speed that took the same time down the box
        if options.duration ~= nil then
            local seconds = type(options.duration) == 'table' and tonumber(options.duration[1]) or nil;
            if seconds ~= nil and seconds > 0 then
                options.speed[1] = math.max(10, math.min(600, math.floor(Travel(options) / seconds + 0.5)));
            end
            options.duration = nil;
        end
    end,
});

ashita.events.register('packet_in', 'sct_items', function(e)
    acquisitions:Packet(e.id, e.data);
end);

ashita.events.register('packet_out', 'sct_item_moves', function(e)
    if e.blocked then return; end
    acquisitions:Outgoing(e.id, e.data, AshitaCore:GetMemoryManager());
end);

ashita.events.register('d3d_present', 'sct_present', function()
    Track();
    -- Initial bag/key-item snapshots and zone refreshes are baselines, not gains.
    if not ready or settleUntil ~= nil then
        acquisitions:Reset();
    else
        acquisitions:Update(AshitaCore:GetMemoryManager());
    end
    local options = app.options;
    local now = os.clock();
    Prune(options, now, statusStream);
    Prune(options, now, dropStream);
    if not app:BeginFrame() then return; end
    itemFramed = false;
    Draw(options, now, statusStream, windowName);
    if options.showDrops[1] and (options.dropsSeparate[1] or #dropStream.lines > 0) then
        local dropOptions = setmetatable({ pos = options.dropsPos, locked = options.dropsLocked }, { __index = options });
        Draw(dropOptions, now, dropStream, windowName .. '.drops');
    end
    place = false;
end);
