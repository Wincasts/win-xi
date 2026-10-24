-- vis taking over drawscale's settings: at the first load for a character, drawscale's settings file is
-- copied over vis's before vis's are read, and said; a character switched to later whose vis settings
-- are new has theirs copied and read again, once; a character already vis's is left alone, and with
-- nothing of drawscale's there is nothing to copy.
local printCheck = H.print
H.print = function(label, ...)
    printCheck(label, ...)
    for i = 1, select('#', ...) do assert(select(i, ...) ~= false, label) end
end

local settings = require('settings')
local files, writes, reloads = {}, {}, 0
local path = 'C:\\ashita\\config\\addons\\vis\\Tester_1\\'
settings.settings_path = function() return path end
settings.reload = function() reloads = reloads + 1 end
files['C:\\ashita\\config\\addons\\drawscale\\Tester_1\\settings.lua'] = 'drawscale for Tester'
files['C:\\ashita\\config\\addons\\drawscale\\Other_1\\settings.lua'] = 'drawscale for Other'
local realExists = ashita.fs.exists
ashita.fs.exists = function(p) if p:find('\\config\\addons\\', 1, true) then return files[p] ~= nil end return realExists(p) end
ashita.fs.create_dir = function() end
local realOpen = io.open
io.open = function(p, mode)
    if type(p) ~= 'string' or not p:find('\\config\\addons\\', 1, true) then return realOpen(p, mode) end
    if mode:find('w') then
        return { write = function(_, text) files[p] = text; writes[#writes + 1] = p end, close = function() end }
    end
    if files[p] == nil then return nil end
    return { read = function() return files[p] end, close = function() end }
end
local function said() return table.concat(H.printed, '\n') end

H.load()
H.print('first load: drawscale\'s file copied over vis\'s', files[path .. 'settings.lua'] == 'drawscale for Tester', #writes == 1,
    '| said, with the startup script', said():find('Your drawscale settings are vis\'s now. vis replaces drawscale: take /addon load drawscale out of your startup script.', 1, true) ~= nil,
    '| and marked', H.options().adopted == true)

-- a switch to a character whose vis settings are new: copied, read again, and the reload's own update settled
path = 'C:\\ashita\\config\\addons\\vis\\Other_1\\'
local n = #H.printed
H.options().adopted = false
H.resettle(); -- the settings library's update with the new character's defaults
H.print('a new character: theirs copied', files[path .. 'settings.lua'] == 'drawscale for Other', '| and read again', reloads == 1)
H.options().adopted = false
H.resettle(); -- the reload's update: the file is looked for once
H.print('the reload settles without copying again', reloads == 1, #writes == 2, H.options().adopted == true,
    '| and says so', said():sub(#table.concat(H.printed, '\n', 1, n) + 1):find('Your drawscale settings are vis\'s now.', 1, true) ~= nil)

-- a character already vis's, and one drawscale never knew
H.resettle()
H.print('already vis\'s: nothing copied', #writes == 2, reloads == 1)
path = 'C:\\ashita\\config\\addons\\vis\\New_1\\'
H.options().adopted = false
H.resettle()
H.print('drawscale never knew them: nothing to copy', #writes == 2, reloads == 1, H.options().adopted == true)
