addon.name    = 'namehooktest';
addon.author  = 'win';
addon.version = '0.2';
addon.desc    = 'Shows namehook 1.46\'s layers, camera and claim slots at work on the target, to check them in game.';

-- A tool for checking namehook in game, not an addon to play with. Each part draws at the target's name
-- point, so that where they agree, they are right:
--
--   layer   a green cross at the target, anchored to it (a layer's drawing at an entity), and a red square
--           at the same point anchored to the world (from last frame's names): the two together
--   camera  a blue dot where winxi.camera puts the same point on the screen: on the cross, under lens too
--   over    the cross and square drawn over everything, not hidden by what is in front of the target
--   slot    every name claimed through a claim slot above Name's: the target's name an orange bar, whatever
--           it is; every other name left to Name (or hidden, without Name), as a lower claim has it
--
--   /nht                         what is on, and how each part is doing
--   /nht layer|camera|over|slot [on|off]
local winxiNeeded = 62;
do
    local ok, found = pcall(require, 'winxi.version');
    local number = ok and type(found) == 'table' and found.Number or 0;
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number);
        print('[namehooktest] ' .. text);
        error(text, 0);
    end
end

require('common');
local imgui = require('imgui');
local fonts = require('winxi.fonts');
local nameplates = require('winxi.nameplates');
local layers = require('winxi.layers');
local camera = require('winxi.camera');

local on = { layer = true, camera = true, over = false, slot = false };
local owner = nameplates.OwnerOf(addon.name);
local layer, slot = nil, nil;
local said = { layer = nil, slot = nil, camera = nil }; -- each part's trouble, as last said
local seen = { layer = 0, world = 0, camera = 0, slot = 0 }; -- frames each was drawn in, since loaded

local EVERY = 0xFF; -- every category: the target's, whatever it is
local TEST_PRIORITY = 200; -- above Name's own claim (nameplates.SharedPriority, 100)

local function say(words)
    print(('\30\81[\30\06namehooktest\30\81]\30\01 %s'):format(words));
end

-- each part's trouble said once in the chat log, and again only when it changes
local function trouble(part, why)
    if (why ~= said[part]) then
        said[part] = why;
        if (why ~= nil) then say(part .. ': ' .. why); end
    end
end

-- Where imgui's font texture has a white pixel, for plain coloured quads
local function whitePixel()
    if (imgui.GetFontTexUvWhitePixel ~= nil) then
        local u, v = imgui.GetFontTexUvWhitePixel();
        if (u ~= nil and type(u) ~= 'number') then u, v = u.x, u.y; end
        return u, v;
    end
    local font = imgui.GetFont();
    local white = font and font.ContainerAtlas and font.ContainerAtlas.TexUvWhitePixel;
    if (white ~= nil) then return white.x, white.y; end
    return nil;
end

-- The target: its index, server id and last frame's name (its point in the world), or nil
local function Target(hook)
    local target = AshitaCore:GetMemoryManager():GetTarget();
    local index = target and target:GetTargetIndex(0) or 0;
    if (index == nil or index == 0) then return nil; end
    local serverId = AshitaCore:GetMemoryManager():GetEntity():GetServerId(index);
    return index, serverId, nameplates.Find(index, hook);
end

-- A box of the white pixel, centred on (x, y) in pixels of the picture, by scale
local function Box(quad, x, y, width, height, color, u, v, scale)
    quad((x - width / 2) * scale, (y - height / 2) * scale, (x + width / 2) * scale, (y + height / 2) * scale, u, v, u, v, color, 0);
end

local function DrawLayer(hook, index, serverId, name, u, v)
    if (layer == nil) then
        local why;
        layer, why = layers.Take(owner, 10);
        if (layer == nil) then trouble('layer', why); return; end
    end
    local scale = layers.Begin(layer, owner);
    if (scale == nil) then layer = nil; return; end -- lost: taken again next frame
    trouble('layer', nil);
    layers.SetTexture(0, fonts.Texture());
    if (index == nil) then return; end
    -- anchored to the target: a cross
    if (layers.AtEntity(index, serverId, 0, 0, 0, 1, 1, 0xFF000000, on.over)) then
        Box(layers.Quad, 0, 0, 30, 5, 0xFF40FF40, u, v, scale);
        Box(layers.Quad, 0, 0, 5, 30, 0xFF40FF40, u, v, scale);
        layers.End();
        seen.layer = seen.layer + 1;
    end
    -- anchored to the world, at the same point as last frame's name: a square's outline
    if (name ~= nil and layers.AtWorld(name.X, name.Y, name.Z, 1, 0, 0, on.over)) then
        Box(layers.Quad, 0, -14, 30, 3, 0xFFFF4040, u, v, scale);
        Box(layers.Quad, 0, 14, 30, 3, 0xFFFF4040, u, v, scale);
        Box(layers.Quad, -14, 0, 3, 30, 0xFFFF4040, u, v, scale);
        Box(layers.Quad, 14, 0, 3, 30, 0xFFFF4040, u, v, scale);
        layers.End();
        seen.world = seen.world + 1;
    end
end

local function DrawCamera(name)
    local cam, why = camera.Get();
    if (cam == nil) then trouble('camera', why); return; end
    trouble('camera', nil);
    if (name == nil) then return; end
    local x, y, _, inside = camera.Project(name.X, name.Y, name.Z, cam);
    if (x == nil or not inside) then return; end
    local draw = imgui.GetForegroundDrawList ~= nil and imgui.GetForegroundDrawList() or imgui.GetBackgroundDrawList();
    draw:AddCircleFilled({ x, y }, 7, imgui.GetColorU32({ 0, 0, 0, 0.9 }), 16);
    draw:AddCircleFilled({ x, y }, 5, imgui.GetColorU32({ 0.25, 0.55, 1, 1 }), 16);
    seen.camera = seen.camera + 1;
end

local function DrawSlot(index, u, v)
    if (slot == nil) then
        local why;
        slot, why = nameplates.TakeSlot(owner, TEST_PRIORITY);
        if (slot == nil) then trouble('slot', why); return; end
    end
    if (not nameplates.ClaimSlot(slot, owner, EVERY, TEST_PRIORITY)) then slot = nil; return; end
    trouble('slot', nil);
    -- never BeginDrawing(nil): that is the plugin's own claim's buffer, Name's
    local target = nameplates.SlotDrawing(slot);
    local scale = target and nameplates.BeginDrawing(target, true);
    if (not scale) then return; end
    nameplates.SetTexture(0, fonts.Texture());
    -- the target's name alone: every other name is left to a lower claim
    if (index ~= nil and nameplates.BeginName(index, 1, 1, 0xFF000000)) then
        Box(nameplates.Quad, 0, -8, 90, 14, 0xFFFF9020, u, v, scale);
        nameplates.EndName();
        seen.slot = seen.slot + 1;
    end
end

local function ReleaseSlot()
    if (slot ~= nil) then nameplates.ReleaseSlot(slot, owner); slot = nil; end
end

local function ReleaseLayer()
    if (layer ~= nil) then layers.Release(layer, owner); layer = nil; end
end

ashita.events.register('d3d_present', 'namehooktest_present', function ()
    local hook = nameplates.Hook();
    if (hook == nil) then
        trouble('layer', nameplates.Problem());
        layer, slot = nil, nil;
        return;
    end
    local u, v = whitePixel();
    if (u == nil or fonts.Texture() == nil) then return; end
    local index, serverId, name = Target(hook);
    if (on.layer) then DrawLayer(hook, index, serverId, name, u, v) else ReleaseLayer() end
    if (on.camera) then DrawCamera(name) end
    if (on.slot) then DrawSlot(index, u, v) else ReleaseSlot() end
end);

ashita.events.register('unload', 'namehooktest_unload', function ()
    ReleaseSlot();
    ReleaseLayer();
end);

local function Status()
    local parts = {};
    for _, part in ipairs({ 'layer', 'camera', 'over', 'slot' }) do parts[#parts + 1] = part .. ' ' .. (on[part] and 'on' or 'off'); end
    say(table.concat(parts, ', ') .. '.');
    say(('layer %s, slot %s; drawn since loaded: cross %d, square %d, dot %d, orange bar %d frames.'):format(
        layer and ('#' .. layer) or 'none', slot and ('#' .. slot) or 'none', seen.layer, seen.world, seen.camera, seen.slot));
    local cam, why = camera.Get();
    say('camera: ' .. (cam and ('this frame\'s' .. (cam.Lens ~= 0 and ', lens warping' or ', no lens warp')) or tostring(why)));
    for part, why in pairs(said) do if (why ~= nil) then say(part .. ': ' .. why); end end
    say('With a target: the green cross, the red square and the blue dot should be one on another, under lens too; with slot on, the target\'s name an orange bar and every other name as Name draws it.');
end

ashita.events.register('command', 'namehooktest_command', function (e)
    local args = e.command:args();
    if (#args == 0 or (args[1]:lower() ~= '/nht' and args[1]:lower() ~= '/namehooktest')) then return; end
    e.blocked = true;
    local part = args[2] and args[2]:lower() or '';
    if (on[part] ~= nil) then
        local word = args[3] and args[3]:lower() or '';
        if (word == 'on' or word == 'off') then on[part] = word == 'on'; else on[part] = not on[part]; end
        if (part == 'slot' and not on.slot) then ReleaseSlot(); end
        if (part == 'layer' and not on.layer) then ReleaseLayer(); end
        say(part .. ' ' .. (on[part] and 'on' or 'off') .. '.');
        return;
    end
    Status();
end);
