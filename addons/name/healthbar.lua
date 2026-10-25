-- Basic HP bars share the active text atlas's white pixel: no extra texture slot or asset. A bar in
-- one of winxi's Bar Textures is drawn by bar_art instead, and where that cannot, as this one.
--
--   healthbar.Begin(white, now) each frame: optional {u,v} from the active text atlas;
--                          otherwise the font's white pixel is looked for afresh
--   healthbar.Bar(left, right, under, scale, fraction, color, width, height, backdrop, texture)
--                         shared HP/cast geometry; returns the foot or unchanged under
--   healthbar.Write(name, entities, left, right, under, scale, color, width, height, full, texture)
--                         the bar under a name, between the plugin's BeginName and EndName; returns
--                         the foot of it, or under where there is none
--   healthbar.Preview     { false }: while true and its checkbox is being drawn (PreviewVisible),
--                         every name that can have a bar has one, going down and up again
--   healthbar.previewing  whether this frame is showing the preview
local imgui = require('imgui');
local nameplates = require('winxi.nameplates');
local barArt = require('bar_art');
local healthbar = {};

-- Session-only, never part of saved settings: as castbar.Preview
healthbar.Preview = { false };
healthbar.previewing = false;
local previewUntil, previewStart, frameNow = 0, nil, 0;
local PREVIEW_PERIOD = 6; -- seconds for a bar to empty and fill again

function healthbar.PreviewVisible(now)
    if healthbar.Preview[1] then
        previewStart = previewStart or now;
        previewUntil = now + 0.25; -- renew only while this control is being drawn
    else previewUntil, previewStart = 0, nil; end
end

-- Where the white pixel is in the font's texture, asked of imgui once a frame and for the first bar;
-- and again if imgui's function for it is another (a test's stand-in)
local whiteU, whiteV, whiteOf = nil, nil, nil;
local activeWhite;

function healthbar.Begin(white, now)
    activeWhite = white;
    whiteU, whiteV = nil, nil;
    frameNow = now or 0;
    healthbar.previewing = healthbar.Preview[1] and previewStart ~= nil and frameNow <= previewUntil or false;
end

-- The preview's HP for a name: down from full to empty and back, each name a little apart from the next
local function previewHP(index)
    local at = ((frameNow - (previewStart or frameNow)) + (index or 0) * 0.37) % PREVIEW_PERIOD / PREVIEW_PERIOD;
    return math.floor((at < 0.5 and 1 - at * 2 or (at - 0.5) * 2) * 100 + 0.5);
end

local function whitePixel()
    if activeWhite then return activeWhite.u, activeWhite.v; end
    local binding = imgui.GetFontTexUvWhitePixel or false;
    if (whiteU ~= nil and whiteOf == binding) then return whiteU, whiteV; end
    whiteOf = binding;
    local u, v;
    if (imgui.GetFontTexUvWhitePixel ~= nil) then
        u, v = imgui.GetFontTexUvWhitePixel();
        if (u ~= nil and type(u) ~= 'number') then u, v = u.x, u.y; end
    else
        local font = imgui.GetFont();
        local white = font and font.ContainerAtlas and font.ContainerAtlas.TexUvWhitePixel;
        if (white ~= nil) then u, v = white.x, white.y; end
    end
    if (type(u) ~= 'number' or type(v) ~= 'number') then return nil; end
    whiteU, whiteV = u, v;
    return u, v;
end

-- Shared HP/cast geometry and white pixel, with identical origins and dimensions.
function healthbar.Bar(left, right, under, scale, fraction, color, width, height, backdrop, texture)
    local border = math.max(1, math.floor(scale + 0.5));
    width = math.max(3 * border, math.floor((width or 60) * scale + 0.5));
    local x = math.floor((left + right - width) * 0.5);
    local y = math.floor(under + math.max(1, math.floor(2 * scale + 0.5)) + 0.5);
    local h = math.max(3 * border, math.floor((height or 6) * scale + 0.5));
    if texture ~= nil and barArt.Draw(texture, x, y, width, h, fraction, color or 0xFFFFFFFF) then
        return y + h;
    end

    local u, v = whitePixel();
    if (u == nil) then return under; end
    -- The plugin feathers these edges in final render-target pixels, AFTER Lens
    -- correction. Keep the fill endpoint fractional for accurate low HP coverage.
    nameplates.Quad(x, y, x + width, y + h, u, v, u, v, 0xFF101010, 0, false, nil, true);
    nameplates.Quad(x + border, y + border, x + width - border, y + h - border,
        u, v, u, v, backdrop or 0xFF483030, 0, false, nil, true);
    if (fraction > 0) then
        nameplates.Quad(x + border, y + border, x + border + (width - 2 * border) * math.min(1, fraction),
            y + h - border, u, v, u, v, color or 0xFFFFFFFF, 0, false, nil, true);
    end
    return y + h;
end

-- Full HP remains hidden normally. While casting, keep the enabled HP row above
-- the cast row even at 100%, so damage does not move the cast bar up/down. The preview shows it
-- whatever the HP.
function healthbar.Write(name, entities, left, right, under, scale, color, width, height, full, texture)
    if (name.ServerId == 0 or entities == nil or entities.GetServerId == nil or entities.GetHPPercent == nil
            or entities:GetServerId(name.EntityIndex) ~= name.ServerId) then return under; end
    local hp = healthbar.previewing and previewHP(name.EntityIndex) or entities:GetHPPercent(name.EntityIndex);
    if type(hp)~='number' or hp~=hp or hp<0 or hp>100 or (hp==100 and not full and not healthbar.previewing) then return under; end
    return healthbar.Bar(left,right,under,scale,hp/100,color,width,height,nil,texture);
end

return healthbar;
