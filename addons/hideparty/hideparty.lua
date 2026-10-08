--[[
* Addons - Copyright (c) 2025 Ashita Development Team
* Contact: https://www.ashitaxi.com/
* Contact: https://discord.gg/Ashita
*
* This file is part of Ashita.
*
* Ashita is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Ashita is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with Ashita.  If not, see <https://www.gnu.org/licenses/>.
--]]

addon.name      = 'hideparty';
addon.author    = 'atom0s';
addon.version   = '1.1';
addon.desc      = 'Adds slash commands to hide, show, or toggle the games party frames.';
addon.link      = 'https://ashitaxi.com/';

require 'common';

local chat = require 'chat';

-- Addon Variables
local hideparty = {
    show = 1,
    ptrs = {
      target = 0,
      party0 = 0,
      party1 = 0,
      party2 = 0,
    },
};

--[[
* Prints the addon help information.
*
* @param {boolean} isError - Flag if this function was invoked due to an error.
--]]
local function print_help(isError)
    -- Print the help header..
    if (isError) then
        print(chat.header(addon.name):append(chat.error('Invalid command syntax for command: ')):append(chat.success('/' .. addon.name)));
    else
        print(chat.header(addon.name):append(chat.message('Available commands:')));
    end

    local cmds = T{
        { '/hideparty', 'Toggles the party frames visibility.' },
        { '/hideparty help', 'Displays the addons help information.' },
        { '/hideparty (hide | h)', 'Sets the party frames to be hidden.' },
        { '/hideparty (show | s)', 'Sets the party frames to be visible.' },
    };

    -- Print the command list..
    cmds:ieach(function (v)
        print(chat.header(addon.name):append(chat.error('Usage: ')):append(chat.message(v[1]):append(' - ')):append(chat.color1(6, v[2])));
    end);
end

--[[
* Sets a game primitives visibility.
*
* @param {number} p - The pointer of the primitive object.
* @param {boolean} v - The visibility status to set.
--]]
local function set_primitive_visibility(p, v)
    local ptr = ashita.memory.read_uint32(p);
    if (ptr ~= 0) then
        ptr = ashita.memory.read_uint32(ptr + 0x08);
        if (ptr ~= 0) then
            ashita.memory.write_uint8(ptr + 0x69, v);
            ashita.memory.write_uint8(ptr + 0x6A, v);
        end
    end
end

--[[
* Diagnostic, switched with /hideparty diag. Temporary: for finding out what the game does to its frames
* when a target is taken and dropped. It only reads memory, and writes what it finds to hidepartydiag.txt
* in the addon's folder.
*
* For each frame it follows the same two pointers the addon does: the frame's window object, then that
* window's primitive (the thing the addon hides). Whenever a target is taken or dropped, or either pointer
* of any frame changes, it records every frame's pointers and visibility flags and the first bytes of both
* objects, on that game frame and the three after it. It looks before the addon writes anything that
* frame, so the flags are as the game left them.
--]]
local diag = {
    on = false,
    frame = 0,
    follow = 0,       -- how many more game frames to record after a change
    hadTarget = nil,
    last = { },       -- frame name -> 'window:primitive' as last seen
    names = { 'target', 'party0', 'party1', 'party2' },
    bytes = 0x80,     -- how much of each object to record
};

local function diag_write(line)
    local file = io.open(addon.path .. 'hidepartydiag.txt', 'a');
    if (file) then
        file:write(line .. '\n');
        file:close();
    end
end

local function diag_dump(label, address)
    if (address == 0) then
        diag_write(('    %s: none'):format(label));
        return;
    end

    diag_write(('    %s at 0x%08X'):format(label, address));
    for row = 0, diag.bytes - 1, 16 do
        local hex = { };
        for column = 0, 15 do
            hex[#hex + 1] = ('%02X'):format(ashita.memory.read_uint8(address + row + column));
        end
        diag_write(('      +%02X  %s'):format(row, table.concat(hex, ' ')));
    end
end

-- The window object and primitive of one frame, 0 for either that is not there
local function diag_pointers(p)
    local window = (p ~= 0) and ashita.memory.read_uint32(p) or 0;
    local primitive = (window ~= 0) and ashita.memory.read_uint32(window + 0x08) or 0;
    return window, primitive;
end

local function diag_record(reason)
    diag_write(('game frame %d  clock %.3f  %s'):format(diag.frame, os.clock(), reason));
    for _, name in ipairs(diag.names) do
        local window, primitive = diag_pointers(hideparty.ptrs[name]);
        local flags = 'no primitive';
        if (primitive ~= 0) then
            flags = ('visible flags %d %d'):format(ashita.memory.read_uint8(primitive + 0x69), ashita.memory.read_uint8(primitive + 0x6A));
        end
        diag_write(('  %s: window 0x%08X  primitive 0x%08X  %s'):format(name, window, primitive, flags));
        diag_dump('window object', window);
        diag_dump('primitive', primitive);
    end
end

-- Called at the start of each presented frame, before the addon sets any visibility
local function diag_update()
    if (not diag.on) then
        return;
    end
    diag.frame = diag.frame + 1;

    local reasons = { };

    local target = AshitaCore:GetMemoryManager():GetTarget();
    local hasTarget = (target:GetTargetIndex(0) ~= 0);
    if (diag.hadTarget ~= nil and hasTarget ~= diag.hadTarget) then
        reasons[#reasons + 1] = hasTarget and 'TARGET TAKEN' or 'TARGET DROPPED';
    end
    diag.hadTarget = hasTarget;

    for _, name in ipairs(diag.names) do
        local window, primitive = diag_pointers(hideparty.ptrs[name]);
        local now = ('%08X:%08X'):format(window, primitive);
        if (diag.last[name] ~= nil and diag.last[name] ~= now) then
            reasons[#reasons + 1] = ('%s pointers changed (%s -> %s)'):format(name, diag.last[name], now);
        end
        diag.last[name] = now;
    end

    if (#reasons > 0) then
        diag.follow = 3;
        diag_record(table.concat(reasons, '; '));
    elseif (diag.follow > 0) then
        diag.follow = diag.follow - 1;
        diag_record('(following frame)');
    end
end

local function diag_toggle()
    diag.on = not diag.on;
    if (diag.on) then
        diag.frame, diag.follow, diag.hadTarget, diag.last = 0, 0, nil, { };
        diag_write('');
        diag_write(('===== %s  diagnostic started  (frames %s) ====='):format(os.date('%Y-%m-%d %H:%M:%S'), hideparty.show and 'shown' or 'hidden'));
        diag_record('state when started');
    end
    print(chat.header(addon.name):append(chat.message('Diagnostic ' .. (diag.on and 'on: writing to hidepartydiag.txt' or 'off') .. '.')));
end

--[[
* event: load
* desc : Event called when the addon is being loaded.
--]]
ashita.events.register('load', 'load_cb', function ()
    -- Find the needed pointers for the main party and target frames..
    local ptr1 = ashita.memory.find(0, 0, '66C78182000000????C7818C000000????????C781900000', 0, 0);
    if (ptr1 == 0) then
        error(chat.header(addon.name):append(chat.error('Error: Failed to locate required pointer. (1)')));
    end

    -- Find the needed pointers for the alliance party frames..
    local ptr2 = ashita.memory.find(0, 0, 'A1????????8B0D????????89442424A1????????33DB89', 0, 0);
    if (ptr2 == 0) then
        error(chat.header(addon.name):append(chat.error('Error: Failed to locate required pointer. (2)')));
    end

    -- Read the base object pointers..
    hideparty.ptrs.party0 = ashita.memory.read_uint32(ptr1 + 0x19);
    hideparty.ptrs.target = ashita.memory.read_uint32(ptr1 + 0x23);
    hideparty.ptrs.party1 = ashita.memory.read_uint32(ptr2 + 0x01);
    hideparty.ptrs.party2 = ashita.memory.read_uint32(ptr2 + 0x07);

    set_primitive_visibility(hideparty.ptrs.party0, 1);
end);

--[[
* event: command
* desc : Event called when the addon is processing a command.
--]]
ashita.events.register('command', 'command_cb', function (e)
    -- Parse the command arguments..
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/hideparty')) then
        return;
    end

    -- Block all related commands..
    e.blocked = true;

    -- Handle: /hideparty - Toggles the party frames visibility.
    if (#args == 1) then
        hideparty.show = not hideparty.show;
        return;
    end

    -- Handle: /hideparty diag - Switches the diagnostic on or off.
    if (#args == 2 and args[2]:any('diag')) then
        diag_toggle();
        return;
    end

    -- Handle: /hideparty help - Shows the addon help.
    if (#args == 2 and args[2]:any('help')) then
        print_help(false);
        return;
    end

    -- Handle: /hideparty hide - Hides the party frames.
    if (#args == 2 and args[2]:any('hide', 'h')) then
        hideparty.show = false;
        return;
    end

    -- Handle: /hideparty show - Shows the party frames.
    if (#args == 2 and args[2]:any('show', 's')) then
        hideparty.show = true;
        return;
    end

    -- Unhandled: Print help information..
    print_help(true);
end);

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
ashita.events.register('d3d_present', 'present_cb', function ()
    diag_update();

    set_primitive_visibility(hideparty.ptrs.party0, hideparty.show and 1 or 0);
    set_primitive_visibility(hideparty.ptrs.party1, hideparty.show and 1 or 0);
    set_primitive_visibility(hideparty.ptrs.party2, hideparty.show and 1 or 0);
    set_primitive_visibility(hideparty.ptrs.target, hideparty.show and 1 or 0);
end);