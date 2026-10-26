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
addon.author    = 'atom0s, win';
addon.version   = '1.3';
addon.desc      = 'Adds slash commands to hide, show, or toggle the games party frames, drawing the target cursor they take with them.';
addon.link      = 'https://ashitaxi.com/';

-- The winxi this addon was made with, or a newer one: each addon is released with its own copy, so an
-- older one may have been put over it (winxi.version)
local winxiNeeded = 56; -- winxi.presence, so party knows not to replace the frames this hides
do
    local ok, found = pcall(require, 'winxi.version');
    local number = ok and type(found) == 'table' and found.Number or 0;
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number);
        print(('\30\68[%s]\30\01 %s'):format(addon.name, text));
        error(text, 0);
    end
end

require 'common';

local chat = require 'chat';
local targetcursor = require 'targetcursor';
local presence = require('winxi.presence');

-- Addon Variables
local hideparty = {
    show = false, -- hidden from the moment it loads
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
            ashita.memory.write_uint8(ptr + 0x69, v); -- the frame's background
            ashita.memory.write_uint8(ptr + 0x6A, v); -- what is written in it
        end
    end
end

--[[
* Returns whether the game's party cursor is out: a member is being picked from the party list, in the
* party menu or as a sub-target.
--]]
local party_pointer = 0;
local function is_cursor_active()
    -- Ashita finds the pointer once, at boot: kept here rather than looked up by name every frame.
    if (party_pointer == 0) then
        party_pointer = AshitaCore:GetPointerManager():Get('party') or 0;
        if (party_pointer == 0) then return false; end
    end
    local ptr = party_pointer;
    ptr = ashita.memory.read_uint32(ptr);
    if (ptr == 0) then return false; end
    ptr = ashita.memory.read_uint32(ptr);
    if (ptr == 0) then return false; end
    return ashita.memory.read_uint32(ptr + 0x54) ~= 0;
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
    -- party's native windows replace these frames as the game draws them: party will not while this is loaded
    presence.Announce('hideparty');
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
    -- The game's cursor cannot move freely between party frames that are hidden: it is thrown out of
    -- the one it enters and on to the next, so that it is trapped in the alliance or in the party.
    -- Hiding and showing one frame at a time only moves the trap. So the party frames are all left
    -- showing for as long as the cursor is out, and hidden again once it has gone.
    local parties = hideparty.show or is_cursor_active();

    set_primitive_visibility(hideparty.ptrs.party0, parties and 1 or 0);
    set_primitive_visibility(hideparty.ptrs.party1, parties and 1 or 0);
    set_primitive_visibility(hideparty.ptrs.party2, parties and 1 or 0);
    set_primitive_visibility(hideparty.ptrs.target, hideparty.show and 1 or 0);

    -- The game's target cursor is part of the target frame, so it goes when the frame does: draw it.
    if (not hideparty.show) then
        targetcursor.Draw();
    end
end);

--[[
* event: unload
* desc : Event called when the addon is being unloaded.
--]]
ashita.events.register('unload', 'unload_cb', function ()
    presence.Withdraw('hideparty');
    -- Hidden from loading, so the frames are given back on the way out, or they would stay hidden.
    set_primitive_visibility(hideparty.ptrs.party0, 1);
    set_primitive_visibility(hideparty.ptrs.party1, 1);
    set_primitive_visibility(hideparty.ptrs.party2, 1);
    set_primitive_visibility(hideparty.ptrs.target, 1);
end);