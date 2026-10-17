-- Auto-translate brackets are drawn as geometry, not font glyphs. Many chat
-- fonts (including ImGui's default) do not contain U+276E/U+276F.
local imgui = require('imgui')
local M = {}
local open, close = '❮', '❯'
local function Parts(text, emit)
    local at = 1
    while true do
        local a = text:find(open, at, true)
        local b = text:find(close, at, true)
        local first = a and b and math.min(a, b) or a or b
        if not first then
            if at <= #text then emit(text:sub(at), false) end
            return
        end
        if first > at then emit(text:sub(at, first - 1), false) end
        emit(text:sub(first, first + 2), true)
        at = first + 3
    end
end
function M.Measure(text)
    if not text:find(open, 1, true) and not text:find(close, 1, true) then return imgui.CalcTextSize(text) end
    local width, size = 0, imgui.GetFontSize()
    Parts(text, function(part, icon)
        width = width + (icon and size * 0.65 or imgui.CalcTextSize(part))
    end)
    return width, size
end
function M.Text(list, pos, color, text)
    if not text:find(open, 1, true) and not text:find(close, 1, true) then
        list:AddText(pos, color, text); return
    end
    local x, y, size = pos[1], pos[2], imgui.GetFontSize()
    Parts(text, function(part, icon)
        if icon then
            local opening = part == open
            local tint = imgui.GetColorU32(opening and {0.3, 1, 0.35, 1} or {1, 0.3, 0.3, 1})
            local left, right = x + size * 0.15, x + size * 0.5
            local tip, edge = opening and left or right, opening and right or left
            list:AddLine({edge, y + size * 0.2}, {tip, y + size * 0.5}, tint, math.max(1, size * 0.14))
            list:AddLine({tip, y + size * 0.5}, {edge, y + size * 0.8}, tint, math.max(1, size * 0.14))
            x = x + size * 0.65
        else
            list:AddText({x, y}, color, part)
            x = x + imgui.CalcTextSize(part)
        end
    end)
end
-- Draw ordered byte spans without exposing protocol escapes to ImGui or wrapping.
-- Source timestamp colours are preserved just like every other inline span.
function M.Rich(list, pos, color, text, spans)
    if not spans or #spans == 0 then return M.Text(list, pos, color, text) end
    local palette = require('palette')
    local at, x = 1, pos[1]
    local function Draw(first, last, tint)
        if first > last then return end
        local part = text:sub(first, last)
        M.Text(list, {x,pos[2]}, tint, part)
        x = x + M.Measure(part)
    end
    for _, span in ipairs(spans) do
        Draw(at, span.first - 1, color)
        local tint = palette.Color(span.bank, span.slot)
        Draw(span.first, span.last, tint and imgui.GetColorU32(tint) or color)
        at = span.last + 1
    end
    Draw(at, #text, color)
end
return M
