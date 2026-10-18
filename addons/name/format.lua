-- How a name is written, as its player sets it out: a line of text in which [name] stands for the
-- name, [distance] for how far off it is, [level] for the levels a monster can be, [checked] for a
-- magnifying glass on a monster its player has checked and [aggro] for the sign that a monster is
-- aggressive or is not, [letter] for the experimental mob spawn-slot letter, [icons] for player icons, and everything
-- else is written as it is.
--
--   format.Compile(text)   the line taken apart, kept by the line: a list of parts, each
--                          { kind = 'text', 'name', 'distance', 'level', 'checked' or 'aggro', text =
--                            what a 'text' part says, color = 0xAARRGGBB, or nil for the name's own }
--                          ('letter' and 'icons' are also kinds)
--                          with .distance, .level, .checked, .aggro, .letter and .icons set if present
-- Options: space=N and color=NAME/#RGB on all tokens; size=N/gap=N on icons;
-- decimals=0..2 on distance; type=single/double on [letters] (legacy alias [letter]).
-- Check formats also support [difficulty], [checklevel], [senses], [links] and
-- [mob: field=family] / [mob: field=modifiers.fire] (see mob_fields.lua).
-- Options may be separated by commas, semicolons or spaces.
--
-- A colour is #RRGGBB, #RGB or one of the names below.
--   [name:#FF8000]  [distance:yellow]   that one thing in that colour
--   [#FF8000] ... [/]                   everything from there to [/], or to the end, in that colour
-- With no colour given a thing is in the colour the game gives the name.
--
-- Square brackets round anything else are not taken for anything, and are written as they are. Only
-- the letters, figures and signs of plain English can be written: the font has no others.
local format = {};
local mobFields = require('mob_fields');
local rules = require('block_rules');

format.Colors = {
    white  = 0xFFFFFF, black  = 0x000000, grey   = 0xA0A0A0, gray   = 0xA0A0A0,
    red    = 0xFF4040, green  = 0x60E060, blue   = 0x6090FF, yellow = 0xFFE040,
    orange = 0xFF9030, purple = 0xC070FF, pink   = 0xFF80C0, cyan   = 0x60E0E0,
};

format.Things = { name = true, distance = true, level = true, checked = true, aggro = true, letter = true, letters = true, icons = true,
    mob = true, difficulty = true, checklevel = true, senses = true, links = true, text = true };

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

-- Token options accept comma/semicolon/space-separated key=value pairs.
-- Legacy [name:yellow] remains shorthand for color=yellow.
local function parameters(kind, typed, inherited)
    local part = { kind = kind, color = inherited };
    if (typed == nil) then return kind ~= 'mob' and kind ~= 'text' and part or nil; end
    local any = false;
    typed = typed:gsub('%s*=%s*', '=');
    for entry in typed:gmatch('[^,;%s]+') do
        any = true;
        local key, value = entry:match('^(%a+)=(.+)$');
        if (key == nil) then key, value = 'color', entry; end
        if (key == 'color') then
            part.color = color(value);
            if (part.color == nil) then return nil; end
        elseif (kind == 'text' and key == 'value') then
            if (value == 'empty') then part.text = '';
            elseif (value:gsub('%%%x%x', '') == '') then
                part.text = value:gsub('%%(%x%x)', function(hex) return string.char(tonumber(hex, 16)); end);
            else return nil; end
        elseif (key == 'when') then
            local normalized = rules.Normalize(value);
            if (normalized == nil) then return nil; end
            part.when = normalized ~= '' and normalized or nil;
        elseif (kind == 'mob' and key == 'display') then
            if (value ~= 'raw' and value ~= 'names' and value ~= 'both') then return nil; end
            part.display = value;
        elseif (kind == 'mob' and key == 'field') then
            if (not mobFields.ByKey[value]) then return nil; end
            part.field = value;
        elseif (kind == 'letter' and key == 'type') then
            if (value ~= 'single' and value ~= 'double') then return nil; end
            part.type = value;
        else
            local number = tonumber(value);
            if (number == nil or number ~= number or math.abs(number) == math.huge) then return nil; end
            local low, high;
            if (key == 'space') then low, high = 0, 64;
            elseif (key == 'within') then low, high = 1, 100;
            elseif (kind == 'icons' and key == 'size') then low, high = 25, 300;
            elseif (kind == 'icons' and key == 'gap') then low, high = 0, 24;
            elseif (kind == 'distance' and key == 'decimals') then low, high = 0, 2;
            else return nil; end
            part[key] = math.max(low, math.min(high, math.floor(number)));
        end
    end
    if ((kind == 'mob' and not part.field) or (kind == 'text' and part.text == nil)) then return nil; end
    return any and part or nil;
end

local compiled = {};
local compiledCount = 0;

-- Apart from format.Compile, which is asked every frame: a function with another made inside it is
-- one LuaJIT will not compile, nor anything that calls it.
local function parse(text)
    local found = { distance = false, level = false, checked = false, aggro = false, letter = false, icons = false };
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
            local thing, tint = inside:lower():match('^%s*(%a+)%s*:%s*(.-)%s*$');
            thing = thing or typed;
            if (thing == 'letters') then thing = 'letter'; end
            local part = format.Things[thing] and parameters(thing, tint, current);

            if (typed == '/') then
                flush();
                current = nil;
            elseif (part ~= nil and part ~= false) then
                flush();
                found[#found + 1] = part;
                found.distance = found.distance or thing == 'distance';
                found.level = found.level or thing == 'level';
                found.checked = found.checked or thing == 'checked';
                found.aggro = found.aggro or thing == 'aggro';
                found.letter = found.letter or thing == 'letter';
                found.icons = found.icons or thing == 'icons';
                found.rules = found.rules or part.when ~= nil or part.within ~= nil;
                found.ruleDistance = found.ruleDistance or part.within ~= nil;
                found.doubleLetters = found.doubleLetters or (thing == 'letter' and part.type == 'double');
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
    return found;
end

function format.Compile(text)
    local found = compiled[text];
    if (found ~= nil) then
        return found;
    end

    found = parse(text);
    if (compiledCount > 64) then
        compiled, compiledCount = {}, 0;
    end
    compiled[text] = found;
    compiledCount = compiledCount + 1;
    return found;
end

-- Legacy filtering utility retained for compatibility/tests. The production renderer
-- compiles the string directly: there are no level/aggro/letter visibility toggles.
function format.Mob(text, showLevel, showAggro, showLetter)
    local base = format.Compile(text);
    -- The toggle works without editing a format; an explicit token controls its position/colour.
    if (showLetter and not base.letter) then
        base.withLetter = base.withLetter or format.Compile(text .. ' [letter]');
        base = base.withLetter;
    end
    if (showLevel and showAggro and (showLetter or not base.letter)) then return base; end
    local key = (showLevel and 1 or 0) + (showAggro and 2 or 0) + (showLetter and 4 or 0);
    base.mobVariants = base.mobVariants or {};
    if (base.mobVariants[key] ~= nil) then return base.mobVariants[key]; end
    local parts = { distance = base.distance, checked = base.checked,
        level = showLevel and base.level or false, aggro = showAggro and base.aggro or false,
        letter = showLetter and base.letter or false, icons = base.icons,
        doubleLetters = showLetter and base.doubleLetters or false, rules = base.rules, ruleDistance = base.ruleDistance };
    local stripDot = false;
    for _, part in ipairs(base) do
        if (part.kind == 'level' and not showLevel) then
            local previous = parts[#parts];
            if (previous ~= nil and previous.kind == 'text') then
                previous.text = previous.text:gsub('%f[%a][Ll][Vv]%.?%s*$', '');
            end
            stripDot = true;
        elseif ((part.kind ~= 'aggro' or showAggro) and (part.kind ~= 'letter' or showLetter)) then
            local copy = {};
            for field, value in pairs(part) do copy[field] = value; end;
            if (copy.kind == 'text') then
                if (stripDot) then copy.text = copy.text:gsub('^%.%s*', ''); end
                local previous = parts[#parts];
                if (previous ~= nil and previous.kind == 'text' and previous.color == copy.color
                        and previous.when == copy.when and previous.within == copy.within and previous.space == copy.space) then
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

-- Serialize copied compiler parts for migrations and the visual builder, without mutating caches.
function format.Serialize(parts, doubleLetters)
    local out = {};
    for _, part in ipairs(parts) do
        if (part.kind == 'text' and not part.when and not part.within and not part.space) then
            out[#out + 1] = part.color and ('[#%06X]%s[/]'):format(part.color % 0x1000000, part.text) or part.text;
        else
            local args = {};
            if (part.kind == 'text') then
                local encoded = part.text:gsub('.', function(char) return ('%%%02X'):format(char:byte()); end);
                args[#args+1] = 'value=' .. (encoded ~= '' and encoded or 'empty');
            end
            if (part.color ~= nil) then args[#args + 1] = ('color=#%06X'):format(part.color % 0x1000000); end
            for _, field in ipairs({ 'space', 'size', 'gap', 'decimals', 'type', 'field', 'display', 'when', 'within' }) do
                local value = field == 'type' and part.kind == 'letter' and doubleLetters and 'double' or part[field];
                if (value ~= nil) then args[#args + 1] = field .. '=' .. tostring(value); end
            end
            out[#out + 1] = '[' .. (part.kind == 'letter' and 'letters' or part.kind)
                .. (#args > 0 and (': ' .. table.concat(args, ', ')) or '') .. ']';
        end
    end
    return table.concat(out);
end

return format;
