-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/winxi_child_background_check.lua
local imgui = require('imgui')
local style = require('winxi.style')
local theme = require('winxi.theme')
local push, pop = imgui.PushStyleColor, imgui.PopStyleColor
local stack = {}
imgui.PushStyleColor = function(id, color)
    stack[#stack + 1] = { id, color }
    return push(id, color)
end
imgui.PopStyleColor = function(count)
    assert(count <= #stack, 'style popped too many colors')
    for _ = 1, count do table.remove(stack) end
    return pop(count)
end
local function transparent()
    for i = #stack, 1, -1 do
        if stack[i][1] == ImGuiCol_ChildBg then
            return stack[i][2][4] == 0
        end
    end
    return false
end
-- Even a palette attempting to supply an opaque child color must not override the rule.
local palette = theme.Palette
theme.Palette = function(settings)
    local entries = {}
    for _, entry in ipairs(palette(settings)) do entries[#entries + 1] = entry end
    entries[#entries + 1] = { ImGuiCol_ChildBg, { 1, 0, 0, 1 } }
    return entries
end
for _, kind in ipairs({ 'game', 'settings' }) do
    for _, pushStyle in ipairs({ style.PushPlain, style.PushFull }) do
        pushStyle({ kind = kind })
        assert(transparent(), kind .. ' child background must be transparent')
        local depth = #stack
        style.PushFull({ kind = kind, alpha = 0.5 })
        assert(transparent(), 'nested child background must remain transparent')
        style.Pop()
        assert(#stack == depth and transparent(), 'nested pop must restore parent style')
        style.Pop()
        assert(#stack == 0, 'style colors must balance')
    end
end
H.print('transparent child backgrounds: plain/full, game/settings, nested, palette override, balanced stacks', true)
