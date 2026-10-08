-- winxi.sound: the small sounds a menu makes, as the game's own menus do.
--
-- Off until the addon turns it on, so nothing sounds unless an addon offers it as a setting:
--
--     local sound = require('winxi.sound');
--     sound.SetEnabled(settings.MenuSounds);
--     sound.Play('move');
--
-- The sounds are named for what happened: move (the highlight went somewhere), tab (to another tab or
-- page), confirm, back and error (what was asked for cannot be done). winxi.controller's grid and menu play them by themselves, so an
-- addon using those need only turn the sounds on; anything else it does with a menu it plays itself.
--
-- Each sound is a wav file called by its name, move.wav and so on. One in the addon's own sounds
-- folder is used before the one that comes with winxi, so an addon, or the person using it, may put
-- their own in place. sound.Set gives a name any file at all, and new names may be made that way.
--
-- Ashita plays one sound at a time and at the volume of the file: a sound cuts short the one before
-- it, and there is nothing here to make one louder or quieter.
local sound = {};

sound.Names = { 'move', 'tab', 'confirm', 'back', 'error' };

local enabled = false;
local files = {};     -- name -> the file to play, or false where there is none: looked for once
local folders = nil;  -- where a sound is looked for, in order

local function Folders()
    if folders == nil then
        folders = {
            string.format('%s\\sounds\\', addon.path),
            string.format('%saddons\\libs\\winxi\\sounds\\', AshitaCore:GetInstallPath()),
        };
    end
    return folders;
end

local function Find(name)
    for _, folder in ipairs(Folders()) do
        local path = string.format('%s%s.wav', folder, name);
        if ashita.fs.exists(path) then
            return path;
        end
    end
    return false;
end

function sound.SetEnabled(value)
    enabled = value and true or false;
end

function sound.IsEnabled()
    return enabled;
end

-- Gives a name a file of the addon's choosing, a full path; nil goes back to looking for it by name
function sound.Set(name, path)
    files[name] = path;
end

-- Looks for the files again, for when they have been changed while the addon was loaded
function sound.Refresh()
    files = {};
end

-- Plays a sound by name. Does nothing while sounds are off, or where there is no file for the name.
function sound.Play(name)
    if not enabled then
        return false;
    end

    local path = files[name];
    if path == nil then
        path = Find(name);
        files[name] = path;
    end
    if not path then
        return false;
    end

    ashita.misc.play_sound(path);
    return true;
end

return sound;
