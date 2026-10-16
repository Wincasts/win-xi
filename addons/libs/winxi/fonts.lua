-- winxi.fonts: the theme's font, the one every winxi window is written in unless the addon says
-- otherwise.
--
--   fonts.Push(settingsKind)  before a window's Begin: the theme's font and size, where it has any;
--                       returns whether anything was pushed, for fonts.Pop. settingsKind true for a
--                       settings window (winxi.window's kinds), which is written in the theme's
--                       Settings Font at its Settings Font Size.
--   fonts.Pop(pushed)   after its End
--   fonts.Get(file)     a font of C:\Windows\Fonts loaded for imgui, or nil (Default, or a file that
--                       would not load); loaded the first time it is asked for
--   fonts.Files()       the .ttf files there are to choose from, sorted, looked for once
--   fonts.Texture()     the Direct3D texture imgui draws the font in use from, as a number, for
--                       drawing its letters elsewhere (a plugin's quads), nil, and which way it was
--                       had; or nil, and why not
--   fonts.TextureDetail() what imgui holds of that texture, read each way apart, as { label, text }
--                       pairs: for diagnostics
--
-- The theme's FontFile (and SettingsFontFile) is a file of C:\Windows\Fonts, or '' for imgui's own
-- font; its FontSize (and SettingsFontSize) is in pixels, or 0 for the base size. Either is only the starting point: an addon that pushes a font of
-- its own inside a window (imgui.PushFont(font, size)) writes in that, and one that pushes only a size
-- (imgui.PushFont(nil, size)) writes in the theme's font at that size.
local imgui = require('imgui');
local theme = require('winxi.theme');

local fonts = {};

fonts.Folder = 'C:\\Windows\\Fonts\\';

local loaded = {}; -- file -> the font, or false where it would not load

function fonts.Get(file)
    if type(file) ~= 'string' or file == '' then
        return nil;
    end
    local found = loaded[file];
    if found == nil then
        local ok, made = pcall(imgui.AddFontFromFileTTF, fonts.Folder .. file, 16);
        found = (ok and made ~= nil) and made or false;
        loaded[file] = found;
        if found == false then
            print(('\30\81[%s]\30\01 The font %s could not be loaded: winxi\'s windows are in the usual one.'):format(addon.name, file));
        end
    end
    return found or nil;
end

local files = nil;

function fonts.Files()
    if files == nil then
        files = {};
        local ok, found = pcall(ashita.fs.get_directory, fonts.Folder, '.*\\.ttf');
        if ok and type(found) == 'table' then
            for _, file in pairs(found) do
                files[#files + 1] = file;
            end
            table.sort(files, function(a, b) return a:lower() < b:lower(); end);
        end
    end
    return files;
end

-- imgui 1.92 keeps the font's texture in two places: the atlas's texture data, and the reference to
-- it that the renderer is handed. Their fields are read first: a field is only read, where asking
-- the reference for its id (GetTexID) trips an assertion in imgui while it holds the texture both
-- ways, which Ashita turns into an exception. On a tester's Windows machine names drew for a while
-- and then both methods threw for the rest of the session, as they can once the renderer has made
-- its textures again (a Direct3D device reset: alt-tab or minimising in full screen, a change of
-- resolution). The methods are asked after the fields, each apart, so that one failing leaves the
-- others.
local function FontAtlas()
    return imgui.GetFont().ContainerAtlas;
end

local function DataField(atlas)
    return atlas.TexData.TexID;
end

local function ReferenceField(atlas)
    return atlas.TexRef._TexID;
end

local function DataId(atlas)
    return atlas.TexData:GetTexID();
end

local function ReferenceId(atlas)
    return atlas.TexRef:GetTexID();
end

-- the ways of asking, in order: a name for what each said, and how to ask
local ROUTES = {
    { 'texture data field', DataField },
    { 'reference field', ReferenceField },
    { 'texture data', DataId },
    { 'reference', ReferenceId },
};

local function Answer(name, ok, id)
    if not ok then
        return ('%s error: %s'):format(name, tostring(id));
    end
    return ('%s id %s'):format(name, tostring(id));
end

function fonts.Texture()
    local ok, atlas = pcall(FontAtlas);
    if not ok or atlas == nil then
        return nil, ('no font atlas: %s'):format(ok and 'none' or tostring(atlas));
    end
    -- asked every frame by some: nothing is made unless none answers
    for index = 1, #ROUTES do
        local route = ROUTES[index];
        local asked, id = pcall(route[2], atlas);
        if asked and type(id) == 'number' and id ~= 0 then
            return id, nil, route[1];
        end
    end
    local answers = {};
    for index, route in ipairs(ROUTES) do
        answers[index] = Answer(route[1], pcall(route[2], atlas));
    end
    return nil, table.concat(answers, '; ');
end

-- what imgui holds of the font's texture, a line each, each read apart: for diagnostics
function fonts.TextureDetail()
    local lines = {};
    local function try(label, read)
        local ok, value = pcall(read);
        lines[#lines + 1] = { label, ok and tostring(value) or ('(unreadable: ' .. tostring(value) .. ')') };
    end
    local atlas = nil;
    try('atlas', function () atlas = FontAtlas(); return atlas ~= nil and 'found' or 'none'; end);
    if atlas == nil then
        return lines;
    end
    try('texture data', function ()
        local data = atlas.TexData;
        return ('unique id %s, %s x %s, status %s'):format(tostring(data.UniqueID), tostring(data.Width), tostring(data.Height), tostring(data.Status));
    end);
    for _, route in ipairs(ROUTES) do
        try(route[1] .. ' id', function () return route[2](atlas); end);
    end
    try('reference data', function ()
        local held = atlas.TexRef._TexData;
        return held == nil and 'none' or tostring(held);
    end);
    try('textures in the list', function ()
        local list = atlas.TexList;
        if type(list) ~= 'table' then
            return tostring(list);
        end
        local each = {};
        for index, data in ipairs(list) do
            local ok, said = pcall(function ()
                return ('%s x %s status %s id %s'):format(tostring(data.Width), tostring(data.Height), tostring(data.Status), tostring(data.TexID));
            end);
            each[#each + 1] = ('[%d] %s'):format(index, ok and said or ('unreadable: ' .. tostring(said)));
        end
        return ('%d: %s'):format(#list, table.concat(each, ', '));
    end);
    return lines;
end

function fonts.Push(settingsKind)
    local font = fonts.Get(theme.For('FontFile', settingsKind));
    local size = tonumber(theme.For('FontSize', settingsKind)) or 0;
    if font == nil and size <= 0 then
        return false;
    end
    imgui.PushFont(font, size);
    return true;
end

function fonts.Pop(pushed)
    if pushed then
        imgui.PopFont();
    end
end

return fonts;
