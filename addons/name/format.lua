-- How a name is written, as its player sets it out: a line of text in which [name] stands for the
-- name, [distance] for how far off it is, [level] for the levels a monster can be, [checked] for a
-- magnifying glass on a monster its player has checked and [aggro] for the sign that a monster is
-- aggressive or is not, [letter] for the experimental mob spawn-slot letter, [icons] for player icons,
-- [party] for a party or alliance member's sign of their place in it, [vendor] for the coin of an NPC
-- that sells, [space] for a gap of its own, and everything else is written as it is.
--
--   format.Compile(text)   the line taken apart, kept by the line: a list of parts, each
--                          { kind = 'text', 'name', 'distance', 'level', 'checked' or 'aggro', text =
--                            what a 'text' part says, color = 0xAARRGGBB, or nil for the name's own }
--                          ('letter', 'icons', 'party' and 'vendor' are also kinds)
--                          with .distance, .level, .checked, .aggro, .letter, .icons, .party and .vendor
--                          set if present, and .partyReplace if a [party] says replace
-- [space], [space: N] or [space: size=N]: N screen pixels (4 without), only between two things written:
-- not at either end of the line, nor beside a token that writes nothing.
-- Options: space=N and color=NAME/#RGB on all tokens, and when=target+checked+nm+relevant and
-- within=N (block_rules.lua); size=N/gap=N on icons; size=N on party, vendor, aggro and checked; replace on [party],
-- its sign in place of the game's icons for a member; decimals=0..2 on distance; spacing=0..10 on
-- name, level and distance, screen pixels between its letters in place of the Letter Spacing setting; type=single/double on
-- [letters] (legacy alias [letter]); exact on [level], the level only once a check has told it, never
-- the database's range; nocombat on [level], nothing while the monster is in combat (block_rules.lua). Options may be separated by commas, semicolons or spaces.
--
-- A colour is #RRGGBB, #RGB or one of the names below.
--   [name:#FF8000]  [distance:yellow]   that one thing in that colour
--   [#FF8000] ... [/]                   everything from there to [/], or to the end, in that colour
-- With no colour given a thing is in the colour the game gives the name.
--
-- Square brackets round anything else are not taken for anything, and are written as they are. Only
-- the letters, figures and signs of plain English can be written: the font has no others.
local format = {};
local rules = require('block_rules');

format.Colors = {
    white  = 0xFFFFFF, black  = 0x000000, grey   = 0xA0A0A0, gray   = 0xA0A0A0,
    red    = 0xFF4040, green  = 0x60E060, blue   = 0x6090FF, yellow = 0xFFE040,
    orange = 0xFF9030, purple = 0xC070FF, pink   = 0xFF80C0, cyan   = 0x60E0E0,
};

format.Things = { name = true, distance = true, level = true, checked = true, aggro = true, letter = true, letters = true, icons = true,
    party = true, vendor = true, space = true };

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
    if (typed == nil) then return part; end
    local any = false;
    typed = typed:gsub('%s*=%s*', '=');
    for entry in typed:gmatch('[^,;%s]+') do
        any = true;
        local key, value = entry:match('^(%a+)=(.+)$');
        if (key == nil and kind == 'level' and entry == 'exact') then key, value = 'exact', 'true'; end
        if (key == nil and kind == 'level' and entry == 'nocombat') then key, value = 'nocombat', 'true'; end
        if (key == nil and kind == 'party' and entry == 'replace') then key, value = 'replace', 'true'; end
        if (key == nil and kind == 'space' and tonumber(entry) ~= nil) then key, value = 'size', entry; end
        if (key == nil) then key, value = 'color', entry; end
        if (kind == 'level' and key == 'exact') then
            if (value ~= 'true' and value ~= 'false') then return nil; end
            part.exact = value == 'true' or nil;
        elseif (kind == 'level' and key == 'nocombat') then
            if (value ~= 'true' and value ~= 'false') then return nil; end
            part.nocombat = value == 'true' or nil;
        elseif (kind == 'party' and key == 'replace') then
            if (value ~= 'true' and value ~= 'false') then return nil; end
            part.replace = value == 'true' or nil;
        elseif (key == 'color') then
            part.color = color(value);
            if (part.color == nil) then return nil; end
        elseif (key == 'when') then
            local normalized = rules.Normalize(value);
            if (normalized == nil) then return nil; end
            part.when = normalized ~= '' and normalized or nil;
        elseif (kind == 'letter' and key == 'type') then
            if (value ~= 'single' and value ~= 'double') then return nil; end
            part.type = value;
        else
            local number = tonumber(value);
            if (number == nil or number ~= number or math.abs(number) == math.huge) then return nil; end
            local low, high;
            if (key == 'space') then low, high = 0, 64;
            elseif (key == 'within') then low, high = 1, 100;
            elseif ((kind == 'icons' or kind == 'party' or kind == 'vendor' or kind == 'aggro' or kind == 'checked') and key == 'size') then low, high = 25, 300;
            elseif (kind == 'space' and key == 'size') then low, high = 0, 64;
            elseif (kind == 'icons' and key == 'gap') then low, high = 0, 24;
            elseif (kind == 'distance' and key == 'decimals') then low, high = 0, 2;
            elseif ((kind == 'name' or kind == 'level' or kind == 'distance') and key == 'spacing') then low, high = 0, 10;
            else return nil; end
            part[key] = math.max(low, math.min(high, math.floor(number)));
        end
    end
    return any and part or nil;
end

local compiled = {};
local compiledCount = 0;

-- Apart from format.Compile, which is asked every frame: a function with another made inside it is
-- one LuaJIT will not compile, nor anything that calls it.
local function parse(text)
    local found = { distance = false, level = false, checked = false, aggro = false, letter = false, icons = false,
        party = false, vendor = false, partyReplace = false };
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
                found.party = found.party or thing == 'party';
                found.vendor = found.vendor or thing == 'vendor';
                found.partyReplace = found.partyReplace or (thing == 'party' and part.replace == true);
                found.rules = found.rules or part.when ~= nil or part.within ~= nil or part.nocombat == true;
                found.ruleCombat = found.ruleCombat or part.nocombat == true;
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

    -- an icon token followed by a [space] has that gap in place of the icons' own spacing
    for index, part in ipairs(found) do
        local nextPart = found[index + 1];
        if ((part.kind == 'icons' or part.kind == 'party' or part.kind == 'vendor') and part.space == nil
                and nextPart ~= nil and nextPart.kind == 'space') then
            part.space = 0;
        end
    end

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

-- A line written back from its parts, as a migration rewrites a saved one: the caches are not touched.
function format.Serialize(parts, doubleLetters)
    local out = {};
    for _, part in ipairs(parts) do
        if (part.kind == 'text') then
            out[#out + 1] = part.color and ('[#%06X]%s[/]'):format(part.color % 0x1000000, part.text) or part.text;
        else
            local args = {};
            if (part.color ~= nil) then args[#args + 1] = ('color=#%06X'):format(part.color % 0x1000000); end
            if (part.exact) then args[#args + 1] = 'exact'; end
            if (part.nocombat) then args[#args + 1] = 'nocombat'; end
            if (part.replace) then args[#args + 1] = 'replace'; end
            for _, field in ipairs({ 'space', 'size', 'gap', 'spacing', 'decimals', 'type', 'when', 'within' }) do
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
