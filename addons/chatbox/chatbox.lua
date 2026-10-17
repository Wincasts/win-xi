addon.name = 'chatbox'
addon.author = 'win'
addon.version = '0.10.0'
addon.desc = 'WinXI native-backed chat, titled with your channel, with selection and an expanded view in WinXI tabs.'
local winxiNeeded = 17
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

local primary, secondary = native.new(native.Primary), native.new(native.Secondary)
local history = model.New()
local decodeErrors, zoning = 0, false
local decodeSample -- latest incoming event; bounded, memory-only diagnostics
local anchorStatus = 'Waiting for native primary chat geometry.'
local app
local open, place, pivot, size, contentSize = { true }, { 20, 0 }, { 0, 1 }, { 0, 0 }, { 0, 0 }
local ROW_GAP = 2
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
        if scroll then view.offset = 0 end
    end
end
local function Release()
    held = nil
    ResetViews(false)
    primary.Stop()
    secondary.Stop()
    input.Stop()
end
local function Reset()
    Release()
    model.Clear(history)
    ResetViews(true)
    spoken, selectedMode = 'Say', nil
    channels.ResetLinkshells()
    layoutState = layout.New()
    decodeErrors, decodeSample = 0, nil
    anchorStatus = 'Waiting for native primary chat geometry.'
end
local function Status()
    local size = app.options.matchGameLogSize[1] and 'the game log\'s size' or '10 rows'
    app:Say((app.options.enabled[1] and 'On' or 'Off') .. '. Compact at ' .. size .. ', native-controlled expansion; ' .. #history.messages .. ' messages retained.')
    app:Say(primary.Status())
    app:Say(anchorStatus)
    app:Say('Input: ' .. input.Status())
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

local function Tip(text)
    if imgui.IsItemHovered() then imgui.SetTooltip(text) end
end
-- Forget the kept messages, the decode sample and where the log was scrolled to: the settings' Clear and /chatbox clear alike.
local function ClearHistory() model.Clear(history); decodeSample = nil; for _, view in ipairs(views) do view.offset, view.pending = 0, 0 end end

app = shell.New({
    defaults = T{ enabled = T{ true }, width = T{ 640 }, matchGameLogSize = T{ true }, matchGameInputSize = T{ false }, fontSize = T{ 12 },
        replaceTabs = T{ true }, replaceScrollbar = T{ true }, replaceText = T{ true },
        appearance = appearance.Defaults(T, theme.Get()), fontFile = '',
        leftPadding = T{ 3 }, rightPadding = T{ 3 }, topPadding = T{ 3 }, bottomPadding = T{ 3 }, paddingVersion = T{ 0 } },
    command = '/chatbox',
    configTitle = 'Chatbox Settings',
    help = '/chatbox opens settings; /chatbox on, off, clear, status, modes (the last lines\' chat modes), bytes (last incoming decode sample). Follows the game log\'s size; native selection, expansion and input controls.',
    drawSettings = function(options)
        if widgets.Header('Chatbox', true) then
            widgets.Label('Replace Native Chat')
            if imgui.Checkbox('##chatbox.enabled', options.enabled) then
                if not options.enabled[1] then Release() end
                app.save()
            end
            Tip('Draws the WinXI log and input bar in place of the game\'s own.\nOff, the game\'s chat log and input come back at once. /chatbox on and off do the same.')
            widgets.Label('Chat History')
            if imgui.SmallButton('Clear##chatbox.clear') then ClearHistory() end
            Tip('Forgets the messages kept for the compact log, 256 at most and never written to disk.\nThe game\'s own history, which the expanded log shows, is left alone.')
            imgui.TextDisabled('Native Square/window selection, confirm to expand, cancel to close.')
            imgui.TextDisabled(primary.Status())
        end
        if widgets.Header('Size') then
            widgets.Label('Match Game Log Size')
            if imgui.Checkbox('##chatbox.matchGameLogSize', options.matchGameLogSize) then app.save() end
            Tip('Takes the width and height of the game\'s own chat log, so changing its size in the game\'s\nsettings changes this one; as many rows as fit at Font Size. Off: Width, and ten rows.')
            widgets.Label('Width')
            imgui.SliderInt('##chatbox.width', options.width, 240, 1200, '%d px')
            if imgui.IsItemDeactivatedAfterEdit() then app.save() end
            Tip('How wide the log and the input bar are, in pixels, with Match Game Log Size and Match Game Input Size off.')
            widgets.Label('Match Game Input Size')
            if imgui.Checkbox('##chatbox.matchGameInputSize', options.matchGameInputSize) then app.save() end
            Tip('Uses the native input width for both boxes and its height/position for the input.\nOff: both boxes use Width (or the game log\'s, with Match Game Log Size). Font Size applies to both.')
        end
        if widgets.Header('Text') then
            widgets.Label('Font')
            local file = options.fontFile
            if imgui.BeginCombo('##chatbox.fontFile', file ~= '' and file or 'Theme\'s Font') then
                if imgui.Selectable('Theme\'s Font##chatbox.font.theme', file == '') and file ~= '' then
                    options.fontFile = ''
                    app.save()
                end
                for _, choice in ipairs(fonts.Files()) do
                    if imgui.Selectable(choice .. '##chatbox.font', file == choice) and file ~= choice then
                        options.fontFile = choice
                        app.save()
                    end
                end
                imgui.EndCombo()
            end
            Tip('The chat\'s font: one of C:\\Windows\\Fonts, or the theme\'s.')
            widgets.Label('Font Size')
            imgui.SliderInt('##chatbox.fontSize', options.fontSize, 8, 24, '%d px')
            if imgui.IsItemDeactivatedAfterEdit() then app.save() end
            Tip('How large the log\'s and the input bar\'s text is, in pixels; both boxes grow with it.\nThe expanded log\'s text too, with Replace Text, though no taller than the game\'s rows.')
        end
        if widgets.Header('Padding') then
            for _, side in ipairs(PADDING_SIDES) do
                widgets.Label(side.label)
                imgui.SliderInt('##chatbox.' .. side.key, options[side.key], 0, PADDING_MOST, '%d px')
                if imgui.IsItemDeactivatedAfterEdit() then app.save() end
                Tip(side.tip)
            end
        end
        if widgets.Header('Expanded') then
            widgets.Label('Replace Tabs')
            if imgui.Checkbox('##chatbox.replaceTabs', options.replaceTabs) then app.save() end
            Tip('Draws the expanded log\'s channel tabs in WinXI\'s tab style and the chat\'s font, each where the game\'s is, so Square and the mouse still choose among them.\nOff, the game\'s own tabs are drawn, tinted.')
            widgets.Label('Replace Scrollbar')
            if imgui.Checkbox('##chatbox.replaceScrollbar', options.replaceScrollbar) then app.save() end
            Tip('Draws the expanded log\'s scrollbar as the compact log\'s, where the game\'s is; scrolling is still the game\'s.\nOff, the game\'s own is drawn, tinted.')
            widgets.Label('Replace Text', true)
            if imgui.Checkbox('##chatbox.replaceText', options.replaceText) then app.save() end
            Tip('Draws the expanded log\'s rows of text in the chat\'s Font, at Font Size or the game\'s row height if that is less, each row where the game draws its own and in the game\'s colours,\nso the cursor, hovering, Confirm and scrolling are still the game\'s. Off, the game\'s own font.')
        end
        if widgets.Header('Window Colors') then appearance.Draw(options.appearance, app.save) end
    end,
    commands = {
        on = function(options) options.enabled[1] = true; app.save() end,
        off = function(options) options.enabled[1] = false; Release(); app.save() end,
        clear = ClearHistory,
        status = Status,
        bytes = function()
            if not decodeSample then app:Say('No decode sample yet. Receive a chat line, then /chatbox bytes.'); return end
            -- Hex is ASCII-only: printing the diagnostic cannot reinterpret the bad character.
            app:Say(('Chat bytes, original mode %d / display mode %d (first 256 bytes per stage):')
                :format(decodeSample.originalMode, decodeSample.mode))
            for _, key in ipairs({'original','modified','expanded','utf8'}) do
                local text = decodeSample[key] or ''
                app:Say(key .. ': ' .. (text:gsub('.', function(c) return ('%02X '):format(c:byte()) end)))
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
        Reset() -- a new character must never inherit another character's private chat
    end,
})

ashita.events.register('command', 'chatbox_mode', function(e)
    if e.blocked then return end
    selectedMode = channels.ModeCommand(e.command_modified or e.command) or selectedMode
end)

ashita.events.register('text_in', 'chatbox_text', function(e)
    -- Observe, never block or rewrite: the game keeps its own history and fallback rendering.
    -- Load filtering/formatting addons before chatbox to observe their modified text.
    if e.blocked then return end
    local originalMode = bit.band(e.mode or 0, 0xff)
    local mode = bit.band(e.mode_modified or e.mode or 0, 0xff)
    -- 190 replays NPC text into the native log; it is not another dialogue line.
    -- Check the original mode too, before another addon's formatting remaps it.
    if originalMode == 190 or mode == 190 or mode == 152 then return end
    spoken = channels.Sent(mode) or spoken
    local raw = e.message_modified or e.message
    if type(raw) ~= 'string' or #raw > model.MaxBytes then return end
    local ok, text, expanded, spans = pcall(encoding.Decode, raw, false, true)
    if not ok or not text then decodeErrors = decodeErrors + 1; return end
    decodeSample = { originalMode=originalMode, mode=mode,
        original=type(e.message)=='string' and e.message:sub(1,256) or '',
        modified=raw:sub(1,256), expanded=type(expanded)=='string' and expanded:sub(1,256) or '',
        utf8=text:sub(1,256) }
    model.Add(history, text, mode, nil, originalMode, spans, e.mode_modified or e.mode)
end)
ashita.events.register('packet_in', 'chatbox_zone', function(e)
    if e.blocked then return end
    if e.id == 0x00b then zoning = true; Release()
    elseif e.id == 0x00a then zoning = false; channels.ResetLinkshells()
    elseif e.id == 0x0e0 then channels.LinkshellPacket(e.data_modified or e.data) end
end)
ashita.events.register('unload', 'chatbox_unload', Reset)

-- Native Square/window focus: a faint light over the box and the game's cursor at its newest line.
-- Both are drawn in the window, so they are part of the captured replacement; no buttons are bound.
local captured, capturedSplit, selectedWindow = false, false, nil
local windowOptions = { capture = function() captured = primary.Capture() end }
local splitOptions = { capture = function() capturedSplit = secondary.Capture() end } -- the second log window's box
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
-- game has it selected (lit), then the rows at the bottom, preserving all source inline colours. A box taller
-- than its whole rows has its room above them. view: the window's own scrolling; filter: which messages it
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
    -- The rows centred between the top padding (under the title's half) and the bottom padding; the
    -- newest at the foot of them, as the game's.
    local step = fontSize + ROW_GAP
    local areaTop = top + math.ceil(fontSize / 2) + options.topPadding[1]
    local areaBottom = box.bottom - options.bottomPadding[1]
    local block = rowCount * step - ROW_GAP
    local x, y = left + inset, areaTop + math.floor(math.max(0, areaBottom - areaTop - block) / 2)
    y = y + (rowCount - #rows) * step
    if lit then
        DrawCursor(list, left, y + (#rows - 1) * step, fontSize)
    end
    drawn.firstY = y
    for _, row in ipairs(rows) do
        if row.text ~= '' then
            local color = imgui.GetColorU32(style.textColor or palette.Mode(row.message.mode) or theme.Get().TextColor)
            render.Rich(list, { x, y }, color, row.text, row.spans)
        end
        y = y + step
    end
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

-- Keep the native rectangle exactly: moving/resizing native content would break mouse hit-tests.
-- The plugin re-enables native drawing at FullLog::Draw and leaves the native rows, cursor and, unless
-- the addon draws its own, tabs and scrollbar visible. No themed rows, title or input are placed over them.
-- The tabs and scrollbar the addon draws stand where uihook measured the game's, so the game's hit-tests,
-- Square selection and scrolling are untouched; the game is asked to leave its own undrawn only while
-- there is a fresh place to draw them in.
local expandedColors, expandedReplace = {}, { tabs = false, scrollbar = false, text = false }
local expandedOptions = { padding = 0, shadow = false,
    capture = function() captured = primary.Capture(true, expandedColors, expandedReplace) end }
local expandedTabs, expandedScroll, expandedRows, expandedScreen = nil, nil, nil, { 0, 0 }
local expandedBox = { 0, 0, 0, 0 } -- the full log's rectangle, which its rows are clipped to
local stripColors = {}
local origin = { 0, 0 }
-- The game's rows of text, decoded once each (CP932 with the game's colour codes to UTF-8 and colour spans)
-- and kept by their bytes: 512 at most, then forgotten together
local decodedRows, decodedCount = {}, 0
local function DecodeRow(raw)
    local entry = decodedRows[raw]
    if entry == nil then
        local ok, text, _, spans = pcall(encoding.Decode, raw, true, true)
        entry = { text = ok and type(text) == 'string' and text or '', spans = ok and spans or nil }
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
-- The game's rows of text where it drew them, in the chat's font at Font Size or the row's height if that is
-- less, each centred in its row, in its chat mode's colour with the game's inline colours kept; the game's
-- cursor row gets the cursor after its text, as the game puts its mark there. Clipped to the full log's box.
local function DrawExpandedRows(list, rows)
    local height
    for _, row in ipairs(rows) do
        if row.top then height = row.bottom - row.top; break end
    end
    if not height or height < 1 then return 0 end
    local size = math.min(app.options.fontSize[1], math.floor(height))
    local chatFont = fonts.Get(app.options.fontFile)
    imgui.PushFont(chatFont, size)
    list:PushClipRect({ expandedBox[1], expandedBox[2] }, { expandedBox[3], expandedBox[4] }, true)
    local fallback = theme.Get().TextColor
    local drawn = 0
    for _, row in ipairs(rows) do
        if row.top then
            local y = row.top + math.floor((row.bottom - row.top - size) / 2)
            local x = row.left
            if row.text ~= '' then
                local entry = DecodeRow(row.text)
                if entry.text ~= '' then
                    render.Rich(list, { x, y }, imgui.GetColorU32(palette.Mode(row.mode) or fallback), entry.text, entry.spans)
                    x = x + render.Measure(entry.text)
                    drawn = drawn + 1
                end
            end
            if row.cursor then DrawMark(list, x + 4, y, size) end
        end
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
        local look = theme.Get()
        stripColors.highlight, stripColors.text, stripColors.border = expandedColors[1], expandedColors[2], expandedColors[3]
        stripColors.background = expandedOptions.background or look.BackgroundColor
        strip.Draw(list, expandedTabs, channels.Filters, channels.TabNames, stripColors, render.Measure)
    end
    if expandedScroll then
        local s = expandedScroll
        local bar = scrollbar.Layout(s.left, s.top, s.bottom, s.count, s.page, s.count - s.page - s.above)
        if bar then
            -- the track faint, and the thumb as the compact log's, both as wide as the game's bar
            list:AddRectFilled({ s.left, s.top }, { s.right, s.bottom }, imgui.GetColorU32(light), 1)
            list:AddRectFilled({ s.left, bar.thumbTop }, { s.right, bar.thumbBottom }, imgui.GetColorU32(scrollbar.White), 1)
        end
    end
    list:PopClipRect()
    if chatFont then imgui.PopFont() end
end
local function DrawExpanded(state, sw, sh)
    held = nil
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
    expandedScreen[1], expandedScreen[2] = sw, sh
    expandedBox[1], expandedBox[2], expandedBox[3], expandedBox[4] = rect[1], rect[2], rect[3], rect[4]
    place[1], place[2] = rect[1], rect[4]
    size[1], size[2] = rect[3]-rect[1], rect[4]-rect[2]
    imgui.SetNextWindowPos(place, ImGuiCond_Always, pivot)
    imgui.SetNextWindowSize(size, ImGuiCond_Always)
    lastDrawn = { frame = frame, expanded = true, left = rect[1], top = rect[2], width = size[1], bottom = rect[4],
        rows = state.pageRows or 0, drawn = 0, firstY = rect[2], title = expandedRows and 'WinXI text' or 'native content', overflow = false }
    window.Plain('winxi.chatbox.expanded', open, flags, DrawExpandedControls, expandedOptions)
    local parts = {}
    if expandedTabs then parts[#parts + 1] = 'tabs' end
    if expandedScroll then parts[#parts + 1] = 'scrollbar' end
    if expandedRows then parts[#parts + 1] = 'text' end
    local own = #parts > 0 and ('WinXI ' .. table.concat(parts, ', '):gsub(', ([^,]+)$', ' and %1')) or nil
    anchorStatus = own and ((expandedRows and 'Expanded native actions; WinXI frame and ' or 'Expanded native rows and actions; WinXI frame and ') .. own .. ' where the game\'s are.')
        or state.nativeControls and 'Expanded native rows and actions; WinXI frame and theme-tinted native controls.'
        or 'Expanded native rows and actions; WinXI frame (control artwork hooks unavailable).'
    if state.nested then anchorStatus = anchorStatus .. ' A menu of the game\'s is open over it.' end
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
    if not app.options.enabled[1] or zoning then Release(); return end
    if not primary.Begin() then
        ResetViews(false)
        secondary.Stop(); input.Stop(); return
    end
    captured, capturedSplit, selectedWindow = false, false, nil
    local splitDrawn, firstHidden = false, false -- firstHidden: the game's log at 0 lines, nothing drawn in its place
    local ok, err = pcall(function()
        local display = imgui.GetIO().DisplaySize
        local sw, sh = display.x or display[1], display.y or display[2]
        if not sw or not sh or sw < 100 or sh < 100 then input.Stop(); return end
        local state = primary.State()
        local expanded = state and state.expanded
        frame = frame + 1
        if expanded then DrawExpanded(state, sw, sh); return end
        local fontSize, padding = app.options.fontSize[1], PADDING_DEFAULT
        -- The title sits across the top edge, half inside: rows keep clear of that half.
        local headroom = math.ceil(fontSize / 2)
        windowOptions.fontSize, windowOptions.padding = fontSize, padding
        appearance.Apply(windowOptions, app.options.appearance.log)
        splitOptions.fontSize, splitOptions.padding = fontSize, padding
        appearance.Apply(splitOptions, app.options.appearance.log)
        -- Compact: the game log's own size (as many rows as fit), or Width and ten rows.
        local logRect = { primary.Rect(sw, sh) }
        local rowCount = model.Rows
        -- what the rows cannot use: the title's half, and the top and bottom padding
        local above, below = headroom + app.options.topPadding[1], app.options.bottomPadding[1]
        local frameHeight = model.Rows * fontSize + (model.Rows - 1) * ROW_GAP + above + below
        size[1] = math.min(app.options.width[1], sw - 40)
        if app.options.matchGameLogSize[1] and #logRect == 4 then
            local fit = layout.Fit(logRect[4] - logRect[2] - above - below, fontSize, 0, ROW_GAP)
            if fit >= 1 then
                rowCount, frameHeight, size[1] = fit, logRect[4] - logRect[2], logRect[3] - logRect[1]
            else
                firstHidden = true -- the game's log sized to no whole row (0 lines): nothing to draw, nothing shown
            end
        end
        size[2] = frameHeight
        local plan = input.Measure(size[1], sh, fontSize, padding, app.options.matchGameInputSize[1],
            app.options.topPadding[1], app.options.bottomPadding[1])
        appearance.Apply(plan, app.options.appearance.input)
        plan.font = fonts.Get(app.options.fontFile)
        plan.leftPadding, plan.rightPadding = app.options.leftPadding[1], app.options.rightPadding[1]
        local box, placeKnown
        placeKnown = #logRect == 4
        box = layout.Arrange(layoutState, logRect, plan,
            size[1], sw, sh, size[2], padding, app.options.matchGameInputSize[1])
        anchorStatus = box and 'Anchored to native chat; log and input share one width.'
            or 'Native chat anchor unavailable or the log does not fit; native log left visible.'
        if firstHidden then box = nil; anchorStatus = 'The game\'s log is at 0 lines: nothing drawn, and nothing of the game\'s shown.' end
        -- The game's second log window, where it shows one: a box where the game puts its own beside the first,
        -- stacked over it (the game's vertical layout: the first's width, over its top) or beside it (horizontal:
        -- the game's width for it, the game's gap from the first, the first's bottom); as tall as the game's (as
        -- many rows as fit) or ten rows; its messages the ones the game's Log Window settings route to it, the
        -- first's the ones routed there.
        local routes = primary.Routes and primary.Routes() or nil
        local splitRect = { secondary.Rect(sw, sh) }
        local second
        if routes and routes.split and #splitRect == 4 then
            local rows, height, secondHidden = model.Rows, frameHeight, false
            local match = app.options.matchGameLogSize[1]
            if match then
                local fit = layout.Fit(splitRect[4] - splitRect[2] - above - below, fontSize, 0, ROW_GAP)
                if fit >= 1 then rows, height = fit, splitRect[4] - splitRect[2] else secondHidden = true end
            end
            if secondHidden then
                splitStatus = 'Second window: the game\'s is at 0 lines; nothing drawn, and nothing of the game\'s shown.'
            elseif firstHidden then
                -- the first at 0 lines: the second where the game draws its own, as it is the one log window shown
                second = { left = splitRect[1], width = splitRect[3] - splitRect[1], bottom = splitRect[4], top = splitRect[2], height = height, rows = rows }
                splitStatus = ('Second window: in the game\'s place, %d rows, the first at 0 lines; the game\'s Log Window settings route its messages.'):format(rows)
            elseif box and #logRect == 4 then
                local beside = splitRect[4] > logRect[2] + 2 -- not wholly above the first: the game's horizontal layout
                if not beside then
                    if box.top - height >= 0 then
                        second = { left = box.left, width = box.width, bottom = box.top, top = box.top - height, height = height, rows = rows }
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
                    if not match then height = frameHeight; rows = model.Rows end
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
        elseif held and not placeKnown and frame - held.frame <= HOLD_FRAMES and held.box.bottom <= sh then
            -- Opening or closing the full log, the game's new place is not known for a frame or two:
            -- the last box stays rather than the game's own log showing through.
            box, rowCount, second = held.box, held.rows, held.second
            anchorStatus = 'Waiting a moment for the game\'s log to settle.'
        end
        if box then
            place[1], place[2] = box.left, box.bottom
            size[1], size[2] = box.width, box.height
            selectedWindow = state ~= nil and state.selectedWindow or nil
            -- the light and cursor on the window the game's focus is on; on the first while the second is not drawn
            local litFirst = selectedWindow ~= nil and (selectedWindow == 1 or not second)
            windowOptions.title = channels.Title(plan.snapshot and channels.Typed(plan.snapshot.text) or selectedMode or spoken)
            imgui.SetNextWindowPos(place, ImGuiCond_Always, pivot)
            imgui.SetNextWindowSize(size, ImGuiCond_Always)
            local chatFont = plan.font
            window.Plain('winxi.chatbox', open, flags, function()
                if chatFont then imgui.PushFont(chatFont, fontSize) end
                local drawn, drawError = pcall(DrawLog, box, rowCount, fontSize, padding, views[1], Filter(routes, 1), litFirst, windowOptions)
                if chatFont then imgui.PopFont() end
                if not drawn then error(drawError, 0) end
            end, windowOptions)
            lastDrawn = views[1].drawn
        end
        if firstHidden then lastDrawn = nil; selectedWindow = state ~= nil and state.selectedWindow or nil end
        -- the second box, with the first's or on its own while the first is at 0 lines
        if second and (captured or firstHidden) and secondary.Begin() then
            local chatFont = plan.font
            splitOptions.title = 'Window 2'
            imgui.SetNextWindowPos({ second.left, second.bottom }, ImGuiCond_Always, pivot)
            imgui.SetNextWindowSize({ second.width, second.height }, ImGuiCond_Always)
            window.Plain('winxi.chatbox.split', open, flags, function()
                if chatFont then imgui.PushFont(chatFont, fontSize) end
                local drawn, drawError = pcall(DrawLog, second, second.rows, fontSize, padding, views[2], Filter(routes, 2), selectedWindow == 2, splitOptions)
                if chatFont then imgui.PopFont() end
                if not drawn then error(drawError, 0) end
            end, splitOptions)
            splitDrawn = capturedSplit
            lastSplit = views[2].drawn
        end
        -- Input is independent: keep it working while waiting for the log's first geometry sample.
        input.Draw(plan.width, sh, fontSize, padding, flags, app.options.matchGameInputSize[1], plan)
    end)
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
