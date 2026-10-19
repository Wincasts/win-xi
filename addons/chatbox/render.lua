-- Auto-translate brackets are drawn as geometry, not font glyphs. Many chat
-- fonts (including ImGui's default) do not contain U+276E/U+276F.
local imgui = require('imgui')
local M = {}
local open, close = '❮', '❯'
-- The part of text that starts at byte at: its first and last bytes and whether it is a bracket; nil past the end.
-- Walked part by part (Measure and Text), with no function made for each call.
local function Part(text, at)
    if at > #text then return nil end
    local a = text:find(open, at, true)
    local b = text:find(close, at, true)
    local first = a and b and math.min(a, b) or a or b
    if not first then return at, #text, false end
    if first > at then return at, first - 1, false end
    return first, first + 2, true
end
function M.Measure(text)
    if not text:find(open, 1, true) and not text:find(close, 1, true) then return imgui.CalcTextSize(text) end
    local width, size = 0, imgui.GetFontSize()
    local at = 1
    while true do
        local first, last, icon = Part(text, at)
        if not first then break end
        width = width + (icon and size * 0.65 or imgui.CalcTextSize(text:sub(first, last)))
        at = last + 1
    end
    return width, size
end
-- The points handed to imgui, which copies them: one table each, filled afresh for every call, not made anew
local textPos, lineFrom, lineTo, richPos = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }
local OPENING, CLOSING = { 0.3, 1, 0.35, 1 }, { 1, 0.3, 0.3, 1 }
function M.Text(list, pos, color, text)
    if not text:find(open, 1, true) and not text:find(close, 1, true) then
        list:AddText(pos, color, text); return
    end
    local x, y, size = pos[1], pos[2], imgui.GetFontSize()
    local at = 1
    while true do
        local first, last, icon = Part(text, at)
        if not first then break end
        local part = text:sub(first, last)
        if icon then
            local opening = part == open
            local tint = imgui.GetColorU32(opening and OPENING or CLOSING)
            local left, right = x + size * 0.15, x + size * 0.5
            local tip, edge = opening and left or right, opening and right or left
            lineFrom[1], lineFrom[2], lineTo[1], lineTo[2] = edge, y + size * 0.2, tip, y + size * 0.5
            list:AddLine(lineFrom, lineTo, tint, math.max(1, size * 0.14))
            lineFrom[1], lineFrom[2], lineTo[1], lineTo[2] = tip, y + size * 0.5, edge, y + size * 0.8
            list:AddLine(lineFrom, lineTo, tint, math.max(1, size * 0.14))
            x = x + size * 0.65
        else
            textPos[1], textPos[2] = x, y
            list:AddText(textPos, color, part)
            x = x + imgui.CalcTextSize(part)
        end
        at = last + 1
    end
end
-- Draw ordered byte spans without exposing protocol escapes to ImGui or wrapping.
-- Source timestamp colours are preserved just like every other inline span.
-- keep (optional): a table that lasts as long as the row, with font and size the font it is drawn in: its parts and
-- where each starts are kept on it, measured once rather than every frame (their colours are still looked up each
-- time, so a change to the game's colours shows at once).
local palette -- required on first use: this module also stands alone
local function Parts(text, spans)
    local parts, at, x = {}, 1, 0
    local function Add(first, last, span)
        if first > last then return end
        local part = text:sub(first, last)
        parts[#parts + 1] = { text = part, x = x, span = span }
        x = x + M.Measure(part)
    end
    for _, span in ipairs(spans) do
        Add(at, span.first - 1, nil)
        Add(span.first, span.last, span)
        at = span.last + 1
    end
    Add(at, #text, nil)
    return parts
end
function M.Rich(list, pos, color, text, spans, keep, font, size)
    if not spans or #spans == 0 then return M.Text(list, pos, color, text) end
    local parts
    if keep and keep.richText == text and keep.richFont == font and keep.richSize == size and keep.richParts then
        parts = keep.richParts
    else
        parts = Parts(text, spans)
        if keep and font ~= nil and size ~= nil then keep.richText, keep.richFont, keep.richSize, keep.richParts = text, font, size, parts end
    end
    palette = palette or require('palette')
    local x, y = pos[1], pos[2]
    for _, part in ipairs(parts) do
        local tint = color
        if part.span then
            local found = palette.Color(part.span.bank, part.span.slot)
            if found then tint = imgui.GetColorU32(found) end
        end
        richPos[1], richPos[2] = x + part.x, y
        M.Text(list, richPos, tint, part.text)
    end
end
return M
