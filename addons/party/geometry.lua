-- Stable reservation sizes, invalidated by style values, font metrics, padding or pet count.
local options = require('options')
local frames = require('frames')
local geometry = {}
local previous, values = {}, {}
local mainHeight, targetHeight, allianceHeight
function geometry.Reserve(saved, padding, fontSize, spacing, petCount)
    local dirty = mainHeight == nil
    for key, value in pairs(saved.style) do
        if type(value) == 'table' then
            local old = previous[key]
            if type(old) ~= 'table' then old = {}; previous[key] = old end
            if old[1] ~= value[1] or old[2] ~= value[2] then dirty = true end
            old[1], old[2] = value[1], value[2]
        else
            if previous[key] ~= value then dirty = true end
            previous[key] = value
        end
    end
    local letters = saved.target.mainDebuffs[1] and saved.target.debuffStyle ~= 'icons'
    if values.padding ~= padding or values.fontSize ~= fontSize or values.spacing ~= spacing
        or values.pets ~= petCount or values.alliance ~= saved.party.allianceScale[1] or values.letters ~= letters then dirty = true end
    if dirty then
        values.padding, values.fontSize, values.spacing = padding, fontSize, spacing
        values.pets, values.alliance, values.letters = petCount, saved.party.allianceScale[1], letters
        local style = options.Style(saved)
        style.trimLast = true
        local _
        _, mainHeight = frames.FullSize(6, 'party', style)
        if petCount > 0 then
            local _, petHeight = frames.FullSize(petCount, 'pets', style)
            mainHeight = mainHeight + petHeight + 2 * padding + 1
        end
        mainHeight = mainHeight + 2 * padding
        style.scale = style.scale * saved.party.allianceScale[1] / 100
        _, allianceHeight = frames.FullSize(6, 'alliance', style)
        allianceHeight = allianceHeight + 2 * padding
        style = options.Style(saved)
        style.showTp, style.trimLast = true, not letters
        _, targetHeight = frames.FullSize(1, 'target', style)
        targetHeight = targetHeight + 2 * padding
        if letters then targetHeight = targetHeight + 2 * (fontSize + spacing) end
    end
    return mainHeight, targetHeight, allianceHeight
end
return geometry
