-- winxi: each slot's recast timer written as winxi writes over an image.
--
-- In the theme's font and Text Color with winxi.text's dark edge (the theme's Text Outline and Outline
-- Color), at Recast Size pixels, centred on the icon. The crossbar's own text is drawn into its D3DX
-- sprite by gdifonts, which has neither the theme's font nor its edge, so this is drawn with imgui on
-- the background draw list: over the crossbar, under every imgui window. Without winxi, Draw returns
-- false and the layout's own Recast text is drawn as before.
local imgui = require('imgui');

local okTheme, theme = pcall(require, 'winxi.theme');
local okFonts, fonts = pcall(require, 'winxi.fonts');
local okText, text = pcall(require, 'winxi.text');
if not (okTheme and okFonts and okText) then theme, fonts, text = nil, nil, nil; end

local recasttext = {};

recasttext.MinSize, recasttext.MaxSize = 8, 40;

-- Writes words centred on cx, cy at size pixels; false where it cannot, for the layout's text instead
function recasttext.Draw(words, cx, cy, size)
    if theme == nil or imgui.GetBackgroundDrawList == nil then return false; end
    local current = theme.Get();
    size = math.max(recasttext.MinSize, math.min(recasttext.MaxSize, tonumber(size) or 16));
    imgui.PushFont(fonts.Get(current.FontFile), size);
    local width, height = imgui.CalcTextSize(words);
    text.Draw(imgui.GetBackgroundDrawList(), math.floor(cx - width / 2 + 0.5), math.floor(cy - height / 2 + 0.5), current.TextColor, words);
    imgui.PopFont();
    return true;
end

return recasttext;
