addon.name = 'chatbox'
addon.author = 'win'
addon.version = '0.11.3'
addon.desc = 'WinXI native-backed chat, input and expanded history, with an optional chat-owned three-slot info panel.'
local winxiNeeded = 25
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
    if options.expandInPlace[1] and expandPlace then menus.PlaceLog(expandPlace.left, expandPlace.bottom)
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
local function Release()
    held, panelAttachment = nil, nil
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
                entries[#entries + 1] = { text = text, mode = mode, originalMode = mode, spans = spans, raw = message.mode }
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
local function Status()
    local size = app.options.matchGameLogSize[1] and 'the game log\'s size' or '10 rows'
    app:Say((app.options.enabled[1] and 'On' or 'Off') .. '. Compact at ' .. size .. ', native-controlled expansion; ' .. #history.messages .. ' messages retained.')
    app:Say(primary.Status())
    app:Say(anchorStatus)
    app:Say('Input: ' .. input.Status())
    app:Say('Lines: ' .. TapStatus() .. '.')
    app:Say('Game history: ' .. import.status .. '.')
    app:Say('Info Panel: ' .. (app.options.infoPanel.layout.enabled[1] and infoPanel.Status() or 'off'))
    app:Say('Game Clock: ' .. infoPanel.HudStatus(app.options.infoPanel, 'clock'))
    app:Say('Compass: ' .. infoPanel.HudStatus(app.options.infoPanel, 'compass'))
    if lastDrawn then
        local d = lastDrawn
        app:Say(('Last box (%s, %d frames ago): %d,%d to %d,%d, %d rows of room, %d drawn from y %d; titled %s.')
            :format(d.expanded and 'expanded' or 'compact', frame - d.frame, d.left, d.top, d.left + d.width, d.bottom,
                d.rows, d.drawn, d.firstY, d.title))
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
local function VisibilitySettings(options, number)
    local id = '##chatbox.visibility.' .. number
    widgets.Label('Window ' .. number .. ' Auto Resize')
    if imgui.Checkbox(id .. '.resize', options.resize) then app.save() end
    Tip('Grows with recent messages routed to this window, up to its configured size; shrinks as those messages age out. Retained history is not deleted.')
    widgets.Label('Animate Resize')
    if imgui.Checkbox(id .. '.animate', options.animate) then app.save() end
    Tip('Auto Resize only: smoothly grows and shrinks this box from its bottom edge. Typing, selecting or scrolling restores the full size immediately.')
    widgets.Label('Resize Duration')
    imgui.SliderFloat(id .. '.resizeDuration', options.resizeDuration, 0.05, 2, '%.2f s')
    if imgui.IsItemDeactivatedAfterEdit() then app.save() end
    Tip('Time for a grow or shrink animation; independent of Fade Duration.')
    widgets.Label('Window ' .. number .. ' Fade When Idle')
    if imgui.Checkbox(id .. '.fade', options.fade) then app.save() end
    Tip('Fades this log and its attached panel out when no messages reach it. New messages fade it back in. Typing, selecting or scrolling the log keeps it visible. Expanded history is unaffected.')
    widgets.Label('Idle Time (seconds)')
    imgui.SliderInt(id .. '.idle', options.idle, 1, 300, '%d s')
    if imgui.IsItemDeactivatedAfterEdit() then app.save() end
    Tip('Messages remain recent for this long. Auto Resize uses recent wrapped rows; Fade When Idle starts fading after this delay.')
    widgets.Label('Fade Duration')
    imgui.SliderFloat(id .. '.duration', options.duration, 0.1, 10, '%.1f s')
    if imgui.IsItemDeactivatedAfterEdit() then app.save() end
    widgets.Label('Minimum Rows')
    imgui.SliderInt(id .. '.minimum', options.minimum, 0, 50, '%d')
    if imgui.IsItemDeactivatedAfterEdit() then app.save() end
    Tip('Auto Resize only: rows left when idle, capped at the window\'s normal capacity. Zero hides the log completely. Typing or selecting restores the full size.')
end
app = shell.New({
    defaults = T{ enabled = T{ true }, timestamps = T{ true }, width = T{ 640 }, followNativeSettings = T{}, matchGameLogSize = T{ true }, matchGameInputSize = T{ false }, fontSize = T{ 12 },
        replaceTabs = T{ true }, replaceScrollbar = T{ true }, replaceText = T{ true }, replaceCursor = T{ true }, expandInPlace = T{ true }, expandedHeight = T{ 75 },
        appearance = appearance.Defaults(T, theme.Get()), fontFile = '', infoPanel = panelModel.Defaults(),
        visibility = { window1 = visibility.Defaults(), window2 = visibility.Defaults() },
        window1Rows = T{ 0 }, window2Rows = T{ 0 },
        leftPadding = T{ 3 }, rightPadding = T{ 3 }, topPadding = T{ 3 }, bottomPadding = T{ 3 }, paddingVersion = T{ 0 },
        windowTitle = T{ '' }, splitTitle = T{ '' } },
    command = '/chatbox',
    configTitle = 'Chatbox Settings',
    help = '/chatbox opens settings; /chatbox on, off, clear, status, modes, bytes; /chatbox timestamps [on|off] shows or hides the timestamps SimpleLog or the timestamp addon write; /chatbox panel [on|off|reset] controls the optional info panel; /chatbox clock and /chatbox compass [hide|show] the game\'s. Native selection, expansion and input controls.',
    drawSettings = function(options)
        if widgets.Header('Chatbox', true) then
            widgets.Label('Replace Native Chat')
            if imgui.Checkbox('##chatbox.enabled', options.enabled) then
                if not options.enabled[1] then Release() end
                app.save()
            end
            Tip('Draws the WinXI log and input bar in place of the game\'s own.\nOff, the game\'s chat log and input come back at once. /chatbox on and off do the same.')
            widgets.Label('Timestamps')
            if imgui.Checkbox('##chatbox.timestamps', options.timestamps) then model.ShowStamps(history, options.timestamps[1]); app.save() end
            Tip('Shows timestamps supplied by either SimpleLog or the timestamp addon, including their original format and colours.\nEnable timestamps in one of those addons; chatbox adds none of its own. Avoid enabling both providers to prevent duplicates.\nOff, timestamps are hidden in the compact, second and expanded logs without deleting them. /chatbox timestamps on and off do the same.')
            widgets.Label('Window Title')
            imgui.InputText('##chatbox.windowTitle', options.windowTitle, TITLE_LONGEST)
            if imgui.IsItemDeactivatedAfterEdit() then app.save() end
            Tip('The words on the compact log\'s top edge. Left empty, the channel you are speaking in, as /cm and /p, /l, /t and the like set it.')
            widgets.Label('Window 2 Title')
            imgui.InputText('##chatbox.splitTitle', options.splitTitle, TITLE_LONGEST)
            if imgui.IsItemDeactivatedAfterEdit() then app.save() end
            Tip('The words on the second log window\'s top edge, with the game\'s Log Window 2 on. Left empty, Window 2.')
            imgui.TextDisabled('Native Square/window selection, confirm to expand, cancel to close.')
            imgui.TextDisabled(primary.Status())
        end
        if widgets.Header('Native Behaviour') then
            widgets.Label('Follow Native Settings')
            if imgui.Checkbox('##chatbox.followNativeSettings', options.followNativeSettings) then
                options.matchGameLogSize[1], options.matchGameInputSize[1] = options.followNativeSettings[1], options.followNativeSettings[1]
                app.save()
            end
            Tip('Follows the game\'s log sizes, content-driven growth/shrinking and input geometry.\nCustom sizing, resizing and fading are disabled while enabled; their saved values are retained.\nOff: use Custom Behaviour for width, row counts and activity controls. Text, padding and appearance remain shared.')
        end
        if widgets.Header('Custom Behaviour') then
            imgui.TextDisabled('Independent sizing and per-window activity controls.')
            if options.followNativeSettings[1] then imgui.TextDisabled('Turn off Follow Native Settings to edit these controls.') end
            imgui.BeginDisabled(options.followNativeSettings[1])
            widgets.Label('Width')
            imgui.SliderInt('##chatbox.width', options.width, 240, 1200, '%d px')
            if imgui.IsItemDeactivatedAfterEdit() then app.save() end
            Tip('How wide the compact log, input bar and expanded view are, in pixels, with Follow Native Settings off. The expanded view clips native history rows to this width; the game still controls their wrapping and hit-tests.')
            for number = 1, 2 do
                widgets.Label('Window ' .. number .. ' Rows')
                local rows = options['window' .. number .. 'Rows']
                imgui.SliderInt('##chatbox.window' .. number .. 'Rows', rows, 0, 50, rows[1] == 0 and 'Automatic' or '%d rows')
                if imgui.IsItemDeactivatedAfterEdit() then app.save() end
                Tip('Zero uses ten rows. A custom count sets this window\'s height without changing its width. With Auto Resize, this is the maximum number of rows. Expanded history is unaffected.')
            end
            imgui.TextDisabled('Content-driven resizing and fading (custom mode only).')
            VisibilitySettings(options.visibility.window1, 1)
            VisibilitySettings(options.visibility.window2, 2)
            imgui.EndDisabled()
        end
        if widgets.Header('Text (Shared)') then
            if widgets.FontFile(options, 'fontFile', '##chatbox.fontFile', { tooltip = 'The chat\'s font: one of C:\\Windows\\Fonts, or the theme\'s.' }) then
                app.save()
            end
            local _, done = widgets.FontSize(options, 'fontSize', '##chatbox.fontSize', { min = 8, max = 24,
                tooltip = 'How large the log\'s and the input bar\'s text is, in pixels; both boxes grow with it.\nThe expanded log\'s text too, with Replace Text, centred on the game\'s rows, whose spacing is the game\'s.' })
            if done then app.save() end
        end
        if widgets.Header('Padding (Shared)') then
            for _, side in ipairs(PADDING_SIDES) do
                widgets.Label(side.label)
                imgui.SliderInt('##chatbox.' .. side.key, options[side.key], 0, PADDING_MOST, '%d px')
                if imgui.IsItemDeactivatedAfterEdit() then app.save() end
                Tip(side.tip)
            end
        end
        if widgets.Header('Expanded (Shared)') then
            imgui.TextDisabled('Expanded history uses native navigation in both behaviours.')
            widgets.Label('Expand In Place')
            if imgui.Checkbox('##chatbox.expandInPlace', options.expandInPlace) then app.save() end
            Tip('Opens the expanded log where the chat log stands, its bottom-left on the first log\'s; the info panel is hidden while it is open,\nso with Anchor Bottom the log takes the panel\'s place as well. Its rows, hovering, Confirm and scrolling move with it. Off, where the game puts it.')
            widgets.Label('Expanded Height')
            imgui.SliderInt('##chatbox.expandedHeight', options.expandedHeight, 25, 100, '%d%%')
            if imgui.IsItemDeactivatedAfterEdit() then app.save() end
            Tip('How far up the screen the expanded log reaches: its top that share of the screen\'s height up from the bottom, and never above\nthe game\'s own window. The game\'s rows above it are cut off; the rest of the log, its scrolling and Confirm are as ever. 100% is the game\'s own.')
            widgets.Label('Replace Tabs')
            if imgui.Checkbox('##chatbox.replaceTabs', options.replaceTabs) then app.save() end
            Tip('Draws the expanded log\'s channel tabs as WinXI buttons, each whole and in the game\'s order, the chosen one lit as the game chooses it\n(Square and the arrows). The game\'s mouse clicks on its tabs stay at its own places. Off, the game\'s own tabs are drawn, tinted.')
            widgets.Label('Replace Scrollbar')
            if imgui.Checkbox('##chatbox.replaceScrollbar', options.replaceScrollbar) then app.save() end
            Tip('Draws the expanded log\'s scrollbar as the compact log\'s, where the game\'s is; scrolling is still the game\'s.\nOff, the game\'s own is drawn, tinted.')
            widgets.Label('Replace Text', true)
            if imgui.Checkbox('##chatbox.replaceText', options.replaceText) then app.save() end
            Tip('Draws the expanded log\'s rows of text in the chat\'s Font at Font Size, each row centred where the game draws its own and in the game\'s colours,\nso the cursor, hovering, Confirm and scrolling are still the game\'s. Off, the game\'s own font.')
            widgets.Label('Replace Cursor')
            if imgui.Checkbox('##chatbox.replaceCursor', options.replaceCursor) then app.save() end
            Tip('With Replace Tabs, Replace Scrollbar and Replace Text on, draws the expanded log\'s cursor, the light on its row and the game\'s marked rows as well,\nso nothing of the game\'s is drawn in it: the game still moves the cursor, follows the mouse and takes Confirm. Off, the game\'s own, tinted.')
        end
        if widgets.Header('Window Colors (Shared)') then appearance.Draw(options.appearance, app.save) end
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
        options.fontSize[1] = math.floor(math.max(8, math.min(24, fontSize)))
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
        -- Migrate the former independent match switches once; the unified setting wins thereafter.
        if type(options.followNativeSettings) ~= 'table' then options.followNativeSettings = T{} end
        if type(options.followNativeSettings[1]) ~= 'boolean' then
            options.followNativeSettings[1] = (type(options.matchGameLogSize) == 'table' and options.matchGameLogSize[1] == true)
                or (type(options.matchGameInputSize) == 'table' and options.matchGameInputSize[1] == true)
        end
        options.matchGameLogSize = T{ options.followNativeSettings[1] }
        options.matchGameInputSize = T{ options.followNativeSettings[1] }
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
    model.Add(history, text, mode, nil, originalMode, spans, line.mode or line.originalMode)
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

-- The log's rows, in the window being drawn (with the chat's font pushed): the light and cursor when the
-- game has it selected (lit), then the rows at the bottom, preserving all source inline colours. Native-sized
-- boxes centre their whole rows within the configured vertical padding. view: the window's own scrolling; filter: which messages it
-- shows (nil, all of them); style: the window's options, for its title and Default Text colour.
local function DrawLog(box, rowCount, fontSize, padding, view, filter, lit, style)
    local options = app.options
    local list = imgui.GetWindowDrawList()
    local left, top = box.left, box.bottom - box.height
    if lit then
        list:AddRectFilled({ left, top }, { left + box.width, box.bottom }, imgui.GetColorU32(light))
    end
    local inset = options.leftPadding[1]
    local width = math.max(1, box.width - inset - options.rightPadding[1])
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
    local drawn = { frame = frame, expanded = false, left = left, top = top, width = box.width, bottom = box.bottom,
        rows = rowCount, drawn = #rows, title = style.title, firstY = 0, overflow = overflow }
    -- The rows centred between the configured top and bottom padding; the
    -- newest at the foot of them, as the game's.
    local step = fontSize + ROW_GAP
    local areaTop = top + options.topPadding[1]
    local areaBottom = box.bottom - options.bottomPadding[1]
    local block = rowCount * step - ROW_GAP
    local spare = areaBottom - areaTop - block
    local x, y = left + inset, areaTop + (spare < 0 and spare or math.floor(spare / 2))
    y = y + (rowCount - #rows) * step
    -- During animated resizing, reveal/hide rows at the top without moving the newest row.
    list:PushClipRect({ left, math.min(areaTop, areaBottom) },
        { left + box.width, areaBottom }, true)
    if lit then
        DrawCursor(list, left, y + (#rows - 1) * step, fontSize)
    end
    drawn.firstY = y
    for _, row in ipairs(rows) do
        if row.text ~= '' then
            local color = imgui.GetColorU32(style.textColor or palette.Mode(row.message.mode) or theme.Get().TextColor)
            render.Rich(list, { x, y }, color, row.text, row.spans, row, font, size)
        end
        y = y + step
    end
    list:PopClipRect()
    local bar = scrollbar.Layout(left+box.width-3-scrollbar.Width,areaTop,areaBottom,metrics.total,rowCount,view.offset)
    drawn.scrollbar = bar
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
    view.drawn = drawn
    return drawn
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
-- which the game highlights and where its cursor is are the game's, by their order (newest first); the game's own
-- places (16 of its units apart) are left to its mouse. Should the row the game has chosen be past what fits, the
-- view moves up to keep it at the top. Returns { row, y } for each line shown, the newest first.
local expandedLines = {}
local function ExpandedLines(rows, size)
    for i = #expandedLines, 1, -1 do expandedLines[i] = nil end
    local step = size + ROW_GAP
    local areaTop, areaBottom = expandedBox[2] + app.options.topPadding[1], expandedBox[4] - app.options.bottomPadding[1]
    local fits = math.max(1, math.floor((areaBottom - areaTop + ROW_GAP) / step))
    local placed, measured = {}, false
    for _, row in ipairs(rows) do
        if row.top then placed[#placed + 1] = row; measured = measured or row.lit end
    end
    local chosen = 1
    for i, row in ipairs(placed) do
        if (measured and row.lit) or (not measured and row.cursor) then chosen = i end
    end
    local first = math.max(1, chosen - fits + 1)
    for i = first, math.min(#placed, first + fits - 1) do
        expandedLines[#expandedLines + 1] = { row = placed[i], y = areaBottom - size - (i - first) * step,
            chosen = (measured and placed[i].lit) or (not measured and placed[i].cursor) }
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
    local size = app.options.fontSize[1]
    local lines = ExpandedLines(rows, size)
    if #lines == 0 then return 0 end
    local chatFont = fonts.Get(app.options.fontFile)
    imgui.PushFont(chatFont, size)
    local font = imgui.GetFont() -- what the rows' kept layouts are measured in
    list:PushClipRect({ expandedBox[1], expandedBox[2] }, { expandedBox[3], expandedBox[4] }, true)
    local left = expandedBox[1] + app.options.leftPadding[1]
    if expandedReplace.all then DrawExpandedLights(list, lines, left, size) end
    local fallback = theme.Get().TextColor
    local drawn = 0
    for _, line in ipairs(lines) do
        local row, x = line.row, left
        if row.text ~= '' then
            local entry = DecodeRow(row.text)
            if entry.text ~= '' then
                local color = expandedOptions.textColor or palette.Mode(row.mode) or fallback
                render.Rich(list, { x, line.y }, imgui.GetColorU32(color), entry.text, entry.spans, entry, font, size)
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
    if chatFont then imgui.PushFont(chatFont, app.options.fontSize[1]) end
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
        local tabTextSize = math.max(8, math.floor(app.options.fontSize[1] * TAB_TEXT_SCALE + 0.5))
        imgui.PushFont(chatFont, tabTextSize)
        local font = imgui.GetFont()
        if font ~= tabFont or tabTextSize ~= tabSize then tabSizes, tabFont, tabSize = {}, font, tabTextSize end
        strip.Draw(list, expandedTabs, channels.Filters, channels.Art, stripColors, MeasureTab)
        imgui.PopFont()
    end
    if expandedScroll then
        -- the compact log's: a thin thumb and no track, inside the log's right edge, over the game's bar's
        -- height and where its page is; brighter while the mouse is on the game's bar (which it drags) or it
        local s = expandedScroll
        local bar = scrollbar.Layout(ExpandedThumbLeft(), math.max(s.top, expandedBox[2] + app.options.topPadding[1]),
            math.min(s.bottom, expandedBox[4] - app.options.bottomPadding[1]),
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
    local rect = { primary.Rect(sw, sh, true) }
    if #rect ~= 4 or rect[1] < 0 or rect[2] < 0 or rect[3] > sw or rect[4] > sh
        or rect[3] <= rect[1] or rect[4] <= rect[2] then
        anchorStatus = 'Waiting for native expanded bounds; full native log left visible.'
        return
    end
    appearance.Apply(expandedOptions, app.options.appearance.log)
    local look = theme.Get()
    expandedColors[1] = look.HighlightColor or controller.HighlightColor
    expandedColors[2] = expandedOptions.titleColor or look.TitleColor or look.TextColor or white
    expandedColors[3] = expandedOptions.border or look.BorderColor or white
    expandedColors[4] = expandedOptions.border or look.BorderColor or white
    -- where the game drew its tabs, scrollbar and rows of text last, to draw the addon's own there and ask the game to leave its undrawn
    local replace = state.nativeReplace
    expandedTabs = replace and app.options.replaceTabs[1] and primary.Tabs(sw, sh) or nil
    expandedScroll = replace and app.options.replaceScrollbar[1] and primary.Scrollbar(sw, sh) or nil
    expandedRows = state.nativeText and app.options.replaceText[1] and primary.Rows(sw, sh) or nil
    expandedReplace.tabs, expandedReplace.scrollbar, expandedReplace.text = expandedTabs ~= nil, expandedScroll ~= nil, expandedRows ~= nil
    -- the whole log, once the addon draws the tabs and text; the scrollbar too, unless the game draws none
    expandedReplace.all = state.nativeMirror == true and app.options.replaceCursor[1] and app.options.replaceScrollbar[1]
        and expandedTabs ~= nil and expandedRows ~= nil
    expandedScreen[1], expandedScreen[2] = sw, sh
    -- Expanded Height: the frame reaches that share of the way up the screen and no higher (nor above the game's
    -- window); the game's rows above it are clipped, its rows, cursor and hit-tests otherwise its own
    local top = math.max(rect[2], math.floor(sh * (1 - app.options.expandedHeight[1] / 100)))
    top = math.min(top, rect[4] - 32)
    local bottom = rect[4]
    -- The custom Width applies to expanded chat too. Matching either game size keeps native bounds;
    -- only the replacement frame/controls change here, never the game's history wrapping or hit-tests.
    local right = rect[3]
    if not app.options.matchGameLogSize[1] and not app.options.matchGameInputSize[1] then
        right = math.min(rect[3], rect[1] + app.options.width[1])
    end
    expandedBox[1], expandedBox[2], expandedBox[3], expandedBox[4] = rect[1], top, right, bottom
    expandedOptions.fontSize = app.options.fontSize[1]
    -- Opened in place: the log's foot stands where it was asked to (within a few pixels of the game's units)
    local opened = app.options.expandInPlace[1] and expandPlace and logMenus
        and math.abs(rect[1] - expandPlace.left) <= 3 and math.abs(bottom - expandPlace.bottom) <= 3
    place[1], place[2] = rect[1], bottom
    size[1], size[2] = right-rect[1], bottom-top
    imgui.SetNextWindowPos(place, ImGuiCond_Always, pivot)
    imgui.SetNextWindowSize(size, ImGuiCond_Always)
    lastDrawn = { frame = frame, expanded = true, left = rect[1], top = top, width = size[1], bottom = bottom,
        rows = state.pageRows or 0, drawn = 0, firstY = top, title = expandedRows and 'WinXI text' or 'native content', overflow = false }
    window.Plain('winxi.chatbox.expanded', open, flags, DrawExpandedControls, expandedOptions)
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

ashita.events.register('d3d_present', 'chatbox_present', function()
    for _, view in ipairs(views) do view.target = nil end -- rearmed only after this frame captures a complete replacement
    app:BeginFrame() -- configures WinXI's shared/local theme and draws settings
    infoPanel.BeginFrame() -- renew menu placement only with this frame's successful host capture
    DrainTap() -- the frame's lines as uihook has them after every addon, or chatbox's own copies
    if not app.options.enabled[1] or zoning then Release(); return end
    infoPanel.Hud(app.options.infoPanel) -- Hide Game Clock and Hide Compass, with or without the panel or chat's capture
    ImportHistory() -- the game's history before chatbox's own, once
    if not primary.Begin() then
        ResetViews(false)
        secondary.Stop(); input.Stop(); return
    end
    captured, capturedSplit, selectedWindow, panelAttachment = false, false, nil, nil
    palette.Source(primary.Colors and primary.Colors() or nil) -- the game's chat colours as configured, where uihook reads them
    local splitDrawn, firstHidden = false, false -- firstHidden: the game's log at 0 lines, nothing drawn in its place
    local compactMinSize = false
    local ok, err = pcall(function()
        local display = imgui.GetIO().DisplaySize
        local sw, sh = display.x or display[1], display.y or display[2]
        if not sw or not sh or sw < 100 or sh < 100 then input.Stop(); return end
        local state = primary.State()
        local expanded = state and state.expanded
        frame = frame + 1
        if expanded then DrawExpanded(state, sw, sh); return end
        -- ImGui's normal minimum is taller than a one-row log or panel-only host.
        imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, { 1, 1 })
        compactMinSize = true
        local fontSize, padding = app.options.fontSize[1], PADDING_DEFAULT
        windowOptions.fontSize, windowOptions.padding = fontSize, padding
        appearance.Apply(windowOptions, app.options.appearance.log)
        splitOptions.fontSize, splitOptions.padding = fontSize, padding
        appearance.Apply(splitOptions, app.options.appearance.log)
        -- Compact: the game log's own size (as many rows as fit), or Width and ten rows.
        local logRect = { primary.Rect(sw, sh) }
        local rowCount = model.Rows
        -- Exact row heights and inter-row gaps, with only the configured padding around them.
        local above, below = app.options.topPadding[1], app.options.bottomPadding[1]
        local frameHeight = model.Rows * fontSize + (model.Rows - 1) * ROW_GAP + above + below
        size[1] = math.min(app.options.width[1], sw - 40)
        -- Matching the game's size: its lines now, as it grows a row a message and shrinks to its fewest while none
        -- come (0, nothing drawn), the box no shorter than the game's window and tall enough for those rows at Font
        -- Size; or, with a uihook that does not say, as many rows as fit the game's window.
        local function Sized(rect, lines)
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
        local match = app.options.matchGameLogSize[1]
        if match then
            local rows, height = Sized(#logRect == 4 and logRect or nil, primary.Lines and primary.Lines() or nil)
            if rows == 0 then
                firstHidden = true -- the game's log at 0 lines: nothing to draw, nothing shown
            elseif rows and #logRect == 4 then
                rowCount, frameHeight, size[1] = rows, height, logRect[3] - logRect[1]
            end
        end
        local customRows = app.options.window1Rows[1]
        if not app.options.followNativeSettings[1] and customRows > 0 then
            rowCount, firstHidden = customRows, false
            frameHeight = customRows * fontSize + (customRows - 1) * ROW_GAP + above + below
            if match and #logRect == 4 then size[1] = logRect[3] - logRect[1] end
        end
        size[2] = frameHeight
        local plan = input.Measure(size[1], sh, fontSize, padding, app.options.matchGameInputSize[1],
            app.options.topPadding[1], app.options.bottomPadding[1])
        appearance.Apply(plan, app.options.appearance.input)
        plan.font = fonts.Get(app.options.fontFile)
        plan.leftPadding, plan.rightPadding = app.options.leftPadding[1], app.options.rightPadding[1]
        local box, placeKnown, panelBase
        placeKnown = #logRect == 4
        box = layout.Arrange(layoutState, logRect, plan,
            size[1], sw, sh, size[2], padding, app.options.matchGameInputSize[1])
        panelBase = box
        anchorStatus = box and 'Anchored to native chat; log and input share one width.'
            or 'Native chat anchor unavailable or the log does not fit; native log left visible.'
        if firstHidden then box = nil; anchorStatus = 'The game\'s log is at 0 lines: nothing drawn, and nothing of the game\'s shown.' end
        -- The game's second log window, where it shows one: a box where the game puts its own beside the first,
        -- stacked over it (the game's vertical layout: its own width when matching, over the first's top) or beside it (horizontal:
        -- the game's width for it, the game's gap from the first, the first's bottom); as tall as the game's (as
        -- many rows as fit) or ten rows; its messages the ones the game's Log Window settings route to it, the
        -- first's the ones routed there.
        local routes = primary.Routes and primary.Routes() or nil
        local splitRect = { secondary.Rect(sw, sh) }
        local second
        if routes and routes.split and #splitRect == 4 then
            local rows, height, secondHidden = model.Rows, model.Rows * fontSize + (model.Rows - 1) * ROW_GAP + above + below, false
            if match then
                local sized, tall = Sized(splitRect, secondary.Lines and secondary.Lines() or nil)
                if sized == 0 then secondHidden = true elseif sized then rows, height = sized, tall end
            end
            local customSecondRows = app.options.window2Rows[1]
            if not app.options.followNativeSettings[1] and customSecondRows > 0 then
                rows, secondHidden = customSecondRows, false
                height = rows * fontSize + (rows - 1) * ROW_GAP + above + below
            end
            if secondHidden then
                splitStatus = 'Second window: the game\'s is at 0 lines; nothing drawn, and nothing of the game\'s shown.'
            elseif firstHidden then
                -- the first at 0 lines: the second where the game draws its own, as it is the one log window shown
                second = { left = splitRect[1], width = splitRect[3] - splitRect[1], bottom = splitRect[4], top = splitRect[4] - height, height = height, rows = rows }
                splitStatus = ('Second window: in the game\'s place, %d rows, the first at 0 lines; the game\'s Log Window settings route its messages.'):format(rows)
            elseif box and #logRect == 4 then
                local beside = splitRect[4] > logRect[2] + 2 -- not wholly above the first: the game's horizontal layout
                if not beside then
                    local width = match and (splitRect[3] - splitRect[1]) or box.width
                    local left = match and (box.left + splitRect[1] - logRect[1]) or box.left
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
                    else left = match and splitRect[1] or box.left + box.width end -- overlapping the first: the game's place, or its right
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
        if box then
            held = { box = box, rows = rowCount, second = second, frame = frame }
        elseif not firstHidden and held and not placeKnown and frame - held.frame <= HOLD_FRAMES and held.box.bottom <= sh then
            -- Opening or closing the full log, the game's new place is not known for a frame or two:
            -- the last box stays rather than the game's own log showing through.
            box, rowCount, second = held.box, held.rows, held.second
            anchorStatus = 'Waiting a moment for the game\'s log to settle.'
        end
        -- Smart visibility runs only on compact boxes; native capture remains armed even at zero opacity.
        local stacked = second and box and #splitRect == 4 and #logRect == 4 and splitRect[4] <= logRect[2] + 2
        panelBase = box or panelBase
        local oldTop, oldBottom = box and box.top, box and box.bottom
        local now = os.clock()
        local function Smart(number, b, capacity, style)
            local view = views[number]
            view.visibility = view.visibility or {}
            local settings = not app.options.followNativeSettings[1] and app.options.visibility and app.options.visibility['window' .. number] or nil
            local active = plan.active or (state and state.selected and (not state.selectedWindow or state.selectedWindow == number))
                or view.offset > 0 or view.drag ~= nil or view.pressed ~= nil
            local function Measure(recent, rows)
                if not recent then return rows * fontSize + (rows - 1) * ROW_GAP + above + below end
                model.ShowStamps(recent, app.options.timestamps[1])
                local width = math.max(1, b.width - app.options.leftPadding[1] - app.options.rightPadding[1])
                if plan.font then imgui.PushFont(plan.font, fontSize) end
                local ok, total = pcall(function()
                    local metrics = model.Metrics(recent, width, plan.font, fontSize, render.Measure)
                    if metrics.total > capacity then
                        metrics = model.Metrics(recent, math.max(1, width - scrollbar.Reserve), plan.font, fontSize, render.Measure)
                    end
                    return metrics.total
                end)
                if plan.font then imgui.PopFont() end
                if not ok then error(total, 0) end
                return total
            end
            local result, rows, alpha = visibility.Apply(view.visibility, settings, history, Filter(routes, number), b, capacity, now, active, Measure)
            style.alpha = alpha
            return result, rows
        end
        box, rowCount = Smart(1, box, rowCount, windowOptions)
        if second then
            if stacked then
                local shifted = {}
                for k, v in pairs(second) do shifted[k] = v end
                local shift = (box and box.top or oldBottom) - oldTop
                shifted.top, shifted.bottom = second.top + shift, second.bottom + shift
                second = shifted
            end
            local rows
            second, rows = Smart(2, second, second.rows, splitOptions)
            if second then second.rows = rows end
        end
        if oldTop and not box then firstHidden = true; lastDrawn = nil end
        -- Open, the input is lifted onto the panel, which keeps the input's bottom; the logs above the input
        local open = plan.active and box ~= nil
        local panelOnly = not box and not second and panelBase ~= nil
        local panelHost, panelSplit = box, second
        if panelOnly then
            -- Keep only a zero-height layout anchor, not the old chat height or padding.
            panelHost = { left = panelBase.left, width = panelBase.width, top = panelBase.bottom,
                bottom = panelBase.bottom, height = 0 }
            if routes and routes.split and #splitRect == 4 and #logRect == 4 and splitRect[4] > logRect[2] + 2 then
                panelSplit = { left = splitRect[1], width = splitRect[3] - splitRect[1], top = panelBase.bottom,
                    bottom = panelBase.bottom, height = 0 }
            end
        end
        panelAttachment = infoPanel.Prepare(app.options.infoPanel, panelHost, panelSplit, plan.height, fontSize, app.options.fontFile,
            open and plan.bottom or nil)
        if panelOnly and panelAttachment then
            -- A zero-height log is not a valid native menu rectangle. Anchor to the actual visible panel.
            panelAttachment.menus = panelAttachment.rect
        end
        -- An attached panel takes the bottom of the logs' place: both boxes drawn wholly above it (copies, so a held box is not lifted twice)
        local lift = panelAttachment and panelAttachment.lift or 0
        if panelAttachment then plan.bottom = plan.bottom - panelAttachment.inputLift end -- this frame's plan, measured afresh each frame
        if lift > 0 then
            local function Lifted(b)
                if not b then return nil end
                local moved = {}
                for k, v in pairs(b) do moved[k] = v end
                moved.top, moved.bottom = b.top - lift, b.bottom - lift
                return moved
            end
            box, second = Lifted(box), Lifted(second)
        end
        -- where the expanded log will open, asked for already, so the game lays it out there from its first frame
        if box and not open then expandPlace = { left = box.left, bottom = box.bottom + lift }
        elseif panelOnly and not open then expandPlace = { left = panelHost.left, bottom = panelHost.bottom } end
        PlaceLog(app.options)
        if box then
            place[1], place[2] = box.left, box.bottom
            size[1], size[2] = box.width, box.height
            selectedWindow = state ~= nil and state.selectedWindow or nil
            -- the light and cursor on the window the game's focus is on; on the first while the second is not drawn
            local litFirst = selectedWindow ~= nil and (selectedWindow == 1 or not second)
            windowOptions.title = OwnTitle(app.options.windowTitle) or channels.Title(plan.snapshot and channels.Typed(plan.snapshot.text) or selectedMode or spoken)
            imgui.SetNextWindowPos(place, ImGuiCond_Always, pivot)
            imgui.SetNextWindowSize(size, ImGuiCond_Always)
            local chatFont = plan.font
            window.Plain('winxi.chatbox', open, flags, function()
                if chatFont then imgui.PushFont(chatFont, fontSize) end
                local drawn, drawError = pcall(DrawLog, box, rowCount, fontSize, padding, views[1], Filter(routes, 1), litFirst, windowOptions)
                if chatFont then imgui.PopFont() end
                if not drawn then error(drawError, 0) end
                infoPanel.Draw(panelAttachment, 0) -- under the lifted log, on its capture
            end, windowOptions)
            lastDrawn = views[1].drawn
        end
        if firstHidden then lastDrawn = nil; selectedWindow = state ~= nil and state.selectedWindow or nil end
        -- the second box, with the first's or on its own while the first is at 0 lines
        if second and (captured or firstHidden) and secondary.Begin() then
            local chatFont = plan.font
            splitOptions.title = OwnTitle(app.options.splitTitle) or 'Window 2'
            imgui.SetNextWindowPos({ second.left, second.bottom }, ImGuiCond_Always, pivot)
            imgui.SetNextWindowSize({ second.width, second.height }, ImGuiCond_Always)
            window.Plain('winxi.chatbox.split', open, flags, function()
                if chatFont then imgui.PushFont(chatFont, fontSize) end
                local drawn, drawError = pcall(DrawLog, second, second.rows, fontSize, padding, views[2], Filter(routes, 2), selectedWindow == 2, splitOptions)
                if chatFont then imgui.PopFont() end
                if not drawn then error(drawError, 0) end
                infoPanel.Draw(panelAttachment, 1)
            end, splitOptions)
            splitDrawn = capturedSplit
            lastSplit = views[2].drawn
        end
        if panelOnly and panelAttachment then
            lastDrawn, lastSplit = nil, nil
            for _, panel in ipairs(panelAttachment.panels) do
                local slot, rect = panel.slot, panel.rect
                if slot == 0 or secondary.Begin() then
                    imgui.SetNextWindowPos({ rect.left, rect.top + rect.height }, ImGuiCond_Always, pivot)
                    imgui.SetNextWindowSize({ rect.width, rect.height }, ImGuiCond_Always)
                    window.Plain('winxi.chatbox.panel.' .. slot, false, flags, function()
                        infoPanel.Draw(panelAttachment, slot)
                    end, panelOnlyOptions[slot + 1])
                    if slot == 1 then splitDrawn = capturedSplit end
                end
            end
        end
        -- Input is independent: keep it working while waiting for the log's first geometry sample.
        input.Draw(plan.width, sh, fontSize, padding, flags, app.options.matchGameInputSize[1], plan)
    end)
    if compactMinSize then imgui.PopStyleVar() end
    if not ok then Release(); error(err, 0) end
    -- The first log at 0 lines keeps Begin's empty hide, so nothing of the game's shows in its place either
    if not captured and not firstHidden then
        ResetViews(false)
        primary.Stop()
        secondary.Stop()
        return
    end
    -- One box or two: the game's second log window is drawn as the second box where the game shows one and
    -- uihook says how the game routes between them; otherwise it is hidden rather than left as a duplicate
    -- under the first. Only hide it after a complete primary capture succeeded (or the first is at 0 lines).
    if firstHidden or (lastDrawn and not lastDrawn.expanded) then
        if not splitDrawn then secondary.Begin() end
        views[1].target = captured and lastDrawn or nil
        views[2].target = splitDrawn and lastSplit or nil
    end
    infoPanel.Tooltip()
end)

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
ashita.events.register('mouse', 'chatbox_scroll', function(e)
    if e.blocked or not app.options.enabled[1] or zoning then return end
    -- Only the wheel, a left press, its release and a scrollbar's drag are ever taken: anything else, most of all the
    -- mouse moving, is let by before the game's state is read
    local message = e.message
    if message == 0x0200 then
        if not (views[1].drag or views[2].drag) then return end
    elseif message == 0x0202 then
        if not (views[1].pressed or views[2].pressed) then return end
    elseif message ~= 0x0201 and message ~= 0x020a then return end
    local state = primary.State()
    if state and (state.expanded or state.nativeBrowse) then
        for _, view in ipairs(views) do view.drag, view.pressed = nil, nil end
        return
    end
    local io = imgui.GetIO()
    local mouse = io.MousePos
    local x, y = mouse and (mouse.x or mouse[1]), mouse and (mouse.y or mouse[2])
    for _, view in ipairs(views) do
        if view.target and (not io.WantCaptureMouse or view.pressed) and Scroll(view, view.target, e, x, y) then return end
    end
end)
