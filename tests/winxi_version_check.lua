-- luajit tests/winxi_version_check.lua
-- Each released addon checks, as it loads, that addons/libs/winxi is at least the winxi it was made
-- with (winxi.version): an older one, or one from before winxi.version, stops it with a plain message
-- in the chat; the current one lets it go on.
local current = dofile('addons/libs/winxi/version.lua').Number
local released = {
    'addons/chatbox/chatbox.lua', 'addons/parse/parse.lua', 'addons/buff/buff.lua', 'addons/name/name.lua', 'addons/party/party.lua', 'addons/inventory/inventory.lua',
    'addons/trigger/trigger.lua', 'addons/winxisettings/winxisettings.lua', 'forks/addons/hideparty/hideparty.lua',
}
local said
print = function(text) said = text end -- what the addon writes in the chat
local function load(path, winxi)
    addon, said = {}, nil
    package.loaded['winxi.version'] = nil
    package.preload['winxi.version'] = winxi and function() return winxi end or nil
    -- the first thing the addon needs after the check: reaching it means the check let it through
    package.preload['common'] = function() error('past the check', 0) end
    package.loaded['common'] = nil
    local ok, problem = pcall(dofile, path)
    return ok, problem
end
-- each addon needs the winxi it says it was made with: never one newer than this, nor before 1
local function needed(path)
    local file = assert(io.open(path, 'rb'))
    local source = file:read('*a')
    file:close()
    return tonumber(source:match('local winxiNeeded = (%d+)'))
end
for _, path in ipairs(released) do
    local need = needed(path)
    assert(need ~= nil and need >= 1 and need <= current, path .. ': winxiNeeded ' .. tostring(need) .. ' with winxi ' .. current)
    local _, problem = load(path, nil)
    assert(problem:find('needs winxi %d+ or newer, and addons/libs/winxi is 0'), path .. ': no winxi.version: ' .. problem)
    assert(said and said:find('install the newest release'), path .. ': not said in the chat')
    _, problem = load(path, { Number = need - 1 })
    assert(problem:find('is ' .. (need - 1) .. ':'), path .. ': older winxi: ' .. problem)
    _, problem = load(path, { Number = need })
    assert(problem == 'past the check' and said == nil, path .. ': the winxi it needs stopped it: ' .. tostring(problem))
    _, problem = load(path, { Number = current + 1 })
    assert(problem == 'past the check', path .. ': newer winxi stopped')
end
io.write(('winxi version: %d released addons stop on a missing winxi or one older than they need, with a message, and load on the one they need or newer\ttrue\n'):format(#released))
