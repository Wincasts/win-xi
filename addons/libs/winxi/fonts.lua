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
