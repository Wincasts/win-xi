-- The diagnostics: why the custom names stopped, said once and written to a log. Run via tests/harness.lua.
local imgui = require('imgui')
local custom = require('custom')
local diag = require('diag')
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
local options = {}
custom.Defaults(options)
local hook = ffi.new('namehook_t')
H.print('no plugin hooks: unhooked', custom.Frame(options, hook) == 'unhooked')
hook.Hooked = 1
imgui.GetFont = function() return { ContainerAtlas = { TexRef = { GetTexID = function() return 0 end },
    TexData = { GetTexID = function() return 0 end } } } end
H.print('font texture of id 0: texture', custom.Frame(options, hook) == 'texture')
imgui.GetFont = function() return { ContainerAtlas = { TexRef = { GetTexID = function() return 0x1234 end } } } end
H.print('no drawing buffer: draw', custom.Frame(options, hook) == 'draw')

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
io.open = realOpen
