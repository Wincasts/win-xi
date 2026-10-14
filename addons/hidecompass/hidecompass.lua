addon.name    = 'hidecompass';
addon.author  = 'win';
addon.version = '1.0';
addon.desc    = 'Hides the game\'s compass.';

require('common');

local chat = require('chat');
local ffi  = require('ffi');

-- The compass is one object in the client, with a state the game itself steps through:
--   0 hidden, 1 asked to show, 2 fading in, 3 shown, 4 fading out.
-- Its drawing is skipped while the state is 0.
local STATE_OFFSET = 0x0D; -- uint8: the state above
local ALPHA_OFFSET = 0x20; -- int32: opacity, 0 to 0x80, with a float after it: how far through the fade, 0 to 1

local hidecompass = {
    hide = true,
    ptr  = nil, -- where the client keeps its pointer to the compass
};

local function print_help(isError)
    if (isError) then
        print(chat.header(addon.name):append(chat.error('Invalid command syntax for command: ')):append(chat.success('/' .. addon.name)));
    else
        print(chat.header(addon.name):append(chat.message('Available commands:')));
    end

    local cmds = T{
        { '/hidecompass', 'Toggles the compass.' },
        { '/hidecompass help', 'Displays the addons help information.' },
        { '/hidecompass (hide | h)', 'Sets the compass to be hidden.' },
        { '/hidecompass (show | s)', 'Sets the compass to be visible.' },
    };

    cmds:ieach(function (v)
        print(chat.header(addon.name):append(chat.error('Usage: ')):append(chat.message(v[1]):append(' - ')):append(chat.color1(6, v[2])));
    end);
end

ashita.events.register('load', 'load_cb', function ()
    -- The client's own step that updates and then draws the compass; it opens by reading the pointer.
    local ptr = ashita.memory.find(0, 0, '8B0D????????85C9741EE8????????B9????????E8????????3C01740B8B0D', 0, 0);
    if (ptr == 0) then
        error(chat.header(addon.name):append(chat.error('Error: Failed to locate required pointer.')));
    end

    hidecompass.ptr = ffi.cast('uint32_t*', ashita.memory.read_uint32(ptr + 0x02));
end);

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/hidecompass')) then
        return;
    end

    e.blocked = true;

    if (#args == 1) then
        hidecompass.hide = not hidecompass.hide;
        return;
    end

    if (#args == 2 and args[2]:any('help')) then
        print_help(false);
        return;
    end

    if (#args == 2 and args[2]:any('hide', 'h')) then
        hidecompass.hide = true;
        return;
    end

    if (#args == 2 and args[2]:any('show', 's')) then
        hidecompass.hide = false;
        return;
    end

    print_help(true);
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    if (not hidecompass.hide or hidecompass.ptr == nil) then
        return;
    end

    -- This runs every frame, so the client's memory is read and written in place, not through calls.
    local compass = hidecompass.ptr[0];
    if (compass == 0) then
        return;
    end

    local bytes = ffi.cast('uint8_t*', compass);
    local state = bytes[STATE_OFFSET];
    if (state == 0) then
        return;
    end

    -- Each frame the game draws the compass and only then, finding it hidden, asks for it to be shown
    -- again. Putting it back to hidden here, after that and before the next frame is drawn, means the
    -- drawing never finds it showing. Once this stops, the game brings the compass back by itself.
    bytes[STATE_OFFSET] = 0;

    -- From then on the state found here is always 1, asked to show, and the one byte above is all that
    -- is written. Only on the first frame is the compass found further along, with some opacity left;
    -- that is cleared as the game clears it at the end of its own fade out, or it would show for a frame
    -- at that opacity when it next fades in.
    if (state ~= 1) then
        local fade = ffi.cast('uint32_t*', compass + ALPHA_OFFSET);
        fade[0] = 0;
        fade[1] = 0;
    end
end);
