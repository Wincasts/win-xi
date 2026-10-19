-- Installed-client auto-translate dictionary and exact six-byte chat tokens.
-- UTF-8 display text is NEVER used in place of an encoded token. See catalogs.md.
local reader = require('winxi.catalog').New('autotranslate');
local auto = {};
auto.Index, auto.Get, auto.Ids, auto.Clear = reader.Index, reader.Get, reader.Ids, reader.Clear;

local function integer(value, max)
    return type(value) == 'number' and value >= 1 and value <= max and value == math.floor(value);
end

function auto.Categories()
    return auto.Index().Categories or {};
end

function auto.Text(id, locale)
    local record = auto.Get(id);
    return record and record.Text[locale or 'en'] or nil;
end

function auto.Search(query, locale, category, limit)
    if type(query) ~= 'string' then return {}; end
    locale = locale or 'en';
    if not (auto.Index().Languages or {})[locale] then return {}; end
    if limit ~= nil and not integer(limit, 65535) then return {}; end
    query = query:lower();
    local found = {};
    for _, id in ipairs(auto.Ids()) do
        local record = auto.Get(id);
        local text = record and record.Text[locale];
        local reading = record and record.Readings[locale];
        if record and (category == nil or record.Category == category) and text and
            (text:lower():find(query, 1, true) or reading and reading:lower():find(query, 1, true)) then
            found[#found + 1] = record;
            if limit and #found >= limit then break; end
        end
    end
    return found;
end

local function language(locale)
    local definition = (auto.Index().Languages or {})[locale or 'en'];
    return definition and definition.Byte;
end

function auto.Token(id, locale)
    local record = auto.Get(id);
    local lang = language(locale);
    if not record or not lang or not record.Text[locale or 'en'] then return nil; end
    return string.char(0xFD, 0x02, lang, record.Category, record.Entry, 0xFD);
end

local function idToken(id, locale, kind)
    if not integer(id, 65535) then return nil; end
    local lang = language(locale);
    if not lang then return nil; end
    local high, low = math.floor(id / 256), id % 256;
    -- FFXI escapes zero ID bytes; a NUL would terminate the chat buffer.
    if high == 0 then kind, high = kind + 2, 0xFF;
    elseif low == 0 then kind, low = kind + 3, 0xFF; end
    return string.char(0xFD, kind, lang, high, low, 0xFD);
end

function auto.ItemToken(id, locale) return idToken(id, locale, 0x07); end
function auto.KeyItemToken(id, locale) return idToken(id, locale, 0x13); end

function auto.Decode(token)
    if type(token) ~= 'string' or #token ~= 6 then return nil; end
    local first, kind, lang, high, low, last = token:byte(1, 6);
    if first ~= 0xFD or last ~= 0xFD or lang == 0 or high == 0 or low == 0 then return nil; end
    if kind == 0x02 then
        return { Kind = 'phrase', Id = high * 256 + low, Category = high, Entry = low, LanguageByte = lang };
    end
    local name;
    if kind == 0x07 or kind == 0x09 or kind == 0x0A then name = 'item';
    elseif kind == 0x13 or kind == 0x15 or kind == 0x16 then name = 'keyitem';
    else return nil; end
    if kind == 0x09 or kind == 0x15 then
        if high ~= 0xFF then return nil; end
        high = 0;
    elseif kind == 0x0A or kind == 0x16 then
        if low ~= 0xFF then return nil; end
        low = 0;
    end
    return { Kind = name, Id = high * 256 + low, LanguageByte = lang };
end

-- Game expansion, if available, returns client-encoded chat text (CP932), not UTF-8.
function auto.Expand(token, brackets)
    if not auto.Decode(token) or not AshitaCore then return nil; end
    local ok, text = pcall(function()
        return AshitaCore:GetChatManager():ParseAutoTranslate(token, brackets ~= false);
    end);
    return ok and text or nil;
end

return auto;
