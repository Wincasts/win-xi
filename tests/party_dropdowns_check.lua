-- Party's Behavior and Visibility tabs and the shared Winxi style widgets (no Party theme tab).
H.load()
local imgui = require('imgui')
local theme = require('winxi.theme')
local widgets = require('winxi.widgets')
local config = require('config')
local saved = H.options()
assert(config.Tabs[1].name == 'Behavior', 'Behavior must be the first tab')
assert(config.Tabs[2].name == 'Visibility', 'Visibility is the second tab')
for _, tab in ipairs(config.Tabs) do
    assert(tab.name ~= 'Winxi Theme' and tab.name ~= 'Global Settings' and not tab.theme)
end
local fadeCalls, fade = 0, widgets.Fade
widgets.Fade = function(value, save, grouped)
    assert(value == saved.fade and type(save) == 'function' and grouped == true)
    fadeCalls = fadeCalls + 1
end
config.Tabs[1].draw(saved)
assert(fadeCalls == 0, 'idle fade controls are not in Behavior')
config.Tabs[2].draw(saved)
widgets.Fade = fade
assert(fadeCalls == 1, 'idle fade controls belong to Visibility')
-- Every tab has Winxi sections, and collapsed sections draw no setting controls.
local header, label = widgets.Header, widgets.Label
local headings = {}
widgets.Header = function(text, first)
    headings[#headings + 1] = text
    if #headings == 1 then assert(first, 'first section has no leading gap') end
    return false
end
widgets.Label = function() error('Collapsed section drew a setting') end
for _, tab in ipairs(config.Tabs) do
    headings = {}
    tab.draw(saved)
    assert(#headings >= 2, 'organized sections in ' .. tab.name)
    if tab.name == 'Behavior' then
        assert(headings[1] == 'Mouse Interaction')
        for _, h in ipairs(headings) do assert(h ~= 'Visibility' and h ~= 'Hide Windows' and h ~= 'Fading', h .. ' moved to Visibility') end
    end
    if tab.name == 'Visibility' then assert(headings[1] == 'Hide Windows' and headings[2] == 'Fading') end
end
widgets.Header, widgets.Label = header, label
-- The library widgets remain covered independently of Party's tabs.
local last = { draw = function() widgets.Appearance() end }

-- the tab: coloured before it is begun, the colours taken off again, and held to the right
local push, pop, beginTab = imgui.PushStyleColor, imgui.PopStyleColor, imgui.BeginTabItem
local colours, flagged = 0, nil
imgui.PushStyleColor = function(...) colours = colours + 1; return push(...) end
imgui.PopStyleColor = function(n) colours = colours - (n or 1); return pop(n) end
imgui.BeginTabItem = function(label, open, flags)
    assert(label == 'Winxi Theme' and colours >= 3, 'the theme tab is coloured')
    flagged = flags
    return true
end
assert(widgets.BeginThemeTab() and colours == 0 and flagged == ImGuiTabItemFlags_Trailing)
-- in the theme's tab colour when chosen, darker when not, lighter under the mouse; recoloured as it changes
local pushedColours = {}
imgui.PushStyleColor = function(slot, colour) pushedColours[slot] = { colour[1], colour[2], colour[3], colour[4] }; colours = colours + 1; return push(slot, colour) end
imgui.BeginTabItem = function() return true end
local tabColour = theme.Get().ThemeTabColor
tabColour[1], tabColour[2], tabColour[3], tabColour[4] = 0.5, 0.25, 0.75, 1
theme.Touch()
widgets.BeginThemeTab()
local active, idle, hovered = pushedColours[ImGuiCol_TabSelected], pushedColours[ImGuiCol_Tab], pushedColours[ImGuiCol_TabHovered]
assert(active[1] == 0.5 and active[2] == 0.25 and active[3] == 0.75 and active[4] == 1, 'chosen: the theme\'s colour')
assert(idle[1] < active[1] and idle[4] < 1, 'not chosen: darker')
assert(hovered[1] > active[1] and math.abs(hovered[3] - 0.9) < 1e-6, 'under the mouse: lighter')
theme.Reset({ 'ThemeTabColor' })
widgets.BeginThemeTab()
assert(pushedColours[ImGuiCol_TabSelected][1] == theme.Defaults.ThemeTabColor[1], 'recoloured when the theme changes')
imgui.PushStyleColor, imgui.PopStyleColor, imgui.BeginTabItem = push, pop, beginTab

-- the chosen tab of any tab bar, and the line under it, in the theme's highlight colour
local function PaletteColour(slot)
    for _, entry in ipairs(theme.Palette()) do
        if entry[1] == slot then return entry[2] end
    end
end
local highlight = theme.Get().HighlightColor
highlight[1], highlight[2], highlight[3], highlight[4] = 0.9, 0.1, 0.2, 0.7
theme.Touch()
for _, slot in ipairs({ ImGuiCol_TabSelected, ImGuiCol_TabDimmedSelected, ImGuiCol_TabSelectedOverline }) do
    local colour = PaletteColour(slot)
    assert(colour[1] == 0.9 and colour[2] == 0.1 and colour[3] == 0.2 and colour[4] == 0.7, 'chosen tab: the highlight colour')
end
assert(PaletteColour(ImGuiCol_Tab)[1] == theme.Get().BorderColor[1], 'other tabs: still from the border colour')
theme.Reset({ 'HighlightColor' })
assert(PaletteColour(ImGuiCol_TabSelected)[4] == theme.Defaults.HighlightColor[4], 'recoloured when the theme changes')

-- what is chosen would be saved to the shared theme's file: not here
local save, written = theme.Save, nil
theme.Save = function() written = true end
local look = theme.Get()
assert(look.BorderStyle == 'theme' and look.BarTexture == 'original' and look.BookendStyle == 'texture' and look.BackgroundStyle == 'plain' and look.TabStyle == 'sheen')
look.BorderStyle, look.BarTexture, look.BookendStyle, look.BackgroundStyle = 'royal_platinum', 'radiant', 'match', 'gradient'
local begin, selectable, finish = imgui.BeginCombo, imgui.Selectable, imgui.EndCombo
local current, opened, ended = nil, 0, 0
local previews, selected = {}, {}
local picks = { BorderStyle = 'Crystal', BarTexture = 'Satin', BarFrame = 'Capsule Outline', BookendStyle = 'Royal Silver', BackgroundStyle = 'FFXI-inspired', TabStyle = 'Brushed Metal', TitleStyle = 'Plate' }
imgui.BeginCombo = function(id, preview)
    current = id:match('^##winxi%.(.+)$')
    if current == 'FontFile' or current == 'TitleFontFile' or current == 'StatusIconSet' then return false end -- the fonts' (winxi_fonts_check) and the icons' (winxisettings_check)
    assert(current and picks[current], id)
    previews[current] = preview
    opened = opened + 1
    return true
end
imgui.Selectable = function(label, on)
    if on then selected[current] = label:match('^(.-)##') end
    return label:match('^(.-)##') == picks[current]
end
imgui.EndCombo = function() ended = ended + 1 end
last.draw(saved)
assert(opened == 7 and ended == 7)
assert(previews.BorderStyle == 'Royal Platinum' and previews.BarTexture == 'Radiant (Bright)' and previews.BookendStyle == 'Match Border' and previews.BackgroundStyle == 'Gradient' and previews.TabStyle == 'Sheen')
assert(selected.BorderStyle == previews.BorderStyle and selected.BarTexture == previews.BarTexture and selected.BookendStyle == previews.BookendStyle)
assert(look.BorderStyle == 'crystal' and look.BarTexture == 'satin' and look.BookendStyle == 'royal_silver' and look.BackgroundStyle == 'ffxi' and look.TabStyle == 'brushed' and look.TitleStyle == 'plate')
assert(previews.TitleStyle == 'Outlined Text')
assert(previews.BarFrame == 'Bar Texture' and look.BarFrame == 'capsule', 'Bar Frame: the texture\'s own to begin with, chosen like the rest')
-- Bookend Style is only offered with bookends on
look.Bookends, opened = false, 0
last.draw(saved)
assert(opened == 6)
look.Bookends = true
-- Title Style is only offered with frame titles on
look.FrameTitles, opened = false, 0
last.draw(saved)
assert(opened == 6)
look.FrameTitles = true
-- Closed combos should not draw selectable items or rewrite settings.
imgui.BeginCombo = function() return false end
imgui.Selectable = function() error('Closed dropdown drew items') end
ended = 0
last.draw(saved)
assert(ended == 0 and look.BorderStyle == 'crystal')
imgui.BeginCombo, imgui.Selectable, imgui.EndCombo = begin, selectable, finish
assert(written, 'a chosen style is saved')
theme.Save = save
theme.Reset()
assert(look.BorderStyle == 'theme' and look.BarTexture == 'original' and look.TabStyle == 'sheen' and look.StatusIcons == true)
H.print('Visibility tab hide and fade controls, no Party theme tab; shared theme widgets and dropdowns', true)
