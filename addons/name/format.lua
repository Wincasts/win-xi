-- How a name is written, as its player sets it out: a line of text in which [name] stands for the
-- name, [distance] for how far off it is and [level] for the levels a monster can be, and everything
-- else is written as it is.
--
--   format.Compile(text)   the line taken apart, kept by the line: a list of parts, each
--                          { kind = 'text', 'name', 'distance' or 'level', text = what a 'text'
--                            part says, color = 0xAARRGGBB, or nil for the name's own }
--                          with .distance set if any part is the distance, and .level if the level
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

format.Things = { name = true, distance = true, level = true };

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

    found = { distance = false, level = false };
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

return format;
