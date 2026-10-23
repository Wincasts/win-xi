addon.name = 'chatbox'
addon.author = 'win'
addon.version = '0.15.0'
addon.desc = 'WinXI native-backed chat, input and expanded history, with an optional chat-owned three-slot info panel.'
local winxiNeeded = 32
do
    local ok, found = pcall(require, 'winxi.version')
    local number = ok and type(found) == 'table' and found.Number or 0
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number)
        print('[chatbox] ' .. text)
        error(text, 0)
    end
end
require('common')
local imgui = require('imgui')
local bit = require('bit')
local shell = require('winxi.shell')
local window = require('winxi.window')
local theme = require('winxi.theme')
local widgets = require('winxi.widgets')
local controller = require('winxi.controller')
local fonts = require('winxi.fonts')
local cursorArt = require('winxi.cursor')
local native = require('winxi.nativechat')
local model = require('log')
local render = require('render')
local encoding = require('encoding')
local channels = require('channels')
local appearance = require('appearance')
local scrollbar = require('scrollbar')
local strip = require('strip')
local palette = require('palette')
local inputModel = require('input')
local input = inputModel.New()
local layout = require('layout')
local layoutState = layout.New()
local visibility = require('visibility')
local links = require('links')
-- The links in a line's bytes as the game gave them (before auto-translate is expanded), for Chat Tooltips; nil
-- where there are none or the lookup fails
local function Tokens(raw)
    local ok, tokens = pcall(links.Tokens, raw)
    return ok and type(tokens) == 'table' and #tokens > 0 and tokens or nil
end
local panelModel = require('winxi.infopanel.chat')
local infoPanel = panelModel.New()
local panelAttachment -- current frame only, appended to its owning chat capture
-- Expand In Place: where the game is asked to open its full log, the first box's bottom-left as last drawn with the
-- input closed, before any lift over a Bottom panel (the panel is hidden while expanded, so the log takes its place
-- too), and uihook's menu bridge that moves it. The bridge is made on first use.
local expandPlace, logMenus
local function LogMenus()
    if logMenus == nil then
        local ok, found = pcall(require, 'winxi.nativemenus')
        logMenus = ok and type(found) == 'table' and found.new and found.new() or false
    end
    return logMenus or nil
end
local function PlaceLog(options)
    local menus = LogMenus()
    if not menus then return end
    if options.mode[1] ~= 'game' and options.expandInPlace[1] and expandPlace then menus.PlaceLog(expandPlace.left, expandPlace.bottom)
    else menus.StopLog() end
end

local primary, secondary = native.new(native.Primary), native.new(native.Secondary)
local history = model.New()
local decodeErrors, zoning = 0, false
local decodeSample -- latest incoming event; bounded, memory-only diagnostics
local anchorStatus = 'Waiting for native primary chat geometry.'
local app
local open, place, pivot, size, contentSize = { true }, { 20, 0 }, { 0, 1 }, { 0, 0 }, { 0, 0 }
local ROW_GAP = 2
local TAB_TEXT_SCALE = 0.85 -- the expanded log's tab names, of Font Size
-- Mode: how the boxes behave and where they stand, in the WinXI look either way. Follow Game: the boxes where the game
-- puts its own, at its sizes, growing and shrinking as its do, the expanded log where the game puts it at its full
-- height. WinXI Skin: Width, rows, activity and the expanded log's place and height of the addon's own.
local MODES = { { key = 'game', label = 'Follow Game' }, { key = 'skin', label = 'WinXI Skin' } }
local function Game(options) return options.mode[1] == 'game' end
-- Position (WinXI Skin): the log at the game's chat, or Custom, its bottom-left wherever it was dragged to with Lock
-- Window off (or typed), the input bar and the second window with it
local POSITIONS = { { key = 'game', label = 'At the Game\'s Chat' }, { key = 'custom', label = 'Custom' } }
local moving -- while the log is dragged: how far the mouse is from the box's bottom-left
-- The room between each edge and the text this frame: the four Padding settings
local pad = { left = 3, right = 3, top = 3, bottom = 3 }
local function Paddings(options)
    pad.left, pad.right, pad.top, pad.bottom = options.leftPadding[1], options.rightPadding[1], options.topPadding[1], options.bottomPadding[1]
end
-- Font Size at 0, Automatic (Follow Game): the size the game's rows give, their pitch the first window's height (less
-- the room above and below the rows, plus a gap) over the lines it shows, less the row gap; taken where the reading is
-- sound (8 to 24 px) and kept until another is; 12 until the first. In WinXI Skin, 0 is 12.
local gameFontSize = 12
local function GameFontSize(rect, lines)
    if rect and lines and lines.shown >= 1 then
        local pitch = (rect[4] - rect[2] - pad.top - pad.bottom + ROW_GAP) / lines.shown
        local size = math.floor(pitch - ROW_GAP)
        if size >= 8 and size <= 24 then gameFontSize = size end
    end
    return gameFontSize
end
local function FontSize()
    local size = app.options.fontSize[1]
    if size > 0 then return size end
    return Game(app.options) and gameFontSize or 12
end
-- Windows stay click-through except for wheel events and the custom scrollbar.
local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoMove,
    ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoInputs,
    ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse,
    ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoBringToFrontOnFocus)
-- The last box drawn, kept up to HOLD_FRAMES while the game's log has no fresh place (opening or closing)
local held, frame, HOLD_FRAMES = nil, 0, 30
local lastDrawn, lastSplit, lastHandOver = nil, nil, nil -- for /chatbox status: the last boxes drawn, and why the game's was shown
local splitStatus = 'Second window: none; the game shows one log window.'
-- /cm selects the persistent input mode; a one-line /p or /l only overrides its preview.
-- Until a mode command is observed, retain the last sent channel as a fallback.
local spoken, selectedMode = 'Say', nil
-- Expanded mode skins the frame and tints native control art. Rows, selection and input remain native.
-- Each log window's own scrolling (the first's, and the second's where the game shows two): the wheel's
-- offset in rows, what the wheel and the scrollbar ask for, and the box drawn last, which the mouse is
-- matched against, set only after a frame captures it whole.
local function NewView(name) return { name = name, offset = 0, pending = 0, pendingScroll = nil, drag = nil, pressed = nil, target = nil } end
local views = { NewView('first'), NewView('second') }
local function ResetViews(scroll)
    for _, view in ipairs(views) do
        view.target, view.pendingScroll, view.drag, view.pressed, view.pending = nil, nil, nil, nil, 0
        if scroll then view.offset, view.visibility = 0, nil end
    end
end
-- Auto-Translate: chatbox's own list of phrases on Tab while typing (translate.lua). The game's own menu, once open,
-- is the game's active menu and takes the input bar back from uihook for as long as it stays open, so Tab is kept
-- from the game and the phrase goes into the game's buffer as its token instead. The picker and the dictionary are
-- made on first use, so a missing one only turns the feature off, with the reason in /chatbox status.
local translate, picker, translateProblem, pickerError
local function Picker()
    if picker == nil then
        local ok, found = pcall(require, 'translate')
        local okAuto, auto = false, nil
        if ok then okAuto, auto = pcall(require, 'winxi.autotranslate') end
        if not ok or type(found) ~= 'table' then picker, translateProblem = false, 'translate.lua could not be loaded: ' .. tostring(found)
        elseif not okAuto or type(auto) ~= 'table' then picker, translateProblem = false, 'winxi.autotranslate could not be loaded: ' .. tostring(auto)
        else
            local made, built = pcall(found.New, auto)
            if made and type(built) == 'table' then translate, picker = found, built
            else picker, translateProblem = false, 'the picker could not be made: ' .. tostring(built) end
        end
    end
    return picker or nil
end
local function PickerOpen() return picker and picker.open == true or false end
local function ClosePicker() if picker then pcall(picker.Close) end end
-- One of the picker's own calls: a failure closes it, kept for /chatbox status, rather than reaching the game's
-- key handling or the frame
local function Use(name, ...)
    local ok, result = pcall(picker[name], ...)
    if ok then return result end
    pickerError = name .. ': ' .. tostring(result)
    ClosePicker()
    return false
end
-- The game's input buffer as the picker reads it: its raw bytes and the caret's byte offset, nil where either fails
local function ReadInput()
    local ok, raw, caret = pcall(function()
        local chat = AshitaCore:GetChatManager()
        return chat:GetInputTextRaw(), chat:GetInputTextRawCaretPosition()
    end)
    if not ok or type(raw) ~= 'string' or type(caret) ~= 'number' or caret ~= caret then return nil end
    return raw, math.max(0, math.min(#raw, math.floor(caret)))
end
-- Each frame the input bar is drawn: the picker follows what is typed (the word at the caret, read again from the
-- game's buffer, since typing stays the game's) and is drawn over the bar
local function DrawPicker(plan)
    if not PickerOpen() then return end
    local raw, caret = ReadInput()
    if not raw or not app.options.autoTranslate[1] then return ClosePicker() end
    Use('Refresh', raw, caret)
    if not PickerOpen() then return end
    local ok, err = pcall(translate.Draw, picker, plan, flags)
    if not ok then
        pickerError = 'Draw: ' .. tostring(err)
        ClosePicker()
    end
end
-- The keys the picker has acted on, each kept from the game until it is let go (by virtual-key code: when it was
-- taken), and whether Shift is held, followed from its own presses and releases
local taken, shiftHeld = {}, false
local function Release()
    held, panelAttachment, moving = nil, nil, nil
    ClosePicker()
    taken = {}
    if logMenus then logMenus.StopLog() end -- the full log back where the game puts it
    infoPanel.Hud(nil) -- the game's clock and compass back
    ResetViews(false)
    primary.Stop()
    secondary.Stop()
    input.Stop()
end
-- The game's own history, put before chatbox's once as it starts (and after a reset, a new character's): the
-- first log window's ring, read through uihook. The game keeps a message as the lines it wrapped it into, its
-- header the same on each; with timestamps on (most lines starting with one), a line with none is the rest of the
-- one before in the same mode and is joined to it, so each message is whole again (without timestamps each line
-- stays a message). Lines chatbox has already had since it started are left out: from the newest back, those found
-- in the first messages it kept. Tried for a while, then given up (no uihook, or an old one).
local IMPORT_TIME = 10 -- seconds, at any frame rate
local import = { wanted = true, asked = false, since = nil, reader = nil, count = 0, status = 'not yet read' }
local function ImportLines(lines)
    local recent = {}
    for i = 1, math.min(#history.messages, 40) do recent[#recent + 1] = history.messages[i].text end
    recent = table.concat(recent, '\n')
    -- each line's bytes and whether it starts with a timestamp (once decoded)
    local parts, stamped = {}, 0
    for _, line in ipairs(lines) do
        local raw = line.text:gsub('%s+$', '')
        if raw ~= '' then
            local ok, text = pcall(encoding.Decode, raw, false, false)
            local stamp = ok and type(text) == 'string' and model.Stamp(text) ~= nil
            if stamp then stamped = stamped + 1 end
            parts[#parts + 1] = { raw = raw, mode = line.mode or 0, stamp = stamp }
        end
    end
    local joining = stamped * 2 >= #parts and stamped > 0
    local joined = {}
    for _, part in ipairs(parts) do
        local last = joined[#joined]
        if joining and not part.stamp and last and last.mode == part.mode then last.raw = last.raw .. ' ' .. part.raw
        else joined[#joined + 1] = { raw = part.raw, mode = part.mode } end
    end
    local entries = {}
    for _, message in ipairs(joined) do
        local mode = bit.band(message.mode, 0xff)
        if mode ~= 190 and mode ~= 152 then
            local ok, text, _, spans = pcall(encoding.Decode, message.raw, false, true)
            if ok and type(text) == 'string' and text:find('%S') then
                entries[#entries + 1] = { text = text, mode = mode, originalMode = mode, spans = spans, raw = message.mode, tokens = Tokens(message.raw) }
            end
        end
    end
    -- the newest of the game's lines may be messages chatbox already has: left out from the newest back
    while #entries > 0 and recent ~= '' and recent:find(entries[#entries].text, 1, true) do entries[#entries] = nil end
    return model.Prepend(history, entries)
end
local function ImportHistory()
    if not import.wanted then return end
    if import.reader == nil then
        local ok, found = pcall(require, 'winxi.nativehistory')
        import.reader = ok and type(found) == 'table' and found.new and found.new() or false
    end
    import.since = import.since or os.clock()
    if not import.reader or os.clock() - import.since > IMPORT_TIME then
        import.wanted, import.status = false, import.reader and import.reader.Status() or 'winxi.nativehistory is missing'
        return
    end
    if not import.asked then import.asked = import.reader.Request(); return end
    local lines = import.reader.Lines()
    if not lines then return end
    import.wanted = false
    import.count = ImportLines(lines)
    import.status = ('%d of the game\'s lines put before chatbox\'s own'):format(import.count)
end
local function Reset()
    Release()
    infoPanel.Reset()
    pcall(links.Reset)
    model.Clear(history)
    import.wanted, import.asked, import.since, import.count, import.status = true, false, nil, 0, 'not yet read'
    ResetViews(true)
    spoken, selectedMode = 'Say', nil
    channels.ResetLinkshells()
    layoutState = layout.New()
    decodeErrors, decodeSample = 0, nil
    anchorStatus = 'Waiting for native primary chat geometry.'
end
local TapStatus -- where each line is read from, defined with the text tap below
local function TranslateStatus()
    if not app.options.autoTranslate[1] then return 'off' end
    if not Picker() then return 'unavailable, ' .. translateProblem end
    local ok, words = pcall(picker.Status)
    words = ok and tostring(words) or 'no status (' .. tostring(words) .. ')'
    return pickerError and (words .. '; last failure ' .. pickerError) or words
end
local function Status()
    local mode = Game(app.options) and 'Follow Game' or 'WinXI Skin'
    app:Say((app.options.enabled[1] and 'On' or 'Off') .. '. ' .. mode .. ', native-controlled expansion; ' .. #history.messages .. ' messages retained.')
    app:Say(primary.Status())
    app:Say(anchorStatus)
    app:Say('Input: ' .. input.Status())
    app:Say('Auto-Translate: ' .. TranslateStatus())
    app:Say('Lines: ' .. TapStatus() .. '.')
    app:Say('Game history: ' .. import.status .. '.')
    app:Say('Info Panel: ' .. (app.options.infoPanel.layout.enabled[1] and infoPanel.Status() or 'off'))
    app:Say('Game Clock: ' .. infoPanel.HudStatus(app.options.infoPanel, 'clock'))
    app:Say('Compass: ' .. infoPanel.HudStatus(app.options.infoPanel, 'compass'))
    if lastDrawn then
        local d = lastDrawn
        app:Say(('Last box (%s, %d frames ago): %d,%d to %d,%d, %d rows of room, %d drawn from y %d; titled %s.')
            :format(d.expanded and 'expanded' or 'compact', frame - d.frame, d.left, d.top, d.left + d.width, d.bottom,
                d.rows, d.drawn, d.firstY, d.title or 'nothing'))
    end
    if lastSplit then
        local d = lastSplit
        app:Say(('Second window (%d frames ago): %d,%d to %d,%d, %d rows of room, %d drawn.')
            :format(frame - d.frame, d.left, d.top, d.left + d.width, d.bottom, d.rows, d.drawn))
    end
    app:Say(splitStatus)
    if lastHandOver then
        local h = lastHandOver
        app:Say(('Last handed to the game %d frames ago: full-log cursor %s of %s, scroll %s, filter %s; mouse %d,%d.')
            :format(frame - h.frame, tostring(h.cursor), tostring(h.pageRows), tostring(h.scroll), tostring(h.filter), h.mouseX, h.mouseY))
    end
    if decodeErrors > 0 then app:Say(('%d messages could not be decoded. Native history browsing remains available.'):format(decodeErrors)) end
end
-- Room between each edge of the log and input bar and their text, in pixels: 3 each by default
local PADDING_DEFAULT, PADDING_MOST = 3, 40
local PADDING_SIDES = {
    { key = 'leftPadding', label = 'Left Padding', tip = 'How far the text sits from the left edge of the log and the input bar, in pixels.' },
    { key = 'rightPadding', label = 'Right Padding', tip = 'How far long lines stop short of the right edge, in pixels.' },
    { key = 'topPadding', label = 'Top Padding', tip = 'Room kept above the log\'s rows, in pixels. Input height uses both vertical paddings, with its text always centred.' },
    { key = 'bottomPadding', label = 'Bottom Padding', tip = 'Room kept below the log\'s rows, in pixels. Input height uses both vertical paddings, with its text always centred.' },
}

local Tip = require('winxi.tooltip').Hover;
-- Chat Tooltips' kinds, each a switch of its own, all on to begin with; missing or not a switch, on
local function TooltipKinds(kinds)
    kinds = type(kinds) == 'table' and kinds or T{}
    for _, kind in ipairs(links.Kinds) do
        local value = kinds[kind.key]
        if type(value) ~= 'table' then kinds[kind.key] = T{ true }
        else value[1] = value[1] ~= false end
    end
    return kinds
end
-- Window Title and Window 2 Title: the words typed for each box's top edge, empty for the channel or 'Window 2'
local TITLE_LONGEST = 64
local function OwnTitle(value)
    local words = type(value) == 'table' and value[1]
    return type(words) == 'string' and words:match('%S') and words or nil
end
-- Forget the kept messages, the decode sample and where the log was scrolled to: the settings' Clear and /chatbox clear alike.
local function ClearHistory() model.Clear(history); decodeSample = nil; for _, view in ipairs(views) do view.offset, view.pending = 0, 0 end end

-- /chatbox clock and /chatbox compass: toggle, or hide/show, the game's own
local function HideHud(options, args, key, name)
    local verb = args[3] and args[3]:lower()
    local hide = options.infoPanel[key]
    if verb == nil then hide[1] = not hide[1]
    elseif verb == 'hide' or verb == 'off' then hide[1] = true
    elseif verb == 'show' or verb == 'on' then hide[1] = false
    else app:Say(('/chatbox %s [hide|show] hides or shows the game\'s %s.'):format(name, name)); return end
    app.save()
    app:Say(hide[1] and ('Game %s hidden. Unload clock and hidecompass, which use the same object.'):format(name)
        or ('Game %s shown.'):format(name))
end
-- Activity, each window's: Auto Resize and Fade When Idle, each with its own controls shown only while it is on, and
-- Idle Time, which both use, while either is
local function VisibilitySettings(options, number)
    local id = '##chatbox.visibility.' .. number
    widgets.Label('Window ' .. number .. ' Auto Resize')
    if imgui.Checkbox(id .. '.resize', options.resize) then app.save() end
    Tip('Grows with recent messages routed to this window, up to its rows; shrinks as those messages age out. The messages are kept.')
    if options.resize[1] then
        widgets.Label('Animate Resize')
        if imgui.Checkbox(id .. '.animate', options.animate) then app.save() end
        Tip('Grows and shrinks the box smoothly from its bottom edge. Typing, selecting or scrolling restores the full size at once.')
        if options.animate[1] then
            widgets.Label('Resize Duration')
            imgui.SliderFloat(id .. '.resizeDuration', options.resizeDuration, 0.05, 2, '%.2f s')
            if imgui.IsItemDeactivatedAfterEdit() then app.save() end
            Tip('How long a grow or shrink takes.')
        end
        widgets.Label('Minimum Rows')
        imgui.SliderInt(id .. '.minimum', options.minimum, 0, 50, '%d')
        if imgui.IsItemDeactivatedAfterEdit() then app.save() end
        Tip('Rows left while idle, no more than the window\'s rows. Zero hides the log wholly; typing or selecting brings it back.')
    end
    widgets.Label('Window ' .. number .. ' Fade When Idle')
    if imgui.Checkbox(id .. '.fade', options.fade) then app.save() end
    Tip('Fades this log and its attached panel out when no messages reach it for Idle Time. A new message fades it back in; typing, selecting or scrolling keeps it visible. The expanded log is unaffected.')
    if options.fade[1] then
        widgets.Label('Fade Duration')
        imgui.SliderFloat(id .. '.duration', options.duration, 0.1, 10, '%.1f s')
        if imgui.IsItemDeactivatedAfterEdit() then app.save() end
        Tip('How long the fade out takes.')
    end
    if options.resize[1] or options.fade[1] then
        widgets.Label('Idle Time')
        imgui.SliderInt(id .. '.idle', options.idle, 1, 300, '%d s')
        if imgui.IsItemDeactivatedAfterEdit() then app.save() end
        Tip('How long a message counts as recent: Auto Resize keeps rows for it, and Fade When Idle starts fading after it.')
    end
end
app = shell.New({
    defaults = T{ enabled = T{ true }, mode = T{ 'game' }, timestamps = T{ true }, width = T{ 640 }, fontSize = T{ 12 },
        locked = T{ true }, position = T{ 'game' }, pos = T{ 20, 1000 },
        replaceExpanded = T{ true }, expandInPlace = T{ true }, expandedHeight = T{ 75 },
        appearance = appearance.Defaults(T, theme.Get()), fontFile = '', infoPanel = panelModel.Defaults(),
        visibility = { window1 = visibility.Defaults(), window2 = visibility.Defaults() },
        window1Rows = T{ 0 }, window2Rows = T{ 0 },
        leftPadding = T{ 3 }, rightPadding = T{ 3 }, topPadding = T{ 3 }, bottomPadding = T{ 3 }, paddingVersion = T{ 0 },
        windowTitle = T{ '' }, splitTitle = T{ '' }, chatTooltips = T{ true }, tooltipNotes = T{ true }, tooltipKinds = TooltipKinds(),
        autoTranslate = T{ true } },
    command = '/chatbox',
    configTitle = 'Chatbox Settings',
    help = '/chatbox opens settings; /chatbox on, off, clear, status, modes, bytes; /chatbox timestamps [on|off] shows or hides the timestamps SimpleLog or the timestamp addon write; /chatbox panel [on|off|reset] controls the optional info panel; /chatbox clock and /chatbox compass [hide|show] the game\'s; /chatbox translate [on|off] turns chatbox\'s own auto-translate list on Tab on or off. Native selection, expansion and input controls.',
    drawSettings = function(options)
        local game = Game(options)
        if widgets.Header('Chatbox', true) then
            widgets.Label('Replace Native Chat')
            if imgui.Checkbox('##chatbox.enabled', options.enabled) then
                if not options.enabled[1] then Release() end
                app.save()
            end
            Tip('Draws the WinXI log and input bar in place of the game\'s own.\nOff, the game\'s chat log and input come back at once. /chatbox on and off do the same.')
            widgets.Label('Auto-Translate')
            if imgui.Checkbox('##chatbox.autoTranslate', options.autoTranslate) then
                if not options.autoTranslate[1] then ClosePicker() end
                app.save()
            end
            Tip('Tab while typing opens chatbox\'s own list of auto-translate phrases for the word at the caret (with no word, the categories);\nTab, Shift+Tab, Up and Down move, Enter puts the phrase in, Escape closes. Off, Tab is the game\'s, whose own menu takes the\ninput bar back for as long as it is open. /chatbox translate on and off do the same.')
            widgets.Label('Mode')
            if imgui.BeginCombo('##chatbox.mode', game and MODES[1].label or MODES[2].label) then
                for _, entry in ipairs(MODES) do
                    if imgui.Selectable(entry.label .. '##chatbox.mode.' .. entry.key, options.mode[1] == entry.key) and options.mode[1] ~= entry.key then
                        options.mode[1] = entry.key
                        app.save()
                    end
                end
                imgui.EndCombo()
            end
            Tip('How the boxes behave and where they stand, in the WinXI look either way. Follow Game: the log, input bar and expanded log where the game puts\nits own, at its sizes, growing and shrinking as its do. WinXI Skin: Width, rows, activity and the expanded log\'s place, in the Layout and Activity sections.')
            widgets.Label('Timestamps')
            if imgui.Checkbox('##chatbox.timestamps', options.timestamps) then model.ShowStamps(history, options.timestamps[1]); app.save() end
            Tip('Shows timestamps supplied by either SimpleLog or the timestamp addon, including their original format and colours.\nEnable timestamps in one of those addons; chatbox adds none of its own. Avoid enabling both providers to prevent duplicates.\nOff, timestamps are hidden in the compact, second and expanded logs without deleting them. /chatbox timestamps on and off do the same.')
            widgets.Label('Chat Tooltips')
            if imgui.Checkbox('##chatbox.chatTooltips', options.chatTooltips) then app.save() end
            Tip('Resting the mouse on an item, key item, auto-translate phrase, spell, ability, weapon skill, quest or place named in the\ncompact log, Window 2 or the expanded log (with Replace Expanded Log) shows what it is, in a tooltip. The shared Winxi tooltip\nsettings (whether they show, the delay and the look) apply.')
            if options.chatTooltips[1] then
                widgets.Label('Tooltip Notes')
                if imgui.Checkbox('##chatbox.tooltipNotes', options.tooltipNotes) then app.save() end
                Tip('The dimmed lines of a tooltip: what the catalogs cannot vouch for (presence is not availability, server units), and a\nphrase\'s category and kind. Off, only the name and the facts.')
                imgui.TextDisabled('Shown for:')
                for _, kind in ipairs(links.Kinds) do
                    widgets.Label(kind.label)
                    if imgui.Checkbox('##chatbox.tooltips.' .. kind.key, options.tooltipKinds[kind.key]) then app.save() end
                    Tip(('Tooltips for %s in the log.'):format(kind.label))
                end
            end
            if widgets.FontFile(options, 'fontFile', '##chatbox.fontFile', { tooltip = 'The chat\'s font: one of C:\\Windows\\Fonts, or the theme\'s.' }) then
                app.save()
            end
            local _, done = widgets.FontSize(options, 'fontSize', '##chatbox.fontSize', { min = game and 0 or 8, max = 24, theme = 'Automatic',
                tooltip = game and 'How large the log\'s, the input bar\'s and the expanded log\'s text is, in pixels.\nAutomatic: the size the game\'s rows give, so the rows stand where the game\'s do.'
                    or 'How large the log\'s and the input bar\'s text is, in pixels; both boxes grow with it.\nThe expanded log\'s text too, with Replace Expanded Log, centred on the game\'s rows, whose spacing is the game\'s.' })
            if done then app.save() end
            imgui.TextDisabled('Native Square/window selection, confirm to expand, cancel to close.')
            imgui.TextDisabled(primary.Status())
        end
        if not game and widgets.Header('Layout') then
            widgets.Lock(options.locked, '##chatbox.locked', { tooltip = 'Off, the log can be taken hold of with the mouse and dragged wherever you want (Position becomes Custom); the wheel and the scrollbar\nstill work. On, it stays where it is, the mouse going through it to the game.' })
            widgets.Label('Position')
            if imgui.BeginCombo('##chatbox.position', options.position[1] == 'custom' and POSITIONS[2].label or POSITIONS[1].label) then
                for _, entry in ipairs(POSITIONS) do
                    if imgui.Selectable(entry.label .. '##chatbox.position.' .. entry.key, options.position[1] == entry.key) and options.position[1] ~= entry.key then
                        options.position[1] = entry.key
                        if entry.key == 'custom' and layoutState.left and layoutState.closedBottom then
                            options.pos[1], options.pos[2] = math.floor(layoutState.left), math.floor(layoutState.closedBottom)
                        end
                        app.save()
                    end
                end
                imgui.EndCombo()
            end
            Tip('Where the log stands. At the Game\'s Chat: where the game puts its own log. Custom: wherever it was dragged to, or the place typed below;\nthe input bar and the second window go with it, and so does the game\'s clock, which uihook keeps at its distance from the log.')
            if options.position[1] == 'custom' then
                widgets.Label('Place')
                imgui.InputInt2('##chatbox.pos', options.pos)
                if imgui.IsItemDeactivatedAfterEdit() then app.save() end
                Tip('The log\'s bottom-left corner, in pixels from the screen\'s top-left; kept on the screen.')
            end
            widgets.Label('Width')
            imgui.SliderInt('##chatbox.width', options.width, 240, 1200, '%d px')
            if imgui.IsItemDeactivatedAfterEdit() then app.save() end
            Tip('How wide the compact log, input bar and expanded log are, in pixels. The expanded log clips the game\'s rows to this width; the game still wraps them and takes the mouse on its own places.')
            for number = 1, 2 do
                widgets.Label('Window ' .. number .. ' Rows')
                local rows = options['window' .. number .. 'Rows']
                imgui.SliderInt('##chatbox.window' .. number .. 'Rows', rows, 0, 50, rows[1] == 0 and 'Automatic' or '%d rows')
                if imgui.IsItemDeactivatedAfterEdit() then app.save() end
                Tip('How many rows this window has. Automatic is ten. With Auto Resize, the most it grows to. The expanded log is unaffected.')
            end
            widgets.Label('Expand In Place')
            if imgui.Checkbox('##chatbox.expandInPlace', options.expandInPlace) then app.save() end
            Tip('Opens the expanded log where the chat log stands, its bottom-left on the first log\'s; the info panel is hidden while it is open,\nso with Anchor Bottom the log takes the panel\'s place as well. Its rows, hovering, Confirm and scrolling move with it. Off, where the game puts it.')
            widgets.Label('Expanded Height')
            imgui.SliderInt('##chatbox.expandedHeight', options.expandedHeight, 25, 100, '%d%%')
            if imgui.IsItemDeactivatedAfterEdit() then app.save() end
            Tip('How far up the screen the expanded log reaches: its top that share of the screen\'s height up from the bottom, and never above\nthe game\'s own window. The game\'s rows above it are cut off; the rest of the log, its scrolling and Confirm are as ever. 100% is the game\'s own.')
        end
        if not game and widgets.Header('Activity') then
            imgui.TextDisabled('Each window grows with its recent messages or fades while idle; off, it stands at its rows.')
            VisibilitySettings(options.visibility.window1, 1)
            VisibilitySettings(options.visibility.window2, 2)
        end
        if widgets.Header('Look') then
            widgets.Label('Window Title')
            imgui.InputText('##chatbox.windowTitle', options.windowTitle, TITLE_LONGEST)
            if imgui.IsItemDeactivatedAfterEdit() then app.save() end
            Tip('The words on the compact log\'s top edge. Left empty, the channel you are speaking in, as /cm and /p, /l, /t and the like set it.')
            widgets.Label('Window 2 Title')
            imgui.InputText('##chatbox.splitTitle', options.splitTitle, TITLE_LONGEST)
            if imgui.IsItemDeactivatedAfterEdit() then app.save() end
            Tip('The words on the second log window\'s top edge, with the game\'s Log Window 2 on. Left empty, Window 2.')
            for _, side in ipairs(PADDING_SIDES) do
                widgets.Label(side.label)
                imgui.SliderInt('##chatbox.' .. side.key, options[side.key], 0, PADDING_MOST, '%d px')
                if imgui.IsItemDeactivatedAfterEdit() then app.save() end
                Tip(side.tip)
            end
            widgets.Label('Replace Expanded Log')
            if imgui.Checkbox('##chatbox.replaceExpanded', options.replaceExpanded) then app.save() end
            Tip('Draws the expanded log\'s channel tabs as WinXI buttons, its scrollbar as the compact log\'s, its rows of text in the chat\'s Font at Font Size\nand its cursor and the light on its row. The rows stand at the chat\'s own pitch, not the game\'s, so the mouse over the log is kept from the game;\nthe wheel still scrolls, and Square, the arrows and Confirm choose rows. Off, the game\'s own are drawn in the WinXI frame, tinted, with its mouse.')
            appearance.Draw(options.appearance, app.save)
        end
    end,
    tabs = {
        { label = 'Info Panel', draw = function(options)
            require('winxi.infopanel.chat_settings').Draw(options.infoPanel, infoPanel, app.save)
        end },
    },
    commands = {
        panel = function(options, args)
            local verb = args[3] and args[3]:lower()
            local enabled = options.infoPanel.layout.enabled
            if verb == nil then enabled[1] = not enabled[1]
            elseif verb == 'on' then enabled[1] = true
            elseif verb == 'off' then enabled[1] = false
            elseif verb == 'reset' then require('winxi.infopanel.exp').Reset(); infoPanel.Invalidate(); return
            else app:Say('/chatbox panel [on|off|reset]; configure slots in the Info Panel tab.'); return end
            infoPanel.Invalidate(); app.save()
            app:Say(enabled[1] and 'Info Panel enabled. Unload clock to avoid duplicate panels.' or 'Info Panel disabled.')
        end,
        clock = function(options, args) HideHud(options, args, 'hideClock', 'clock') end,
        compass = function(options, args) HideHud(options, args, 'hideCompass', 'compass') end,
        timestamps = function(options, args)
            local verb = args[3] and args[3]:lower()
            local shown = options.timestamps
            if verb == nil then shown[1] = not shown[1]
            elseif verb == 'on' or verb == 'show' then shown[1] = true
            elseif verb == 'off' or verb == 'hide' then shown[1] = false
            else app:Say('/chatbox timestamps [on|off] shows or hides the timestamps SimpleLog or the timestamp addon write.'); return end
            model.ShowStamps(history, shown[1])
            app.save()
            app:Say(shown[1] and 'Timestamps shown.' or 'Timestamps hidden; the messages keep them.')
        end,
        translate = function(options, args)
            local verb = args[3] and args[3]:lower()
            local on = options.autoTranslate
            if verb == nil then on[1] = not on[1]
            elseif verb == 'on' then on[1] = true
            elseif verb == 'off' then on[1] = false
            else return app:Say('/chatbox translate [on|off] turns chatbox\'s own auto-translate list on Tab on or off.') end
            if not on[1] then ClosePicker() end
            app.save()
            app:Say(on[1] and 'Auto-Translate on: Tab while typing opens chatbox\'s list of phrases.' or 'Auto-Translate off: Tab is the game\'s again.')
        end,
        on = function(options) options.enabled[1] = true; app.save() end,
        off = function(options) options.enabled[1] = false; Release(); app.save() end,
        clear = ClearHistory,
        status = Status,
        bytes = function()
            -- held: each line said here goes through text_in itself and would take the sample's place
            local sample = decodeSample
            if not sample then app:Say('No decode sample yet. Receive a chat line, then /chatbox bytes.'); return end
            -- Hex is ASCII-only: printing the diagnostic cannot reinterpret the bad character.
            app:Say(('Chat bytes, original mode %d / display mode %d%s, %s (first 256 bytes per stage%s):')
                :format(sample.originalMode, sample.mode, sample.injected and ', an addon\'s own line' or '',
                    sample.stamp and 'a timestamp in front' or sample.final and 'no timestamp in front'
                        or 'no timestamp in front (one written by an addon loaded after chatbox never reaches it without uihook 0.8)',
                    sample.final and '; final: as uihook read it after every addon' or ''))
            for _, key in ipairs({'original','modified','final','expanded','utf8'}) do
                local text = sample[key]
                if text then app:Say(key .. ': ' .. (text:gsub('.', function(c) return ('%02X '):format(c:byte()) end))) end
            end
        end,
        -- the last lines kept and their chat modes, to learn a channel's mode from the game
        modes = function()
            local messages = history.messages
            if #messages == 0 then app:Say('No lines kept yet.') end
            for i = math.max(1, #messages - 9), #messages do
                local message = messages[i]
                app:Say(('mode %3d: %s'):format(message.mode, message.text:sub(1, 60)))
            end
        end,
    },
    onSettings = function(options)
        local width = tonumber(options.width[1]) or 640
        if width ~= width then width = 640 end
        options.width[1] = math.floor(math.max(240, math.min(1200, width)))
        local fontSize = tonumber(options.fontSize[1]) or 12
        if fontSize ~= fontSize then fontSize = 12 end
        fontSize = math.floor(math.max(0, math.min(24, fontSize))) -- 0 is Automatic
        if fontSize > 0 and fontSize < 8 then fontSize = 8 end
        options.fontSize[1] = fontSize
        -- Retire old display filters/rewriters and colour overrides, even for existing characters.
        options.combat, options.colors, options.themeColors = nil, nil, nil
        options.inlineColors, options.timestampOwnColor, options.timestampColor = nil, nil, nil
        options.appearance = appearance.Repair(options.appearance, T, theme.Get())
        if type(options.fontFile) ~= 'string' then options.fontFile = '' end
        for _, side in ipairs(PADDING_SIDES) do
            if type(options[side.key]) ~= 'table' then options[side.key] = T{ PADDING_DEFAULT } end
            local amount = tonumber(options[side.key][1]) or PADDING_DEFAULT
            if amount ~= amount then amount = PADDING_DEFAULT end
            options[side.key][1] = math.floor(math.max(0, math.min(PADDING_MOST, amount)))
        end
        -- Once: the first paddings were 4 on every side; left all at that, they take the 3 of now.
        if type(options.paddingVersion) ~= 'table' then options.paddingVersion = T{ 0 } end
        if (tonumber(options.paddingVersion[1]) or 0) < 1 then
            local untouched = true
            for _, side in ipairs(PADDING_SIDES) do untouched = untouched and options[side.key][1] == 4 end
            if untouched then
                for _, side in ipairs(PADDING_SIDES) do options[side.key][1] = PADDING_DEFAULT end
            end
            options.paddingVersion[1] = 1
            if app then app.save() end -- the first load runs before app exists; the next save keeps it
        end
        -- Mode, from settings before it: Follow Native Settings (or, before that, either of Match Game Log Size and
        -- Match Game Input Size) on was Follow Game, off WinXI Skin; the old keys are dropped
        if type(options.followNativeSettings) == 'table' or type(options.matchGameLogSize) == 'table'
            or type(options.matchGameInputSize) == 'table' then
            local legacy = nil
            if type(options.followNativeSettings) == 'table' and type(options.followNativeSettings[1]) == 'boolean' then
                legacy = options.followNativeSettings[1]
            end
            if legacy == nil then
                legacy = (type(options.matchGameLogSize) == 'table' and options.matchGameLogSize[1] == true)
                    or (type(options.matchGameInputSize) == 'table' and options.matchGameInputSize[1] == true)
            end
            options.mode = T{ legacy and 'game' or 'skin' }
            options.followNativeSettings, options.matchGameLogSize, options.matchGameInputSize = nil, nil, nil
        end
        if type(options.mode) ~= 'table' or (options.mode[1] ~= 'game' and options.mode[1] ~= 'skin') then options.mode = T{ 'game' } end
        -- Lock Window, Position and the place
        if type(options.locked) ~= 'table' then options.locked = T{ true } end
        options.locked[1] = options.locked[1] ~= false
        if type(options.position) ~= 'table' or (options.position[1] ~= 'game' and options.position[1] ~= 'custom') then options.position = T{ 'game' } end
        if type(options.pos) ~= 'table' then options.pos = T{} end
        for i = 1, 2 do
            local n = tonumber(options.pos[i])
            if not n or n ~= n or math.abs(n) == math.huge then n = i == 1 and 20 or 1000 end
            options.pos[i] = math.floor(n)
        end
        -- Replace Expanded Log, from the four switches before it (tabs, scrollbar, text and cursor): on where all were
        local legacyReplace, allOn = false, true
        for _, key in ipairs({ 'replaceTabs', 'replaceScrollbar', 'replaceText', 'replaceCursor' }) do
            if type(options[key]) == 'table' then legacyReplace, allOn = true, allOn and options[key][1] == true end
            options[key] = nil
        end
        if legacyReplace then options.replaceExpanded = T{ allOn } end
        if type(options.replaceExpanded) ~= 'table' then options.replaceExpanded = T{ true } end
        options.replaceExpanded[1] = options.replaceExpanded[1] ~= false
        options.infoPanel = panelModel.Complete(options.infoPanel)
        options.visibility = visibility.Complete(options.visibility)
        for _, key in ipairs({ 'window1Rows', 'window2Rows' }) do
            local rows = tonumber(type(options[key]) == 'table' and options[key][1]) or 0
            if rows ~= rows then rows = 0 end
            options[key] = T{ math.max(0, math.min(50, math.floor(rows))) }
        end
        if type(options.timestamps) ~= 'table' then options.timestamps = T{ true } end
        options.timestamps[1] = options.timestamps[1] ~= false
        model.ShowStamps(history, options.timestamps[1])
        if type(options.chatTooltips) ~= 'table' then options.chatTooltips = T{ true } end
        options.chatTooltips[1] = options.chatTooltips[1] ~= false
        if type(options.tooltipNotes) ~= 'table' then options.tooltipNotes = T{ true } end
        options.tooltipNotes[1] = options.tooltipNotes[1] ~= false
        options.tooltipKinds = TooltipKinds(options.tooltipKinds)
        if type(options.autoTranslate) ~= 'table' then options.autoTranslate = T{ true } end
        options.autoTranslate[1] = options.autoTranslate[1] ~= false
        for _, key in ipairs({ 'windowTitle', 'splitTitle' }) do
            local words = type(options[key]) == 'table' and options[key][1]
            options[key] = T{ type(words) == 'string' and words:sub(1, TITLE_LONGEST - 1) or '' }
        end
        if type(options.expandedHeight) ~= 'table' then options.expandedHeight = T{ 75 } end
        options.expandedHeight[1] = math.max(25, math.min(100, math.floor(tonumber(options.expandedHeight[1]) or 75)))
        Reset() -- a new character must never inherit another character's private chat
    end,
})

ashita.events.register('command', 'chatbox_mode', function(e)
    if e.blocked then return end
    selectedMode = channels.ModeCommand(e.command_modified or e.command) or selectedMode
end)

-- A line kept: { originalMode, mode (both whole mode words), raw (the bytes kept), original (the bytes the game was
-- given), injected, final (uihook's copy of the bytes kept, where it is the source) }. Observed, never blocked or
-- rewritten: the game keeps its own history and fallback rendering.
local function Keep(line)
    local originalMode = bit.band(line.originalMode or 0, 0xff)
    local mode = bit.band(line.mode or line.originalMode or 0, 0xff)
    -- 190 replays NPC text into the native log; it is not another dialogue line.
    -- Check the original mode too, before another addon's formatting remaps it.
    if originalMode == 190 or mode == 190 or mode == 152 then return end
    spoken = channels.Sent(mode) or spoken
    local raw = line.raw
    if type(raw) ~= 'string' or #raw > model.MaxBytes then return end
    local ok, text, expanded, spans = pcall(encoding.Decode, raw, false, true)
    if not ok or not text then decodeErrors = decodeErrors + 1; return end
    decodeSample = { originalMode=originalMode, mode=mode, injected=line.injected == true, stamp=model.Stamp(text) ~= nil,
        original=type(line.original)=='string' and line.original:sub(1,256) or '',
        modified=raw:sub(1,256), final=type(line.final)=='string' and line.final:sub(1,256) or nil,
        expanded=type(expanded)=='string' and expanded:sub(1,256) or '', utf8=text:sub(1,256) }
    model.Add(history, text, mode, nil, originalMode, spans, line.mode or line.originalMode, Tokens(raw))
end
-- Each line read through uihook after every addon (winxi.nativetext, uihook 0.8 or newer): chatbox's own text_in
-- copy of a line is held until the frame's lines are drained, and the line is kept as uihook has it, so a formatter
-- loaded after chatbox (SimpleLog's timestamps, a filter's block) still reaches it and the load order does not
-- matter. Where uihook runs before the addons (loaded before the addons plugin), its copy is the game's original:
-- chatbox's own, which may have been formatted, is kept instead. Without the tap, each line is kept as it arrives.
-- A held copy uihook never matches (a line it did not see) is kept as it is after HOLD seconds.
local HOLD = 0.5
local tap = { reader = nil, pending = {}, used = false }
local function TapReady()
    if tap.reader == nil then
        local ok, found = pcall(require, 'winxi.nativetext')
        tap.reader = ok and type(found) == 'table' and found.new and found.new() or false
    end
    return tap.reader and tap.reader.Ready() or false
end
TapStatus = function()
    if tap.used then return 'read through uihook after every addon; the load order does not matter' end
    return 'chatbox\'s own text_in: load formatting addons before it (' .. (tap.reader and tap.reader.Status() or 'winxi.nativetext is missing') .. ')'
end
local function DrainTap()
    local lines = tap.reader and tap.reader.Drain() or nil
    if lines then
        tap.used = true
        for _, got in ipairs(lines) do
            -- chatbox's own copy of the same line: the first still held with the same original bytes and mode
            local own
            for i, held in ipairs(tap.pending) do
                if held.original == got.original and bit.band(held.originalMode, 0xff) == bit.band(got.mode, 0xff) then
                    own = table.remove(tap.pending, i); break
                end
            end
            if not got.blocked and not (own and own.blocked) then
                local line = { originalMode = got.mode, mode = got.finalMode, raw = got.text, original = got.original,
                    injected = got.injected, final = got.text }
                -- uihook's copy the game's original while chatbox's own was changed: uihook ran before the addons
                if not got.modified and own and own.raw ~= own.original then line.mode, line.raw = own.mode, own.raw end
                Keep(line)
            end
        end
    elseif tap.used then tap.used = false end
    if #tap.pending > 0 then
        local now, kept = os.clock(), {}
        for _, held in ipairs(tap.pending) do
            if lines == nil or now - held.time > HOLD then
                if not held.blocked then Keep(held) end
            else kept[#kept + 1] = held end
        end
        tap.pending = kept
    end
end
ashita.events.register('text_in', 'chatbox_text', function(e)
    local raw = e.message_modified or e.message
    if type(raw) ~= 'string' then return end
    local line = { originalMode = e.mode or 0, mode = e.mode_modified or e.mode or 0, raw = raw, original = e.message,
        injected = e.injected == true, blocked = e.blocked == true, time = os.clock() }
    if TapReady() then tap.pending[#tap.pending + 1] = line; return end
    if not line.blocked then Keep(line) end
end)
ashita.events.register('packet_in', 'chatbox_zone', function(e)
    if e.blocked then return end
    infoPanel.Packet(app.options.infoPanel, e.id, e.data_modified or e.data)
    if e.id == 0x00b then zoning = true; Release()
    elseif e.id == 0x00a then zoning = false; channels.ResetLinkshells()
    elseif e.id == 0x0e0 then channels.LinkshellPacket(e.data_modified or e.data) end
end)
ashita.events.register('unload', 'chatbox_unload', Reset)

-- Native Square/window focus: a faint light over the box and the game's cursor at its newest line.
-- Both are drawn in the window, so they are part of the captured replacement; no buttons are bound.
local captured, capturedSplit, selectedWindow = false, false, nil
local windowOptions = { capture = function()
    captured = primary.Capture()
    infoPanel.Captured(panelAttachment, 0, captured)
end }
local splitOptions = { capture = function()
    capturedSplit = secondary.Capture()
    infoPanel.Captured(panelAttachment, 1, capturedSplit)
end }
-- A collapsed log has no frame/title or invisible full-size hit area. Only the panel is captured.
local panelOnlyOptions = {
    { padding = 0, background = {0,0,0,0}, border = {0,0,0,0}, capture = windowOptions.capture },
    { padding = 0, background = {0,0,0,0}, border = {0,0,0,0}, capture = splitOptions.capture },
} -- the second log window's box
local white, light = { 1, 1, 1, 1 }, { 1, 1, 1, 0.07 }

-- The game's right-pointing cursor (as party's), its point at the box's left edge on the given row;
-- drawn out past the window's edge, so the clip is opened. '>' where the art cannot be read.
local function DrawCursor(list, edge, rowTop, fontSize)
    local handle, art = cursorArt.Get()
    list:PushClipRect({ 0, 0 }, { edge + 4096, rowTop + 4096 }, false)
    if handle then
        local height = fontSize + 2
        local width = height * art[5] / art[6]
        local left = math.max(0, edge + 3 - width)
        list:AddImage(handle, { left, rowTop - 1 }, { left + width, rowTop - 1 + height },
            { art[1], art[2] }, { art[3], art[4] }, imgui.GetColorU32(white))
    else
        local width = imgui.CalcTextSize('>')
        list:AddText({ math.max(0, edge + 2 - width), rowTop }, imgui.GetColorU32(controller.HighlightColor), '>')
    end
    list:PopClipRect()
end

-- Chat Tooltips: the row and the character under the mouse this frame, found as a compact log is drawn (in the font
-- it is drawn in) and shown after that log's capture, outside its window, so the tooltip is never part of the replay
-- in the game's chat. Cleared as each frame starts; the last box drawn under the mouse wins.
local hovered = { text = nil, offset = 0, row = nil, view = nil, expanded = false, mirror = false }
-- mirror: the expanded log was drawn this frame with its rows the addon's and captured, so the mouse over it is kept from the game
-- The bytes of the UTF-8 character a lead byte starts (a stray continuation byte counts as one)
local function CharacterBytes(b) return b >= 0xf0 and 4 or b >= 0xe0 and 3 or b >= 0xc0 and 2 or 1 end
-- The 1-based byte offset of the character dx pixels into text as it is drawn, or nil before it or past its end:
-- each character's right edge is the width of the text up to it, measured as render.Rich draws it. The edges only
-- grow from one character to the next, so the first past dx is found by halving: the characters' ends walked once,
-- then a handful of the text's beginnings measured, not one for every character. (Each character measured alone and
-- the widths added would not do: imgui rounds every width it measures up to a whole pixel, and the sum drifts right
-- of the text as it is drawn.)
local characterEnds = {} -- the last byte of each character of the text being walked, refilled each call
local function CharacterAt(text, dx)
    if dx < 0 or render.Measure(text) <= dx then return nil end
    local count, at = 0, 1
    while at <= #text do
        local after = at + CharacterBytes(text:byte(at))
        count = count + 1
        characterEnds[count] = after - 1
        at = after
    end
    -- the whole text reaches past dx, so the last character's edge does: the first edge past it lies from low to high
    local low, high = 1, count
    while low < high do
        local middle = math.floor((low + high) / 2)
        if render.Measure(text:sub(1, characterEnds[middle])) > dx then high = middle else low = middle + 1 end
    end
    return low == 1 and 1 or characterEnds[low - 1] + 1
end
-- Where the mouse is for Chat Tooltips in a box, or nil: with them on, the mouse not over a window of imgui's own
-- (the settings), no scrollbar or log being dragged, and the mouse inside the box's rows
local function TipMouse(left, width, areaTop, areaBottom)
    if not app.options.chatTooltips[1] or moving or views[1].drag or views[2].drag then return nil end
    local io = imgui.GetIO()
    local mouse = not io.WantCaptureMouse and io.MousePos
    if not mouse then return nil end
    local x, y = mouse.x or mouse[1], mouse.y or mouse[2]
    if not x or not y or x < left or x >= left + width or y < areaTop or y >= areaBottom then return nil end
    return x, y
end

-- What DrawLog says of the box it drew (view.drawn): which rows, where, and its scrollbar, as the mouse hook matches
-- it (view.target) and /chatbox status tells it (lastDrawn, lastSplit). Each window has three tables for it, and a
-- frame fills one that none of those holds, so a box once handed out stays as it was drawn, whatever later frames do.
local function DrawnTable(view)
    local pool = view.drawnPool
    if not pool then pool = { {}, {}, {} }; view.drawnPool = pool end
    for i = 1, #pool do
        local t = pool[i]
        if t ~= view.drawn and t ~= view.target and t ~= lastDrawn and t ~= lastSplit then return t end
    end
end
-- the points and corners DrawLog hands imgui, which copies them: filled afresh for each row, not made anew
local rowPos, logClipMin, logClipMax = { 0, 0 }, { 0, 0 }, { 0, 0 }
-- The log's rows, in the window being drawn (with the chat's font pushed): the light and cursor when the
-- game has it selected (lit), then the rows at the bottom, preserving all source inline colours. Native-sized
-- boxes centre their whole rows within the configured vertical padding. view: the window's own scrolling; filter: which messages it
-- shows (nil, all of them); style: the window's options, for its title and Default Text colour.
local function DrawLog(box, rowCount, fontSize, padding, view, filter, lit, style)
    local list = imgui.GetWindowDrawList()
    local left, top = box.left, box.bottom - box.height
    if lit then
        list:AddRectFilled({ left, top }, { left + box.width, box.bottom }, imgui.GetColorU32(light))
    end
    local inset = pad.left
    local width = math.max(1, box.width - inset - pad.right)
    local font, size = imgui.GetFont(), imgui.GetFontSize()
    local modes = filter
    local visible = history
    local metrics = model.Metrics(visible,width,font,size,render.Measure,modes)
    if metrics.total > rowCount then
        width = math.max(1,width-scrollbar.Reserve)
        metrics = model.Metrics(visible,width,font,size,render.Measure,modes)
    end
    local rows, overflow
    if view.pendingScroll ~= nil then
        view.offset = math.max(0,math.min(math.max(0,metrics.total-rowCount),view.pendingScroll))
        view.pending, view.pendingScroll = 0, nil
    end
    local movement = view.pending < 0 and math.ceil(view.pending) or math.floor(view.pending)
    view.offset = math.max(0, view.offset + movement)
    view.pending = view.pending - movement
    rows, view.offset, overflow = model.Tail(visible, width, font, size, render.Measure, rowCount, modes, 0, view.offset)
    -- The rows centred between the configured top and bottom padding; the
    -- newest at the foot of them, as the game's.
    local step = fontSize + ROW_GAP
    local areaTop = top + pad.top
    local areaBottom = box.bottom - pad.bottom
    local block = rowCount * step - ROW_GAP
    local spare = areaBottom - areaTop - block
    local x, y = left + inset, areaTop + (spare < 0 and spare or math.floor(spare / 2))
    y = y + (rowCount - #rows) * step
    -- During animated resizing, reveal/hide rows at the top without moving the newest row.
    logClipMin[1], logClipMin[2] = left, math.min(areaTop, areaBottom)
    logClipMax[1], logClipMax[2] = left + box.width, areaBottom
    list:PushClipRect(logClipMin, logClipMax, true)
    if lit then
        DrawCursor(list, left, y + (#rows - 1) * step, fontSize)
    end
    local firstY = y
    local tipX, tipY = TipMouse(left, box.width, areaTop, areaBottom)
    for _, row in ipairs(rows) do
        if row.text ~= '' then
            local color = imgui.GetColorU32(style.textColor or palette.Mode(row.message.mode) or theme.Get().TextColor)
            rowPos[1], rowPos[2] = x, y
            render.Rich(list, rowPos, color, row.text, row.spans, row, font, size)
            -- the one row under the mouse is walked for the character; every other row is two comparisons
            if tipY and tipY >= y and tipY < y + step then
                local offset = CharacterAt(row.text, tipX - x)
                if offset then hovered.text, hovered.offset, hovered.row, hovered.view, hovered.expanded = row.text, offset, row, view, false end
            end
        end
        y = y + step
    end
    list:PopClipRect()
    local bar = scrollbar.Layout(left+box.width-3-scrollbar.Width,areaTop,areaBottom,metrics.total,rowCount,view.offset)
    if bar then
        local io = imgui.GetIO()
        local mouse = io.MousePos
        local hovered = not io.WantCaptureMouse and scrollbar.Hit(bar,
            mouse and (mouse.x or mouse[1]),mouse and (mouse.y or mouse[2]))
        local tint = (hovered or view.drag ~= nil) and scrollbar.Bright or scrollbar.White
        list:AddRectFilled({bar.left,bar.thumbTop},{bar.right,bar.thumbBottom},imgui.GetColorU32(tint),1)
    else
        view.drag = nil
    end
    contentSize[1], contentSize[2] = width, box.height - padding * 2
    imgui.Dummy(contentSize)
    -- the box drawn written only now, all of it, as it was made only once the rows were drawn
    local drawn = DrawnTable(view)
    drawn.frame, drawn.expanded, drawn.left, drawn.top, drawn.width, drawn.bottom = frame, false, left, top, box.width, box.bottom
    drawn.rows, drawn.drawn, drawn.title, drawn.firstY, drawn.overflow, drawn.scrollbar = rowCount, #rows, style.title, firstY, overflow, bar
    view.drawn = drawn
    return drawn
end

-- The tokens whose bracket pairs open in a row, for links.At: as many skipped as there are ❮ in the message's shown
-- text before the row, then as many as the row has; nil where it has none. Kept on the row, which lasts as long as
-- the log's layout does.
local function RowTokens(row)
    if row.tokenSlice == nil then
        local tokens, slice = row.message.tokens, false
        if tokens and row.offset then
            local _, before = model.Shown(history, row.message):sub(1, row.offset - 1):gsub('❮', '')
            local _, within = row.text:gsub('❮', '')
            if within > 0 and before < #tokens then
                slice = {}
                for i = before + 1, math.min(#tokens, before + within) do slice[#slice + 1] = tokens[i] end
            end
        end
        row.tokenSlice = slice
    end
    return row.tokenSlice or nil
end
-- The tooltip of what the mouse is on in a compact log, or in the expanded log while its rows are the addon's, after
-- that log is captured: the kinds shown are Chat Tooltips' own; a failed lookup shows nothing
local tipKinds = {}
local function ChatTooltip()
    if not hovered.text then return end
    local view = hovered.view
    local shown = hovered.expanded and captured and lastDrawn ~= nil and lastDrawn.expanded
        or (view == views[1] and captured) or (view == views[2] and capturedSplit)
    if not shown then return end
    for _, kind in ipairs(links.Kinds) do
        local box = app.options.tooltipKinds[kind.key]
        tipKinds[kind.key] = type(box) == 'table' and box[1] == true
    end
    local slice = nil
    if hovered.row then
        local ok, found = pcall(RowTokens, hovered.row)
        slice = ok and found or nil
    end
    local found, reference = pcall(links.At, hovered.text, hovered.offset, slice, tipKinds)
    if found and reference then pcall(links.Tooltip, reference, app.options.tooltipNotes[1]) end
end

-- Keep the native rectangle exactly: drawing elsewhere would break mouse hit-tests. Expand In Place moves the
-- game's own log (uihook moves its layout target, so its hit-tests move with it); the box follows its rectangle.
-- The plugin re-enables native drawing at FullLog::Draw and leaves the native rows, cursor and, unless
-- the addon draws its own, tabs and scrollbar visible. No themed rows, title or input are placed over them.
-- The tabs and scrollbar the addon draws stand where uihook measured the game's, so the game's hit-tests,
-- Square selection and scrolling are untouched; the game is asked to leave its own undrawn only while
-- there is a fresh place to draw them in.
-- all: with the tabs, scrollbar and text the addon's, the game leaves the rest undrawn as well (its row light, cursor
-- and marks), which DrawExpandedRows draws from the rows' cursor, pressed and marked: the whole log mirrored.
local expandedColors, expandedReplace = {}, { tabs = false, scrollbar = false, text = false, all = false }
-- the compact log's window: its padding, font size and the theme's shadow, the log's colours (set as it is drawn)
local expandedOptions = { padding = PADDING_DEFAULT,
    capture = function() captured = primary.Capture(true, expandedColors, expandedReplace) end }
local expandedTabs, expandedScroll, expandedRows, expandedScreen = nil, nil, nil, { 0, 0 }
local expandedBox = { 0, 0, 0, 0 } -- the full log's rectangle, which its rows are clipped to
-- the expanded log's scrollbar thumb's left, as the compact log's: inside its right edge
local function ExpandedThumbLeft() return expandedBox[3] - 3 - scrollbar.Width end
local stripColors, stripButton = {}, { 0, 0, 0, 0 }
local expandedStatus, expandedStatusKey -- the expanded log's status line, and what it was made from
-- The tabs' names measured once in the font and size they are drawn in, not every frame
local tabSizes, tabFont, tabSize = {}, nil, nil
local function MeasureTab(words)
    local known = tabSizes[words]
    if not known then
        local width, height = render.Measure(words)
        known = { width, height }
        tabSizes[words] = known
    end
    return known[1], known[2]
end
local origin = { 0, 0 }
-- The game's rows of text, decoded once each (CP932 with the game's colour codes to UTF-8 and colour spans)
-- and kept by their bytes: 512 at most, then forgotten together, and forgotten as Timestamps changes (a row is kept
-- as it is shown, its stamp taken off while they are hidden)
local decodedRows, decodedCount, decodedStamps = {}, 0, true
local function DecodeRow(raw)
    local stamps = app.options.timestamps[1] ~= false
    if stamps ~= decodedStamps then decodedRows, decodedCount, decodedStamps = {}, 0, stamps end
    local entry = decodedRows[raw]
    if entry == nil then
        local ok, text, _, spans = pcall(encoding.Decode, raw, true, true)
        text, spans = ok and type(text) == 'string' and text or '', ok and spans or nil
        if not stamps then text, spans = model.Unstamp(text, spans) end
        entry = { text = text, spans = spans }
        if decodedCount >= 512 then decodedRows, decodedCount = {}, 0 end
        decodedRows[raw], decodedCount = entry, decodedCount + 1
    end
    return entry
end
-- The game's cursor art (as the compact log's) with its left edge at x, on a row of that height
local function DrawMark(list, x, rowTop, fontSize)
    local handle, art = cursorArt.Get()
    if handle then
        local height = fontSize + 2
        local width = height * art[5] / art[6]
        list:AddImage(handle, { x, rowTop - 1 }, { x + width, rowTop - 1 + height },
            { art[1], art[2] }, { art[3], art[4] }, imgui.GetColorU32(white))
    else
        list:AddText({ x, rowTop }, imgui.GetColorU32(controller.HighlightColor), '>')
    end
end
-- The game's rows laid out as the compact log lays out its own: Font Size + ROW_GAP apart, the newest with its text
-- ending at the Bottom Padding, older ones up from it, as many as fit between the paddings. Which rows they are,
-- which the game highlights and where its cursor is are the game's, by their order (newest first). The game's own
-- places (16 of its units apart) do not line up with these, so the mouse is kept from the game's log while the rows
-- are the addon's (the mouse hook below); the wheel still scrolls, and Square, the arrows and Confirm choose rows.
-- Should the row the game has chosen be past what fits, the view moves up to keep it at the top. Returns { row, y }
-- for each line shown, the newest first.
-- The lists and each line's table are kept and filled afresh every frame (they are read only as the frame draws).
local expandedLines, expandedPlaced, expandedLinePool = {}, {}, {}
local function ExpandedLines(rows, size)
    for i = #expandedLines, 1, -1 do expandedLines[i] = nil end
    for i = #expandedPlaced, 1, -1 do expandedPlaced[i] = nil end
    local step = size + ROW_GAP
    local areaTop, areaBottom = expandedBox[2] + pad.top, expandedBox[4] - pad.bottom
    local fits = math.max(1, math.floor((areaBottom - areaTop + ROW_GAP) / step))
    local placed, measured = expandedPlaced, false
    for _, row in ipairs(rows) do
        if row.top then placed[#placed + 1] = row; measured = measured or row.lit end
    end
    local chosen = 1
    for i, row in ipairs(placed) do
        if (measured and row.lit) or (not measured and row.cursor) then chosen = i end
    end
    local first = math.max(1, chosen - fits + 1)
    for i = first, math.min(#placed, first + fits - 1) do
        local n = #expandedLines + 1
        local line = expandedLinePool[n]
        if not line then line = {}; expandedLinePool[n] = line end
        line.row, line.y = placed[i], areaBottom - size - (i - first) * step
        line.chosen = (measured and placed[i].lit) or (not measured and placed[i].cursor)
        expandedLines[n] = line
    end
    return expandedLines
end
-- With the whole log the addon's, the lights the game would have drawn under its rows: across the log (to the
-- scrollbar), a line tall with half the row gap either side, each row the game highlights (lit, where uihook
-- measured its highlight; without that, the cursor's row) in the highlight colour, brighter held down, and a row it
-- marks faintly
local rowLight = { 1, 1, 1, 0.25 }
local function DrawExpandedLights(list, lines, x, size)
    local right = expandedBox[3] - 4
    local highlight = expandedColors[1] or controller.HighlightColor
    for _, line in ipairs(lines) do
        local row = line.row
        if line.chosen or row.pressed or row.marked then
            local color = light
            if line.chosen or row.pressed then
                rowLight[1], rowLight[2], rowLight[3] = highlight[1], highlight[2], highlight[3]
                rowLight[4] = row.pressed and 0.45 or 0.25
                color = rowLight
            end
            -- short of the scrollbar's thumb
            local edge = expandedScroll and math.min(right, ExpandedThumbLeft() - 2) or right
            list:AddRectFilled({ math.max(expandedBox[1] + 1, x - 4), line.y - ROW_GAP / 2 }, { edge, line.y + size + ROW_GAP / 2 },
                imgui.GetColorU32(color), 2)
        end
    end
end
-- The game's rows of text as the compact log draws its own (ExpandedLines): the chat's font at Font Size, from the
-- log's left edge in by Left Padding, in the Default Text colour or the chat mode's with the game's inline colours
-- kept; the game's cursor row gets the cursor after its text. Clipped to the full log's box.
local function DrawExpandedRows(list, rows)
    local size = FontSize()
    local lines = ExpandedLines(rows, size)
    if #lines == 0 then return 0 end
    local chatFont = fonts.Get(app.options.fontFile)
    imgui.PushFont(chatFont, size)
    local font = imgui.GetFont() -- what the rows' kept layouts are measured in
    list:PushClipRect({ expandedBox[1], expandedBox[2] }, { expandedBox[3], expandedBox[4] }, true)
    local left = expandedBox[1] + pad.left
    if expandedReplace.all then DrawExpandedLights(list, lines, left, size) end
    local fallback = theme.Get().TextColor
    local drawn = 0
    -- Chat Tooltips here too: the row and character under the mouse, as the compact log finds its own (the game's
    -- rows carry no tokens: a bracketed phrase or link is known by its words), each row's its step tall, the gap
    -- under its text included, so the hover holds from one row to the next
    local tipX, tipY = TipMouse(expandedBox[1], expandedBox[3] - expandedBox[1], expandedBox[2], expandedBox[4])
    local step = size + ROW_GAP
    for _, line in ipairs(lines) do
        local row, x = line.row, left
        if row.text ~= '' then
            local entry = DecodeRow(row.text)
            if entry.text ~= '' then
                local color = expandedOptions.textColor or palette.Mode(row.mode) or fallback
                render.Rich(list, { x, line.y }, imgui.GetColorU32(color), entry.text, entry.spans, entry, font, size)
                if tipY and tipY >= line.y and tipY < line.y + step then
                    local offset = CharacterAt(entry.text, tipX - x)
                    if offset then hovered.text, hovered.offset, hovered.row, hovered.view, hovered.expanded = entry.text, offset, nil, nil, true end
                end
                if row.cursor then x = x + render.Measure(entry.text) end -- only the cursor's row needs its end
                drawn = drawn + 1
            end
        end
        if row.cursor then DrawMark(list, x + 4, line.y, size) end
    end
    list:PopClipRect()
    imgui.PopFont()
    return drawn
end
local function DrawExpandedControls()
    if not expandedTabs and not expandedScroll and not expandedRows then return end
    local list = imgui.GetWindowDrawList()
    if expandedRows and lastDrawn then lastDrawn.drawn = DrawExpandedRows(list, expandedRows) end
    if not expandedTabs and not expandedScroll then return end
    local chatFont = fonts.Get(app.options.fontFile)
    local fontSize = FontSize()
    if chatFont then imgui.PushFont(chatFont, fontSize) end
    list:PushClipRect(origin, expandedScreen, false) -- the game's tabs may stand above the frame
    if expandedTabs then
        -- a winxi game window's button colour, the border colour faint as the theme's palette gives imgui's
        -- buttons, and the Highlight Color for the chosen tab
        local look = theme.Get()
        local border = expandedColors[3]
        stripButton[1], stripButton[2], stripButton[3], stripButton[4] = border[1], border[2], border[3], border[4] * 0.25
        stripColors.button, stripColors.chosen, stripColors.text = stripButton, expandedColors[1], expandedColors[2]
        stripColors.background = expandedOptions.background or look.BackgroundColor
        stripColors.right, stripColors.foot = expandedBox[3] - 4, expandedBox[2] -- on the fitted frame's top
        -- the tabs' names a little smaller than the log's text
        local tabTextSize = math.max(8, math.floor(fontSize * TAB_TEXT_SCALE + 0.5))
        imgui.PushFont(chatFont, tabTextSize)
        local font = imgui.GetFont()
        if font ~= tabFont or tabTextSize ~= tabSize then tabSizes, tabFont, tabSize = {}, font, tabTextSize end
        strip.Draw(list, expandedTabs, channels.Filters, channels.Art, stripColors, MeasureTab)
        imgui.PopFont()
    end
    if expandedScroll then
        -- the compact log's: a thin thumb and no track, inside the log's right edge, over the game's bar's
        -- height and where its page is; brighter while the mouse is on the game's bar or it. The game's bar (and a
        -- few pixels round it) is left the game's by the mouse hook, so the game still takes its presses and drags
        local s = expandedScroll
        local bar = scrollbar.Layout(ExpandedThumbLeft(), math.max(s.top, expandedBox[2] + pad.top),
            math.min(s.bottom, expandedBox[4] - pad.bottom),
            s.count, s.page, s.count - s.page - s.above)
        if bar then
            local io = imgui.GetIO()
            local mouse = io.MousePos
            local x, y = mouse and (mouse.x or mouse[1]), mouse and (mouse.y or mouse[2])
            local hovered = x and y and y >= s.top and y < s.bottom
                and ((x >= s.left - 2 and x < s.right + 2) or scrollbar.Hit(bar, x, y))
            local tint = hovered and scrollbar.Bright or scrollbar.White
            list:AddRectFilled({ bar.left, bar.thumbTop }, { bar.right, bar.thumbBottom }, imgui.GetColorU32(tint), 1)
        end
    end
    list:PopClipRect()
    if chatFont then imgui.PopFont() end
end
-- A rectangle the game's log gives (primary.Rect and the like, up to four numbers or none) in a table kept for it, as
-- { ... } had it: #t is 4 only when all four came
local function Fill(t, a, b, c, d, e)
    t[1], t[2], t[3], t[4], t[5] = a, b, c, d, e
    return t
end
-- the full log's rectangle as the game gives it, and the box it is drawn in as lastDrawn has it: one table each,
-- filled afresh every frame the log is expanded (only lastDrawn holds the box past its frame, for /chatbox status,
-- and the mouse hook never matches it)
local fullRect, expandedDrawn = {}, {}
local function DrawExpanded(state, sw, sh)
    held = nil
    PlaceLog(app.options) -- kept where it was asked to open, or given back
    ResetViews(true)
    secondary.Stop()
    input.Stop()
    if state.nativeBrowse or not state.expandedSupported or not state.nativeContent then
        local mouse = imgui.GetIO().MousePos
        lastHandOver = { frame = frame, cursor = state.cursor, pageRows = state.pageRows, scroll = state.scroll,
            filter = state.filter, mouseX = mouse and (mouse.x or mouse[1]) or -1, mouseY = mouse and (mouse.y or mouse[2]) or -1 }
        anchorStatus = 'Expanded chat remains native: nested menu or native-content skin unavailable.'
        return
    end
    local rect = Fill(fullRect, primary.Rect(sw, sh, true))
    if #rect ~= 4 or rect[1] < 0 or rect[2] < 0 or rect[3] > sw or rect[4] > sh
        or rect[3] <= rect[1] or rect[4] <= rect[2] then
        anchorStatus = 'Waiting for native expanded bounds; full native log left visible.'
        return
    end
    -- The theme's frame and colours in both modes, and with Replace Expanded Log the tabs, scrollbar, text and cursor
    -- the addon's. Follow Game: where the game puts the log, at its full height; WinXI Skin: Width, Expanded Height and
    -- Expand In Place.
    local game = Game(app.options)
    Paddings(app.options)
    appearance.Apply(expandedOptions, app.options.appearance.log)
    local look = theme.Get()
    expandedColors[1] = look.HighlightColor or controller.HighlightColor
    expandedColors[2] = expandedOptions.titleColor or look.TitleColor or look.TextColor or white
    expandedColors[3] = expandedOptions.border or look.BorderColor or white
    expandedColors[4] = expandedOptions.border or look.BorderColor or white
    -- where the game drew its tabs, scrollbar and rows of text last, to draw the addon's own there and ask the game to leave its undrawn
    local replace = state.nativeReplace and app.options.replaceExpanded[1]
    expandedTabs = replace and primary.Tabs(sw, sh) or nil
    expandedScroll = replace and primary.Scrollbar(sw, sh) or nil
    expandedRows = state.nativeText and app.options.replaceExpanded[1] and primary.Rows(sw, sh) or nil
    expandedReplace.tabs, expandedReplace.scrollbar, expandedReplace.text = expandedTabs ~= nil, expandedScroll ~= nil, expandedRows ~= nil
    -- the whole log, once the addon draws the tabs and text; the scrollbar too, unless the game draws none
    expandedReplace.all = state.nativeMirror == true and replace == true and expandedTabs ~= nil and expandedRows ~= nil
    expandedScreen[1], expandedScreen[2] = sw, sh
    -- Expanded Height (the skin's): the frame reaches that share of the way up the screen and no higher (nor above the
    -- game's window); the game's rows above it are clipped, its rows, cursor and hit-tests otherwise its own
    local top = rect[2]
    if not game then top = math.max(rect[2], math.floor(sh * (1 - app.options.expandedHeight[1] / 100))) end
    top = math.min(top, rect[4] - 32)
    local bottom = rect[4]
    -- The skin's Width applies to expanded chat too, within the game's bounds; only the replacement frame and controls
    -- change, never the game's history wrapping or hit-tests. Follow Game keeps the game's bounds.
    local right = rect[3]
    if not game then right = math.min(rect[3], rect[1] + app.options.width[1]) end
    expandedBox[1], expandedBox[2], expandedBox[3], expandedBox[4] = rect[1], top, right, bottom
    expandedOptions.fontSize = FontSize()
    -- Opened in place: the log's foot stands where it was asked to (within a few pixels of the game's units)
    local opened = not game and app.options.expandInPlace[1] and expandPlace and logMenus
        and math.abs(rect[1] - expandPlace.left) <= 3 and math.abs(bottom - expandPlace.bottom) <= 3
    place[1], place[2] = rect[1], bottom
    size[1], size[2] = right-rect[1], bottom-top
    imgui.SetNextWindowPos(place, ImGuiCond_Always, pivot)
    imgui.SetNextWindowSize(size, ImGuiCond_Always)
    local d = expandedDrawn
    d.frame, d.expanded, d.left, d.top, d.width, d.bottom = frame, true, rect[1], top, size[1], bottom
    d.rows, d.drawn, d.firstY, d.title, d.overflow = state.pageRows or 0, 0, top, expandedRows and 'WinXI text' or 'native content', false
    lastDrawn = d
    window.Plain('winxi.chatbox.expanded', open, flags, DrawExpandedControls, expandedOptions)
    hovered.mirror = expandedRows ~= nil and captured
    -- the status line, made again only when what it says changes
    local key = (expandedTabs and 1 or 0) + (expandedScroll and 2 or 0) + (expandedRows and 4 or 0) + (expandedReplace.all and 8 or 0)
        + (state.nativeControls and 16 or 0) + (opened and 32 or 0) + (state.nested and 64 or 0)
    if key ~= expandedStatusKey then
        local parts = {}
        if expandedTabs then parts[#parts + 1] = 'tabs' end
        if expandedScroll then parts[#parts + 1] = 'scrollbar' end
        if expandedRows then parts[#parts + 1] = 'text' end
        if expandedReplace.all then parts[#parts + 1] = 'cursor' end
        local own = #parts > 0 and ('WinXI ' .. table.concat(parts, ', '):gsub(', ([^,]+)$', ' and %1')) or nil
        expandedStatus = own and ((expandedRows and 'Expanded native actions; WinXI frame and ' or 'Expanded native rows and actions; WinXI frame and ') .. own .. ' where the game\'s are.')
            or state.nativeControls and 'Expanded native rows and actions; WinXI frame and theme-tinted native controls.'
            or 'Expanded native rows and actions; WinXI frame (control artwork hooks unavailable).'
        if opened then expandedStatus = expandedStatus .. ' Opened where the chat log stands.' end
        if state.nested then expandedStatus = expandedStatus .. ' A menu of the game\'s is open over it.' end
        expandedStatusKey = key
    end
    anchorStatus = expandedStatus
end

-- The game's routing between its two log windows, as functions of a message, one each, kept while the routing
-- is what it was, so the model's caches hold: nil (everything) while the game shows one window.
local routeFilters = { routes = nil }
local function Filter(routes, window)
    if not routes or not routes.split then return nil end
    if routeFilters.routes ~= routes then
        routeFilters.routes = routes
        routeFilters[1] = function(message) return native.Shows(routes, 1, message.raw or message.mode) end
        routeFilters[2] = function(message) return native.Shows(routes, 2, message.raw or message.mode) end
    end
    return routeFilters[window]
end

do -- the frame's helpers are this block's, not the main chunk's (LuaJIT allows it 200 locals)
    -- The compact frame, in phases, each a function of its own called in turn from DrawFrame: MeasureFirst (the first
    -- box), MeasureSecond (the game's second log window), HoldBox (the last box kept a moment while the game's log
    -- settles), Activity (Auto Resize and Fade When Idle), PanelAndLift (the info panel, the lift over it and where the
    -- expanded log will open) and DrawBoxes (the windows themselves), then the input bar. What one phase finds and those
    -- after it use is kept here, every field written afresh each frame before it is read: one table, not a closure's
    -- dozens of locals made anew every frame. firstHidden (the game's log at 0 lines, nothing drawn in its place),
    -- splitDrawn and compactMinSize are read by the handler after the frame, and set false by it before.
    local compact = {}
    local logRect, splitRect = {}, {} -- the game's first and second log windows, as Fill keeps them
    local MIN_SIZE = { 1, 1 }
    local WINDOW_KEYS = { 'window1', 'window2' } -- each window's Activity settings
    local splitPlace, splitSize, panelPlace, panelSize = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }
    local liftedFirst, liftedSecond = {}, {} -- the boxes lifted over the panel, drawn this frame and held by nothing after
    local heldBox = {} -- held, when there is one: filled afresh with each box drawn
    -- Rows and height for a box from the game's window: its lines now (0 rows at 0 lines), the box no shorter than the
    -- window; or, with a uihook that does not say, as many rows as fit the window; nil without a window
    local function Sized(rect, lines, fontSize, above, below)
        if lines then
            if lines.shown < 1 then return 0 end
            local height = lines.shown * fontSize + (lines.shown - 1) * ROW_GAP + above + below
            if rect then height = math.max(height, rect[4] - rect[2]) end
            return lines.shown, height
        end
        if not rect then return nil end
        local fit = layout.Fit(rect[4] - rect[2] - above - below, fontSize, 0, ROW_GAP)
        if fit < 1 then return 0 end
        return fit, rect[4] - rect[2]
    end
    -- Follow Game: the game log's own size (its lines now, as it grows a row a message and shrinks to its fewest
    -- while none come: at 0, nothing drawn), the box no shorter than the game's window and tall enough for those
    -- rows at Font Size (or, with a uihook that does not say, as many rows as fit the game's window), the input
    -- bar's place and size the game's, and the second window where the game puts its own. WinXI Skin: Width and
    -- ten rows, or Window 1 Rows and Window 2 Rows. The WinXI look either way.
    local function MeasureFirst(c, sw, sh)
        local game = Game(app.options)
        c.game = game
        Paddings(app.options)
        Fill(logRect, primary.Rect(sw, sh))
        local lines = game and primary.Lines and primary.Lines() or nil
        if game then GameFontSize(#logRect == 4 and logRect or nil, lines) end
        local fontSize, padding = FontSize(), PADDING_DEFAULT
        c.fontSize, c.padding = fontSize, padding
        windowOptions.fontSize, windowOptions.padding = fontSize, padding
        appearance.Apply(windowOptions, app.options.appearance.log)
        splitOptions.fontSize, splitOptions.padding = fontSize, padding
        appearance.Apply(splitOptions, app.options.appearance.log)
        local rowCount = model.Rows
        -- Exact row heights and inter-row gaps, with only the room above and below around them.
        local above, below = pad.top, pad.bottom
        c.above, c.below = above, below
        local frameHeight = model.Rows * fontSize + (model.Rows - 1) * ROW_GAP + above + below
        size[1] = math.min(app.options.width[1], sw - 40)
        if game then
            local rows, height = Sized(#logRect == 4 and logRect or nil, lines, fontSize, above, below)
            if rows == 0 then
                c.firstHidden = true -- the game's log at 0 lines: nothing to draw, nothing shown
            elseif rows and #logRect == 4 then
                rowCount, frameHeight, size[1] = rows, height, logRect[3] - logRect[1]
            end
        else
            local customRows = app.options.window1Rows[1]
            if customRows > 0 then
                rowCount = customRows
                frameHeight = customRows * fontSize + (customRows - 1) * ROW_GAP + above + below
            end
        end
        size[2] = frameHeight
        local plan = input.Measure(size[1], sh, fontSize, padding, game, above, below)
        appearance.Apply(plan, app.options.appearance.input)
        plan.font = fonts.Get(app.options.fontFile)
        plan.leftPadding, plan.rightPadding = pad.left, pad.right
        c.plan = plan
        c.placeKnown = #logRect == 4
        -- Position Custom (the skin's): the box where it was dragged to, the input bar with it; the game's log must still be drawn
        local custom = not game and app.options.position[1] == 'custom' and app.options.pos or nil
        local box = layout.Arrange(layoutState, logRect, plan, size[1], sw, sh, size[2], padding, game, custom)
        c.panelBase = box
        anchorStatus = box and (custom and 'At its own place (Position Custom); the input bar with it.' or 'Anchored to native chat; log and input share one width.')
            or 'Native chat anchor unavailable or the log does not fit; native log left visible.'
        if c.firstHidden then box = nil; anchorStatus = 'The game\'s log is at 0 lines: nothing drawn, and nothing of the game\'s shown.' end
        c.box, c.rowCount = box, rowCount
    end
    -- The game's second log window, where it shows one: a box where the game puts its own beside the first,
    -- stacked over it (the game's vertical layout: its own width in Follow Game, over the first's top) or beside it
    -- (horizontal: the game's width for it, the game's gap from the first, the first's bottom); as tall as the
    -- game's (as many rows as fit) or ten rows; its messages the ones the game's Log Window settings route to it,
    -- the first's the ones routed there. A new table for the box each frame: held keeps it.
    local function MeasureSecond(c, sw, sh)
        local routes = primary.Routes and primary.Routes() or nil
        c.routes = routes
        Fill(splitRect, secondary.Rect(sw, sh))
        local box, game, fontSize, above, below = c.box, c.game, c.fontSize, c.above, c.below
        local second
        if routes and routes.split and #splitRect == 4 then
            local rows, height, secondHidden = model.Rows, model.Rows * fontSize + (model.Rows - 1) * ROW_GAP + above + below, false
            if game then
                local sized, tall = Sized(splitRect, secondary.Lines and secondary.Lines() or nil, fontSize, above, below)
                if sized == 0 then secondHidden = true elseif sized then rows, height = sized, tall end
            else
                local customSecondRows = app.options.window2Rows[1]
                if customSecondRows > 0 then
                    rows = customSecondRows
                    height = rows * fontSize + (rows - 1) * ROW_GAP + above + below
                end
            end
            if secondHidden then
                splitStatus = 'Second window: the game\'s is at 0 lines; nothing drawn, and nothing of the game\'s shown.'
            elseif c.firstHidden then
                -- the first at 0 lines: the second where the game draws its own, as it is the one log window shown
                second = { left = splitRect[1], width = splitRect[3] - splitRect[1], bottom = splitRect[4], top = splitRect[4] - height, height = height, rows = rows }
                splitStatus = ('Second window: in the game\'s place, %d rows, the first at 0 lines; the game\'s Log Window settings route its messages.'):format(rows)
            elseif box and #logRect == 4 then
                local beside = splitRect[4] > logRect[2] + 2 -- not wholly above the first: the game's horizontal layout
                if not beside then
                    local width = game and (splitRect[3] - splitRect[1]) or box.width
                    local left = game and (box.left + splitRect[1] - logRect[1]) or box.left
                    if left >= 0 and left + width <= sw and box.top - height >= 0 then
                        second = { left = left, width = width, bottom = box.top, top = box.top - height, height = height, rows = rows }
                        splitStatus = ('Second window: over the first, %d rows; the game\'s Log Window settings route its messages.'):format(rows)
                    else
                        splitStatus = 'Second window: no room above the first; the game\'s is left visible.'
                    end
                else
                    local width = splitRect[3] - splitRect[1]
                    local left
                    if splitRect[1] >= logRect[3] - 2 then left = box.left + box.width + (splitRect[1] - logRect[3]) -- to the right of the first
                    elseif splitRect[3] <= logRect[1] + 2 then left = box.left - (logRect[1] - splitRect[3]) - width -- to its left
                    else left = game and splitRect[1] or box.left + box.width end -- overlapping the first: the game's place, or its right
                    if left >= 0 and left + width <= sw and box.bottom - height >= 0 then
                        second = { left = left, width = width, bottom = box.bottom, top = box.bottom - height, height = height, rows = rows }
                        splitStatus = ('Second window: beside the first, %d rows; the game\'s Log Window settings route its messages.'):format(rows)
                    else
                        splitStatus = 'Second window: no room beside the first; the game\'s is left visible.'
                    end
                end
            end
        elseif routes and routes.split then
            splitStatus = 'Second window: the game shows one, but its place is not known; the game\'s is left visible.'
        elseif #splitRect == 4 and not routes then
            splitStatus = 'Second window: hidden; uihook has no window routing.'
        else
            splitStatus = 'Second window: none; the game shows one log window.'
        end
        c.second = second
    end
    -- The boxes kept (held) as they are drawn; opening or closing the full log, the game's new place is not known for
    -- a frame or two: the last box stays rather than the game's own log showing through.
    local function HoldBox(c, sh)
        if c.box then
            held = heldBox
            held.box, held.rows, held.second, held.frame = c.box, c.rowCount, c.second, frame
        elseif not c.firstHidden and held and not c.placeKnown and frame - held.frame <= HOLD_FRAMES and held.box.bottom <= sh then
            c.box, c.rowCount, c.second = held.box, held.rows, held.second
            anchorStatus = 'Waiting a moment for the game\'s log to settle.'
        end
    end
    -- Activity's measure of a window's recent messages (the rows they wrap to in the box being sized, the scrollbar's
    -- room taken where they overflow it) or of a number of rows (the height they take)
    local function RecentTotal(recent, width, font, fontSize, capacity)
        local metrics = model.Metrics(recent, width, font, fontSize, render.Measure)
        if metrics.total > capacity then
            metrics = model.Metrics(recent, math.max(1, width - scrollbar.Reserve), font, fontSize, render.Measure)
        end
        return metrics.total
    end
    local function MeasureRecent(recent, rows)
        local c = compact
        local fontSize, plan = c.fontSize, c.plan
        if not recent then return rows * fontSize + (rows - 1) * ROW_GAP + c.above + c.below end
        model.ShowStamps(recent, app.options.timestamps[1])
        local width = math.max(1, c.measureBox.width - pad.left - pad.right)
        if plan.font then imgui.PushFont(plan.font, fontSize) end
        local ok, total = pcall(RecentTotal, recent, width, plan.font, fontSize, c.measureCapacity)
        if plan.font then imgui.PopFont() end
        if not ok then error(total, 0) end
        return total
    end
    -- One window's Activity: the box as Auto Resize sizes it (nil while hidden) and its rows, its alpha on its style
    local function Smart(c, number, b, capacity, style)
        local view = views[number]
        view.visibility = view.visibility or {}
        local settings = not c.game and app.options.visibility and app.options.visibility[WINDOW_KEYS[number]] or nil
        local state = c.state
        local active = c.plan.active or (state and state.selected and (not state.selectedWindow or state.selectedWindow == number))
            or view.offset > 0 or view.drag ~= nil or view.pressed ~= nil
        c.measureBox, c.measureCapacity = b, capacity -- for MeasureRecent, which visibility.Apply calls before it returns
        local result, rows, alpha = visibility.Apply(view.visibility, settings, history, Filter(c.routes, number), b, capacity, c.now, active, MeasureRecent)
        style.alpha = alpha
        return result, rows
    end
    -- Activity (the skin's) runs only on compact boxes; native capture remains armed even at zero opacity. The second
    -- box stacked over the first moves with the first's top (a copy: the box held, or one a panel keeps, is not moved).
    local function Activity(c)
        local box, second = c.box, c.second
        local stacked = second and box and #splitRect == 4 and #logRect == 4 and splitRect[4] <= logRect[2] + 2
        c.panelBase = box or c.panelBase
        local oldTop, oldBottom = box and box.top, box and box.bottom
        c.now = os.clock()
        box, c.rowCount = Smart(c, 1, box, c.rowCount, windowOptions)
        if second then
            if stacked then
                local shifted = {}
                for k, v in pairs(second) do shifted[k] = v end
                local shift = (box and box.top or oldBottom) - oldTop
                shifted.top, shifted.bottom = second.top + shift, second.bottom + shift
                second = shifted
            end
            local rows
            second, rows = Smart(c, 2, second, second.rows, splitOptions)
            if second then second.rows = rows end
        end
        if oldTop and not box then c.firstHidden = true; lastDrawn = nil end
        c.box, c.second = box, second
    end
    -- A box lifted over the panel, into a table of its own (cleared first), or nil
    local function Lifted(b, lift, into)
        if not b then return nil end
        for k in pairs(into) do into[k] = nil end
        for k, v in pairs(b) do into[k] = v end
        into.top, into.bottom = b.top - lift, b.bottom - lift
        return into
    end
    -- The expanded log's place, kept in one table
    local function SetExpandPlace(left, bottom)
        if not expandPlace then expandPlace = {} end
        expandPlace.left, expandPlace.bottom = left, bottom
    end
    -- Open, the input is lifted onto the panel, which keeps the input's bottom; the logs above the input. An attached
    -- panel takes the bottom of the logs' place: both boxes drawn wholly above it (copies, so a held box is not lifted
    -- twice). Where the expanded log will open is asked for already, so the game lays it out there from its first frame.
    local function PanelAndLift(c)
        local box, second, plan, panelBase = c.box, c.second, c.plan, c.panelBase
        local open = plan.active and box ~= nil
        local panelOnly = not box and not second and panelBase ~= nil
        local panelHost, panelSplit = box, second
        if panelOnly then
            -- Keep only a zero-height layout anchor, not the old chat height or padding.
            panelHost = { left = panelBase.left, width = panelBase.width, top = panelBase.bottom,
                bottom = panelBase.bottom, height = 0 }
            local routes = c.routes
            if routes and routes.split and #splitRect == 4 and #logRect == 4 and splitRect[4] > logRect[2] + 2 then
                panelSplit = { left = splitRect[1], width = splitRect[3] - splitRect[1], top = panelBase.bottom,
                    bottom = panelBase.bottom, height = 0 }
            end
        end
        panelAttachment = infoPanel.Prepare(app.options.infoPanel, panelHost, panelSplit, plan.height, c.fontSize, app.options.fontFile,
            open and plan.bottom or nil)
        local lift = panelAttachment and panelAttachment.lift or 0
        if panelAttachment then plan.bottom = plan.bottom - panelAttachment.inputLift end -- this frame's plan, measured afresh each frame
        if lift > 0 then box, second = Lifted(box, lift, liftedFirst), Lifted(second, lift, liftedSecond) end
        if box and not open then SetExpandPlace(box.left, box.bottom + lift)
        elseif panelOnly and not open then SetExpandPlace(panelHost.left, panelHost.bottom) end
        PlaceLog(app.options)
        c.box, c.second, c.open, c.panelOnly = box, second, open, panelOnly
    end
    -- Each window's contents, drawn inside it (with the chat's font pushed round the log), then its panel slot
    local function DrawFirstWindow()
        local c = compact
        local chatFont = c.chatFont
        if chatFont then imgui.PushFont(chatFont, c.fontSize) end
        local drawn, drawError = pcall(DrawLog, c.box, c.rowCount, c.fontSize, c.padding, views[1], Filter(c.routes, 1), c.litFirst, windowOptions)
        if chatFont then imgui.PopFont() end
        if not drawn then error(drawError, 0) end
        infoPanel.Draw(panelAttachment, 0) -- under the lifted log, on its capture
    end
    local function DrawSecondWindow()
        local c = compact
        local chatFont, second = c.chatFont, c.second
        if chatFont then imgui.PushFont(chatFont, c.fontSize) end
        local drawn, drawError = pcall(DrawLog, second, second.rows, c.fontSize, c.padding, views[2], Filter(c.routes, 2), selectedWindow == 2, splitOptions)
        if chatFont then imgui.PopFont() end
        if not drawn then error(drawError, 0) end
        infoPanel.Draw(panelAttachment, 1)
    end
    -- a panel drawn on its own (no log above it), by its slot, and its window's name: each made once
    local panelDraws, panelNames = {}, {}
    local function PanelDraw(slot)
        local draw = panelDraws[slot]
        if not draw then
            draw = function() infoPanel.Draw(panelAttachment, slot) end
            panelDraws[slot], panelNames[slot] = draw, 'winxi.chatbox.panel.' .. slot
        end
        return draw, panelNames[slot]
    end
    -- The windows: the first box, the second with the first's or on its own while the first is at 0 lines, or the
    -- panel alone
    local function DrawBoxes(c)
        local box, second, state = c.box, c.second, c.state
        if box then
            place[1], place[2] = box.left, box.bottom
            size[1], size[2] = box.width, box.height
            selectedWindow = state ~= nil and state.selectedWindow or nil
            -- the light and cursor on the window the game's focus is on; on the first while the second is not drawn
            c.litFirst = selectedWindow ~= nil and (selectedWindow == 1 or not second)
            local plan = c.plan
            windowOptions.title = OwnTitle(app.options.windowTitle) or channels.Title(plan.snapshot and channels.Typed(plan.snapshot.text) or selectedMode or spoken)
            imgui.SetNextWindowPos(place, ImGuiCond_Always, pivot)
            imgui.SetNextWindowSize(size, ImGuiCond_Always)
            c.chatFont = plan.font
            window.Plain('winxi.chatbox', c.open, flags, DrawFirstWindow, windowOptions)
            lastDrawn = views[1].drawn
        end
        if c.firstHidden then lastDrawn = nil; selectedWindow = state ~= nil and state.selectedWindow or nil end
        if second and (captured or c.firstHidden) and secondary.Begin() then
            c.chatFont = c.plan.font
            splitOptions.title = OwnTitle(app.options.splitTitle) or 'Window 2'
            splitPlace[1], splitPlace[2] = second.left, second.bottom
            imgui.SetNextWindowPos(splitPlace, ImGuiCond_Always, pivot)
            splitSize[1], splitSize[2] = second.width, second.height
            imgui.SetNextWindowSize(splitSize, ImGuiCond_Always)
            window.Plain('winxi.chatbox.split', c.open, flags, DrawSecondWindow, splitOptions)
            c.splitDrawn = capturedSplit
            lastSplit = views[2].drawn
        end
        if c.panelOnly and panelAttachment then
            lastDrawn, lastSplit = nil, nil
            for _, panel in ipairs(panelAttachment.panels) do
                local slot, rect = panel.slot, panel.rect
                if slot == 0 or secondary.Begin() then
                    panelPlace[1], panelPlace[2] = rect.left, rect.top + rect.height
                    imgui.SetNextWindowPos(panelPlace, ImGuiCond_Always, pivot)
                    panelSize[1], panelSize[2] = rect.width, rect.height
                    imgui.SetNextWindowSize(panelSize, ImGuiCond_Always)
                    local draw, name = PanelDraw(slot)
                    window.Plain(name, false, flags, draw, panelOnlyOptions[slot + 1])
                    if slot == 1 then c.splitDrawn = capturedSplit end
                end
            end
        end
    end
    -- The frame's drawing, called through pcall: the expanded log, or the compact boxes phase by phase and the input bar
    local function DrawFrame()
        local display = imgui.GetIO().DisplaySize
        local sw, sh = display.x or display[1], display.y or display[2]
        if not sw or not sh or sw < 100 or sh < 100 then input.Stop(); return end
        local state = primary.State()
        local expanded = state and state.expanded
        frame = frame + 1
        if expanded then DrawExpanded(state, sw, sh); return end
        -- ImGui's normal minimum is taller than a one-row log or panel-only host.
        imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, MIN_SIZE)
        local c = compact
        c.compactMinSize = true
        c.state = state
        MeasureFirst(c, sw, sh)
        MeasureSecond(c, sw, sh)
        HoldBox(c, sh)
        Activity(c)
        PanelAndLift(c)
        DrawBoxes(c)
        -- Input is independent: keep it working while waiting for the log's first geometry sample.
        c.inputDrawn = input.Draw(c.plan.width, sh, c.fontSize, c.padding, flags, c.game, c.plan) == true
        -- The picker only over the bar: a frame without it (closed, expanded, a failed capture) closes it, below
        if c.inputDrawn then DrawPicker(c.plan) end
    end
    -- The tooltips, drawn past every window
    local function Tooltips()
        infoPanel.Tooltip()
        ChatTooltip()
    end
    local function Present()
        for _, view in ipairs(views) do view.target = nil end -- rearmed only after this frame captures a complete replacement
        hovered.text, hovered.row, hovered.view, hovered.expanded, hovered.mirror = nil, nil, nil, false, false -- found again as this frame's logs are drawn
        app:BeginFrame() -- configures WinXI's shared/local theme and draws settings
        infoPanel.BeginFrame() -- renew menu placement only with this frame's successful host capture
        DrainTap() -- the frame's lines as uihook has them after every addon, or chatbox's own copies
        if not app.options.enabled[1] or zoning then Release(); return end
        infoPanel.Hud(app.options.infoPanel) -- Hide Game Clock and Hide Compass, with or without the panel or chat's capture
        ImportHistory() -- the game's history before chatbox's own, once
        if not primary.Begin() then
            ResetViews(false)
            ClosePicker()
            secondary.Stop(); input.Stop(); return
        end
        captured, capturedSplit, selectedWindow, panelAttachment = false, false, nil, nil
        palette.Source(primary.Colors and primary.Colors() or nil) -- the game's chat colours as configured, where uihook reads them
        local c = compact
        c.splitDrawn, c.firstHidden, c.compactMinSize, c.inputDrawn = false, false, false, false
        local ok, err = pcall(DrawFrame)
        if not c.inputDrawn then ClosePicker() end
        if c.compactMinSize then imgui.PopStyleVar() end
        if not ok then Release(); error(err, 0) end
        -- The first log at 0 lines keeps Begin's empty hide, so nothing of the game's shows in its place either
        if not captured and not c.firstHidden then
            ResetViews(false)
            primary.Stop()
            secondary.Stop()
            return
        end
        -- One box or two: the game's second log window is drawn as the second box where the game shows one and
        -- uihook says how the game routes between them; otherwise it is hidden rather than left as a duplicate
        -- under the first. Only hide it after a complete primary capture succeeded (or the first is at 0 lines).
        if c.firstHidden or (lastDrawn and not lastDrawn.expanded) then
            if not c.splitDrawn then secondary.Begin() end
            views[1].target = captured and lastDrawn or nil
            views[2].target = c.splitDrawn and lastSplit or nil
        end
        -- The tooltips are drawn here, past every window, where no font of winxi's is pushed: the theme's goes round them,
        -- as a tooltip in a themed window has it (winxi.tooltip keeps the font it finds unless Tooltip Font Size says otherwise)
        local themeFont = fonts.Push(false)
        ok, err = pcall(Tooltips)
        fonts.Pop(themeFont)
        if not ok then error(err, 0) end
    end
    ashita.events.register('d3d_present', 'chatbox_present', Present)
end

-- Only the wheel over an overflowing box and left-button interactions with its scrollbar are taken; each box
-- has its own. All other mouse input stays native. true when the event was taken.
local function Scroll(view, box, e, x, y)
    local bar, message = box.scrollbar, e.message
    if view.pressed and message == 0x0202 then -- left up, including outside the log
        view.drag, view.pressed = nil, nil
        e.blocked = true
        return true
    end
    if view.drag and message == 0x0200 and bar and y then
        view.pendingScroll = scrollbar.Drag(bar,y,view.drag)
        e.blocked = true
        return true
    end
    if message == 0x0201 and scrollbar.Hit(bar,x,y) then
        view.pressed = true
        if y >= bar.thumbTop and y < bar.thumbBottom then
            view.drag = y-bar.thumbTop
        else
            view.pendingScroll = scrollbar.Page(bar,y)
        end
        e.blocked = true
        return true
    end
    if message ~= 0x020a or not x or not y or x < box.left or x >= box.left + box.width
        or y < box.top or y >= box.bottom or not box.overflow then return false end
    -- Ashita exposes the signed wheel delta; wparam is a fallback for raw WNDPROC events.
    local delta = tonumber(e.delta)
    if not delta and e.wparam then delta = bit.arshift(tonumber(e.wparam), 16) end
    if not delta or delta == 0 then return false end
    view.pending = view.pending + delta / 120 * 3
    e.blocked = true -- never scroll native history underneath the themed viewport
    return true
end
-- Lock Window off (WinXI Skin): the log taken hold of with the left button anywhere on it but its scrollbar and dragged
-- wherever you want, its bottom-left (before any lift over the input bar or the panel) kept as the place and Position
-- made Custom from the first drag; the second window and the input bar go with it. Let go, the place is saved. true
-- when the event was taken.
local function Drag(e, x, y, captured)
    local message = e.message
    if moving then
        if message == 0x0200 then
            if x and y then app.options.pos[1], app.options.pos[2] = math.floor(x - moving[1] + 0.5), math.floor(y - moving[2] + 0.5) end
        elseif message == 0x0202 then
            moving = nil
            app.save()
        else return false end
        e.blocked = true
        return true
    end
    if message ~= 0x0201 or captured or Game(app.options) or app.options.locked[1] then return false end
    local box = views[1].target
    if not box or not x or not y or x < box.left or x >= box.left + box.width or y < box.top or y >= box.bottom
        or scrollbar.Hit(box.scrollbar, x, y) then return false end
    local pos = app.options.pos
    if app.options.position[1] ~= 'custom' then
        pos[1], pos[2] = math.floor(layoutState.left or box.left), math.floor(layoutState.closedBottom or box.bottom)
        app.options.position[1] = 'custom'
    end
    moving = { x - pos[1], y - pos[2] }
    e.blocked = true
    return true
end
-- The expanded log with its rows the addon's (Replace Expanded Log): they stand at the chat's own pitch, not the
-- game's 16 units, so the game's hover and clicks would land on other rows than the ones shown. Every mouse message
-- but the wheels (0x020a, 0x020e) is kept from the game over the rows: its moves, and the presses and double-clicks
-- of each button (left, right, middle and the side ones), along with the release of every press kept, wherever it
-- is let go; a release of a press the game had goes to it, wherever it is let go, and a move goes through while a
-- press the game had is held (its scrollbar dragged off the bar, or the camera turned across the log). The game's
-- scrollbar (a few pixels round it) and its tabs are its own, and so is the mouse while a menu of the game's (a
-- row's action menu, the input line) is open over the log. The wheel scrolls whatever the rows' places, and Square,
-- the arrows and Confirm still choose rows. The game's state is read only for a move or press over the log's box.
local MOUSE_BUTTON = { [0x0201] = 1, [0x0202] = 1, [0x0203] = 1, [0x0204] = 2, [0x0205] = 2, [0x0206] = 2,
    [0x0207] = 3, [0x0208] = 3, [0x0209] = 3, [0x020b] = 4, [0x020c] = 4, [0x020d] = 4 }
local MOUSE_UP = { [0x0202] = true, [0x0205] = true, [0x0208] = true, [0x020c] = true }
local MOUSE_DOUBLE = { [0x0203] = true, [0x0206] = true, [0x0209] = true, [0x020d] = true }
local MOUSE_HELD = { 0x0001, 0x0002, 0x0010, 0x0060 } -- each button's MK_ bits in a move's wparam
local SCROLL_MARGIN = 4 -- round the game's scrollbar, still the game's
-- by button: its press kept from the game and still held; whether its last press was kept; a press the game had, held
local keptHeld, keptLast, passedHeld = { false, false, false, false }, { false, false, false, false }, { false, false, false, false }
local keptCount, passedCount = 0, 0
local function Inside(x, y, left, top, right, bottom) return x >= left and x < right and y >= top and y < bottom end
-- The mouse over the mirrored log's rows, and the game's state lets it be kept: the box first, then the game's
-- scrollbar and tabs, and only then the state
local function OverMirror()
    if not hovered.mirror then return false end
    local mouse = imgui.GetIO().MousePos
    local x, y = mouse and (mouse.x or mouse[1]), mouse and (mouse.y or mouse[2])
    if not x or not y or not Inside(x, y, expandedBox[1], expandedBox[2], expandedBox[3], expandedBox[4]) then return false end
    local s = expandedScroll
    if s and Inside(x, y, s.left - SCROLL_MARGIN, s.top - SCROLL_MARGIN, s.right + SCROLL_MARGIN, s.bottom + SCROLL_MARGIN) then return false end
    if expandedTabs then
        for _, tab in ipairs(expandedTabs) do
            if Inside(x, y, tab.left, tab.top, tab.right, tab.bottom) then return false end
        end
    end
    local state = primary.State()
    return state ~= nil and state.expanded == true and not state.nativeBrowse and not state.nested
end
-- a button pressed (kept from the game, or let through to it) or let go (neither)
local function Hold(button, kept, through)
    if keptHeld[button] then keptCount = keptCount - 1 end
    if passedHeld[button] then passedCount = passedCount - 1 end
    keptHeld[button], passedHeld[button] = kept, through and not kept
    if kept then keptCount = keptCount + 1 elseif through then passedCount = passedCount + 1 end
end
-- true when the event was kept from the game
local function KeepExpandedMouse(e, message)
    if message == 0x0200 then
        if keptCount > 0 then
            local held = tonumber(e.wparam)
            if held then -- a release missed (let go outside the game's window): forgotten
                for button = 1, 4 do
                    if keptHeld[button] and bit.band(held, MOUSE_HELD[button]) == 0 then Hold(button, false, false) end
                end
            end
            if keptCount > 0 then e.blocked = true; return true end
        end
        if passedCount > 0 or e.blocked or not OverMirror() then return false end
        e.blocked = true
        return true
    end
    local button = MOUSE_BUTTON[message]
    if MOUSE_UP[message] then
        local kept = keptHeld[button]
        Hold(button, false, false)
        if kept then e.blocked = true end
        return kept
    end
    -- a press, or a double-click (the second press of one): kept over the rows, and a double-click as its first press was
    local kept = not e.blocked and (OverMirror() or (MOUSE_DOUBLE[message] and keptLast[button])) or false
    Hold(button, kept, not e.blocked)
    keptLast[button] = kept
    if kept then e.blocked = true end
    return kept
end
ashita.events.register('mouse', 'chatbox_scroll', function(e)
    local message = e.message
    if (MOUSE_BUTTON[message] or (message == 0x0200 and (hovered.mirror or keptCount > 0))) and KeepExpandedMouse(e, message) then return end
    if e.blocked or not app.options.enabled[1] or zoning then return end
    -- Only the wheel, a left press, its release and a drag (the scrollbar's, or the log's) are ever taken: anything
    -- else, most of all the mouse moving, is let by before the game's state is read
    if message == 0x0200 then
        if not (moving or views[1].drag or views[2].drag) then return end
    elseif message == 0x0202 then
        if not (moving or views[1].pressed or views[2].pressed) then return end
    elseif message ~= 0x0201 and message ~= 0x020a then return end
    local state = primary.State()
    if state and (state.expanded or state.nativeBrowse) then
        for _, view in ipairs(views) do view.drag, view.pressed = nil, nil end
        moving = nil
        return
    end
    local io = imgui.GetIO()
    local mouse = io.MousePos
    local x, y = mouse and (mouse.x or mouse[1]), mouse and (mouse.y or mouse[2])
    if Drag(e, x, y, io.WantCaptureMouse) then return end
    for _, view in ipairs(views) do
        if view.target and (not io.WantCaptureMouse or view.pressed) and Scroll(view, view.target, e, x, y) then return end
    end
end)

-- Auto-Translate's keys. While the game's input is open and the setting is on, Tab is kept from the game in every
-- form (its press, repeats, release and the character it types), so the game's own menu never opens and the bar
-- stays chatbox's; a press opens the picker or moves it. While the picker is open, Up, Down, Page Up, Page Down,
-- Enter and Escape are its own. Tab, Enter and Escape act once a press and are then kept from the game until they
-- are let go: the character each types comes as a second press with the same lparam, and Enter's, reaching the game
-- after the phrase is in and the picker closed, would send the line. A taken key pressed afresh well after (its
-- release missed, the window having lost focus) is a new press. The arrows and pages type nothing and move on every
-- repeat. Anything else is the game's.
local VK_TAB = 9
local VK_SHIFTS = { [16] = true, [160] = true, [161] = true }
local PICKER_KEYS = { [38] = 'up', [40] = 'down', [33] = 'pageUp', [34] = 'pageDown', [13] = 'enter', [27] = 'escape' }
local ONCE = { [VK_TAB] = true, [13] = true, [27] = true }
local TAKEN_AFRESH = 0.25 -- seconds after which a taken key's fresh press is a new one
-- DirectInput's ids for the same keys: Tab, and the picker's (both Enters), each kept by the same rule
local DIK_TAB = 0x0F
local DIK_PICKER = { [0xC8] = 38, [0xD0] = 40, [0xC9] = 33, [0xD1] = 34, [0x1C] = 13, [0x9C] = 13, [0x01] = 27 }
local function InputOpen()
    local ok, state = pcall(function() return AshitaCore:GetChatManager():IsInputOpen() end)
    return ok and state == 0x11
end
local function Translating() return app.options.enabled[1] and app.options.autoTranslate[1] and not zoning end
local function Act(action)
    if action == 'up' then Use('Move', -1)
    elseif action == 'down' then Use('Move', 1)
    elseif action == 'pageUp' then Use('Page', -1)
    elseif action == 'pageDown' then Use('Page', 1)
    elseif action == 'enter' then
        -- The buffer as it is now, not as the last frame saw it: a letter typed since would be left beside the token
        local raw, caret = ReadInput()
        if raw then Use('Refresh', raw, caret) end
        local ok, chat = pcall(function() return AshitaCore:GetChatManager() end)
        if ok and chat and PickerOpen() then Use('Enter', chat) else ClosePicker() end
    elseif action == 'escape' then Use('Back') end
end
ashita.events.register('key', 'chatbox_translate', function(e)
    local vk, lparam = tonumber(e.wparam) or 0, tonumber(e.lparam) or 0
    local up, repeated = bit.band(lparam, 0x80000000) ~= 0, bit.band(lparam, 0x40000000) ~= 0
    if VK_SHIFTS[vk] then shiftHeld = not up end
    local since = taken[vk]
    if since and (up or repeated or os.clock() - since < TAKEN_AFRESH) then
        e.blocked = true
        if up then taken[vk] = nil end
        return
    end
    taken[vk] = nil
    if e.blocked or not Translating() then return end
    if not InputOpen() then return ClosePicker() end
    if vk == VK_TAB then
        if not Picker() then return end -- no dictionary: Tab stays the game's
        e.blocked = true
        if up or repeated then return end
        taken[vk] = os.clock()
        if PickerOpen() then return Use('Move', shiftHeld and -1 or 1) end
        local raw, caret = ReadInput()
        if raw then Use('Open', raw, caret) else ClosePicker() end
        return
    end
    local action = PickerOpen() and PICKER_KEYS[vk]
    if not action then return end
    e.blocked = true
    if up or (repeated and ONCE[vk]) then return end
    if ONCE[vk] then taken[vk] = os.clock() end
    Act(action)
end)
-- The game's buttons come through DirectInput: Tab, and the picker's keys while it is open or taken, are kept from
-- that path as well, so the game never sees half of a key the picker has
ashita.events.register('key_data', 'chatbox_translate_data', function(e)
    if e.blocked then return end
    local key = tonumber(e.key)
    if key == DIK_TAB then
        if Translating() and InputOpen() and Picker() then e.blocked = true end
        return
    end
    local vk = DIK_PICKER[key]
    if vk and (taken[vk] or (PickerOpen() and Translating() and InputOpen())) then e.blocked = true end
end)
