-- winxisettings: winxi's appearance options in a window of their own, one tab for the windows on the
-- game screen and one for the settings windows; and the theme's two sets of values behind them
H.load()
local imgui = require('imgui')
local theme = require('winxi.theme')
local window = require('winxi.window')

local begun, colors, pushed = {}, {}, {}
local realBegin, realColor, realPush = imgui.Begin, imgui.ColorEdit4, imgui.PushStyleColor
imgui.Begin = function(name, ...) begun[#begun + 1] = name return true end
imgui.ColorEdit4 = function(id, ...) colors[id] = true return false end
imgui.PushStyleColor = function(slot, color) if slot == ImGuiCol_WindowBg then pushed[#pushed + 1] = color end end

-- open from the start, and drawn with winxi as a settings window
H.frames(1)
assert(begun[1] == 'winxi Appearance', tostring(begun[1]))

-- the first tab, Game Windows: the game screen's values alone
H.tab(1)
colors = {}
H.frames(1)
assert(colors['##winxi.BackgroundColor'] and colors['##winxi.TitleColor'], 'UI Elements: game window colours')
assert(not colors['##winxi.SettingsBackgroundColor'] and not colors['##winxi.ThemeTabColor'], 'UI Elements: no settings window colours')

-- the first has no icons: they have the second tab
local combosSeen = {}
local realCombo = imgui.BeginCombo
imgui.BeginCombo = function(id) combosSeen[id] = true return false end
H.tab(1)
H.frames(1)
assert(not combosSeen['##winxi.StatusIconSet'], 'Game Windows: no status icons')
H.tab(2)
combosSeen = {}
H.frames(1)
assert(combosSeen['##winxi.StatusIconSet'], 'Icons: status icons')
imgui.BeginCombo = realCombo

-- the fourth: the settings windows' alone
H.tab(4)
colors = {}
H.frames(1)
assert(colors['##winxi.SettingsBackgroundColor'] and colors['##winxi.SettingsTextColor'] and colors['##winxi.ThemeTabColor'], 'Settings Windows: their colours')
assert(not colors['##winxi.BackgroundColor'] and not colors['##winxi.TitleColor'], 'Settings Windows: no game window colours')
H.tab(1)
H.print('winxisettings: open on load; Game Windows, Icons and Settings Windows tabs, each with its own values', true)

-- each kind of window has its own background
local current = theme.Get()
current.BackgroundColor[1], current.SettingsBackgroundColor[1] = 0.25, 0.75
theme.Touch()
pushed = {}
window.Plain('game', { true }, 0, function() end)
window.Plain('settings', { true }, 0, function() end, { kind = window.Settings })
assert(pushed[1][1] == 0.25 and pushed[2][1] == 0.75, 'backgrounds: ' .. tostring(pushed[1][1]) .. ' ' .. tostring(pushed[2][1]))
assert(theme.For('Padding', true) == current.SettingsPadding and theme.For('Padding') == current.Padding, 'theme.For')
assert(theme.Palette(true) ~= theme.Palette(false), 'a palette for each kind')
H.print('winxi: game and settings windows drawn from values of their own', true)

-- a theme kept before settings windows had their own: they keep the colours and font they had
local own = { BackgroundColor = { 0.5, 0.1, 0.1, 1 }, FontFile = 'arial.ttf', Padding = 4 }
theme.Configure(false, own)
assert(own.SettingsBackgroundColor[1] == 0.5 and own.SettingsFontFile == 'arial.ttf', 'migrated')
assert(own.SettingsPadding == theme.Defaults.SettingsPadding, 'padding not migrated: ' .. own.SettingsPadding)
-- each reset is of its own values alone
theme.Reset(theme.SettingsWindowKeys)
assert(own.SettingsBackgroundColor[1] == theme.Defaults.SettingsBackgroundColor[1] and own.BackgroundColor[1] == 0.5, 'settings reset leaves the game windows')
theme.Reset(theme.GameWindowKeys)
assert(own.BackgroundColor[1] == theme.Defaults.BackgroundColor[1] and own.Padding == theme.Defaults.Padding, 'game reset')
theme.Configure(true, nil)
H.print('winxi: an old theme moved over; each reset is of its own values', true)

-- Title All Caps: offered with the titles, and every title written in capitals
do
    local titles = require('winxi.titles')
    local look = theme.Get()
    local checks = {}
    local realCheckbox = imgui.Checkbox
    imgui.Checkbox = function(id) checks[id] = true return false end
    H.tab(1)
    H.frames(1)
    imgui.Checkbox = realCheckbox
    assert(checks['##winxi.TitleAllCaps'], 'offered')
    -- an addon's own Winxi Theme tab keeps the status icons under Styles
    local combos = {}
    local realCombo = imgui.BeginCombo
    imgui.BeginCombo = function(id) combos[id] = true return false end
    require('winxi.widgets').Appearance()
    imgui.BeginCombo = realCombo
    assert(combos['##winxi.StatusIconSet'], 'status icons in a whole Appearance')
    local written = {}
    local list = setmetatable({ AddText = function(_, _, _, words) written[#written + 1] = words end }, { __index = function() return function() end end })
    local getList = imgui.GetWindowDrawList
    imgui.GetWindowDrawList = function() return list end
    look.FrameTitles, look.TitleStyle = true, 'outline'
    titles.Draw('Party')
    assert(written[#written] == 'Party', 'as given: ' .. tostring(written[#written]))
    look.TitleAllCaps, written = true, {}
    titles.Draw('Target of Target')
    assert(#written == 5 and written[5] == 'TARGET OF TARGET', 'capitals: ' .. tostring(written[5]))
    look.TitleAllCaps = false
    imgui.GetWindowDrawList = getList
    H.print('title all caps: offered, and every title in capitals', true)
end

-- Break In Border: the border drawn round the gap, never clipped (a clip rect in the game's Direct3D 8
-- moved the border under the gap by a pixel)
do
    local borders = require('winxi.borders')
    local clips, points, strokes, images = 0, {}, 0, {}
    local list = setmetatable({
        PushClipRect = function() clips = clips + 1 end,
        PathLineTo = function(_, p) points[#points + 1] = { p[1], p[2] } end,
        PathStroke = function() strokes = strokes + 1 end,
        AddImage = function(_, _, a, b, uvA, uvB) images[#images + 1] = { a[1], a[2], b[1], b[2], uvA[1], uvB[1] } end,
    }, { __index = function() return function() end end })
    local getList, getPos, getSize = imgui.GetWindowDrawList, imgui.GetWindowPos, imgui.GetWindowSize
    imgui.GetWindowDrawList = function() return list end
    imgui.GetWindowPos = function() return 100, 200 end
    imgui.GetWindowSize = function() return 180, 61 end
    -- plain: one line from the right of the gap, round the window, to its left
    borders.Draw(nil, 200, 250)
    assert(clips == 0 and strokes == 1, 'one line, unclipped')
    assert(points[1][1] == 250 and points[1][2] == 200.5 and points[#points][1] == 200 and points[#points][2] == 200.5, 'from the gap round to it')
    -- art: the top edge in two pieces, either side of the gap, each with its own part of the image
    borders.Draw(77, 200, 250)
    assert(clips == 0 and #images == 9, 'nine pieces, unclipped: ' .. #images)
    local top = {}
    for _, image in ipairs(images) do if image[2] == 200 and image[1] > 100 and image[3] < 280 then top[#top + 1] = image end end
    assert(#top == 2 and top[1][3] == 200 and top[2][1] == 250, 'either side of the gap')
    assert(math.abs(top[1][6] - top[2][5]) > 0.1, 'each its own part of the image')
    -- a gap off the end of the top edge leaves the border whole
    strokes = 0
    borders.Draw(nil, 400, 450)
    assert(strokes == 0, 'whole')
    imgui.GetWindowDrawList, imgui.GetWindowPos, imgui.GetWindowSize = getList, getPos, getSize
    H.print('break in border: the border drawn round the gap, never clipped', true)
end

-- the third: the tooltips' alone, always the shared theme's
H.tab(3)
colors = {}
H.frames(1)
assert(colors['##winxi.TooltipBackgroundColor'] and colors['##winxi.TooltipBorderColor'] and colors['##winxi.TooltipTextColor'], 'Tooltips: their colours')
assert(not colors['##winxi.BackgroundColor'] and not colors['##winxi.SettingsBackgroundColor'], 'Tooltips: no window colours')
H.tab(1)
for _, key in ipairs(theme.TooltipKeys) do
    for _, other in ipairs(theme.GameWindowKeys) do assert(key ~= other, 'a game window key: ' .. key) end
end
H.print('winxisettings: a Tooltips tab with its own values, apart from the game windows\'', true)

-- winxi.tooltip: drawn in the tooltip colours, wrapped, balanced, and not before the delay
do
    local tooltip = require('winxi.tooltip')
    local shared = theme.Shared()
    local now, depth, shown, tint = 0, 0, 0, nil
    local real = { imgui.GetTime, imgui.BeginTooltip, imgui.EndTooltip, imgui.PushStyleColor, imgui.PopStyleColor, imgui.PushStyleVar, imgui.PopStyleVar, imgui.IsItemHovered }
    imgui.GetTime = function() return now end
    imgui.BeginTooltip = function() shown = shown + 1 end
    imgui.EndTooltip = function() end
    imgui.PushStyleColor = function(slot, color) depth = depth + 1 if slot == ImGuiCol_PopupBg then tint = color end end
    imgui.PopStyleColor = function(n) depth = depth - (n or 1) end
    imgui.PushStyleVar = function() depth = depth + 1 end
    imgui.PopStyleVar = function(n) depth = depth - (n or 1) end
    imgui.IsItemHovered = function() return true end

    tooltip.Hover('Goes.')
    assert(shown == 1 and depth == 0 and tint == shared.TooltipBackgroundColor, 'shown at once, balanced, in its colour')
    shared.TooltipDelay = 500
    -- hovered a frame at a time, from a rest
    for frame = 0, 9 do now = 5 + frame * 0.05 tooltip.Hover('Goes.') end
    assert(shown == 1, 'not before the delay')
    for frame = 10, 11 do now = 5 + frame * 0.05 tooltip.Hover('Goes.') end
    assert(shown == 3 and depth == 0, 'after it')
    -- away a while, and back: the wait starts again
    now = 7
    tooltip.Hover('Goes.')
    assert(shown == 3, 'waits again')
    shared.TooltipDelay, shared.TooltipsEnabled = 0, false
    assert(tooltip.Begin() == false and shown == 3, 'off')
    shared.TooltipsEnabled = true

    imgui.GetTime, imgui.BeginTooltip, imgui.EndTooltip, imgui.PushStyleColor, imgui.PopStyleColor, imgui.PushStyleVar, imgui.PopStyleVar, imgui.IsItemHovered = unpack(real)
    H.print('winxi.tooltip: in its colours, after its delay, not at all while off', true)
end

-- every section collapses: [-] while open, [+] while collapsed, a click on its title changes which
do
    local titles, lastText, clickOn = {}, nil, nil
    local realText, realClicked = imgui.TextColored, imgui.IsItemClicked
    imgui.TextColored = function(_, text) titles[#titles + 1] = text lastText = text end
    imgui.IsItemClicked = function() return lastText == clickOn end
    H.tab(1)
    colors = {}
    H.frames(1)
    assert(titles[1] == '[-] Window' and colors['##winxi.BackgroundColor'], 'open: ' .. tostring(titles[1]))
    clickOn = '[-] Window'
    H.frames(1)
    clickOn, titles, colors = nil, {}, {}
    H.frames(1)
    assert(titles[1] == '[+] Window' and not colors['##winxi.BackgroundColor'], 'collapsed: ' .. tostring(titles[1]))
    -- the Font section under it is still open
    local fontOpen = false
    for _, t in ipairs(titles) do if t == '[-] Font' then fontOpen = true end end
    assert(fontOpen, 'the others stay open')
    clickOn = '[+] Window'
    H.frames(1)
    clickOn, titles, colors = nil, {}, {}
    H.frames(1)
    assert(titles[1] == '[-] Window' and colors['##winxi.BackgroundColor'], 'opened again')
    imgui.TextColored, imgui.IsItemClicked = realText, realClicked
    H.print('sections collapse and open again with [-] and [+], each on its own', true)
end

-- Custom Icons: None, or a set, any folder of libs\winxi\statusicons, the one winxi comes with first
do
    local statusicons = require('winxi.statusicons')
    local look = theme.Get()
    local realDir, realExists, realCombo, realSelectable = ashita.fs.get_directory, ashita.fs.exists, imgui.BeginCombo, imgui.Selectable
    ashita.fs.exists = function(path) return not path:find('\\mine\\%d+%.png$') or path:find('\\[12]%.png$') ~= nil end
    local listed, pick, shownAs = {}, nil, nil
    ashita.fs.get_directory = function(path, mask)
        if mask == nil then return { 'mine', 'ffxiv', 'sheet.png', 'Another Set' } end
        if path:find('\\mine\\$') then return { '1.png', '2.png', 'notes.txt' } end
        return {}
    end
    imgui.BeginCombo = function(id, preview) if id == '##winxi.StatusIconSet' then shownAs = preview end return id == '##winxi.StatusIconSet' end
    imgui.Selectable = function(label) listed[#listed + 1] = label return label:match('^([^#]*)') == pick end
    H.tab(2)
    H.frames(1)
    assert(shownAs == 'ffxiv' and look.StatusIcons and look.StatusIconSet == 'ffxiv', 'FFXIV to start: ' .. tostring(shownAs))
    assert(#listed == 4 and listed[1]:find('^None') and listed[2]:find('^ffxiv') and listed[3]:find('^Another Set') and listed[4]:find('^mine'),
        'None, then the sets, the one winxi comes with first: ' .. table.concat(listed, ', '))
    pick = 'mine'
    H.frames(1)
    assert(look.StatusIcons and look.StatusIconSet == 'mine' and statusicons.Set() == 'mine', 'a set chosen')
    assert(statusicons.Has(2) and not statusicons.Has(3), 'its icons are the folder\'s')
    assert(statusicons.OwnLeft == 0 and statusicons.OwnRight == 1, 'without a set.lua, the whole picture')
    pick = 'None'
    H.frames(1)
    assert(look.StatusIcons == false and look.StatusIconSet == 'mine', 'None: the game\'s icons')
    pick = nil
    H.frames(1)
    assert(shownAs == 'None', 'shown as None')
    look.StatusIcons, look.StatusIconSet = true, 'ffxiv'
    theme.Touch()
    assert(statusicons.Set() == 'ffxiv' and statusicons.OwnAspect == 0.75 and statusicons.OwnLeft == 0.125, 'back to FFXIV\'s shape')
    ashita.fs.get_directory, ashita.fs.exists, imgui.BeginCombo, imgui.Selectable = realDir, realExists, realCombo, realSelectable
    H.print('Custom Icons: None or any folder of icons, FFXIV first', true)
end

-- the sections' titles are in the theme's Sub-Category Color, chosen on the Settings Windows tab
do
    local tints = {}
    local realText = imgui.TextColored
    imgui.TextColored = function(color, text) if text:find('^%[[-+]%] ') then tints[#tints + 1] = color end end
    H.tab(4)
    colors = {}
    H.frames(1)
    local chosen = theme.Get().SettingsHeaderColor
    assert(colors['##winxi.SettingsHeaderColor'], 'a picker for it on the Settings Windows tab')
    assert(#tints > 0 and tints[1] == chosen, 'titles drawn in it')
    assert(chosen[1] == 1.0 and chosen[2] == 0.75 and chosen[3] == 0.55, 'orange to start')
    imgui.TextColored = realText
    H.print('section titles in the Sub-Category Color, chosen with the settings windows', true)
end

-- the command closes it, and /wxi opens it again
H.command('/winxi')
begun = {}
H.frames(1)
assert(#begun == 0, 'closed')
H.command('/wxi')
H.frames(1)
assert(begun[1] == 'winxi Appearance', 'opened by /wxi')
H.command('/WXI')
begun = {}
H.frames(1)
assert(#begun == 0, 'closed by /wxi')
H.print('/winxi closes it; /wxi opens and closes it', true)
imgui.Begin, imgui.ColorEdit4, imgui.PushStyleColor = realBegin, realColor, realPush

-- the fifth, Layouts: the resolution, Switch With Resolution, and a button to keep this one's
local buttons, checks = {}, {}
local realButton, realCheckbox = imgui.Button, imgui.Checkbox
imgui.Button = function(label) buttons[#buttons + 1] = label return false end
imgui.Checkbox = function(id) checks[id] = true return false end
H.command('/winxi')
H.tab(5)
H.frames(1)
local saveShown = false
for _, label in ipairs(buttons) do saveShown = saveShown or label == 'Save Layout for 1920x1080' end
H.print('Layouts: the resolution, Switch With Resolution and Save Layout', saveShown and checks['##winxisettings.automatic'] == true)
imgui.Button, imgui.Checkbox = realButton, realCheckbox
