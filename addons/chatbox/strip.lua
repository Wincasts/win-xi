-- The expanded log's tabs, drawn as winxi's buttons along the top of the log. uihook measures the game's tab
-- strip as it is drawn and, asked, leaves it undrawn; which tabs there are, their order and which is chosen
-- are the game's, read from that strip, and choosing one (Square, the arrows) is still the game's. The game
-- draws each tab not chosen only its first 30 units wide, the next one over the rest; these are all whole,
-- side by side from where the game's strip starts, as wide as the longest name needs (all the same width,
-- as the game's), narrowed only to fit the log. Each is a winxi game window's button: rounded at the
-- style's FrameRounding, the theme's button colour (the border colour, faint), the Highlight Color for the
-- chosen tab, over the log's background (the strip may stand above its frame), its short name (Win 1, LS 1,
-- A (J)...) centred in the chat's font a little smaller than its Font Size with winxi's dark edge, cut to what
-- fits. No mouse light: the game's hit-tests for its tabs
-- are its own places, not these. A tab is named by its art, which uihook gives as its channel, through the
-- client's own pairing of art and filter (channels.Art) to the filter's name; one whose art is not known by
-- its place.
local imgui = require('imgui')
local text = require('winxi.text')
local M = { Gap = 4, Padding = 10, Grow = 4, Rounding = 4, Inset = 3 }

-- The name cut to fit a width, a letter at a time from its end (the names are the game's English ones)
function M.Fit(name, width, measure)
    local label = name
    while #label > 1 and measure(label) > width do label = label:sub(1, -2) end
    return label
end

-- The tabs left to right, each with its name: its art's filter's tab name (or its name), or 'Tab n'
function M.Named(strip, filters, art)
    local sorted = {}
    for i, tab in ipairs(strip) do sorted[i] = tab end
    table.sort(sorted, function(a, b) return a.left < b.left end)
    local named = {}
    for i, tab in ipairs(sorted) do
        local filter = tab.channel ~= nil and art[tab.channel] or nil
        local known = filter ~= nil and filters[filter] or nil
        named[i] = { tab = tab, name = known and (known.tab or known.name) or ('Tab ' .. i) }
    end
    return named
end

-- Where each is drawn: from the strip's left, each Padding either side of the longest name, Gap apart, all
-- one width, narrowed so the row ends by right (the log's edge), Grow taller than the game's strip upward, its foot
-- at foot (the log's frame's top) or the game's. Sets left and right on each; returns the row's top and bottom.
function M.Layout(named, right, measure, foot)
    local top, bottom, start, widest = nil, nil, nil, 0
    for _, entry in ipairs(named) do
        local tab = entry.tab
        top = math.min(top or tab.top, tab.top)
        bottom = math.max(bottom or tab.bottom, tab.bottom)
        start = math.min(start or tab.left, tab.left)
        widest = math.max(widest, (measure(entry.name)))
    end
    local width = widest + 2 * M.Padding
    local count = #named
    if right and count > 0 and start + count * width + (count - 1) * M.Gap > right then
        width = math.max(1, (right - start - (count - 1) * M.Gap) / count)
    end
    for i, entry in ipairs(named) do
        entry.left = start + (i - 1) * (width + M.Gap)
        entry.right = entry.left + width
    end
    if top and foot then top, bottom = foot - (bottom - top), foot end
    return top and top - M.Grow, bottom
end

-- strip: the tabs as winxi.nativechat gives them (left, top, right, bottom, channel, selected). filters:
-- filter -> { name = ... }; art: a tab's art (its channel) -> filter. colors: button, chosen, text (each a
-- table of four), background (under the buttons; may be nil), right (where the row must end) and foot (where its
-- foot stands: the log's frame's top), each may be nil.
-- measure(words) -> width, height.
function M.Draw(list, strip, filters, art, colors, measure)
    local named = M.Named(strip, filters, art)
    if #named == 0 then return end
    local top, bottom = M.Layout(named, colors.right, measure, colors.foot)
    local style = imgui.GetStyle and imgui.GetStyle()
    local rounding = style and style.FrameRounding or M.Rounding
    for _, entry in ipairs(named) do
        local a, b = { entry.left, top }, { entry.right, bottom }
        local radius = math.floor(math.min(rounding, (bottom - top) / 2, (entry.right - entry.left) / 2))
        if colors.background then list:AddRectFilled(a, b, imgui.GetColorU32(colors.background), radius) end
        list:AddRectFilled(a, b, imgui.GetColorU32(entry.tab.selected and colors.chosen or colors.button), radius)
        local label = M.Fit(entry.name, entry.right - entry.left - 2 * M.Inset, measure)
        local width, height = measure(label)
        text.Draw(list, entry.left + (entry.right - entry.left - width) / 2, top + (bottom - top - height) / 2, colors.text, label, 1)
    end
end
return M
