-- winxi.legacy: bringing settings over for a tool that has become an addon of its own.
--
-- Several addons began as tools of xitools, which kept each tool's settings among its own, with one
-- theme, one set of rules for hiding and one choice of which tools fade for all of them.
--
--     local found = legacy.FromXitools('inv', options, { 'isVisible', 'pos', ... });
--
-- copies what xitools kept, for the character logged in, into the addon's settings: the tool's own
-- settings named in the list, and of xitools' as a whole its theme (options.useSharedTheme and
-- options.theme), its rules for hiding (options.hide, as winxi.game has them) and whether the tool's
-- windows faded (options.fadeInOut[1]), each where the addon's settings have a place for it. Returns
-- whether xitools had anything for the tool.
--
-- An addon does this once for each character, and not before the character is known
-- (settings.logged_in): it keeps a flag of its own to say it has been done.
local settings = require('settings');

local legacy = {};

-- Another addon's settings for the character logged in, as it saved them, or nil
function legacy.ReadSettings(addonName)
    local path = ('%s\\config\\addons\\%s\\%s_%d\\settings.lua'):format(
        AshitaCore:GetInstallPath(), addonName, settings.name, settings.server_id);
    if not ashita.fs.exists(path) then
        return nil;
    end

    local chunk = loadfile(path);
    if chunk == nil then
        return nil;
    end
    local ok, saved = pcall(chunk);
    return ok and type(saved) == 'table' and saved or nil;
end

local hideRules = {
    UnderMap = 'hideUnderMap', UnderChat = 'hideUnderChat', WhileLoading = 'hideWhileLoading',
    DuringEvent = 'hideDuringEvent', WithInterface = 'hideWithInterface',
};

function legacy.FromXitools(tool, options, keys)
    local old = legacy.ReadSettings('xitools');
    local saved = old and type(old.tools) == 'table' and old.tools[tool];
    if type(saved) ~= 'table' then
        return false;
    end

    for _, key in ipairs(keys) do
        if saved[key] ~= nil then
            options[key] = saved[key];
        end
    end

    local globals = old.globals;
    if type(globals) == 'table' then
        if globals.useSharedTheme ~= nil then
            options.useSharedTheme = globals.useSharedTheme and true or false;
        end
        if type(globals.theme) == 'table' then
            options.theme = globals.theme;
        end

        if type(options.hide) == 'table' then
            for rule, key in pairs(hideRules) do
                if type(globals[key]) == 'table' then
                    options.hide[rule] = globals[key][1] and true or false;
                end
            end
        end

        -- the tool's windows faded if xitools' fading was on and the tool was one of those chosen
        local fading = globals.fade;
        if type(fading) == 'table' and type(options.fadeInOut) == 'table' then
            local chosen = type(fading.tools) == 'table' and fading.tools[tool];
            options.fadeInOut[1] = (fading.Enabled and type(chosen) == 'table' and chosen[1]) and true or false;
        end
    end

    return true;
end

return legacy;
