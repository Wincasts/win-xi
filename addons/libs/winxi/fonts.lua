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
--                       drawing its letters elsewhere (a plugin's quads); or nil, and why not
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
-- it that the renderer is handed. The data is asked first. Asking the reference, while it holds the
-- texture both ways (as it can once the atlas has been made again, a font added while running, say),
-- trips an assertion in imgui that Ashita turns into an exception: asked first, alone, that kept the
-- data from ever being asked. Each is asked apart, so that one failing leaves the other.
local function FontAtlas()
    return imgui.GetFont().ContainerAtlas;
end

local function DataId(atlas)
    return atlas.TexData:GetTexID();
end

local function ReferenceId(atlas)
    return atlas.TexRef:GetTexID();
end

local function Answer(ok, id)
    if not ok then
        return ('error: %s'):format(tostring(id));
    end
    return ('id %s'):format(tostring(id));
end

function fonts.Texture()
    local ok, atlas = pcall(FontAtlas);
    if not ok or atlas == nil then
        return nil, ('no font atlas: %s'):format(ok and 'none' or tostring(atlas));
    end
    local dataOk, data = pcall(DataId, atlas);
    if dataOk and type(data) == 'number' and data ~= 0 then
        return data;
    end
    local referenceOk, reference = pcall(ReferenceId, atlas);
    if referenceOk and type(reference) == 'number' and reference ~= 0 then
        return reference;
    end
    return nil, ('texture data %s; reference %s'):format(Answer(dataOk, data), Answer(referenceOk, reference));
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
