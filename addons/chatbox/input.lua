-- A WinXI front end to FFXI's own input controller. Never grab ImGui keyboard focus:
-- the game retains mode shortcuts, command dispatch, history, IME and auto-translate.
local M = {}
function M.Prompt()
    return '> '
end
function M.Snapshot(chat, decode)
    if chat:IsInputOpen() ~= 0x11 then return nil end
    local raw = chat:GetInputTextRaw()
    if type(raw) ~= 'string' or #raw > 8192 then error('Input buffer unavailable') end
    local ok, display = pcall(function() return chat:GetInputTextDisplay() end)
    if not ok or type(display) ~= 'string' or display == '' then display = raw end
    if #display > 32768 then error('Input display buffer too large') end
    -- The native display inserts 7F FF at the caret. Prefer that over a raw-byte index
    -- while previewing auto-translate or IME, where display and raw lengths can differ.
    local marker = display:find('\127\255', 1, true)
    local prefix
    if marker then prefix = display:sub(1, marker - 1)
    else
        local position = chat:GetInputTextRawCaretPosition()
        if type(position) ~= 'number' or position ~= position then error('Input caret unavailable') end
        prefix = raw:sub(1, math.max(0, math.min(#raw, math.floor(position))))
    end
    local text, before = decode(display, true), decode(prefix, true)
    if not text or not before then error('Input decoding unavailable') end
    return { text = text:gsub('[\r\n]', ' '), before = before:gsub('[\r\n]', ' ') }
end

-- The bar's place and size. top and bottom: the room above and below the line (padding where not
-- given). The bar is its line and that room tall; matched to the native bar, it takes the native bar's
-- place, width and height, but never less than its line and that room, so the text is never shrunk to
-- fit: a larger Text Size grows the bar upward from the native bar's foot. The line is centred in
-- the whole bar, regardless of asymmetric size allowances. The native bitmap font is not copied.
function M.Layout(width, screenWidth, screenHeight, fontSize, padding, rect, top, bottom)
    top, bottom = top or padding, bottom or padding
    local layout = { x = 20, bottom = screenHeight - 20, width = width,
        height = fontSize + top + bottom, fontSize = fontSize, padding = padding, matched = false,
        top = top, bottomPadding = bottom }
    if type(rect) ~= 'table' or #rect ~= 4 then return layout end
    for _, value in ipairs(rect) do
        if type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge then return layout end
    end
    local w, h = rect[3] - rect[1], rect[4] - rect[2]
    if w < 32 or h < 8 or h > 256 or rect[1] < 0 or rect[2] < 0
        or rect[3] > screenWidth or rect[4] > screenHeight then return layout end
    layout.x, layout.bottom, layout.width = rect[1], rect[4], w
    layout.height = math.max(h, fontSize + top + bottom)
    layout.matched = true
    return layout
end

function M.New()
    local imgui = require('imgui')
    local window = require('winxi.window')
    local native = require('winxi.nativechat')
    local encoding = require('encoding')
    local render = require('render')
    local hook = native.new(native.Input)
    local scroll, problem = 0, nil
    local bar = {}
    function bar.Stop() hook.Stop(); scroll = 0 end
    function bar.Status() return problem or hook.Status() end
    function bar.Measure(width, screenHeight, fontSize, padding, matchGameSize, top, bottom)
        local display = imgui.GetIO().DisplaySize
        local rect = { hook.Rect(display.x or display[1], screenHeight) }
        local layout = M.Layout(width, display.x or display[1], screenHeight, fontSize, padding, matchGameSize and rect or nil, top, bottom)
        layout.sourceRect = rect
        local ok, snapshot = pcall(M.Snapshot, AshitaCore:GetChatManager(), encoding.Decode)
        layout.active, layout.snapshot = ok and snapshot ~= nil, ok and snapshot or nil
        problem = not ok and tostring(snapshot) or nil
        if matchGameSize and layout.active and not layout.matched then
            problem = 'Native input size unavailable; using compact WinXI size until fresh geometry is available.'
        end
        return layout
    end
    function bar.Draw(width, screenHeight, fontSize, padding, flags, matchGameSize, prepared)
        local layout = prepared or bar.Measure(width, screenHeight, fontSize, padding, matchGameSize)
        if not layout.active then bar.Stop(); return false end
        if not hook.Begin() then return false end
        local snapshot = layout.snapshot
        local captured, minSizePushed = false, false
        local drawn, err = pcall(function()
            imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, { 1, 1 })
            minSizePushed = true
            width, fontSize, padding = layout.width, layout.fontSize, layout.padding
            imgui.SetNextWindowPos({ layout.x, layout.bottom }, ImGuiCond_Always, { 0, 1 })
            imgui.SetNextWindowSize({ width, layout.height }, ImGuiCond_Always)
            window.Plain('winxi.chatbox.input', { true }, flags, function()
                -- Use the chat's font and padding, with the line centred in the whole bar.
                if layout.font then imgui.PushFont(layout.font, fontSize) end
                local ok, failure = pcall(function()
                    local theme = require('winxi.theme').Get()
                    local list = imgui.GetWindowDrawList()
                    local inset = layout.leftPadding or padding
                    local x = layout.x + inset
                    local y = layout.bottom - layout.height + (layout.height - fontSize) / 2
                    local prompt = M.Prompt()
                    local promptWidth = imgui.CalcTextSize(prompt)
                    local room = math.max(1, width - inset - (layout.rightPadding or padding) - promptWidth - 3)
                    local caret = render.Measure(snapshot.before)
                    -- Scroll only as necessary, keeping the caret on-screen for edits anywhere in a line.
                    scroll = math.max(0, math.min(scroll, caret))
                    if caret - scroll > room then scroll = caret - room end
                    local color = imgui.GetColorU32(layout.textColor or theme.TextColor)
                    list:AddText({ x, y }, color, prompt)
                    x = x + promptWidth
                    list:PushClipRect({ x, y }, { x + room + 2, y + fontSize }, true)
                    render.Text(list, { x - scroll, y }, color, snapshot.text)
                    if os.clock() % 1 < 0.6 then
                        list:AddLine({ x + caret - scroll, y }, { x + caret - scroll, y + fontSize }, color, 1)
                    end
                    list:PopClipRect()
                    imgui.Dummy({ width - padding * 2, layout.height - 2 * padding })
                end)
                if layout.font then imgui.PopFont() end
                if not ok then error(failure, 0) end
            end, { padding = padding, fontSize = fontSize,
                background = layout.background, border = layout.border, textColor = layout.textColor,
                capture = function() captured = hook.Capture() end })
        end)
        if minSizePushed then imgui.PopStyleVar() end
        if not drawn or not captured then
            hook.Stop()
            problem = not drawn and tostring(err) or 'Input capture failed; native input restored.'
            return false
        end
        return true
    end
    return bar
end
return M
