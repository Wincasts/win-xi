addon.name    = 'occlusionfix';
addon.author  = 'win';
addon.version = '1.0';
addon.desc    = 'Stops characters near walls, door frames and counters blinking out of view.';

require('common');

local chat = require('chat');
local patch = require('patch');

local mem = {
    find = function (pattern) return ashita.memory.find(0, 0, pattern, 0, 0); end,
    read = function (addr, n) return ashita.memory.read_array(addr, n); end,
    write = function (addr, bytes)
        local ok, prot = ashita.memory.unprotect(addr, #bytes);
        if not ok then
            return false;
        end
        ashita.memory.write_array(addr, bytes);
        ashita.memory.protect(addr, #bytes, prot);
        return true;
    end,
};

local state = nil; -- the three calls, from patch.find

local function say(s)
    print(chat.header(addon.name):append(chat.message(s)));
end

local function fail(s)
    print(chat.header(addon.name):append(chat.error(s)));
end

local function Status()
    say(patch.active(mem, state) and 'on: characters are not hidden by the occlusion test.'
        or 'off: the game\'s occlusion test hides characters as it does without the addon.');
end

ashita.events.register('load', 'occlusionfix_load', function ()
    local found, why = patch.find(mem);
    if found == nil then
        fail(('The occlusion test was not found (%s); nothing is changed.'):format(why));
        return;
    end
    state = found;
    patch.set(mem, state, true);
end);

ashita.events.register('unload', 'occlusionfix_unload', function ()
    patch.set(mem, state, false);
end);

ashita.events.register('command', 'occlusionfix_command', function (e)
    local args = e.command:args();
    if #args == 0 or args[1]:lower() ~= '/occlusionfix' then
        return;
    end
    e.blocked = true;
    if state == nil then
        fail('The occlusion test was not found when the addon loaded; nothing is changed.');
        return;
    end
    local arg = (args[2] or ''):lower();
    if arg == 'on' or arg == 'off' then
        patch.set(mem, state, arg == 'on');
    elseif arg == '' then
        patch.set(mem, state, not patch.active(mem, state));
    else
        say('/occlusionfix [on|off] - on: characters are drawn wherever the depth buffer shows them. off: stock.');
        return;
    end
    Status();
end);
