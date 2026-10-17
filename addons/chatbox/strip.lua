-- The expanded log's tabs, drawn in WinXI's look where the game draws its own. uihook measures the game's
-- tab strip as it is drawn and, asked, leaves it undrawn, so these stand exactly where the game's hit-tests
-- and Square selection are: choosing a tab is still the game's. The game's tabs overlap at their edges
-- and are stacked: they are drawn in the order the game drew them, each over the ones before it, and
-- the chosen one last, on top of all. Each is a square-cornered box, as winxi's windows are: the window's
-- background colour, so that it covers what is under it, the Highlight Color over that (solid for the
-- chosen one, faint for the rest), the theme's tab style over both, and an edge in the border colour,
-- so that where one lies over another the join shows. The tab's name, in the chat's font with winxi's
-- dark edge, is centred in the part of the tab left uncovered, cut to what fits there. With the whole
-- strip drawn, the tabs are named by where they stand, left to right (channels.TabNames: Window, Say,
-- Tell, Party, Linkshell 1, Linkshell 2, Assist (J), Assist (E), Unity, Shout); with fewer, by the
-- channel whose sprite each was drawn with, or its place.
local imgui = require('imgui')
local tabs = require('winxi.tabs')
local text = require('winxi.text')
local M = { Faint = 0.35, Chosen = 1.6, Inset = 3 }

-- The name cut to fit a width, a letter at a time from its end (the names are the game's English ones)
function M.Fit(name, width, measure)
    local label = name
    while #label > 1 and measure(label) > width do label = label:sub(1, -2) end
    return label
end

-- The order to draw in: the game's, the chosen tab moved to the end
function M.Order(strip)
    local order, chosen = {}, nil
    for _, tab in ipairs(strip) do
        if tab.selected and not chosen then chosen = tab else order[#order + 1] = tab end
    end
    if chosen then order[#order + 1] = chosen end
    return order
end

-- What of a tab is left uncovered by the tabs drawn after it: its left and right, the overlaps taken off
function M.Uncovered(order, at)
    local tab = order[at]
    local left, right = tab.left, tab.right
    for after = at + 1, #order do
        local over = order[after]
        if over.left < right and over.right > left then
            if over.left > tab.left then right = math.min(right, over.left) else left = math.max(left, over.right) end
        end
    end
    return left, math.max(left, right)
end

-- Each tab's name: by its rank from the left when the strip is whole, else by its channel or place
function M.Names(strip, names, byPlace)
    local ranked = {}
    for i, tab in ipairs(strip) do ranked[i] = tab end
    table.sort(ranked, function(a, b) return a.left < b.left end)
    local result = {}
    for rank, tab in ipairs(ranked) do
        local known = #strip == #byPlace and byPlace[rank] or (tab.channel and names[tab.channel] and names[tab.channel].name)
        result[tab] = known or ('Tab ' .. rank)
    end
    return result
end

-- strip: the tabs as winxi.nativechat gives them (left, top, right, bottom, channel, selected), in the
-- game's draw order. names: channel -> { name = ... }; byPlace: the names left to right for a whole
-- strip. colors: highlight, text, border, background (each a table of four; background and border may
-- be nil). measure(words) -> width, height.
function M.Draw(list, strip, names, byPlace, colors, measure)
    local order = M.Order(strip)
    local named = M.Names(strip, names, byPlace)
    local highlight = colors.highlight
    for at, tab in ipairs(order) do
        local a, b = { tab.left, tab.top }, { tab.right, tab.bottom }
        if colors.background then list:AddRectFilled(a, b, imgui.GetColorU32(colors.background)) end
        local fill = { highlight[1], highlight[2], highlight[3], tab.selected and math.min(1, highlight[4] * M.Chosen) or highlight[4] * M.Faint }
        list:AddRectFilled(a, b, imgui.GetColorU32(fill))
        tabs.Over(list, tab.left, tab.top, tab.right, tab.bottom, 0)
        if colors.border then list:AddRect(a, b, imgui.GetColorU32(colors.border)) end
        local left, right = M.Uncovered(order, at)
        local label = M.Fit(named[tab], right - left - 2 * M.Inset, measure)
        local width, height = measure(label)
        text.Draw(list, left + (right - left - width) / 2, tab.top + (tab.bottom - tab.top - height) / 2, colors.text, label, 1)
    end
end
return M
