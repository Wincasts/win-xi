addon.name    = 'buffs';
addon.author  = 'win (and claude)';
addon.version = '1.0';
addon.desc    = 'The statuses you are under, with FFXIV\'s icons and the time each has left.';
addon.link    = 'https://github.com/Wincasts/ffxi-addons';

-- The player's own statuses in a window, in place of the game's row of icons: each with an icon
-- from the icons folder (FFXIV's, by tools/build_status_icons.py) or the game's own where the folder
-- has none, and the time it has left under it. After the statustimers addon (heals), which showed
-- how the times are read and how the game's own icons are switched off.
--
--   /buffs           shows or hides the window (it only appears while there is a status to show)
--   /buffs config    opens or closes the settings

require('common');
local imgui = require('imgui');
local widgets = require('winxi.widgets');
local shell = require('winxi.shell');
local theme = require('winxi.theme');
local text = require('winxi.text');
local icons = require('icons');
local native = require('native');
local statuses = require('statuses');

local windowName = 'winxi.buffs';
local gap = 4;      -- between one icon and the next
local timerGap = 1; -- between an icon and its time

-- The settings, kept for each character. The shell adds its own: fading in and out, the rules for
-- hiding, the theme.
local defaults = T{
    isVisible = T{ true },
    pos = T{ 100, 100 },
    iconSize = T{ 40 },       -- an icon's height
    perRow = T{ 16 },         -- how many icons before a new row
    showTimers = T{ true },
    ffxivIcons = T{ true },   -- the icons folder's, where it has one
    hideGameIcons = T{ true },
};

-- The time left as the window writes it: seconds under a minute, then minutes, then hours. Each is
-- made once.
local labels = {};

local function Label(seconds)
    local key, format, value;
    if seconds >= 3600 then
        value = math.floor(seconds / 3600);
        key, format = 20000 + value, '%dh';
    elseif seconds >= 60 then
        value = math.floor(seconds / 60);
        key, format = 10000 + value, '%dm';
    else
        key, format, value = seconds, '%d', seconds;
    end
    local label = labels[key];
    if label == nil then
        label = format:format(value);
        labels[key] = label;
    end
    return label;
end

local function HidesTimer(id)
    local icon = AshitaCore:GetResourceManager():GetStatusIconByIndex(id);
    return icon ~= nil and icon.HideTimer ~= 0;
end

local function Tooltip(id)
    local resources = AshitaCore:GetResourceManager();
    local icon = resources:GetStatusIconByIndex(id);
    imgui.BeginTooltip();
    imgui.Text(('%s (%d)'):format(resources:GetString('buffs.names', id) or '?', id));
    if icon ~= nil then
        if icon.Description ~= nil and icon.Description[1] ~= nil then
            imgui.Text(icon.Description[1]);
        end
        if icon.CanCancel ~= 0 then
            imgui.TextDisabled('Right click to remove.');
        end
    end
    imgui.EndTooltip();
end

local current = {}; -- the statuses this frame
local cell = { 0, 0 };
local cornerA, cornerB = { 0, 0 }, { 0, 0 };
local uvA, uvB = { 0, 0 }, { 1, 1 };
local white = imgui.GetColorU32({ 1, 1, 1, 1 });
local widest = nil; -- how wide the widest time is, measured once

local function DrawStatuses(options)
    local height = options.iconSize[1];
    local width = math.floor(height * icons.OwnAspect + 0.5);
    local showTimers = options.showTimers[1];
    local useOwn = options.ffxivIcons[1];
    local perRow = math.max(1, options.perRow[1]);
    local _, textHeight = imgui.CalcTextSize('0');
    if widest == nil then
        widest = imgui.CalcTextSize('00m');
    end

    -- a status has one item, as wide as its icon or its time, whichever is wider
    cell[1] = showTimers and math.max(width, widest) or width;
    cell[2] = showTimers and height + timerGap + textHeight or height;

    local drawList = imgui.GetWindowDrawList();
    local textColor = theme.Get().TextColor;
    for index, status in ipairs(current) do
        if index > 1 and (index - 1) % perRow ~= 0 then
            imgui.SameLine(0, gap);
        end

        local x, y = imgui.GetCursorScreenPos();
        imgui.Dummy(cell);
        if imgui.IsItemHovered() then
            Tooltip(status.id);
            if imgui.IsItemClicked(ImGuiMouseButton_Right) then
                local icon = AshitaCore:GetResourceManager():GetStatusIconByIndex(status.id);
                if icon ~= nil and icon.CanCancel ~= 0 then
                    statuses.Cancel(status.id);
                end
            end
        end

        local handle, own = icons.Get(status.id, useOwn);
        if handle ~= nil then
            local left = x + (cell[1] - width) / 2;
            if own then
                cornerA[1], cornerA[2], cornerB[1], cornerB[2] = left, y, left + width, y + height;
                uvA[1], uvB[1] = icons.OwnLeft, icons.OwnRight;
            else
                -- the game's icons are square: as wide as the others, in the middle of their height
                local top = y + (height - width) / 2;
                cornerA[1], cornerA[2], cornerB[1], cornerB[2] = left, top, left + width, top + width;
                uvA[1], uvB[1] = 0, 1;
            end
            drawList:AddImage(handle, cornerA, cornerB, uvA, uvB, white);
        end

        if showTimers and status.seconds ~= nil and not HidesTimer(status.id) then
            local label = Label(status.seconds);
            local labelWidth = imgui.CalcTextSize(label);
            text.Draw(drawList, x + (cell[1] - labelWidth) / 2, y + height + timerGap, textColor, label);
        end
    end
end

local hideFailed = false; -- said once, if the game's icons cannot be switched off

local function ApplyGameIcons(options)
    if not native.Set(options.hideGameIcons[1]) and not hideFailed then
        hideFailed = true;
        print(('\30\81[%s]\30\01 %s'):format(addon.name, 'The game\'s own status icons could not be hidden: another addon may have hidden them already.'));
    end
end

local function DrawSettings(options)
    widgets.Label('Visible');
    imgui.Checkbox('##buffs.visible', options.isVisible);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Whether the window shows while you are under a status. /buffs switches this.');
    end
    widgets.Label('Position');
    if imgui.InputInt2('##buffs.position', options.pos) then
        imgui.SetWindowPos(windowName, options.pos);
    end

    widgets.Gap();
    widgets.Label('FFXIV Icons');
    imgui.Checkbox('##buffs.ffxivIcons', options.ffxivIcons);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Uses the icons in the addon\'s icons folder, which are FFXIV\'s, for every status that has one there.\nOff, every status has the game\'s own icon.');
    end
    widgets.Label('Icon Size');
    widgets.PushControlWidth();
    imgui.SliderInt('##buffs.iconSize', options.iconSize, 16, 96);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('How tall an icon is, in pixels. The icons are 64 tall as made: at 64, or 32, they are at their sharpest.');
    end
    widgets.Label('Icons Per Row');
    imgui.SliderInt('##buffs.perRow', options.perRow, 1, 32);
    widgets.PopControlWidth();
    widgets.Label('Show Time Left');
    imgui.Checkbox('##buffs.showTimers', options.showTimers);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Writes under each icon how long the status has left: seconds, then minutes (m), then hours (h).');
    end

    widgets.Gap();
    widgets.Label('Hide Game\'s Icons');
    if imgui.Checkbox('##buffs.hideGameIcons', options.hideGameIcons) then
        hideFailed = false;
        ApplyGameIcons(options);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Stops the game drawing its own row of status icons, which this window stands in for.\nThey come back when this is switched off, or the addon is unloaded.');
    end
end

local app = shell.New({
    defaults = defaults,
    window = windowName,
    configTitle = 'Buffs Settings',
    command = '/buffs',
    help = '/buffs shows or hides the window; /buffs config opens or closes the settings.',
    drawSettings = DrawSettings,
    onSettings = ApplyGameIcons,
});

ashita.events.register('unload', 'buffs_unload', function()
    native.Set(false);
end);

ashita.events.register('d3d_present', 'buffs_present', function()
    if not app:BeginFrame() then
        return;
    end
    -- the window is there only while there is a status to show
    if statuses.Read(current) == 0 then
        return;
    end
    app:Window(app.options.isVisible, DrawStatuses);
end);
