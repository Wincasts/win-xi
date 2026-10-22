-- The banner's styles other than Classic Text: Title Card, Pennant, Kanji Watermark, Letter Reveal,
-- Classic Window, Elemental Weather and Kind Frames.
--
--   styles.ids, styles.labels      the styles there are, Classic Text first, and their names
--   styles.valid(id)               whether id is one of them
--   styles.draw(id, list, c)       draws style id on an imgui draw list from c (presentation.lua
--                                  fills it): the words, fonts, sizes, colours, fade and how long
--                                  the banner has been up, which the entrances follow
--   styles.vertical(chars)         whether Japanese words can be written top to bottom here
--   styles.weather_element(id)     the element of a weather id and 1 or 2 for single or double weather
--   styles.elements                each element's colour
--
-- Each is drawn straight onto the draw list, under every imgui window, and fades with the banner as
-- a whole; its entrance plays over the first second or two. Text has winxi.text's dark edge.
local imgui = require('imgui');
local text = require('winxi.text');

local M = {};

M.ids = { 'classic', 'titlecard', 'pennant', 'kanji', 'reveal', 'window', 'element', 'kind' };
M.labels = { classic = 'Classic Text', titlecard = 'Title Card', pennant = 'Pennant', kanji = 'Kanji Watermark',
    reveal = 'Letter Reveal', window = 'Classic Window', element = 'Elemental Weather', kind = 'Kind Frames' };

function M.valid(id)
    return M.labels[id] ~= nil;
end

local function clamp(t) return t < 0 and 0 or (t > 1 and 1 or t); end
local function out_cubic(t) t = 1 - clamp(t); return 1 - t * t * t; end
local function out_back(t)
    t = clamp(t) - 1;
    return 1 + 2.2 * t * t * t + 1.2 * t * t;
end

-- Colours, packed for the draw list: c's colour at a fraction of the banner's fade.
local scratch, white = { 0, 0, 0, 0 }, { 1, 1, 1, 1 };
local function packed(color, alpha)
    scratch[1], scratch[2], scratch[3], scratch[4] = color[1], color[2], color[3], (color[4] or 1) * alpha;
    return imgui.GetColorU32(scratch);
end

-- Words as their characters (UTF-8), kept for the words last asked for.
local split_cache, split_count = {}, 0;
local function chars(words)
    local found = split_cache[words];
    if not found then
        found = {};
        for ch in words:gmatch('[%z\1-\127\194-\244][\128-\191]*') do found[#found + 1] = ch; end
        if split_count >= 64 then split_cache, split_count = {}, 0; end
        split_cache[words], split_count = found, split_count + 1;
    end
    return found;
end

-- How wide each character is in the font pushed, at a size: measured once.
local widths = setmetatable({}, { __mode = 'k' });
local default_font = {};
local function width_of(font, size, ch)
    local by_font = widths[font or default_font];
    if not by_font then by_font = {}; widths[font or default_font] = by_font; end
    local by_size = by_font[size];
    if not by_size then by_size = {}; by_font[size] = by_size; end
    local w = by_size[ch];
    if not w then w = imgui.CalcTextSize(ch); by_size[ch] = w; end
    return w;
end

-- Words with room between every letter (tracking): their width, and drawing them from x.
local function tracked_width(font, size, letters, gap)
    local w = 0;
    for i = 1, #letters do w = w + width_of(font, size, letters[i]); end
    return w + gap * math.max(0, #letters - 1);
end
local function tracked(list, font, size, letters, gap, x, y, color, dark, edge)
    for i = 1, #letters do
        local ch = letters[i];
        if ch ~= ' ' then text.Packed(list, x, y, color, ch, edge, dark); end
        x = x + width_of(font, size, ch) + gap;
    end
end

-- Where a group of a width starts, for the banner's alignment at x.
local function left_of(c, width)
    if c.alignment == 'left' then return c.x; end
    if c.alignment == 'right' then return c.x - width; end
    return c.x - width / 2;
end

local p1, p2, p3, p4 = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
local function at(p, x, y) p[1], p[2] = x, y; return p; end

-- A line of words in a font: pushed, measured and drawn, at a fraction of the fade.
local function line(list, c, font, size, words, x, y, color, alpha)
    imgui.PushFont(font, size);
    if alpha > .01 then text.Packed(list, x, y, packed(color, alpha), words, c.edge, packed(c.outline, alpha)); end
    imgui.PopFont();
end
local function measure(font, size, words)
    imgui.PushFont(font, size);
    local w, h = imgui.CalcTextSize(words);
    imgui.PopFont();
    return w, h;
end

-- Title Card: region in spaced capitals, two rules growing out from a diamond, the name settling from
-- wide spacing to its own, and the day and weather under it.
local function title_card(list, c)
    local S, D, age = c.title_size, c.detail_size, c.age;
    local upper = chars(c.upper:upper());
    local name = chars(c.title);
    imgui.PushFont(c.detail_font, D);
    local upper_gap = D * .5;
    local upper_w = #upper > 0 and tracked_width(c.detail_font, D, upper, upper_gap) or 0;
    imgui.PopFont();
    imgui.PushFont(c.title_font, S);
    local settle = out_cubic(age / 1.6);
    local name_gap = S * (.18 + .42 * (1 - settle));
    local final_w = tracked_width(c.title_font, S, name, S * .18);
    local name_w = tracked_width(c.title_font, S, name, name_gap);
    imgui.PopFont();
    local width = math.max(final_w, upper_w) * 1.1;
    local cx = left_of(c, width) + width / 2;
    local y = c.y;
    local later = c.alpha * clamp((age - .6) / 1);

    if #upper > 0 then
        imgui.PushFont(c.detail_font, D);
        local color, dark = packed(c.detail_color, later), packed(c.outline, later);
        tracked(list, c.detail_font, D, upper, upper_gap, cx - upper_w / 2, y, color, dark, c.edge);
        imgui.PopFont();
        y = y + D * 1.5;
    end

    -- The rules: brightest at the diamond, fading to nothing at their ends.
    local r, grow = math.max(3, D * .32), out_cubic(age / 1.1);
    local half = math.max(final_w * .55, S * 4) * grow;
    local thick = math.max(1, math.floor(S / 30 + .5));
    local mid = y + r;
    local solid, clear = packed(c.detail_color, c.alpha), packed(c.detail_color, 0);
    local shade, shade_clear = packed(c.outline, c.alpha * .8), packed(c.outline, 0);
    if half > 1 then
        local inner = r * 2.2;
        for pass = 1, 2 do
            local off = pass == 1 and 1 or 0;
            local a, b = pass == 1 and shade or solid, pass == 1 and shade_clear or clear;
            list:AddRectFilledMultiColor(at(p1, cx - inner - half, mid - thick / 2 + off), at(p2, cx - inner, mid + thick / 2 + off), b, a, a, b);
            list:AddRectFilledMultiColor(at(p1, cx + inner, mid - thick / 2 + off), at(p2, cx + inner + half, mid + thick / 2 + off), a, b, b, a);
        end
    end
    local diamond = c.alpha * clamp(age / .5);
    for pass = 1, 2 do
        local off = pass == 1 and 1 or 0;
        list:AddQuad(at(p1, cx, mid - r + off), at(p2, cx + r, mid + off), at(p3, cx, mid + r + off), at(p4, cx - r, mid + off),
            pass == 1 and packed(c.outline, diamond) or packed(c.detail_color, diamond), thick);
    end
    y = mid + r + D * .5;

    local shown = c.alpha * clamp(age / .8);
    imgui.PushFont(c.title_font, S);
    tracked(list, c.title_font, S, name, name_gap, cx - name_w / 2, y, packed(c.title_color, shown), packed(c.outline, shown), c.edge);
    local _, height = imgui.CalcTextSize(c.title);
    imgui.PopFont();
    y = y + height + D * .3;

    if c.meta ~= '' then
        local w = measure(c.detail_font, D, c.meta);
        line(list, c, c.detail_font, D, c.meta, cx - w / 2, y, c.detail_color, later);
    end
end

-- Pennant colours: the nation's, from its flag; slate and silver for a region without one.
local palettes = {
    sandoria = { base = { .50, .06, .09, 1 }, light = { .78, .12, .16, 1 }, trim = { .86, .72, .40, 1 } },
    bastok = { base = { .07, .09, .38, 1 }, light = { .17, .25, .66, 1 }, trim = { .84, .70, .36, 1 } },
    windurst = { base = { .10, .33, .05, 1 }, light = { .20, .55, .10, 1 }, trim = { .96, .80, .26, 1 } },
    jeuno = { base = { .34, .09, .09, 1 }, light = { .56, .20, .14, 1 }, trim = { .93, .78, .45, 1 } },
    ahturhgan = { base = { .05, .05, .05, 1 }, light = { .20, .20, .19, 1 }, trim = { .86, .68, .20, 1 } },
    none = { base = { .14, .17, .24, 1 }, light = { .27, .31, .42, 1 }, trim = { .76, .79, .85, 1 } },
};
M.palettes = palettes;

-- Pennant: a banner in the nation's colours drops from the top of the screen, the flag at its head
-- and the name in capitals down it; the region, name, day and weather beside it.
local function pennant(list, c)
    local S, D, age = c.title_size, c.detail_size, c.age;
    local W, L = c.pennant_width, c.pennant_length;
    local notch = W * .35;
    local colors = palettes[c.flag or 'none'] or palettes.none;
    local upper_letters = chars(c.upper:upper());
    local upper_gap = D * .3;
    imgui.PushFont(c.detail_font, D);
    local upper_w = #upper_letters > 0 and tracked_width(c.detail_font, D, upper_letters, upper_gap) or 0;
    imgui.PopFont();
    local name_w = measure(c.title_font, S, c.title);
    local meta_w = c.meta ~= '' and measure(c.detail_font, D, c.meta) or 0;
    local side_w = math.max(upper_w, name_w, meta_w);
    local gap = S * .5;
    local px = left_of(c, W + gap + side_w);
    local drop = out_back(age / 1.0);
    local top = -L * (1 - drop);
    local bottom = top + L - notch;
    local a = c.alpha;

    -- Shadow, cloth, the two tails, a sheen down the middle.
    list:AddRectFilled(at(p1, px + 5, top), at(p2, px + W + 5, bottom + 5), packed(c.outline, a * .35));
    local base, light = packed(colors.base, a), packed(colors.light, a);
    list:AddRectFilledMultiColor(at(p1, px, top), at(p2, px + W / 2, bottom), base, light, light, base);
    list:AddRectFilledMultiColor(at(p1, px + W / 2, top), at(p2, px + W, bottom), light, base, base, light);
    list:AddTriangleFilled(at(p1, px, bottom), at(p2, px + W / 2, bottom), at(p3, px, bottom + notch), base);
    list:AddTriangleFilled(at(p1, px + W / 2, bottom), at(p2, px + W, bottom), at(p3, px + W, bottom + notch), base);

    -- Trim: a line inside the edge, following the tails.
    local t = math.max(3, W * .07);
    local thick = math.max(1, W / 40);
    local trim = packed(colors.trim, a);
    local b1, b2 = bottom + notch - t * 2.4, bottom - t * 1.1;
    list:AddLine(at(p1, px + t, top), at(p2, px + t, b1), trim, thick);
    list:AddLine(at(p1, px + t, b1), at(p2, px + W / 2, b2), trim, thick);
    list:AddLine(at(p1, px + W / 2, b2), at(p2, px + W - t, b1), trim, thick);
    list:AddLine(at(p1, px + W - t, b1), at(p2, px + W - t, top), trim, thick);

    -- The flag at its head, framed in the trim; a crystal where the region has none.
    local cs = W * .62;
    local cx, cy = px + W / 2, top + W * .16;
    if c.flag_image then
        list:AddRectFilled(at(p1, cx - cs / 2 - thick * 2, cy - thick * 2), at(p2, cx + cs / 2 + thick * 2, cy + cs + thick * 2), trim);
        list:AddImage(c.flag_image.handle, at(p1, cx - cs / 2, cy), at(p2, cx + cs / 2, cy + cs), at(p3, 0, 0), at(p4, 1, 1), packed(white, a));
    else
        local r = cs * .32;
        local my = cy + cs / 2;
        list:AddQuadFilled(at(p1, cx, my - r * 1.3), at(p2, cx + r, my), at(p3, cx, my + r * 1.3), at(p4, cx - r, my), trim);
        list:AddQuad(at(p1, cx, my - r * 1.3), at(p2, cx + r, my), at(p3, cx, my + r * 1.3), at(p4, cx - r, my), packed(c.outline, a * .6), 1);
    end

    -- The name down it, one capital under another, as large as fits.
    local letters = chars(c.title:upper());
    local count = 0;
    for i = 1, #letters do count = count + (letters[i] == ' ' and .5 or 1); end
    local y0, y1 = cy + cs + W * .2, bottom - W * .1;
    local size = math.floor(math.min(c.pennant_letter, (y1 - y0) / math.max(1, count)));
    if size >= 8 then
        imgui.PushFont(c.title_font, size);
        local color, dark = packed(c.title_color, a), packed(c.outline, a);
        local y = y0;
        for i = 1, #letters do
            local ch = letters[i];
            if ch == ' ' then
                y = y + size * .5;
            else
                text.Packed(list, math.floor(cx - width_of(c.title_font, size, ch) / 2 + .5), math.floor(y + .5), color, ch, c.edge, dark);
                y = y + size;
            end
        end
        imgui.PopFont();
    end

    -- Beside it: region, name, day and weather, fading in once it has dropped.
    local sx, y = px + W + gap, c.y;
    local beside = a * clamp((age - .6) / .8);
    local slide = (1 - out_cubic((age - .6) / .8)) * -S * .4;
    if #upper_letters > 0 then
        imgui.PushFont(c.detail_font, D);
        tracked(list, c.detail_font, D, upper_letters, upper_gap, sx + slide, y, packed(c.detail_color, beside), packed(c.outline, beside), c.edge);
        imgui.PopFont();
        y = y + D * 1.4;
    end
    line(list, c, c.title_font, S, c.title, sx + slide, y, c.title_color, beside);
    y = y + S * 1.2;
    if c.meta ~= '' then line(list, c, c.detail_font, D, c.meta, sx + slide, y, c.detail_color, beside); end
end

-- Japanese written top to bottom. The font has no vertical forms and imgui cannot turn a glyph, so
-- what changes when Japanese is set vertically is done by hand: the long vowel mark ー is drawn as
-- its vertical stroke, and small kana move to the top right of their square. Names with Latin
-- letters, digits, brackets or a hyphen (the [S] zones, Abyssea - ..., 2716号採石場) would need
-- rotated forms, so they are written across instead.
local small = {};
for ch in ('ァィゥェォッャュョヮヵヶぁぃぅぇぉっゃゅょゎ'):gmatch('[\194-\244][\128-\191]*') do small[ch] = true; end
local LONG = 'ー';
function M.vertical(letters)
    for i = 1, #letters do
        local ch = letters[i];
        if #ch == 1 or ch:match('^\239\188') or ch:match('^\239\189') or ch == '〔' or ch == '〕' then return false; end
    end
    return #letters > 0;
end

-- The i-th line of the Kanji Watermark's words: how far it has faded in, and how far below its place.
local function rise(c, age, S, i)
    local t = (age - i * .25) / .9;
    return c.alpha * clamp(t), (1 - out_cubic(t)) * S * .4;
end

-- Kanji Watermark: the zone's Japanese name huge and faint behind the English, top to bottom beside it
-- or across behind it; above the English name the Japanese of the line over it.
local function kanji(list, c)
    local S, D, age = c.title_size, c.detail_size, c.age;
    local jf, K = c.kanji_font, c.kanji_size;
    local ja = (jf and c.zone_ja and c.zone_ja ~= '') and chars(c.zone_ja) or nil;
    local vertical = ja and c.kanji_vertical and M.vertical(ja);
    local upper = c.upper;
    local upper_font = c.detail_font;
    if jf and c.upper_ja and c.upper_ja ~= '' and upper ~= '' then
        upper, upper_font = c.upper_ja .. '  ·  ' .. upper, jf;
    end
    local upper_w = upper ~= '' and measure(upper_font, D, upper) or 0;
    local name_w, name_h = measure(c.title_font, S, c.title);
    local meta_w = c.meta ~= '' and measure(c.detail_font, D, c.meta) or 0;
    local block_w = math.max(upper_w, name_w, meta_w);

    local mark_w = 0;
    if ja and not vertical then mark_w = measure(jf, K, c.zone_ja); end
    local gap = S * .6;
    local group_w = vertical and (block_w + gap + K) or math.max(block_w, mark_w);
    local gx = left_of(c, group_w);
    local bx = vertical and gx or gx + (group_w - block_w) / 2;

    -- The watermark first, under the words.
    if ja then
        local shown = c.alpha * c.kanji_opacity * out_cubic(age / 2);
        local drift = -K * .25 * (1 - out_cubic(age / 2));
        local color = packed(c.title_color, shown);
        imgui.PushFont(jf, K);
        if vertical then
            local x0, y = bx + block_w + gap, c.y - K * .2 + drift;
            for i = 1, #ja do
                local ch = ja[i];
                if ch == LONG then
                    local w = math.max(1, K * .055);
                    list:AddRectFilled(at(p1, x0 + K / 2 - w / 2, y + K * .1), at(p2, x0 + K / 2 + w / 2, y + K * .9), color);
                else
                    local w = width_of(jf, K, ch);
                    local dx, dy = 0, 0;
                    if small[ch] then dx, dy = K * .13, -K * .13; end
                    at(p1, x0 + (K - w) / 2 + dx, y + dy);
                    list:AddText(p1, color, ch);
                end
                y = y + K;
            end
        else
            at(p1, gx + (group_w - mark_w) / 2, c.y - K * .3 + drift);
            list:AddText(p1, color, c.zone_ja);
        end
        imgui.PopFont();
    end

    -- The words, rising in one after another.
    local y = c.y;
    if upper ~= '' then
        local shown, off = rise(c, age, S, 0);
        line(list, c, upper_font, D, upper, bx, y + off, c.detail_color, shown);
        y = y + D * 1.5;
    end
    local shown, off = rise(c, age, S, 1);
    line(list, c, c.title_font, S, c.title, bx, y + off, c.title_color, shown);
    y = y + name_h + D * .3;
    if c.meta ~= '' then
        shown, off = rise(c, age, S, 2);
        line(list, c, c.detail_font, D, c.meta, bx, y + off, c.detail_color, shown);
    end
end

-- Letter Reveal: the name a letter at a time, each dropping in out of a blur (two faint copies
-- either side, closing on it, as imgui has no blur), then the region between two short rules.
local function reveal(list, c)
    local S, D, age = c.title_size, c.detail_size, c.age;
    local name = chars(c.title);
    imgui.PushFont(c.title_font, S);
    local name_w = tracked_width(c.title_font, S, name, 0);
    local _, name_h = imgui.CalcTextSize(c.title);
    imgui.PopFont();
    local upper_w = c.upper ~= '' and measure(c.detail_font, D, c.upper) or 0;
    local meta_w = c.meta ~= '' and measure(c.detail_font, D, c.meta) or 0;
    local rule, rule_gap = D * 1.5, D * .6;
    local block = math.max(name_w, upper_w + (rule + rule_gap) * 2, meta_w);
    local cx = left_of(c, block) + block / 2;
    local y = c.y;

    imgui.PushFont(c.title_font, S);
    local x = cx - name_w / 2;
    for i = 1, #name do
        local ch = name[i];
        if ch ~= ' ' then
            local t = (age - (i - 1) * .055) / .7;
            local settle = out_cubic(t);
            local dy = -S * .25 * (1 - settle);
            local shown = c.alpha * clamp(t);
            local blur = 1 - settle;
            if blur > .01 and shown > .01 then
                local ghost = packed(c.title_color, c.alpha * .35 * blur * clamp(t * 3));
                local spread = S * .06 * blur;
                text.Packed(list, x - spread, y + dy - S * .08 * blur, ghost, ch, 0);
                text.Packed(list, x + spread, y + dy - S * .08 * blur, ghost, ch, 0);
            end
            if shown > .01 then text.Packed(list, x, y + dy, packed(c.title_color, shown), ch, c.edge, packed(c.outline, shown)); end
        end
        x = x + width_of(c.title_font, S, ch);
    end
    imgui.PopFont();
    y = y + name_h + D * .4;

    local later = c.alpha * clamp((age - (#name - 1) * .055 - .5) / .8);
    if c.upper ~= '' then
        line(list, c, c.detail_font, D, c.upper, cx - upper_w / 2, y, c.detail_color, later);
        if later > .01 then
            local mid, thick = y + D * .6, math.max(1, D / 16);
            local color, dark = packed(c.detail_color, later * .7), packed(c.outline, later * .7);
            for side = -1, 1, 2 do
                local near = cx + side * (upper_w / 2 + rule_gap);
                local far = near + side * rule;
                list:AddLine(at(p1, near, mid + 1), at(p2, far, mid + 1), dark, thick);
                list:AddLine(at(p1, near, mid), at(p2, far, mid), color, thick);
            end
        end
        y = y + D * 1.4;
    end
    if c.meta ~= '' then line(list, c, c.detail_font, D, c.meta, cx - meta_w / 2, y, c.detail_color, later); end
end

-- Classic Window: the banner in the game's own blue menu window, silver edged, opening from a line,
-- with the menu's pointer beside the name.
local window_colors = { top = { .18, .24, .48, 1 }, bottom = { .06, .08, .20, 1 }, frame = { .66, .67, .75, 1 },
    inner = { .10, .12, .24, 1 }, shine = { 1, 1, 1, .16 }, pointer = { .91, .91, .95, 1 } };
local function classic_window(list, c)
    local S, D, age, a = c.title_size, c.detail_size, c.age, c.alpha;
    local upper_w = c.upper ~= '' and measure(c.detail_font, D, c.upper) or 0;
    local name_w, name_h = measure(c.title_font, S, c.title);
    local meta_w = c.meta ~= '' and measure(c.detail_font, D, c.meta) or 0;
    local pad_x, pad_y = S * 1.1, D * .8;
    local w = math.max(upper_w, name_w, meta_w, S * 6) + pad_x * 2;
    local h = pad_y * 2 + name_h + (c.upper ~= '' and D * 1.4 or 0) + (c.meta ~= '' and D * 1.4 or 0);
    local x0 = left_of(c, w);
    local open = out_cubic(age / .35);
    local mid = c.y + h / 2;
    local top, bottom = mid - h * (.05 + .95 * open) / 2, mid + h * (.05 + .95 * open) / 2;
    -- The frame's corners are rounded; the body inside it, square, is set in far enough to stay within them.
    local R = math.max(3, S * .14);
    local b = math.max(2, math.floor(R * .35 + .5));
    list:AddRectFilled(at(p1, x0 + 3, top + 4), at(p2, x0 + w + 3, bottom + 4), packed(c.outline, a * .35), R);
    list:AddRectFilled(at(p1, x0, top), at(p2, x0 + w, bottom), packed(window_colors.frame, a), R);
    local high, low = packed(window_colors.top, a), packed(window_colors.bottom, a);
    list:AddRectFilledMultiColor(at(p1, x0 + b, top + b), at(p2, x0 + w - b, bottom - b), high, high, low, low);
    list:AddRect(at(p1, x0 + b, top + b), at(p2, x0 + w - b, bottom - b), packed(window_colors.inner, a), 0, 0, 1);
    list:AddLine(at(p1, x0 + b + R, top + b + 2), at(p2, x0 + w - b - R, top + b + 2), packed(window_colors.shine, a), 1);

    local shown = a * clamp((age - .25) / .25);
    if shown <= .01 then return; end
    local cx, y = x0 + w / 2, c.y + pad_y;
    if c.upper ~= '' then
        line(list, c, c.detail_font, D, c.upper, cx - upper_w / 2, y, c.detail_color, shown);
        y = y + D * 1.4;
    end
    line(list, c, c.title_font, S, c.title, cx - name_w / 2, y, c.title_color, shown);

    -- The pointer, its tip just short of the name, nodding towards it.
    local k = S * .55 / 17;
    local tip_x = cx - name_w / 2 - S * .2 - math.abs(math.sin(age * 4)) * S * .08;
    local tip_y = y + name_h / 2;
    local bx, by = tip_x - 17 * k, tip_y - 8 * k;
    local fill, dark = packed(window_colors.pointer, shown), packed(c.outline, shown);
    list:AddTriangleFilled(at(p1, tip_x, tip_y), at(p2, bx, by), at(p3, bx + 5 * k, tip_y), fill);
    list:AddTriangleFilled(at(p1, tip_x, tip_y), at(p2, bx + 5 * k, tip_y), at(p3, bx, by + 16 * k), fill);
    list:AddLine(at(p1, tip_x, tip_y), at(p2, bx, by), dark, 1);
    list:AddLine(at(p1, bx, by), at(p2, bx + 5 * k, tip_y), dark, 1);
    list:AddLine(at(p1, bx + 5 * k, tip_y), at(p2, bx, by + 16 * k), dark, 1);
    list:AddLine(at(p1, bx, by + 16 * k), at(p2, tip_x, tip_y), dark, 1);
    y = y + name_h + D * .4;

    if c.meta ~= '' then line(list, c, c.detail_font, D, c.meta, cx - meta_w / 2, y, c.detail_color, shown); end
end

-- The eight elements' colours, the weathers' elements in the order of their ids (4 Fire, 5 Fire x2,
-- 6 Water and so on to 19 Dark x2) and the days'.
local elements = {
    fire = { .93, .36, .25, 1 }, ice = { .56, .85, .96, 1 }, wind = { .40, .82, .50, 1 }, earth = { .82, .65, .30, 1 },
    thunder = { .71, .54, .96, 1 }, water = { .31, .58, .90, 1 }, light = { .96, .94, .86, 1 }, dark = { .55, .39, .72, 1 },
};
M.elements = elements;
local weather_order = { 'fire', 'water', 'earth', 'wind', 'ice', 'thunder', 'light', 'dark' };
local day_elements = { Firesday = 'fire', Earthsday = 'earth', Watersday = 'water', Windsday = 'wind', Iceday = 'ice',
    Lightningday = 'thunder', Lightsday = 'light', Darksday = 'dark' };
function M.weather_element(id)
    if type(id) ~= 'number' or id < 4 or id > 19 then return nil, 0; end
    return weather_order[math.floor((id - 4) / 2) + 1], id % 2 == 1 and 2 or 1;
end
-- 'Firesday 14:20' as 'Firesday' and ' 14:20', kept for the words last asked for.
local day_split = {};
local function day_parts(vana)
    if day_split.vana ~= vana then
        day_split.vana = vana;
        day_split.day, day_split.rest = nil, nil;
        if vana then day_split.day, day_split.rest = vana:match('^(%a+)(.*)$'); end
    end
    return day_split.day, day_split.rest;
end
local pale = { 0, 0, 0, 1 };
local function paler(color)
    for i = 1, 3 do pale[i] = color[i] + (1 - color[i]) * .6; end
    return pale;
end

-- A crystal: a diamond turned by an angle, its upper left face lighter, outlined.
local q = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } };
local function corner(p, x, y, dx, dy, cos, sin) p[1], p[2] = x + dx * cos - dy * sin, y + dx * sin + dy * cos; end
local function crystal(list, x, y, w, h, angle, color, alpha, outline)
    local cos, sin = math.cos(angle), math.sin(angle);
    corner(q[1], x, y, 0, -h, cos, sin); corner(q[2], x, y, w, 0, cos, sin);
    corner(q[3], x, y, 0, h, cos, sin); corner(q[4], x, y, -w, 0, cos, sin);
    list:AddQuadFilled(q[1], q[2], q[3], q[4], packed(color, alpha));
    list:AddTriangleFilled(q[1], q[4], at(p1, x, y), packed(paler(color), alpha));
    list:AddQuad(q[1], q[2], q[3], q[4], packed(outline, alpha * .8), 1);
end

-- A band across, clear at its ends and of a colour in the middle: two gradients from the middle out.
local function band(list, cx, y, half, thick, color, alpha)
    local solid, clear = packed(color, alpha), packed(color, 0);
    list:AddRectFilledMultiColor(at(p1, cx - half, y - thick / 2), at(p2, cx, y + thick / 2), clear, solid, solid, clear);
    list:AddRectFilledMultiColor(at(p1, cx, y - thick / 2), at(p2, cx + half, y + thick / 2), solid, clear, clear, solid);
end

-- Elemental Weather: the name over a glowing band in the weather's element's colour (the day's when
-- the weather has none or is not shown), a crystal for single weather and two for double beside the
-- weather in capitals, and the day in its element's colour.
local function elemental(list, c)
    local S, D, age, a = c.title_size, c.detail_size, c.age, c.alpha;
    local element, count = M.weather_element(c.weather_id);
    local day, rest = day_parts(c.vana);
    local tint = elements[element or (day and day_elements[day]) or ''] or c.detail_color;
    local upper_w = c.upper ~= '' and measure(c.detail_font, D, c.upper) or 0;
    local name_w, name_h = measure(c.title_font, S, c.title);
    local weather = c.weather and chars(c.weather:upper()) or nil;
    local weather_gap = D * .2;
    imgui.PushFont(c.detail_font, D);
    local weather_w = weather and tracked_width(c.detail_font, D, weather, weather_gap) or 0;
    imgui.PopFont();
    local gem = D * .45;
    local gems_w = element and (count * gem * 2 + (count - 1) * gem * .7) or 0;
    local row_w = gems_w + ((element and weather) and D * .6 or 0) + weather_w;
    local day_w = day and measure(c.detail_font, D, day) or 0;
    local rest_w = day and measure(c.detail_font, D, rest) or (c.vana and measure(c.detail_font, D, c.vana) or 0);
    local bar_w = math.max(name_w * 1.1, S * 6);
    local block = math.max(upper_w, name_w, bar_w, row_w, day_w + rest_w);
    local cx = left_of(c, block) + block / 2;
    local y = c.y;

    local shown = a * clamp(age / .6);
    if c.upper ~= '' then
        line(list, c, c.detail_font, D, c.upper, cx - upper_w / 2, y, c.detail_color, shown);
        y = y + D * 1.4;
    end
    line(list, c, c.title_font, S, c.title, cx - name_w / 2, y, c.title_color, shown);
    y = y + name_h + D * .4;

    -- The band, growing from the middle, with a glow of wider faint bands round it and a pale heart.
    local half = bar_w / 2 * out_cubic(age / 1.2);
    local thick = math.max(2, math.floor(S * .06 + .5));
    if half > 1 then
        for k = 3, 1, -1 do band(list, cx, y + thick / 2, half * (1 + k * .04), thick + k * D * .3, tint, a * .1); end
        band(list, cx, y + thick / 2, half, thick, tint, a);
        band(list, cx, y + thick / 2, half * .45, math.max(1, thick / 2), paler(tint), a);
    end
    y = y + thick + D * .7;

    local later = a * clamp((age - .5) / .8);
    if element or weather then
        local x = cx - row_w / 2;
        local my = y + D * .6;
        if element then
            for j = 1, count do
                local t = (age - .2 - (j - 1) * .2) / .8;
                local grow = out_back(t);
                if grow > .01 then
                    crystal(list, x + gem, my, gem * grow, gem * 1.4 * grow, -2.36 * (1 - out_cubic(t)), elements[element], a * clamp(t * 2), c.outline);
                end
                x = x + gem * 2.7;
            end
            x = x - gem * .7 + (weather and D * .6 or 0);
        end
        if weather then
            imgui.PushFont(c.detail_font, D);
            tracked(list, c.detail_font, D, weather, weather_gap, x, y, packed(c.detail_color, later), packed(c.outline, later), c.edge);
            imgui.PopFont();
        end
        y = y + D * 1.5;
    end
    if day then
        local x = cx - (day_w + rest_w) / 2;
        line(list, c, c.detail_font, D, day, x, y, elements[day_elements[day]] or c.detail_color, later);
        if rest ~= '' then line(list, c, c.detail_font, D, rest, x + day_w, y, c.detail_color, later); end
    elseif c.vana then
        line(list, c, c.detail_font, D, c.vana, cx - rest_w / 2, y, c.detail_color, later);
    end
end

-- Kind Frames: a look for each kind of zone. A city's name on a framed plaque, open country's over a
-- horizon line, a dungeon's carved in stone and lit as by a torch, flickering in. A zone of no known
-- kind is open country.
local plaque_colors = { top = { .17, .20, .28, 1 }, bottom = { .10, .12, .18, 1 }, gold = { .79, .66, .37, 1 } };
local function plaque(list, c)
    local S, D, age, a = c.title_size, c.detail_size, c.age, c.alpha;
    local upper_w = c.upper ~= '' and measure(c.detail_font, D, c.upper) or 0;
    local name_w, name_h = measure(c.title_font, S, c.title);
    local meta_w = c.meta ~= '' and measure(c.detail_font, D, c.meta) or 0;
    local pad_x, pad_y = S * .9, S * .25;
    local w, h = name_w + pad_x * 2, name_h + pad_y * 2;
    local block = math.max(w, upper_w, meta_w);
    local cx = left_of(c, block) + block / 2;
    local y = c.y;
    local later = a * clamp((age - .3) / .5);

    if c.upper ~= '' then
        line(list, c, c.detail_font, D, c.upper, cx - upper_w / 2, y, c.detail_color, later);
        y = y + D * 1.5;
    end
    local half = w / 2 * out_cubic(age / .5);
    if half > 1 then
        local border = math.max(1, math.floor(S / 32 + .5));
        list:AddRectFilled(at(p1, cx - half + 4, y + 5), at(p2, cx + half + 4, y + h + 5), packed(c.outline, a * .4));
        list:AddRectFilled(at(p1, cx - half - 3, y - 3), at(p2, cx + half + 3, y + h + 3), packed(plaque_colors.bottom, a));
        local high, low = packed(plaque_colors.top, a), packed(plaque_colors.bottom, a);
        list:AddRectFilledMultiColor(at(p1, cx - half, y), at(p2, cx + half, y + h), high, high, low, low);
        local gold = packed(plaque_colors.gold, a);
        list:AddRect(at(p1, cx - half, y), at(p2, cx + half, y + h), gold, 0, 0, border);
        local inset = border + 2;
        if half > inset * 2 then
            list:AddRect(at(p1, cx - half + inset, y + inset), at(p2, cx + half - inset, y + h - inset), gold, 0, 0, 1);
        end
    end
    line(list, c, c.title_font, S, c.title, cx - name_w / 2, y + pad_y, c.title_color, later);
    y = y + h + D * .6;
    if c.meta ~= '' then line(list, c, c.detail_font, D, c.meta, cx - meta_w / 2, y, c.detail_color, later); end
end

local function open_country(list, c)
    local S, D, age, a = c.title_size, c.detail_size, c.age, c.alpha;
    local upper_w = c.upper ~= '' and measure(c.detail_font, D, c.upper) or 0;
    local name_w, name_h = measure(c.title_font, S, c.title);
    local meta_w = c.meta ~= '' and measure(c.detail_font, D, c.meta) or 0;
    local block = math.max(name_w * 1.2, upper_w, meta_w);
    local cx = left_of(c, block) + block / 2;
    local y = c.y;
    local later = a * clamp((age - .5) / .8);

    if c.upper ~= '' then
        line(list, c, c.detail_font, D, c.upper, cx - upper_w / 2, y, c.detail_color, later);
        y = y + D * 1.4;
    end
    local shown, off = a * clamp(age / .9), (1 - out_cubic(age / .9)) * S * .3;
    line(list, c, c.title_font, S, c.title, cx - name_w / 2, y + off, c.title_color, shown);
    y = y + name_h + D * .3;
    local half = name_w * .6 * out_cubic(age / 1.2);
    if half > 1 then
        local thick = math.max(1, math.floor(S / 40 + .5));
        band(list, cx, y + 1, half, thick, c.outline, a * .8);
        band(list, cx, y, half, thick, c.title_color, a);
    end
    y = y + D * .6;
    if c.meta ~= '' then line(list, c, c.detail_font, D, c.meta, cx - meta_w / 2, y, c.detail_color, later); end
end

-- The torchlight's flicker: how lit the carving is from each time on, in seconds.
local flicker = { { 0, 0 }, { .24, .6 }, { .34, .2 }, { .53, .9 }, { .72, .7 }, { .96, 1 } };
local function lit(age)
    local v = 0;
    for i = 1, #flicker do if age >= flicker[i][1] then v = flicker[i][2]; end end
    return v;
end
local stone_colors = { stone = { .72, .67, .57, 1 }, ember = { 1, .55, .16, 1 }, chip = { 1, .92, .75, 1 }, cut = { 0, 0, 0, 1 } };
local function carved(list, c)
    local S, D = c.title_size, c.detail_size;
    local a = c.alpha * lit(c.age);
    if a <= .01 then return; end
    local name = chars(c.title:upper());
    local gap = S * .14;
    imgui.PushFont(c.title_font, S);
    local name_w = tracked_width(c.title_font, S, name, gap);
    local _, name_h = imgui.CalcTextSize(c.title);
    imgui.PopFont();
    local upper_w = c.upper ~= '' and measure(c.detail_font, D, c.upper) or 0;
    local meta_w = c.meta ~= '' and measure(c.detail_font, D, c.meta) or 0;
    local block = math.max(name_w, upper_w, meta_w);
    local cx = left_of(c, block) + block / 2;
    local y = c.y;

    if c.upper ~= '' then
        line(list, c, c.detail_font, D, c.upper, cx - upper_w / 2, y, stone_colors.stone, a * .85);
        y = y + D * 1.5;
    end
    -- The torch's glow round it, the cut's shadow above and its lit lip below, then the stone.
    local x = cx - name_w / 2;
    imgui.PushFont(c.title_font, S);
    local ember = packed(stone_colors.ember, a * .12);
    local spread = math.max(2, S / 20);
    tracked(list, c.title_font, S, name, gap, x - spread, y, ember, nil, 0);
    tracked(list, c.title_font, S, name, gap, x + spread, y, ember, nil, 0);
    tracked(list, c.title_font, S, name, gap, x, y - spread, ember, nil, 0);
    tracked(list, c.title_font, S, name, gap, x, y + spread, ember, nil, 0);
    tracked(list, c.title_font, S, name, gap, x, y - 1, packed(stone_colors.cut, a * .9), nil, 0);
    tracked(list, c.title_font, S, name, gap, x, y + 1, packed(stone_colors.chip, a * .25), nil, 0);
    tracked(list, c.title_font, S, name, gap, x, y, packed(stone_colors.stone, a), packed(c.outline, a * .6), c.edge);
    imgui.PopFont();
    y = y + name_h + D * .5;
    if c.meta ~= '' then line(list, c, c.detail_font, D, c.meta, cx - meta_w / 2, y, stone_colors.stone, a * .85); end
end

local function kind_frames(list, c)
    if c.kind == 'city' then return plaque(list, c); end
    if c.kind == 'dungeon' then return carved(list, c); end
    return open_country(list, c);
end

local draws = { titlecard = title_card, pennant = pennant, kanji = kanji,
    reveal = reveal, window = classic_window, element = elemental, kind = kind_frames };

function M.draw(id, list, c)
    local draw = draws[id];
    if not draw then return false; end
    draw(list, c);
    return true;
end

return M;
