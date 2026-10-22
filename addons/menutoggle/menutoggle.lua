addon.name    = 'menutoggle';
addon.author  = 'win';
addon.version = '0.2';
addon.desc    = 'Start closes the main menu and the social menu, in place of moving from one to the other.';

require('common');

local chat = require('chat');
local game = require('winxi.game');

-- The game opens the main menu (menuwind) on the menu button, and on a second press moves on to the
-- social menu (socialme). While either is on top the press is kept from the game and the cancel button
-- pressed for it, which closes the menu; at any other time Start reaches the game as it is.
--
-- DirectInput numbers the buttons by their offset in the controller's state, 48 for the first; the
-- DualSense's Options is its tenth button and Circle its third. XInput's numbers are those of
-- winxi.controller.Button.
local DINPUT = { start = 57, cancel = 50, down = 128 };
local XINPUT = { start = 4, cancel = 13, down = 1 };

local HOLD = 0.05; -- seconds the cancel button is held, long enough for the game to see it down

local enabled = true;
local taken = false;  -- whether the press of Start now held was kept from the game
local release = nil;  -- { device, button, at }: the cancel button to let go of, and when

-- the menus Start closes: the main menu, and the social menu it moves on to
local CLOSES = { menuwind = true, socialme = true };

local function MenuOnTop()
    return CLOSES[game.MenuName():match('^menu%s+(%S+)%s*$') or ''] == true;
end

local function Handle(kind, device, e)
    if e.button ~= kind.start then
        return;
    end
    if e.state == kind.down then
        taken = enabled and release == nil and MenuOnTop();
        if taken then
            e.blocked = true;
            device:QueueButtonData(kind.cancel, kind.down);
            release = { device = device, button = kind.cancel, at = os.clock() + HOLD };
        end
    elseif taken then
        -- the release of a press the game never saw
        e.blocked = true;
        taken = false;
    end
end

ashita.events.register('dinput_button', 'menutoggle_dinput', function(e)
    Handle(DINPUT, AshitaCore:GetInputManager():GetController(), e);
end);

ashita.events.register('xinput_button', 'menutoggle_xinput', function(e)
    Handle(XINPUT, AshitaCore:GetInputManager():GetXInput(), e);
end);

ashita.events.register('d3d_present', 'menutoggle_present', function()
    if release ~= nil and os.clock() >= release.at then
        release.device:QueueButtonData(release.button, 0);
        release = nil;
    end
end);

-- an unload with the cancel button down lets it go
ashita.events.register('unload', 'menutoggle_unload', function()
    if release ~= nil then
        release.device:QueueButtonData(release.button, 0);
        release = nil;
    end
end);

ashita.events.register('command', 'menutoggle_command', function(e)
    local args = e.command:args();
    if #args == 0 or args[1]:lower() ~= '/menutoggle' then
        return;
    end
    e.blocked = true;

    local choice = (args[2] or ''):lower();
    if choice == 'on' then
        enabled = true;
    elseif choice == 'off' then
        enabled = false;
    elseif choice == '' then
        enabled = not enabled;
    else
        print(chat.header(addon.name):append(chat.error('Usage: /menutoggle [on|off]')));
        return;
    end
    print(chat.header(addon.name):append(chat.message('Start closes the main menu: '))
        :append(enabled and chat.success('on') or chat.error('off')));
end);
