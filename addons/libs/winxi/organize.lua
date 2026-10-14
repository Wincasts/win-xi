-- winxi.organize: arranging an addon's windows on screen.
--
-- While organizing, the addon shows its windows filled with sample data so that they can be dragged
-- into place. Each is labelled, an alignment grid can be drawn behind them, and dropping one window
-- onto another links them: the dropped window snaps against the side it was dropped towards and is
-- held there, a fixed gap away, as the other moves or changes size. A small Unlink button beside each
-- linked window breaks its link. Links are the addon's to save: it hands over a list, which is added
-- to and removed from in place.
--
-- Once, after loading settings (and again whenever they are replaced):
--     organize.SetLinks(settings.links)          -- a list, kept wherever the addon keeps its settings
--     organize.SetLabels({ ['window name'] = 'Label' })   -- optional: what each window is called
--
-- Every frame:
--     organize.BeginFrame()                      -- before any window; draws the grid while organizing
--     ... for each window that can be arranged:
--         organize.Place(name, pos)              -- before its Begin: pos is its saved { x, y }
--         organize.Label(name)                   -- inside it, before its content
--         organize.Track(name, pos)              -- inside it, after its content
--     organize.EndFrame()                        -- after every window; draws the Unlink buttons
--
-- organize.IsActive() says whether the windows are being arranged, for the addon to draw sample data
-- and to let the mouse reach windows that are otherwise click-through. organize.Controls() draws the
-- Organize button, with the grid's checkbox beside it while organizing, for a settings window.
-- organize.IsLinked(name) says whether a window is held against another, which decides where it is.
local bit = require('bit');
local imgui = require('imgui');
local tooltip = require('winxi.tooltip');

local organize = {};

local active = false;
local gridOn = { true };

local labels = {};     -- window name -> what it is called while organizing
local links = {};      -- { child = window name, parent = window name, side = 'below'|'above'|'right'|'left' }
local rects = {};      -- window name -> where it was last drawn: { x, y, w, h, frame }
local frame = 0;
local dragging = nil;  -- the window the mouse went down on, and where it was then: { name, x, y }

local linkGap = 5;     -- between a linked window and the one it is held against

local labelText = { 0.81, 0.81, 0.50, 1.0 };
local labelBackground = { 0.08, 0.08, 0.08, 0.8 };

-- Two points, reused for whatever is drawn or placed next: imgui copies them as it is given them
local from, to = { 0, 0 }, { 0, 0 };

function organize.IsActive()
    return active;
end

function organize.SetActive(value)
    active = value and true or false;
end

-- Hands over the saved list of links, which is then added to and removed from in place
function organize.SetLinks(savedLinks)
    links = savedLinks or {};
end

function organize.SetLabels(windowLabels)
    labels = windowLabels or {};
end

local function LabelFor(name)
    return labels[name] or name;
end

local function FindLink(child)
    for index, link in ipairs(links) do
        if link.child == child then
            return link, index;
        end
    end
    return nil;
end

-- Whether a window is held against another, which then decides where it is
function organize.IsLinked(name)
    return FindLink(name) ~= nil;
end

-- True when ancestor is the parent of name, or its parent's parent, and so on
local function IsLinkedUnder(name, ancestor)
    local link = FindLink(name);
    local steps = 0;
    while link ~= nil and steps < 32 do
        if link.parent == ancestor then
            return true;
        end
        link = FindLink(link.parent);
        steps = steps + 1;
    end
    return false;
end

-- Where a linked window belongs, from where its parent was last drawn. Nothing when it has no link, or
-- when there is not yet enough to go on. The same table is handed back each time, to be used at once:
-- this runs for every window, every frame.
local linkedPos = { 0, 0 };

local function LinkedPos(name)
    local link = FindLink(name);
    if link == nil then
        return nil;
    end

    local parent = rects[link.parent];
    if parent == nil then
        return nil;
    end

    local pos = linkedPos;
    if link.side == 'below' then
        pos[1], pos[2] = parent.x, parent.y + parent.h + linkGap;
        return pos;
    elseif link.side == 'right' then
        pos[1], pos[2] = parent.x + parent.w + linkGap, parent.y;
        return pos;
    end

    -- above and to the left depend on the window's own size as well
    local own = rects[name];
    if own == nil then
        return nil;
    end

    if link.side == 'above' then
        pos[1], pos[2] = parent.x, parent.y - linkGap - own.h;
    else
        pos[1], pos[2] = parent.x - linkGap - own.w, parent.y;
    end
    return pos;
end

-- Positions the window about to be drawn: against its parent if it is linked, unless it is the one
-- being dragged, otherwise wherever it was left. pos is the window's saved { x, y }, kept up to date.
function organize.Place(name, pos)
    local linked = nil;
    if dragging == nil or dragging.name ~= name then
        linked = LinkedPos(name);
    end

    if linked ~= nil then
        pos[1], pos[2] = linked[1], linked[2];
        imgui.SetNextWindowPos(linked, ImGuiCond_Always);
    else
        imgui.SetNextWindowPos(pos, ImGuiCond_FirstUseEver);
    end
end

-- Names the window being drawn, while organizing. The name goes just above the window, outside it, so
-- the window keeps its real size; below it when there is no room above.
function organize.Label(name)
    if not active then
        return;
    end

    local text = LabelFor(name);

    -- Older builds cannot draw outside a window: there the name becomes the window's first line
    if imgui.GetForegroundDrawList == nil then
        imgui.PushStyleColor(ImGuiCol_Text, labelText);
        imgui.Text(('[ %s ]'):format(text));
        imgui.PopStyleColor();
        return;
    end

    local x, y = imgui.GetWindowPos();
    local _, windowHeight = imgui.GetWindowSize();
    local textWidth, textHeight = imgui.CalcTextSize(text);

    local labelY = y - textHeight - 6;
    if labelY < 0 then
        labelY = y + windowHeight + 2;
    end

    local drawList = imgui.GetForegroundDrawList();
    from[1], from[2] = x, labelY;
    to[1], to[2] = x + textWidth + 8, labelY + textHeight + 4;
    drawList:AddRectFilled(from, to, imgui.GetColorU32(labelBackground), 2);
    from[1], from[2] = x + 4, labelY + 2;
    drawList:AddText(from, imgui.GetColorU32(labelText), text);
end

-- Notes where the window being drawn is, and whether a drag has just started on it
function organize.Track(name, pos)
    local x, y = imgui.GetWindowPos();
    local w, h = imgui.GetWindowSize();

    pos[1], pos[2] = x, y;

    local rect = rects[name];
    if rect == nil then
        rect = {};
        rects[name] = rect;
    end
    rect.x, rect.y, rect.w, rect.h, rect.frame = x, y, w, h, frame;

    if active and dragging == nil and imgui.IsWindowHovered() and imgui.IsMouseClicked(0) then
        dragging = { name = name, x = x, y = y };
    end
end

-- A dragged window has been let go. If it was dropped overlapping another window it is linked to that
-- one (the one it overlaps most), on whichever side it was dropped towards.
local function ResolveDrop(drag)
    local own = rects[drag.name];
    if own == nil then
        return;
    end

    -- a click, not a drag
    if math.abs(own.x - drag.x) < 3 and math.abs(own.y - drag.y) < 3 then
        return;
    end

    local target, targetArea = nil, 0;
    for name, other in pairs(rects) do
        -- only windows on screen now, and never one that is itself held against the dragged window
        if name ~= drag.name and other.frame >= frame - 1 and not IsLinkedUnder(name, drag.name) then
            local overlapW = math.min(own.x + own.w, other.x + other.w) - math.max(own.x, other.x);
            local overlapH = math.min(own.y + own.h, other.y + other.h) - math.max(own.y, other.y);
            if overlapW > 0 and overlapH > 0 and overlapW * overlapH > targetArea then
                target, targetArea = name, overlapW * overlapH;
            end
        end
    end

    if target == nil then
        return;
    end

    -- which side: compare the two centres, scaled so a wide window does not always win sideways
    local other = rects[target];
    local dx = ((own.x + own.w / 2) - (other.x + other.w / 2)) / ((own.w + other.w) / 2);
    local dy = ((own.y + own.h / 2) - (other.y + other.h / 2)) / ((own.h + other.h) / 2);

    local side;
    if math.abs(dy) >= math.abs(dx) then
        side = dy >= 0 and 'below' or 'above';
    else
        side = dx >= 0 and 'right' or 'left';
    end

    local link = FindLink(drag.name);
    if link ~= nil then
        link.parent = target;
        link.side = side;
    else
        table.insert(links, { child = drag.name, parent = target, side = side });
    end
end

local gridSpacing = 25;
local gridColor = { 1.0, 1.0, 1.0, 0.12 };
local gridCenterColor = { 1.0, 1.0, 1.0, 0.45 };
local gridVisible = { true };
local gridFlags = nil;
local gridName = nil;
local noPadding = { 0, 0 };

local function Line(drawList, x1, y1, x2, y2, color, thickness)
    from[1], from[2] = x1, y1;
    to[1], to[2] = x2, y2;
    drawList:AddLine(from, to, color, thickness);
end

-- A grid over the whole screen for lining windows up against, with bold lines through the centre.
-- The lines are spaced outwards from the centre, so the grid is the same on both sides of it.
-- Drawn in a see-through window of its own that takes no input and stays behind the others.
local function DrawGrid()
    local display = imgui.GetIO().DisplaySize;
    local width, height = display.x, display.y;
    local centerX, centerY = math.floor(width / 2), math.floor(height / 2);

    gridFlags = gridFlags or bit.bor(
        ImGuiWindowFlags_NoDecoration,
        ImGuiWindowFlags_NoInputs,
        ImGuiWindowFlags_NoSavedSettings,
        ImGuiWindowFlags_NoBackground or 0,
        ImGuiWindowFlags_NoBringToFrontOnFocus or 0,
        ImGuiWindowFlags_NoFocusOnAppearing or 0);

    -- every addon draws in the one imgui, so the window is named for the addon it belongs to
    gridName = gridName or ('winxi.grid.' .. addon.name);

    from[1], from[2] = 0, 0;
    to[1], to[2] = width, height;
    imgui.SetNextWindowPos(from);
    imgui.SetNextWindowSize(to);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, noPadding);

    if imgui.Begin(gridName, gridVisible, gridFlags) then
        local drawList = imgui.GetWindowDrawList();
        local thin = imgui.GetColorU32(gridColor);
        local bold = imgui.GetColorU32(gridCenterColor);

        for offset = gridSpacing, math.max(centerX, centerY), gridSpacing do
            if offset <= centerX then
                Line(drawList, centerX - offset, 0, centerX - offset, height, thin, 1);
                Line(drawList, centerX + offset, 0, centerX + offset, height, thin, 1);
            end
            if offset <= centerY then
                Line(drawList, 0, centerY - offset, width, centerY - offset, thin, 1);
                Line(drawList, 0, centerY + offset, width, centerY + offset, thin, 1);
            end
        end

        Line(drawList, centerX, 0, centerX, height, bold, 3);
        Line(drawList, 0, centerY, width, centerY, bold, 3);
    end

    imgui.End();
    imgui.PopStyleVar();
    gridVisible[1] = true;
end

-- Call once a frame, before any window is drawn
function organize.BeginFrame()
    frame = frame + 1;

    if dragging ~= nil and not imgui.IsMouseDown(0) then
        if active then
            ResolveDrop(dragging);
        end
        dragging = nil;
    end

    if active and gridOn[1] then
        DrawGrid();
    end
end

local unlinkVisible = { true };
local unlinkFlags = nil;
local unlinkPadding = { 4, 4 };
local unlinkPivot = { 1, 0 };  -- the button's top right corner goes at the point
local unlinkNames = {};        -- window name -> its button's window: made once

-- Call once a frame, after every window has been drawn. While organizing, puts a small floating Unlink
-- button beside each linked window, for breaking its link.
function organize.EndFrame()
    if not active then
        return;
    end

    unlinkFlags = unlinkFlags or bit.bor(
        ImGuiWindowFlags_NoDecoration,
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoSavedSettings,
        ImGuiWindowFlags_NoMove or 0,
        ImGuiWindowFlags_NoFocusOnAppearing or 0);

    for index = #links, 1, -1 do
        local link = links[index];
        local rect = rects[link.child];

        if rect ~= nil and rect.frame == frame then
            -- beside the window's top corner, on the side away from its parent
            if link.side == 'left' then
                from[1], from[2] = rect.x - 4, rect.y;
                imgui.SetNextWindowPos(from, ImGuiCond_Always, unlinkPivot);
            else
                from[1], from[2] = rect.x + rect.w + 4, rect.y;
                imgui.SetNextWindowPos(from, ImGuiCond_Always);
            end

            local name = unlinkNames[link.child];
            if name == nil then
                name = 'winxi.unlink.' .. link.child;
                unlinkNames[link.child] = name;
            end

            imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, unlinkPadding);
            if imgui.Begin(name, unlinkVisible, unlinkFlags) then
                if imgui.Button('Unlink') then
                    table.remove(links, index);
                end
                if imgui.IsItemHovered() then
                    tooltip.Show(('Stop holding %s against %s.'):format(LabelFor(link.child), LabelFor(link.parent)));
                end
            end
            imgui.End();
            imgui.PopStyleVar();
            unlinkVisible[1] = true;
        end
    end
end

local buttonOn = { 0.23, 0.67, 0.91, 1.0 }; -- the Organize button while it is switched on

-- The Organize button, against the right edge of the line it is on, with the grid's checkbox to its
-- left while organizing. For the foot of a settings window. framePadding is the horizontal frame padding
-- in use there (4 if not given), which the button's width depends on.
function organize.Controls(framePadding)
    if active then
        imgui.Checkbox('Alignment Grid', gridOn);
        if imgui.IsItemHovered() then
            tooltip.Show('Draws a grid over the screen while organizing, with bold lines through the centre.');
        end
        imgui.SameLine();
    end

    -- right-aligned by hand: the button is as wide as its label and the frame padding either side of it
    local label = 'Organize';
    local width = imgui.CalcTextSize(label) + 2 * (framePadding or 4);
    local available = imgui.GetContentRegionAvail();
    imgui.SetCursorPosX(imgui.GetCursorPosX() + math.max(0, available - width));

    -- lit while it is switched on
    local wasActive = active;
    if wasActive then
        imgui.PushStyleColor(ImGuiCol_Button, buttonOn);
    end
    if imgui.Button(label) then
        active = not active;
    end
    if wasActive then
        imgui.PopStyleColor();
    end

    if imgui.IsItemHovered() then
        tooltip.Show('Shows the windows filled with sample data, so they can be dragged into place and compared.\nEach is labelled.\nDrop one window onto another to link them: it snaps against the side it was dropped towards and stays there. Unlink with the button beside it.\nPress again to finish.');
    end
end

return organize;
