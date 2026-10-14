-- winxi.tooltip: tooltips in winxi's look, for every addon that draws with winxi.
--
--   tooltip.Hover(text)   after a control: shows text while the control is under the mouse. In place of
--                         if imgui.IsItemHovered() then imgui.SetTooltip(text) end
--   tooltip.Show(text)    shows text now, for an addon that has asked imgui itself what is hovered
--   tooltip.Begin()       for a tooltip of anything else (images, several lines, colours): returns
--   tooltip.End()         whether it is shown, and if so its content follows and tooltip.End() after
--
--     if imgui.IsItemHovered() and tooltip.Begin() then
--         imgui.Image(icon, size);
--         imgui.Text(name);
--         tooltip.End();
--     end
--
-- How every tooltip looks and behaves is the shared theme's (winxi.theme's Tooltip keys, set in
-- winxisettings), whether or not the addon follows the shared theme for its windows: whether tooltips
-- are shown at all, how long the mouse rests before one shows, its colours, padding, text size and how
-- wide it grows before its words go on to another line.
local imgui = require('imgui');
local theme = require('winxi.theme');

local tooltip = {};

-- Asked for again within this many seconds, a tooltip is still the one that was waiting: moving from
-- one control to the next does not start the wait again, as imgui's own tooltips have it
local stillAsked = 0.1;
local lastAsked = -1;   -- when a tooltip was last asked for
local waitingSince = 0; -- when the mouse came to rest over something with one

local padding = { 6, 6 };
local opened = {};      -- what tooltip.Begin pushed, for tooltip.End: { colours, vars, font }

-- imgui's clock, where this build of imgui gives it
local function Now()
    return tonumber(imgui.GetTime ~= nil and imgui.GetTime()) or os.clock();
end

-- Whether the mouse has rested long enough for the tooltip to show
local function Waited(delay)
    local now = Now();
    if now - lastAsked > stillAsked then
        waitingSince = now;
    end
    lastAsked = now;
    return now - waitingSince >= delay;
end

function tooltip.Begin()
    local shared = theme.Shared();
    if not shared.TooltipsEnabled then
        return false;
    end
    if not Waited((tonumber(shared.TooltipDelay) or 0) / 1000) then
        return false;
    end

    imgui.PushStyleColor(ImGuiCol_PopupBg, shared.TooltipBackgroundColor);
    imgui.PushStyleColor(ImGuiCol_Border, shared.TooltipBorderColor);
    imgui.PushStyleColor(ImGuiCol_Text, shared.TooltipTextColor);
    padding[1], padding[2] = shared.TooltipPadding, shared.TooltipPadding;
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, padding);

    -- 0 keeps the size of the window it is over
    local size = tonumber(shared.TooltipFontSize) or 0;
    opened.font = size > 0;
    if opened.font then
        imgui.PushFont(nil, size);
    end

    imgui.BeginTooltip();
    imgui.PushTextWrapPos(imgui.GetCursorPosX() + shared.TooltipMaxWidth);
    return true;
end

function tooltip.End()
    imgui.PopTextWrapPos();
    imgui.EndTooltip();
    if opened.font then
        imgui.PopFont();
    end
    imgui.PopStyleVar();
    imgui.PopStyleColor(3);
end

function tooltip.Show(text)
    if text ~= nil and tooltip.Begin() then
        imgui.Text(text);
        tooltip.End();
    end
end

function tooltip.Hover(text)
    if text ~= nil and imgui.IsItemHovered() then
        tooltip.Show(text);
    end
end

return tooltip;
