-- The styles in winxi's theme, as the Winxi Theme tab sets them: the last tab, coloured apart, its
-- dropdowns showing the chosen label and keeping the key, and a closed dropdown changing nothing
H.load()
local imgui = require('imgui')
local theme = require('winxi.theme')
local widgets = require('winxi.widgets')
local config = require('config')
local saved = H.options()
local last = config.Tabs[#config.Tabs]
assert(last.name == 'Winxi Theme' and last.theme, 'Winxi Theme must be the last tab')
for _, tab in ipairs(config.Tabs) do assert(tab.name ~= 'Appearance') end

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
assert(look.BorderStyle == 'theme' and look.BarTexture == 'original' and look.BookendStyle == 'texture' and look.BackgroundStyle == 'plain')
look.BorderStyle, look.BarTexture, look.BookendStyle, look.BackgroundStyle = 'royal_platinum', 'radiant', 'match', 'gradient'
local begin, selectable, finish = imgui.BeginCombo, imgui.Selectable, imgui.EndCombo
local current, opened, ended = nil, 0, 0
local previews, selected = {}, {}
local picks = { BorderStyle = 'Crystal', BarTexture = 'Satin', BookendStyle = 'Royal Silver', BackgroundStyle = 'FFXI-inspired', TitleStyle = 'Plate' }
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
assert(opened == 5 and ended == 5)
assert(previews.BorderStyle == 'Royal Platinum' and previews.BarTexture == 'Radiant (Bright)' and previews.BookendStyle == 'Match Border' and previews.BackgroundStyle == 'Gradient')
assert(selected.BorderStyle == previews.BorderStyle and selected.BarTexture == previews.BarTexture and selected.BookendStyle == previews.BookendStyle)
assert(look.BorderStyle == 'crystal' and look.BarTexture == 'satin' and look.BookendStyle == 'royal_silver' and look.BackgroundStyle == 'ffxi' and look.TitleStyle == 'plate')
assert(previews.TitleStyle == 'Outlined Text')
-- Bookend Style is only offered with bookends on
look.Bookends, opened = false, 0
last.draw(saved)
assert(opened == 4)
look.Bookends = true
-- Title Style is only offered with frame titles on
look.FrameTitles, opened = false, 0
last.draw(saved)
assert(opened == 4)
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
assert(look.BorderStyle == 'theme' and look.BarTexture == 'original' and look.StatusIcons == true)
H.print('theme styles: last coloured tab, dropdowns, saved keys, previews, selection and closed menus', true)
