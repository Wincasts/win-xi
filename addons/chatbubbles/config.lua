-- Settings/UI boundary: rendering consumes appearance, packet readers consume modes.
local imgui = require('imgui');
local settings = require('settings');
local modes = require('modes');
local screen = require('winxi.screen');
local M = { open = { false } };
local function defaults()
    local channels = T{};
    for _, mode in ipairs(modes.All) do channels[mode.key] = T{ mode.default == true }; end
    return T{ enabled = T{ true }, modes = channels, appearance = T{
        background = T{ 1, 1, 1, 0.96 }, text = T{ 0.05, 0.05, 0.05, 1 },
        gameTextColors = T{ true },
    } };
end
local function settle(options)
    local base = defaults();
    if (type(options) ~= 'table') then options = base; end
    if (type(options.enabled) ~= 'table' or type(options.enabled[1]) ~= 'boolean') then options.enabled = base.enabled; end
    if (type(options.modes) ~= 'table') then options.modes = base.modes; end
    for _, mode in ipairs(modes.All) do
        local value = options.modes[mode.key];
        if (type(value) ~= 'table' or type(value[1]) ~= 'boolean') then options.modes[mode.key] = base.modes[mode.key]; end
    end
    if (type(options.appearance) ~= 'table') then options.appearance = base.appearance; end
    local gameColors = options.appearance.gameTextColors;
    if (type(gameColors) ~= 'table' or type(gameColors[1]) ~= 'boolean') then
        options.appearance.gameTextColors = base.appearance.gameTextColors;
    end
    for _, key in ipairs({ 'background', 'text' }) do
        local color = options.appearance[key];
        if (type(color) ~= 'table') then color = base.appearance[key]; end
        for i = 1, 4 do
            local value = color[i];
            color[i] = type(value) == 'number' and value == value and math.max(0, math.min(1, value)) or base.appearance[key][i];
        end
        options.appearance[key] = color;
    end
    return options;
end
M.options = settle(settings.load(defaults()));
function M.Save() settings.save(); end
function M.Enabled() return M.options.enabled[1]; end
function M.SetEnabled(value) M.options.enabled[1] = value; M.Save(); end
function M.Allows(mode)
    local value = M.options.modes[tostring(mode)];
    return value ~= nil and value[1] == true;
end
function M.AllowsNpc(mode)
    local value = M.options.modes['npc:' .. tostring(mode)];
    return value ~= nil and value[1] == true;
end
function M.Toggle() M.open[1] = not M.open[1]; end
function M.Preset(white)
    local bg = white and { 1, 1, 1, 0.96 } or { 0.08, 0.09, 0.12, 0.92 };
    local text = white and { 0.05, 0.05, 0.05, 1 } or { 1, 1, 1, 1 };
    for i = 1, 4 do
        M.options.appearance.background[i] = bg[i];
        M.options.appearance.text[i] = text[i];
    end
    M.Save();
end
settings.register('settings', 'chatbubbles_config', function(options)
    M.options = settle(options or M.options);
end);
ashita.events.register('unload', 'chatbubbles_save', M.Save);

function M.Draw()
    if (not M.open[1]) then return; end
    if (imgui.Begin('Chat Bubbles Settings', M.open)) then
        screen.Keep('Chat Bubbles Settings');
        if (imgui.Checkbox('Enable bubbles', M.options.enabled)) then M.Save(); end
        if (imgui.BeginTabBar('##chatbubbles.settings')) then
            if (imgui.BeginTabItem('Appearance')) then
                imgui.Text('Presets');
                if (imgui.Button('White bubbles')) then M.Preset(true); end
                imgui.SameLine();
                if (imgui.Button('Dark bubbles')) then M.Preset(false); end
                imgui.Separator();
                if (imgui.ColorEdit4('Background', M.options.appearance.background)) then M.Save(); end
                if (imgui.Checkbox('Match in-game chat text colors', M.options.appearance.gameTextColors)) then M.Save(); end
                if (imgui.ColorEdit4('Text (manual / fallback)', M.options.appearance.text)) then M.Save(); end
                imgui.TextWrapped('Game colors follow FFXI Config > Font Colors and update while bubbles are visible. Manual RGB applies when matching is off, to local tests, or if lookup is unavailable. Text opacity always applies. Game-colored text gets a dark outline on light backgrounds.');
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('Chat Modes')) then
                imgui.TextWrapped('Only enabled modes generate bubbles. NPC text channels are separate from player packet modes; dialogue 150/151 is enabled by default. Speakers still need a namehook anchor. Unattributed narration is skipped.');
                if (imgui.Button('Enable all')) then
                    for _, mode in ipairs(modes.All) do M.options.modes[mode.key][1] = true; end
                    M.Save();
                end
                imgui.SameLine();
                if (imgui.Button('Disable all')) then
                    for _, mode in ipairs(modes.All) do M.options.modes[mode.key][1] = false; end
                    M.Save();
                end
                for _, mode in ipairs(modes.All) do
                    if (imgui.Checkbox(('%02d: %s##chatbubbles.mode.%d'):format(mode.id, mode.label, mode.id), M.options.modes[mode.key])) then M.Save(); end
                end
                imgui.EndTabItem();
            end
            imgui.EndTabBar();
        end
    end
    imgui.End();
end
return M;
