addon.name = 'chatbubbles';
addon.author = 'win';
addon.version = '0.98';
addon.desc = 'Configurable chat bubbles anchored by namehook, in the world or on the screen.';

-- The winxi this addon was made with, or a newer one: each addon is released with its own copy, so an
-- older one may have been put over it (winxi.version)
local winxiNeeded = 59; -- namehook_draw_t's TexturesExtra (57: winxi.abi, 55: nameplates.Generation)
do
    local ok, found = pcall(require, 'winxi.version');
    local number = ok and type(found) == 'table' and found.Number or 0;
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number);
        print(('\30\68[%s]\30\01 %s'):format(addon.name, text));
        error(text, 0);
    end
end

require('common');
local imgui = require('imgui');
local shell = require('winxi.shell');
local nameplates = require('winxi.nameplates');
local bubbles = require('bubbles');
local encoding = require('encoding');
local world = require('world');
local screen = require('screen');
local fonts = require('winxi.fonts');
local game = require('winxi.game');
local config = require('config');
local npc = require('npc');
local modes = require('modes');
local bit = require('bit');
local colors = require('colors');
local state = bubbles.New();
local npcState = npc.New();
local wasEnabled; -- whether the bubbles were on last frame, once the settings are loaded
local targetMessage;
local diagnosticUntil = 0;
local stats = { incoming = 0, outgoing = 0, anchors = 0, matched = 0, drawn = 0,
    npcText = 0, npcAttributed = 0, npcReason = 'none' };

local function ownName()
    local name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0);
    return type(name) == 'string' and name ~= '' and name:lower() or nil;
end

local function clear()
    state = bubbles.New();
    npcState = npc.New();
    targetMessage = nil;
    diagnosticUntil = 0;
    world.Clear();
end

local function prune(now)
    if (targetMessage and now >= targetMessage.expires) then targetMessage = nil; end
    return bubbles.Prune(state, now) + npc.Prune(npcState, now) + (targetMessage and 1 or 0);
end

local app; -- the shell's: the settings, their window and the command

local function report(text)
    app:Say(text);
end

local missingCleared = false; -- cleared since namehook was last found missing
local problemSaid = nil;      -- why namehook cannot be used, as last said in the chat log

ashita.events.register('load', 'chatbubbles_load', function ()
    report('Requires namehook 1.24+. /chatbubbles opens the settings; Say and NPC dialogue are enabled by default.');
end);

ashita.events.register('unload', 'chatbubbles_unload', clear);

local function validNpc(actor)
    return AshitaCore:GetMemoryManager():GetEntity():GetServerId(actor.index) == actor.id;
end

local function lookupNpc(actor)
    if (not validNpc(actor)) then return nil; end
    local raw = AshitaCore:GetMemoryManager():GetEntity():GetName(actor.index);
    if (type(raw) ~= 'string' or raw == '') then return nil; end
    return { index = actor.index, id = actor.id, name = encoding.Decode(raw) };
end

ashita.events.register('packet_in', 'chatbubbles_packet', function (e)
    if (config.Enabled() and not e.blocked) then
        npc.Packet(npcState, e.id, e.data, os.clock(), validNpc);
    end
    if (e.id == 0x00A or e.id == 0x00B) then
        clear(); -- zone entry/exit: never carry speech to another area's entities
    elseif (config.Enabled() and e.id == 0x017 and not e.blocked) then
        local speaker, text, mode = bubbles.Parse(e.data, config.Allows);
        if (speaker) then
            stats.incoming = stats.incoming + 1;
            bubbles.Add(state, speaker, encoding.Decode(text), os.clock(), mode);
        end
    end
end);

ashita.events.register('text_in', 'chatbubbles_npc_text', function (e)
    local mode = bit.band(e.mode, 0xFF);
    if (not config.Enabled() or not modes.Npc[mode] or not config.AllowsNpc(mode)) then return; end
    if (type(e.message) ~= 'string' or #e.message > 8192) then return; end
    -- Read the original client-resolved text, even if another chat UI blocks its
    -- display. Never alter text, mode, or blocked state ourselves.
    stats.npcText = stats.npcText + 1;
    local text = encoding.Decode(e.message, true);
    local candidates = {};
    for _, name in nameplates.Each() do
        if (tonumber(name.ServerId) >= 0x01000000) then
            candidates[#candidates + 1] = { index = tonumber(name.EntityIndex), id = tonumber(name.ServerId),
                name = encoding.Decode(nameplates.Name(name)) };
        end
    end
    local message, reason = npc.Resolve(npcState, text, mode, os.clock(), candidates, lookupNpc);
    if (message) then
        stats.npcAttributed = stats.npcAttributed + 1;
        -- a line that waits for a key before the next carries the game's prompt escape, DEL '1'
        message.prompt = e.message:find('\127\49', 1, true) ~= nil;
    else stats.npcReason = reason or 'unknown'; end
end);

ashita.events.register('packet_out', 'chatbubbles_outgoing', function (e)
    if (not config.Enabled() or (e.id ~= 0x0B5 and e.id ~= 0x0B6) or e.blocked) then return; end
    local text, mode = bubbles.ParseOutgoing(e.data, config.Allows, e.id);
    local speaker = text and ownName();
    if (speaker) then
        stats.outgoing = stats.outgoing + 1;
        local message = bubbles.Add(state, speaker, encoding.Decode(text), os.clock(), mode);
        if (message) then message.outgoing = true; end
    end
end);

-- What every command says after: whether the bubbles are on, what is wrong, and the counts
local function status()
    local problem = nameplates.Problem() or world.Problem();
    report((config.Enabled() and 'On' or 'Off') .. '. ' .. (problem or 'namehook ready.')
        .. ' /chatbubbles on | off | clear | status | test | target [text]');
    report(('Enabled chat packets in/out: %d/%d; active messages: %d; last frame anchors/matches/drawn: %d/%d/%d')
        :format(stats.incoming, stats.outgoing, prune(os.clock()), stats.anchors, stats.matched, stats.drawn));
    if (colors.Problem()) then report(colors.Problem()); end
    report(('NPC text received/attributed: %d/%d; last skipped line: %s')
        :format(stats.npcText, stats.npcAttributed, stats.npcReason));
end

-- The settings, the settings window and the command are the shell's; the verbs here are its own
app = shell.New({
    defaults     = config.Defaults(),
    configTitle  = 'Chat Bubbles Settings',
    hideAppearance = true,
    menuOnlyCommands = true,
    command      = '/chatbubbles',
    help         = '/chatbubbles opens or closes the settings; /chatbubbles on | off | clear | status | test | target [text].',
    settingsLabel = 'Appearance',
    drawSettings = config.DrawAppearance,
    tabs         = { { label = 'Chat Modes', draw = config.DrawModes } },
    commands     = {
        on = function () config.SetEnabled(true); status(); end,
        off = function () config.SetEnabled(false); clear(); status(); end,
        clear = function () clear(); status(); end,
        status = status,
        target = function (_, args)
            local memory = AshitaCore:GetMemoryManager();
            local target = memory:GetTarget();
            local index = target:GetTargetIndex(target:GetIsSubTargetActive());
            local id = index and index > 0 and index < 0x900 and memory:GetEntity():GetServerId(index) or 0;
            if (id == 0) then report('Select a nearby target first.'); return; end
            local text = args[3] and encoding.Decode(table.concat(args, ' ', 3)) or 'Test speech bubble';
            if (text == '' or not text:find('%S')) then report('Test text cannot be empty.'); return; end
            config.SetEnabled(true);
            targetMessage = { text = text, expires = os.clock() + 8, index = index, id = id };
            report('Local test bubble created for your target (8 seconds). No chat was sent.');
            status();
        end,
        test = function ()
            config.SetEnabled(true);
            diagnosticUntil = os.clock() + 8;
            local speaker = ownName();
            if (speaker) then
                bubbles.Add(state, speaker, 'Test speech bubble', os.clock());
                state.messages[speaker].synthetic = true;
            end
            report('8-second test: a fixed label should appear at the top, plus a bubble above your head if an anchor exists.');
            status();
        end,
    },
    onSettings   = function (options)
        config.Settle(options);
    end,
});
config.Attach(app);
if (config.options == nil) then config.Settle(app.options); end
wasEnabled = config.Enabled();

ashita.events.register('d3d_present', 'chatbubbles_present', function ()
    app:BeginFrame(); -- the settings window, while it is open
    if (not app.showConfig[1]) then config.preview[1] = false; end
    if (not config.Enabled()) then
        if (wasEnabled) then clear(); end
        wasEnabled = false;
        return;
    end
    wasEnabled = true;
    local now = os.clock();
    stats.anchors, stats.matched, stats.drawn = 0, 0, 0;
    if (now < diagnosticUntil) then
        local testDraw = imgui.GetBackgroundDrawList();
        testDraw:AddRectFilled({ 20, 60 }, { 370, 100 }, imgui.GetColorU32({ 0.08, 0.09, 0.12, 1 }), 6);
        testDraw:AddText({ 30, 70 }, imgui.GetColorU32({ 1, 1, 1, 1 }), 'chatbubbles: overlay drawing works');
    end
    -- an NPC's line that waits for a key stays while the game waits, with the arrow on it: held a
    -- second past each frame the game is in an event, and let go a second after it ends
    local appearance = config.options.appearance;
    local waiting = appearance.arrow ~= nil and appearance.arrow[1] == true and game.IsEventHappening();
    if (waiting) then
        for _, message in pairs(npcState.messages) do
            if (message.prompt) then message.expires = math.max(message.expires, now + 1); end
        end
    end
    -- Preview, in the settings: a sample over the player's own name, kept a second past each frame
    -- it is wanted, drawn whatever the channel switches say and with the arrow, if that is on
    if (config.preview ~= nil and config.preview[1]) then
        local speaker = ownName();
        local message = speaker and state.messages[speaker];
        if (speaker and (message == nil or not message.preview)) then
            message = bubbles.Add(state, speaker, 'The quick brown fox jumps over the lazy dog: a preview of the bubbles.', now);
            if (message) then message.synthetic, message.preview = true, true; end
        end
        if (message) then message.expires = math.max(message.expires, now + 1); end
    end
    local active = prune(now);
    local hook = nameplates.Hook();
    if (hook == nil) then
        -- Nothing can be drawn without namehook: what was waiting is let go of (once, and again only when
        -- something new comes), and why is said once in the chat log, as damage does
        if (active > 0 or not missingCleared) then clear(); end
        missingCleared = true;
        local problem = nameplates.Problem();
        if (problem ~= problemSaid) then
            problemSaid = problem;
            if (problem ~= nil) then report(problem); end
        end
        return;
    end
    missingCleared, problemSaid = false, nil;
    -- Publish an empty frame too, so expired speech disappears immediately: and with Draw On Screen
    -- every frame is empty, the world's bubbles gone the frame it is turned on
    local onScreen = appearance.onScreen ~= nil and appearance.onScreen[1] == true;
    local scale = world.Begin(hook);
    if ((not scale and not onScreen) or active == 0) then return; end
    local display = imgui.GetIO().DisplaySize;
    local seen = {};
    -- the bubbles' font and size, where they are not everything else's: the font is a file name, as
    -- widgets.FontFile keeps it (a table of one up to 0.93, which config.Settle brings over)
    local font = fonts.Get(appearance.font);
    local fontSize = appearance.fontSize ~= nil and appearance.fontSize[1] or 0;
    local pushed = font ~= nil or fontSize > 0;
    if (pushed) then imgui.PushFont(font, fontSize > 0 and fontSize or imgui.GetFontSize()); end
    for _, name in nameplates.Each() do
        stats.anchors = stats.anchors + 1;
        local speaker = nameplates.Name(name):lower();
        local synthetic = targetMessage and name.EntityIndex == targetMessage.index
            and name.ServerId == targetMessage.id and targetMessage;
        local dialogue = npc.ForName(npcState, name);
        if (dialogue and not config.AllowsNpc(dialogue.mode)) then dialogue = nil; end
        local message = synthetic or dialogue or state.messages[speaker];
        if (message and not synthetic and not dialogue and not message.synthetic and not config.Allows(message.mode)) then message = nil; end
        -- NPC dialogue and target tests are bound to index AND server ID. Player
        -- packet chat still cannot attach to arbitrary same-named NPCs.
        if (message and not seen[message] and (synthetic or dialogue or name.Category <= nameplates.Category.Player)) then
            stats.matched = stats.matched + 1;
            message.waiting = (dialogue ~= nil and message.prompt == true and waiting)
                or (message.preview == true and appearance.arrow ~= nil and appearance.arrow[1] == true);
            local x, y = nameplates.Screen(name);
            if (x and x >= 0 and x <= display.x and y >= 0 and y <= display.y) then
                seen[message] = true;
                local drawn;
                if (onScreen) then
                    drawn = screen.Draw(name, message, now, x, y, display, appearance);
                else
                    drawn = world.Draw(name, message, now, scale, appearance);
                end
                if (drawn) then stats.drawn = stats.drawn + 1; end
            end
        end
    end
    if (pushed) then imgui.PopFont(); end
end);
