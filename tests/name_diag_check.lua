-- The diagnostics: why the custom names stopped, said once and written to a log. Run via tests/harness.lua.
local imgui = require('imgui')
local custom = require('custom')
local diag = require('diag')
-- a 60th of a second goes by with each frame: a pause is seen after half a second, 30 of them
local frame = diag.Frame
diag.Frame = function(...) H.wait(1 / 60); return frame(...) end
local ffi = require('ffi')
-- the plugin as not loaded: what is written of it must not stop the rest
AshitaCore.GetPluginManager = function() return { IsLoaded = function() return false end } end

-- what is written is kept here, not on disk
local written = {}
local realOpen = io.open
io.open = function(path, mode)
    if mode == 'w' and path:find('\\logs\\', 1, true) then
        local file = { path = path, text = {} }
        written[#written + 1] = file
        return { write = function(_, ...) for _, part in ipairs({ ... }) do file.text[#file.text + 1] = part end end,
            close = function() end }
    end
    return realOpen(path, mode)
end

-- custom.Frame says why it drew nothing
local defaults = {}
custom.Defaults(defaults)
local hook = ffi.new('namehook_t')
H.print('no plugin hooks: unhooked', custom.Frame(defaults, hook) == 'unhooked')
hook.Hooked = 1
imgui.GetFont = function() return { ContainerAtlas = { TexData = { UniqueID = 2, Status = 2, Width = 512, Height = 256 } } } end
H.print('font texture not ready: texture', custom.Frame(defaults, hook) == 'texture')
imgui.GetFont = function() return { ContainerAtlas = {} } end
H.print('font texture unreadable: texture', custom.Frame(defaults, hook) == 'texture')
imgui.GetFont = function() return { ContainerAtlas = { TexData = { UniqueID = 2, Status = 0, Width = 512, Height = 256 } } } end
H.print('no drawing buffer: draw', custom.Frame(defaults, hook) == 'draw')

-- off unless asked for: nothing kept, said or written
local options = H.options()
H.print('off by default', options.diagnostics[1] == false, diag.Enabled() == false)
for _ = 1, 40 do diag.Frame('texture') end
diag.Frame(nil)
H.print('off: a long pause is not written or said', #written == 0, diag.Status() == 'Drawing')
H.command('/name custom off')
H.print('other verbs still only say the help', H.printed[#H.printed]:find('Use /name to open', 1, true) ~= nil)
H.command('/name diag')
H.print('/name diag turns it on, and it is kept', options.diagnostics[1] == true, diag.Enabled(), H.saves() > 0)

-- a pause too short to be seen is only counted
for _ = 1, 5 do diag.Frame(nil) end
for _ = 1, 3 do diag.Frame('texture') end
diag.Frame(nil)
H.print('short pause: nothing said or written', #written == 0)

-- one long enough that the game's names come back is said once and written once
local before = #H.printed
for _ = 1, 40 do diag.Frame('texture') end
H.print('long pause: written once', #written == 1, written[1] and written[1].path:match('config\\addons\\name\\logs\\name%-[%d%-]+%.txt$') ~= nil)
H.print('and said', #H.printed == before + 1 and H.printed[#H.printed]:find('Custom names stopped', 1, true) ~= nil)
H.print('status while stopped', diag.Status():match('^Stopped for') ~= nil)
diag.Frame(nil)
for _ = 1, 40 do diag.Frame('texture') end
H.print('the same reason again: not written again', #written == 1)
diag.Frame(nil)
H.print('drawing again', diag.Status() == 'Drawing')

-- the plugin unloaded on purpose is not worth a word
for _ = 1, 40 do diag.Frame('unloaded') end
diag.Frame(nil)
H.print('unloaded: nothing written', #written == 1)

-- errors are kept once, with a count
diag.Error('boom', 'boom\ntraceback')
diag.Error('boom', 'boom\ntraceback')
diag.Options = { fontSize = { 28 }, font = 'corbeli.ttf' }
local path = diag.Write('asked for')
local text = table.concat(written[#written].text)
H.print('asked for: written', path ~= nil and diag.LastPath() == path)
H.print('log has the reason, pauses, error, history and settings',
    text:find('texture    1 short, 2 seen', 1, true) ~= nil,
    text:find('2 times, first', 1, true) ~= nil,
    text:find('Custom names back after', 1, true) ~= nil,
    text:find('fontSize               28', 1, true) ~= nil)
if os.getenv('SHOW_LOG') then H.print(text) end
local count = #written
H.command('/name diag log')
H.print('/name diag log writes one', #written == count + 1, H.printed[#H.printed]:find('Log written to', 1, true) ~= nil)
H.command('/name diag off')
H.print('/name diag off', options.diagnostics[1] == false, diag.Enabled() == false)
io.open = realOpen
