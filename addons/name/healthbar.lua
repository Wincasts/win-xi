-- Basic HP bars share the font atlas's white pixel: no extra texture slot or asset.
--
--   healthbar.Begin()     each frame, before any bar: the white pixel is looked for afresh
--   healthbar.Write(name, entities, left, right, under, scale, color, width, height)
--                         the bar under a name, between the plugin's BeginName and EndName; returns
--                         the foot of it, or under where there is none
local imgui = require('imgui');
local nameplates = require('winxi.nameplates');
local healthbar = {};

-- Where the white pixel is in the font's texture, asked of imgui once a frame and for the first bar;
-- and again if imgui's function for it is another (a test's stand-in)
local whiteU, whiteV, whiteOf = nil, nil, nil;

function healthbar.Begin()
    whiteU, whiteV = nil, nil;
end

local function whitePixel()
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

-- The caller applies the shared toggle/combat filter; every category is eligible.
function healthbar.Write(name, entities, left, right, under, scale, color, width, height)
    -- Entity indices can be reused between the plugin's snapshot and this frame.
    if (name.ServerId == 0 or entities == nil or entities.GetServerId == nil or entities.GetHPPercent == nil
            or entities:GetServerId(name.EntityIndex) ~= name.ServerId) then
        return under;
    end
    local hp = entities:GetHPPercent(name.EntityIndex);
    if (type(hp) ~= 'number' or hp ~= hp or hp < 0 or hp >= 100) then return under; end

    local u, v = whitePixel();
    if (u == nil) then return under; end

    local border = math.max(1, math.floor(scale + 0.5));
    width = math.max(3 * border, math.floor((width or 60) * scale + 0.5));
    local x = math.floor((left + right - width) * 0.5);
    local y = under + math.max(1, math.floor(2 * scale + 0.5));
    local h = math.max(3 * border, math.floor((height or 6) * scale + 0.5));
    nameplates.Quad(x, y, x + width, y + h, u, v, u, v, 0xFF101010, 0, false);
    nameplates.Quad(x + border, y + border, x + width - border, y + h - border,
        u, v, u, v, 0xFF483030, 0, false);
    if (hp > 0) then
        nameplates.Quad(x + border, y + border, x + border + (width - 2 * border) * hp / 100,
            y + h - border, u, v, u, v, color or 0xFFFFFFFF, 0, false);
    end
    return y + h;
end

return healthbar;
