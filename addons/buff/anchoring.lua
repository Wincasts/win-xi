-- Default HUD placement calibrated against Screenshot_20261014_111534.png at 1:1 menu scale.
-- Use Ashita's existing scaling helper, not the experimental menu rectangle probe. This does
-- not read the buff bar's live geometry or inherit native UI layering.
local bit = require('bit');
local imgui = require('imgui');
local game = require('winxi.game');
local style = require('winxi.style');
local fade = require('winxi.fade');
local fonts = require('winxi.fonts');
local screen = require('winxi.screen');
local scalingOK, scaling = pcall(require, 'scaling');
if not scalingOK then scaling = nil; end

local anchoring = {};
-- Visible first-icon origin, in native menu coordinates (client borders excluded).
local nativeOrigin = { 148, 50 };
local position = { 0, 0 };
local spacing = { 8, 4 };
local appearance = { padding = 0, background = { 0, 0, 0, 0 }, alpha = 1 };

-- Optional anchored-only whole-bar workaround, not native menu clipping.
-- Cover all native menu panels and submenus, including mcr1pall/mcr2pall macro palettes.
-- Ordinary inline chat and the buff selector remain usable without hiding the bar.
function anchoring.HideForMenu(options)
    if not options.anchorToDefault or not options.anchorToDefault[1]
        or not options.hideWithMenus or not options.hideWithMenus[1] then return false; end
    local name = game.MenuName():match('^menu%s+(%S+)%s*$');
    return name ~= nil and name ~= 'buff' and name ~= 'inline';
end

function anchoring.IsHidden()
    -- Actual HUD visibility, not menu occlusion. The shell separately applies configured hiding
    -- rules (including expanded chat); those rules are not native draw-order inheritance.
    return game.IsLoading() or game.IsInterfaceHidden() or game.IsEventHappening();
end

-- The nudge is in display pixels, independent of native UI scale. Menu resolution comes from
-- Ashita's scaling helper; DisplaySize is current, so window-size changes update the anchor.
function anchoring.Position(nudge, display, menu)
    local sx, sy = 1, 1;
    local w, h = display.x or display[1], display.y or display[2];
    if menu and type(menu.w) == 'number' and type(menu.h) == 'number'
        and menu.w > 0 and menu.h > 0 and menu.w < 65536 and menu.h < 65536
        and type(w) == 'number' and type(h) == 'number' and w > 0 and h > 0
        and w < 65536 and h < 65536 then
        sx, sy = w / menu.w, h / menu.h;
    end
    return math.floor(nativeOrigin[1] * sx + 0.5) + nudge[1],
        math.floor(nativeOrigin[2] * sy + 0.5) + nudge[2];
end

-- menuChecked is true only when the caller already applied HideForMenu this frame.
function anchoring.Draw(name, options, draw, menuChecked)
    -- Do not linger when the HUD itself is hidden.
    if anchoring.IsHidden() or (not menuChecked and anchoring.HideForMenu(options)) then return false; end
    local wanted = options.isVisible[1];
    local alpha = wanted and 1 or 0;
    if options.fadeInOut[1] then alpha = fade.Presence(name, wanted); end
    if alpha <= 0.01 then return false; end

    position[1], position[2] = anchoring.Position(options.anchorAdjustment,
        imgui.GetIO().DisplaySize, scaling and scaling.menu);
    imgui.SetNextWindowPos(position, ImGuiCond_Always);
    appearance.alpha = alpha;
    style.PushPlain(appearance);
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, spacing);
    local pushedFont = fonts.Push();
    local begun, drawn = false, false;
    local ok, err = pcall(function()
        drawn = imgui.Begin(name, nil, bit.bor(style.TitlelessFlags(),
            ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoSavedSettings,
            ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoBringToFrontOnFocus,
            wanted and 0 or ImGuiWindowFlags_NoInputs));
        begun = true;
        if drawn then screen.Keep(name); draw(options); end
    end);
    local ended, endError = true, nil;
    if begun then ended, endError = pcall(imgui.End); end
    fonts.Pop(pushedFont);
    imgui.PopStyleVar(2);
    style.Pop();
    if not ok then error(err, 0); end
    if not ended then error(endError, 0); end
    return drawn;
end

return anchoring;
