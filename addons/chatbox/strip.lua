-- The expanded log's tabs, drawn in WinXI's look where the game draws its own. uihook measures the game's
-- tab strip as it is drawn and, asked, leaves it undrawn, so these stand exactly where the game's hit-tests
-- and Square selection are: choosing a tab is still the game's. Each tab is a block with a rounded top in
-- the Highlight Color, the chosen one solid and the rest faint, the theme's tab style over it, and the
-- channel's name in the chat's font with winxi's dark edge, cut to what fits. Under the row, the tab
-- style's line, brighter under the chosen tab.
local imgui = require('imgui')
local tabs = require('winxi.tabs')
local text = require('winxi.text')
local M = { Radius = 4, Faint = 0.35, Chosen = 1.6, Inset = 3 }

-- The name cut to fit a width, a letter at a time from its end (the names are the game's English ones)
function M.Fit(name, width, measure)
    local label = name
    while #label > 1 and measure(label) > width do label = label:sub(1, -2) end
    return label
end

-- strip: the tabs as winxi.nativechat gives them (left, top, right, bottom, channel, selected), left to
-- right. names: channel -> { name = ... }. color: the labels' colour. measure(words) -> width, height.
function M.Draw(list, strip, names, highlight, color, measure)
    local left, right, bottom, chosenLeft, chosenRight = math.huge, -math.huge, nil, nil, nil
    local flags = ImDrawFlags_RoundCornersTop or 0
    for place, tab in ipairs(strip) do
        local fill = { highlight[1], highlight[2], highlight[3], tab.selected and math.min(1, highlight[4] * M.Chosen) or highlight[4] * M.Faint }
        list:AddRectFilled({ tab.left, tab.top }, { tab.right, tab.bottom }, imgui.GetColorU32(fill), M.Radius, flags)
        tabs.Over(list, tab.left, tab.top, tab.right, tab.bottom, M.Radius)
        local known = tab.channel and names[tab.channel]
        local label = M.Fit(known and known.name or ('Tab ' .. place), tab.right - tab.left - 2 * M.Inset, measure)
        local width, height = measure(label)
        text.Draw(list, tab.left + (tab.right - tab.left - width) / 2, tab.top + (tab.bottom - tab.top - height) / 2, color, label, 1)
        if tab.selected then chosenLeft, chosenRight = tab.left, tab.right end
        left, right, bottom = math.min(left, tab.left), math.max(right, tab.right), tab.bottom
    end
    if bottom then tabs.Line(list, left, right, bottom, chosenLeft, chosenRight) end
end
return M
