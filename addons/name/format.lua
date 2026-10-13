-- How a name is written, as its player sets it out: a line of text in which [name] stands for the
-- name, [distance] for how far off it is, [level] for the levels a monster can be, [checked] for a
-- magnifying glass on a monster its player has checked and [aggro] for the sign that a monster is
-- aggressive or is not, [letter] for the experimental mob spawn-slot letter, and everything
-- else is written as it is.
--
--   format.Compile(text)   the line taken apart, kept by the line: a list of parts, each
--                          { kind = 'text', 'name', 'distance', 'level', 'checked' or 'aggro', text =
--                            what a 'text' part says, color = 0xAARRGGBB, or nil for the name's own }
--                          ('letter' is also a kind)
--                          with .distance, .level, .checked, .aggro and .letter set if present
--
-- A colour is #RRGGBB, #RGB or one of the names below.
--   [name:#FF8000]  [distance:yellow]   that one thing in that colour
--   [#FF8000] ... [/]                   everything from there to [/], or to the end, in that colour
-- With no colour given a thing is in the colour the game gives the name.
--
-- Square brackets round anything else are not taken for anything, and are written as they are. Only
-- the letters, figures and signs of plain English can be written: the font has no others.
local format = {};

format.Colors = {
    white  = 0xFFFFFF, black  = 0x000000, grey   = 0xA0A0A0, gray   = 0xA0A0A0,
    red    = 0xFF4040, green  = 0x60E060, blue   = 0x6090FF, yellow = 0xFFE040,
    orange = 0xFF9030, purple = 0xC070FF, pink   = 0xFF80C0, cyan   = 0x60E0E0,
};

format.Things = { name = true, distance = true, level = true, checked = true, aggro = true, letter = true };

-- A colour as it is typed, as 0xFFRRGGBB, or nil if it is not one
local function color(typed)
    local named = format.Colors[typed];
    if (named ~= nil) then
        return 0xFF000000 + named;
    end

    local digits = typed:match('^#(%x+)$');
    if (digits ~= nil and #digits == 6) then
        return 0xFF000000 + tonumber(digits, 16);
    elseif (digits ~= nil and #digits == 3) then
        local red, green, blue = tonumber(digits:sub(1, 1), 16), tonumber(digits:sub(2, 2), 16), tonumber(digits:sub(3, 3), 16);
        return 0xFF000000 + red * 0x110000 + green * 0x1100 + blue * 0x11;
    end
    return nil;
end

local compiled = {};
local compiledCount = 0;

function format.Compile(text)
    local found = compiled[text];
    if (found ~= nil) then
        return found;
    end

    found = { distance = false, level = false, checked = false, aggro = false, letter = false };
    local current = nil; -- the colour of what follows
    local plain = '';

    local function flush()
        if (plain ~= '') then
            found[#found + 1] = { kind = 'text', text = plain, color = current };
            plain = '';
        end
    end

    local at = 1;
    while (at <= #text) do
        local open, close, inside = text:find('^%[([^%[%]]*)%]', at);
        if (open ~= nil) then
            local typed = inside:lower():gsub('%s+', '');
            local thing, tint = typed:match('^(%a+):(.+)$');
            thing = thing or typed;

            if (typed == '/') then
                flush();
                current = nil;
            elseif (format.Things[thing] and (tint == nil or color(tint) ~= nil)) then
                flush();
                found[#found + 1] = { kind = thing, color = tint and color(tint) or current };
                found.distance = found.distance or thing == 'distance';
                found.level = found.level or thing == 'level';
                found.checked = found.checked or thing == 'checked';
                found.aggro = found.aggro or thing == 'aggro';
                found.letter = found.letter or thing == 'letter';
            elseif (color(typed) ~= nil) then
                flush();
                current = color(typed);
            else
                -- nothing this knows: written as it was typed
                plain = plain .. text:sub(open, close);
            end
            at = close + 1;
        else
            plain = plain .. text:sub(at, at);
            at = at + 1;
        end
    end
    flush();

    -- what the font cannot write is left out
    for _, part in ipairs(found) do
        if (part.kind == 'text') then
            part.text = part.text:gsub('[^\32-\126]', '');
        end
    end

    if (compiledCount > 64) then
        compiled, compiledCount = {}, 0;
    end
    compiled[text] = found;
    compiledCount = compiledCount + 1;
    return found;
end

-- Toggle mob-only tokens without changing the saved string. Cache variants on the
-- compiled format so unchanged nameplates do not allocate filtered parts every frame.
function format.Mob(text, showLevel, showAggro, showLetter)
    local base = format.Compile(text);
    -- The toggle works without editing a format; an explicit token controls its position/colour.
    if (showLetter and not base.letter) then base = format.Compile(text .. ' [letter]'); end
    if (showLevel and showAggro and (showLetter or not base.letter)) then return base; end
    local key = (showLevel and 1 or 0) + (showAggro and 2 or 0) + (showLetter and 4 or 0);
    base.mobVariants = base.mobVariants or {};
    if (base.mobVariants[key] ~= nil) then return base.mobVariants[key]; end
    local parts = { distance = base.distance, checked = base.checked,
        level = showLevel and base.level or false, aggro = showAggro and base.aggro or false,
        letter = showLetter and base.letter or false };
    local stripDot = false;
    for _, part in ipairs(base) do
        if (part.kind == 'level' and not showLevel) then
            local previous = parts[#parts];
            if (previous ~= nil and previous.kind == 'text') then
                previous.text = previous.text:gsub('%f[%a][Ll][Vv]%.?%s*$', '');
            end
            stripDot = true;
        elseif ((part.kind ~= 'aggro' or showAggro) and (part.kind ~= 'letter' or showLetter)) then
            local copy = { kind = part.kind, text = part.text, color = part.color };
            if (copy.kind == 'text') then
                if (stripDot) then copy.text = copy.text:gsub('^%.%s*', ''); end
                local previous = parts[#parts];
                if (previous ~= nil and previous.kind == 'text' and previous.color == copy.color) then
                    previous.text = (previous.text .. copy.text):gsub(' +', ' ');
                else
                    parts[#parts + 1] = copy;
                end
            else
                parts[#parts + 1] = copy;
            end
            stripDot = false;
        end
    end
    if (parts[1] ~= nil and parts[1].kind == 'text') then
        parts[1].text = parts[1].text:gsub('^ +', '');
    end
    if (parts[#parts] ~= nil and parts[#parts].kind == 'text') then
        parts[#parts].text = parts[#parts].text:gsub(' +$', '');
    end
    base.mobVariants[key] = parts;
    return parts;
end

return format;
