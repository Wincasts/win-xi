-- A font-independent cog: available with every winxi font, no icon asset required.
local imgui = require('imgui')
local tips = require('winxi.tooltip')
local M = {}
function M.GearSize() return imgui.GetFontSize() + 8 end
function M.GearButton()
    local size = M.GearSize()
    local clicked = imgui.Button('##parse.columns', { size, size })
    local left, top = imgui.GetItemRectMin()
    local cx, cy, radius = left + size / 2, top + size / 2, imgui.GetFontSize() * 0.46
    local draw, color = imgui.GetWindowDrawList(), imgui.GetColorU32(ImGuiCol_Text)
    local points = {}
    for tooth = 0, 7 do
        for step = 0, 3 do
            local angle = (tooth * 4 + step) * math.pi / 16
            local r = (step == 1 or step == 2) and radius or radius * 0.74
            points[#points + 1] = { cx + math.cos(angle) * r, cy + math.sin(angle) * r }
        end
    end
    for index, point in ipairs(points) do
        local nextPoint = points[index % #points + 1]
        draw:AddLine(point, nextPoint, color, 1)
    end
    draw:AddCircle({ cx, cy }, radius * 0.32, color, 12, 1)
    tips.Hover('Edit columns')
    return clicked
end
return M
