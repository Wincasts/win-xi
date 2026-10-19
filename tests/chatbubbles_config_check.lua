-- Standalone: luajit tests/chatbubbles_config_check.lua
package.path = './addons/chatbubbles/?.lua;' .. package.path;
T = function(value) return value; end;
local saves, callback, loadDefaults = 0;
local button, checkbox, changedColor;
local labels, ends = {}, 0;
package.loaded.settings = {
    load = function(defaults) loadDefaults = defaults; return defaults; end,
    save = function() saves = saves + 1; end,
    register = function(_, _, fn) callback = fn; end,
};
ashita = { events = { register = function() end } };
package.loaded.imgui = {
    Begin = function() return true; end,
    End = function() ends = ends + 1; end,
    BeginTabBar = function() return true; end, EndTabBar = function() end,
    BeginTabItem = function() return true; end, EndTabItem = function() end,
    Text = function() end, TextWrapped = function() end,
    SameLine = function() end, Separator = function() end,
    Button = function(label) return label == button; end,
    Checkbox = function(label, value)
        labels[label] = true;
        if label == checkbox then value[1] = not value[1]; return true; end
        return false;
    end,
    ColorEdit4 = function(label, value)
        if label == changedColor then value[1] = 0.25; return true; end
        return false;
    end,
};
local config = require('config');
local modes = require('modes');
local bubbles = require('bubbles');
local function allows(mode)
    return mode.source == 'text' and config.AllowsNpc(mode.id) or (mode.source ~= 'text' and config.Allows(mode.id));
end
assert(#modes.All == 42 and config.Enabled());
for _, mode in ipairs(modes.All) do assert(allows(mode) == mode.default); end
assert(config.AllowsNpc(150) and config.AllowsNpc(151) and not config.Allows(150));
assert(not config.Allows(255));
assert(loadDefaults.appearance.background[1] > 0.9, 'white bubbles to begin with, since the shared defaults');
assert(config.options.appearance.gameTextColors[1] == true);
config.Toggle();
config.Draw();
for _, mode in ipairs(modes.All) do
    assert(labels[('%02d: %s##chatbubbles.mode.%d'):format(mode.id, mode.label, mode.id)]);
end
button = 'White bubbles'; config.Draw(); button = nil;
assert(config.options.appearance.background[1] == 1 and config.options.appearance.text[1] == 0.05);
changedColor = 'Background'; config.Draw(); changedColor = nil;
assert(config.options.appearance.background[1] == 0.25);
checkbox = 'Match in-game chat text colors'; config.Draw(); checkbox = nil;
assert(config.options.appearance.gameTextColors[1] == false);
config.Preset(true);
assert(config.options.appearance.gameTextColors[1] == false); -- presets do not override matching preference
button = 'Enable all'; config.Draw(); button = nil;
for _, mode in ipairs(modes.All) do assert(allows(mode)); end
-- All catalogued incoming channel IDs can be enabled, and are filtered before decode.
for _, mode in ipairs(modes.All) do
    local packet = ('\0'):rep(4) .. string.char(mode.id) .. ('\0'):rep(3)
        .. 'Tester' .. ('\0'):rep(9) .. 'Hello' .. '\0';
    local speaker, text, parsed = bubbles.Parse(packet, config.Allows);
    if mode.source == 'text' then assert(speaker == nil); -- separate ID namespace
    else assert(speaker == 'tester' and text == 'Hello' and parsed == mode.id); end
end
for id in pairs(modes.Outgoing) do
    local packet = ('\0'):rep(4) .. string.char(id) .. '\0Own channel message\0';
    local text, mode = bubbles.ParseOutgoing(packet, config.Allows, 0x0B5);
    assert(text == 'Own channel message' and mode == id);
end
local tiny = ('\0'):rep(8) .. 'Tester' .. ('\0'):rep(9) .. 'a';
assert(select(2, bubbles.Parse(tiny, config.Allows)) == 'a'); -- padded packet can end without a null
button = 'Disable all'; config.Draw(); button = nil;
for _, mode in ipairs(modes.All) do
    assert(not allows(mode));
    local packet = ('\0'):rep(4) .. string.char(mode.id) .. '\0Skipped\0';
    assert(bubbles.ParseOutgoing(packet, config.Allows, 0x0B5) == nil);
end
checkbox = '03: Tell##chatbubbles.mode.3'; config.Draw(); checkbox = nil;
assert(config.Allows(3) and not config.Allows(0));
config.SetEnabled(false); assert(not config.Enabled());
assert(saves > 0 and ends > 0);
-- Character settings reload retains mode preferences and settles future/malformed fields.
callback({ enabled = { true }, modes = { ['3'] = { true } },
    appearance = { background = { 2, -1, 0 / 0, 0.5 }, text = false } });
assert(config.Enabled() and config.Allows(3) and config.Allows(0));
assert(config.AllowsNpc(150) and config.AllowsNpc(151)); -- old settings gain NPC defaults
assert(config.options.appearance.background[1] == 1 and config.options.appearance.background[2] == 0);
assert(config.options.appearance.background[3] == 1 and config.options.appearance.text[1] == 0.05); -- the defaults' white and dark
assert(config.options.appearance.gameTextColors[1] == true); -- migration defaults to matching
callback({ enabled = { true }, modes = {}, appearance = { gameTextColors = { false } } });
assert(config.options.appearance.gameTextColors[1] == false); -- saved manual preference survives reload
config.Preset(false);
assert(config.options.appearance.background[1] == 0.08);
print('chatbubbles config: saved settings, tabs, colors, presets, all channel switches and reload normalization passed');
