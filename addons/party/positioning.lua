-- Edge-relative automatic layout in output pixels. Manual positions are left intact.
local M = {}
local function valid(value)
    return type(value) == 'number' and value == value and value > 0 and value < math.huge
end
function M.Layout(width, height, mainHeight, targetHeight, allianceHeight)
    if not valid(width) or not valid(height) then return nil end
    local mainTop = height - 15 - mainHeight
    local targetTop = mainTop - 5 - targetHeight
    -- Two full alliance parties, separated by the existing 5px link gap. Their
    -- position does not depend on current party sizes or target visibility.
    local allianceTop = targetTop - 35 - allianceHeight * 2 - 5
    return { width = width, height = height, mainTop = mainTop,
        allianceTop = allianceTop, allianceHeight = allianceHeight }
end
function M.Managed(key)
    return key == 'party1' or key == 'party2' or key == 'party3' or key == 'main'
end
function M.Place(key, width, height, layout, currentMainTop, currentAllianceBottom)
    local x = layout.width - 15 - width
    local y
    if key == 'party1' then y = layout.height - 15 - height
    elseif key == 'main' then y = (currentMainTop or layout.mainTop) - 5 - height
    elseif key == 'party2' then y = layout.allianceTop
    elseif key == 'party3' then y = (currentAllianceBottom or (layout.allianceTop + layout.allianceHeight)) + 5
    else return nil end
    return M.Clamp(x, y, width, height, layout.width, layout.height)
end
-- Oversized layouts cannot preserve every requested gap. Keep the window accessible.
function M.Clamp(x, y, width, height, screenWidth, screenHeight)
    if not valid(screenWidth) or not valid(screenHeight) then return x, y end
    return math.max(0, math.min(x, math.max(0, screenWidth - width))),
        math.max(0, math.min(y, math.max(0, screenHeight - height)))
end
return M
